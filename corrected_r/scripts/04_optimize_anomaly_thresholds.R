# Leakage-safe Isolation Forest threshold analysis
# Run after corrected_r/scripts/01_modeling.R has generated validation_predictions.csv
# and test_predictions.csv. Fits Isolation Forest on training rows only.
# Thresholds are set from validation-score quantiles, then frozen for test evaluation.

library(tidyverse)
library(isotree)

data_path <- "data/transactions.csv"
validation_path <- "corrected_r/outputs/validation_predictions.csv"
test_path <- "corrected_r/outputs/test_predictions.csv"
out_dir <- "corrected_r/outputs"

if (!file.exists(data_path)) stop("Missing data/transactions.csv.")
if (!file.exists(validation_path)) {
  stop("Missing validation_predictions.csv. Download the updated 01_modeling.R and rerun it.")
}
if (!file.exists(test_path)) stop("Missing test_predictions.csv. Run 01_modeling.R first.")

raw <- readr::read_csv(data_path, show_col_types = FALSE)
validation_pred <- readr::read_csv(validation_path, show_col_types = FALSE)
test_pred <- readr::read_csv(test_path, show_col_types = FALSE)

required <- c("transaction_id", "is_fraud", "amount", "velocity_24h",
              "account_age_days", "amount_zscore", "device_mismatch",
              "prior_fraud_flag")
if (length(setdiff(required, names(raw)))) {
  stop("The source data is missing required columns.")
}
if (anyDuplicated(raw$transaction_id)) stop("Duplicate transaction IDs in source data.")

d <- raw |>
  mutate(is_fraud = as.integer(is_fraud)) |>
  select(all_of(required)) |>
  drop_na()

# Recreate exactly the stratified 60/20/20 split used by 01_modeling.R.
set.seed(2026)
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

# Fit only on training features. Fraud labels are not supplied to Isolation Forest.
make_features <- function(x) {
  x |>
    transmute(
      log_amount = log1p(amount),
      velocity_24h,
      account_age_days,
      amount_zscore,
      device_mismatch,
      prior_fraud_flag
    )
}
iso_train <- make_features(train)
iso_valid <- make_features(validation)
iso_test <- make_features(test)

set.seed(2026)
iso_model <- isotree::isolation.forest(
  iso_train,
  ntrees = 500,
  sample_size = min(256L, nrow(iso_train)),
  ndim = 1,
  nthreads = 1
)

valid_score <- as.numeric(predict(iso_model, iso_valid, type = "score"))
test_score <- as.numeric(predict(iso_model, iso_test, type = "score"))

# Verify the independently reconstructed split aligns with the model exports.
if (!identical(as.character(validation$transaction_id),
               as.character(validation_pred$transaction_id))) {
  validation_pred <- validation_pred |>
    mutate(transaction_id = as.character(transaction_id))
  validation <- validation |>
    mutate(transaction_id = as.character(transaction_id))
}
if (!setequal(as.character(validation$transaction_id),
              as.character(validation_pred$transaction_id))) {
  stop("Validation IDs do not match the model export. Rerun modeling and this script.")
}
if (!setequal(as.character(test$transaction_id),
              as.character(test_pred$transaction_id))) {
  stop("Test IDs do not match the model export. Rerun modeling and this script.")
}

valid_scored <- validation |>
  transmute(transaction_id = as.character(transaction_id),
            actual = is_fraud, anomaly_score = valid_score) |>
  left_join(validation_pred |>
              mutate(transaction_id = as.character(transaction_id)) |>
              select(transaction_id, xgboost_predicted, xgboost_probability),
            by = "transaction_id")
test_scored <- test |>
  transmute(transaction_id = as.character(transaction_id),
            actual = is_fraud, anomaly_score = test_score) |>
  left_join(test_pred |>
              mutate(transaction_id = as.character(transaction_id)) |>
              select(transaction_id, xgboost_predicted, xgboost_probability),
            by = "transaction_id")

if (anyNA(valid_scored$xgboost_predicted) || anyNA(test_scored$xgboost_predicted)) {
  stop("Some XGBoost predictions did not match the recreated split.")
}

# Thresholds are determined from validation score quantiles only.
alert_targets <- c(0.01, 0.02, 0.05, 0.10)
thresholds <- tibble(
  target_validation_alert_rate = alert_targets,
  anomaly_threshold = purrr::map_dbl(
    alert_targets,
    ~ as.numeric(stats::quantile(valid_scored$anomaly_score,
                                 probs = 1 - .x, na.rm = TRUE, type = 1))
  )
)

evaluate <- function(dat, flag, split_name, strategy, target_rate = NA_real_,
                     threshold = NA_real_) {
  actual <- dat$actual == 1L
  predicted <- flag
  tp <- sum(predicted & actual)
  fp <- sum(predicted & !actual)
  tn <- sum(!predicted & !actual)
  fn <- sum(!predicted & actual)
  tibble(
    split = split_name,
    strategy = strategy,
    target_validation_alert_rate = target_rate,
    anomaly_threshold = threshold,
    n = nrow(dat),
    alerts = sum(predicted),
    true_positives = tp,
    false_positives = fp,
    true_negatives = tn,
    false_negatives = fn,
    precision = ifelse(tp + fp > 0, tp / (tp + fp), NA_real_),
    recall = ifelse(tp + fn > 0, tp / (tp + fn), NA_real_),
    specificity = ifelse(tn + fp > 0, tn / (tn + fp), NA_real_),
    false_positive_rate = ifelse(tn + fp > 0, fp / (tn + fp), NA_real_),
    f1 = ifelse(2 * tp + fp + fn > 0, 2 * tp / (2 * tp + fp + fn), NA_real_)
  )
}

results <- list()
for (i in seq_len(nrow(thresholds))) {
  target <- thresholds$target_validation_alert_rate[i]
  cutoff <- thresholds$anomaly_threshold[i]

  for (split_name in c("validation", "test")) {
    dat <- if (split_name == "validation") valid_scored else test_scored
    anomaly_flag <- dat$anomaly_score >= cutoff
    xgb_flag <- as.integer(dat$xgboost_predicted) == 1L

    results[[length(results) + 1L]] <-
      evaluate(dat, anomaly_flag, split_name,
               paste0("Isolation_Forest_top_", target * 100, "pct"),
               target, cutoff)
    results[[length(results) + 1L]] <-
      evaluate(dat, xgb_flag, split_name, "XGBoost", target, cutoff)
    results[[length(results) + 1L]] <-
      evaluate(dat, xgb_flag | anomaly_flag, split_name,
               paste0("XGBoost_OR_IF_top_", target * 100, "pct"),
               target, cutoff)
    results[[length(results) + 1L]] <-
      evaluate(dat, xgb_flag & anomaly_flag, split_name,
               paste0("XGBoost_AND_IF_top_", target * 100, "pct"),
               target, cutoff)
  }
}

comparison <- bind_rows(results)
readr::write_csv(thresholds, file.path(out_dir, "if_validation_thresholds.csv"))
readr::write_csv(comparison, file.path(out_dir, "if_threshold_policy_comparison.csv"))
readr::write_csv(
  valid_scored |> mutate(split = "validation"),
  file.path(out_dir, "if_validation_scores.csv")
)
readr::write_csv(
  test_scored |> mutate(split = "test"),
  file.path(out_dir, "if_test_scores.csv")
)
saveRDS(iso_model, file.path(out_dir, "isolation_forest_train_only.rds"))

cat("\nValidation-derived anomaly thresholds:\n")
print(thresholds)
cat("\nValidation and untouched test performance by alert policy:\n")
print(comparison)
message("Saved validation-derived thresholds and leakage-safe test comparisons.")
