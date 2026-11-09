# FraudDetect corrected modeling pipeline
# Run from repository root. All threshold selection occurs on validation data.
# The test set is used once for final evaluation only.

source("corrected_r/scripts/00_setup.R")
library(tidyverse)
library(ranger)
library(xgboost)
library(pROC)
library(PRROC)

set.seed(2026)
dir.create("corrected_r/outputs", recursive = TRUE, showWarnings = FALSE)

raw <- readr::read_csv("data/transactions.csv", show_col_types = FALSE)
required <- c("transaction_id", "is_fraud", "geography", "time_of_day",
              "merchant_category", "prior_fraud_flag", "velocity_24h",
              "device_mismatch", "account_age_days", "amount", "amount_zscore")
missing_cols <- setdiff(required, names(raw))
if (length(missing_cols)) {
  stop("Missing required columns in data/transactions.csv: ",
       paste(missing_cols, collapse = ", "))
}

d <- raw |>
  mutate(
    is_fraud = as.integer(is_fraud),
    international = as.integer(geography == "international"),
    is_night = as.integer(time_of_day == "night"),
    high_risk_category = as.integer(merchant_category %in%
                                      c("ATM", "luxury", "electronics")),
    log_amount = log1p(amount)
  ) |>
  select(transaction_id, is_fraud, log_amount, international, is_night,
         high_risk_category, prior_fraud_flag, velocity_24h,
         device_mismatch, account_age_days, amount_zscore) |>
  drop_na()

if (!all(d$is_fraud %in% c(0L, 1L))) stop("is_fraud must be coded 0/1.")
if (length(unique(d$is_fraud)) != 2L) stop("Both fraud classes must be present.")

# Stratified, mutually exclusive 60/20/20 train/validation/test split.
stratified_sample <- function(y, proportion) {
  unlist(lapply(split(seq_along(y), y), function(idx) {
    n <- max(1L, floor(length(idx) * proportion))
    sample(idx, size = min(n, length(idx)))
  }), use.names = FALSE)
}
train_idx <- stratified_sample(d$is_fraud, 0.60)
remaining_idx <- setdiff(seq_len(nrow(d)), train_idx)
validation_local <- stratified_sample(d$is_fraud[remaining_idx], 0.50)
validation_idx <- remaining_idx[validation_local]
test_idx <- setdiff(remaining_idx, validation_idx)

train <- d[train_idx, ]
validation <- d[validation_idx, ]
test <- d[test_idx, ]
predictors <- setdiff(names(d), c("transaction_id", "is_fraud"))

class_counts <- table(factor(train$is_fraud, levels = c(0, 1)))
if (any(class_counts == 0)) stop("Training split must contain both classes.")
positive_weight <- as.numeric(class_counts[1] / class_counts[2])

# Random Forest. Class weights are estimated from training labels only.
rf_train <- train |>
  select(is_fraud, all_of(predictors)) |>
  mutate(is_fraud = factor(is_fraud, levels = c(0, 1)))
rf <- ranger(
  dependent.variable.name = "is_fraud",
  data = rf_train,
  probability = TRUE,
  num.trees = 500,
  mtry = max(1, floor(sqrt(length(predictors)))),
  class.weights = c("0" = 1, "1" = positive_weight),
  seed = 2026,
  importance = "permutation"
)
rf_valid_prob <- predict(rf, data = validation[, predictors])$predictions[, "1"]
rf_test_prob <- predict(rf, data = test[, predictors])$predictions[, "1"]

# XGBoost. Early stopping uses validation data; the test set is not used for tuning.
dtrain <- xgb.DMatrix(as.matrix(train[, predictors]), label = train$is_fraud)
dvalid <- xgb.DMatrix(as.matrix(validation[, predictors]), label = validation$is_fraud)
dtest <- xgb.DMatrix(as.matrix(test[, predictors]), label = test$is_fraud)

xgb_params <- list(
  objective = "binary:logistic",
  eval_metric = "aucpr",
  max_depth = 3,
  eta = 0.04,
  subsample = 0.8,
  colsample_bytree = 0.8,
  scale_pos_weight = positive_weight
)

# Early stopping with save_best=TRUE returns a booster sliced to its
# validation-selected best iteration. This avoids depending on best_iteration
# metadata fields that differ across xgboost R package versions.
xgb_model <- xgb.train(
  params = xgb_params,
  data = dtrain,
  nrounds = 500,
  evals = list(validation = dvalid),
  callbacks = list(
    xgb.cb.early.stop(
      stopping_rounds = 30,
      maximize = TRUE,
      metric_name = "validation_aucpr",
      save_best = TRUE,
      verbose = FALSE
    )
  ),
  verbose = 0
)
xgb_valid_prob <- as.numeric(predict(xgb_model, dvalid))
xgb_test_prob <- as.numeric(predict(xgb_model, dtest))

# Keep the equal-weight blend as a comparator, not as the assumed champion.
valid_probs <- list(
  Random_Forest = as.numeric(rf_valid_prob),
  XGBoost = as.numeric(xgb_valid_prob)
)
test_probs <- list(
  Random_Forest = as.numeric(rf_test_prob),
  XGBoost = as.numeric(xgb_test_prob)
)
valid_probs$Equal_Weight_Blend <- (valid_probs$Random_Forest + valid_probs$XGBoost) / 2
test_probs$Equal_Weight_Blend <- (test_probs$Random_Forest + test_probs$XGBoost) / 2

# Select a separate Youden-J threshold for each candidate on validation data.
select_threshold <- function(y, probability) {
  r <- pROC::roc(y, probability, levels = c(0, 1),
                 direction = "<", quiet = TRUE)
  as.numeric(pROC::coords(r, x = "best", best.method = "youden",
                          ret = "threshold", transpose = FALSE)[1])
}
thresholds <- purrr::map_dbl(valid_probs, ~ select_threshold(validation$is_fraud, .x))

# Final test metrics. No test-set threshold optimization.
evaluate_model <- function(model_name) {
  probability <- test_probs[[model_name]]
  threshold <- thresholds[[model_name]]
  predicted <- as.integer(probability >= threshold)
  actual <- test$is_fraud
  tp <- sum(predicted == 1 & actual == 1)
  fp <- sum(predicted == 1 & actual == 0)
  tn <- sum(predicted == 0 & actual == 0)
  fn <- sum(predicted == 0 & actual == 1)
  test_roc <- pROC::roc(actual, probability, levels = c(0, 1),
                        direction = "<", quiet = TRUE)
  pr <- PRROC::pr.curve(
    scores.class0 = probability[actual == 1],
    scores.class1 = probability[actual == 0],
    curve = FALSE
  )
  tibble(
    model = model_name,
    threshold_selected_on_validation = threshold,
    test_roc_auc = as.numeric(pROC::auc(test_roc)),
    test_pr_auc = pr$auc.integral,
    precision = ifelse(tp + fp > 0, tp / (tp + fp), NA_real_),
    recall = ifelse(tp + fn > 0, tp / (tp + fn), NA_real_),
    specificity = ifelse(tn + fp > 0, tn / (tn + fp), NA_real_),
    false_positive_rate = ifelse(fp + tn > 0, fp / (fp + tn), NA_real_),
    true_positives = tp,
    false_positives = fp,
    true_negatives = tn,
    false_negatives = fn,
    test_n = length(actual),
    test_fraud_prevalence = mean(actual)
  )
}

metrics <- purrr::map_dfr(names(test_probs), evaluate_model)
readr::write_csv(metrics, "corrected_r/outputs/model_comparison.csv")

# Include IDs to enable a direct row-level comparison with anomaly scores.
prediction_output <- tibble(
  transaction_id = test$transaction_id,
  actual = test$is_fraud
)
for (model_name in names(test_probs)) {
  safe_name <- tolower(model_name)
  prediction_output[[paste0(safe_name, "_probability")]] <- test_probs[[model_name]]
  prediction_output[[paste0(safe_name, "_threshold")]] <- thresholds[[model_name]]
  prediction_output[[paste0(safe_name, "_predicted")]] <-
    as.integer(test_probs[[model_name]] >= thresholds[[model_name]])
}
readr::write_csv(prediction_output, "corrected_r/outputs/test_predictions.csv")

# Validation-selected thresholds and model artifacts for reproducibility.
readr::write_csv(
  tibble(model = names(thresholds), validation_threshold = unname(thresholds)),
  "corrected_r/outputs/validation_thresholds.csv"
)
readr::write_csv(
  tibble(feature = names(rf$variable.importance),
         permutation_importance = as.numeric(rf$variable.importance)),
  "corrected_r/outputs/rf_variable_importance.csv"
)
saveRDS(
  list(random_forest = rf, xgboost = xgb_model,
       thresholds = thresholds, predictors = predictors, seed = 2026),
  "corrected_r/outputs/models.rds"
)

print(metrics)
message("Saved model comparison, thresholds, predictions with transaction IDs, and model artifacts.")
