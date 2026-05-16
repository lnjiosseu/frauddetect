# =============================================================================
# FraudDetect: 03_modeling.R — Logistic Regression + Random Forest + Ensemble
# =============================================================================

# Clear environment
#rm(list = ls())

library(tidyverse)
library(pROC)

transactions <- read_csv("data/transactions.csv", show_col_types = FALSE)

# -----------------------------------------------------------------------------
# 1. Prepare model matrix
# -----------------------------------------------------------------------------
model_data <- transactions %>%
  mutate(
    is_fraud          = as.factor(is_fraud),
    international     = as.integer(geography == "international"),
    is_night          = as.integer(time_of_day == "night"),
    is_high_risk_cat  = as.integer(merchant_category %in% c("ATM", "luxury", "electronics")),
    log_amount        = log1p(amount)
  ) %>%
  select(is_fraud, log_amount, international, is_night, is_high_risk_cat,
         prior_fraud_flag, velocity_24h, device_mismatch,
         account_age_days, amount_zscore)

# Train/test split (80/20)
set.seed(42)
n         <- nrow(model_data)
train_idx <- sample(seq_len(n), size = floor(0.8 * n))
train     <- model_data[train_idx, ]
test      <- model_data[-train_idx, ]

cat(sprintf("Train: %d | Test: %d | Fraud rate train: %.2f%%\n",
            nrow(train), nrow(test),
            100 * mean(train$is_fraud == "1")))

# -----------------------------------------------------------------------------
# 2. SMOTE-style oversampling (manual — no external package needed)
# -----------------------------------------------------------------------------
minority <- train %>% filter(is_fraud == "1")
majority <- train %>% filter(is_fraud == "0")

# Oversample minority to ~20% of training set
target_minority <- floor(0.20 * nrow(majority))
minority_os <- minority[sample(nrow(minority), target_minority, replace = TRUE), ]
train_bal <- bind_rows(majority, minority_os) %>% slice_sample(prop = 1)

cat(sprintf("Balanced train: %d | Fraud rate: %.2f%%\n",
            nrow(train_bal), 100 * mean(train_bal$is_fraud == "1")))

# -----------------------------------------------------------------------------
# 3. Logistic Regression
# -----------------------------------------------------------------------------
features <- c("log_amount", "international", "is_night", "is_high_risk_cat",
              "prior_fraud_flag", "velocity_24h", "device_mismatch",
              "account_age_days", "amount_zscore")

formula_lr <- as.formula(paste("is_fraud ~", paste(features, collapse = " + ")))

lr_model  <- glm(formula_lr, data = train_bal, family = binomial())
lr_probs  <- predict(lr_model, newdata = test, type = "response")
lr_roc    <- roc(as.numeric(test$is_fraud) - 1, lr_probs, quiet = TRUE)
lr_auc    <- round(auc(lr_roc), 4)

cat(sprintf("\nLogistic Regression AUC-ROC: %.4f\n", lr_auc))

# -----------------------------------------------------------------------------
# 4. Manual Random Forest (via base R — no randomForest package required)
#    Build 50 decision stumps and aggregate (bagging approximation)
# -----------------------------------------------------------------------------
build_stump <- function(data, features) {
  best_feat  <- NULL; best_thresh <- NULL; best_gini <- Inf
  y <- as.integer(data$is_fraud) - 1
  for (feat in features) {
    vals    <- data[[feat]]
    threshs <- quantile(vals, probs = seq(0.1, 0.9, by = 0.1), na.rm = TRUE)
    for (thr in unique(threshs)) {
      left  <- y[vals <= thr]; right <- y[vals > thr]
      if (length(left) == 0 | length(right) == 0) next
      gini_left  <- 1 - sum((table(left)  / length(left))^2)
      gini_right <- 1 - sum((table(right) / length(right))^2)
      gini_w     <- (length(left) * gini_left + length(right) * gini_right) / length(y)
      if (gini_w < best_gini) {
        best_gini <- gini_w; best_feat <- feat; best_thresh <- thr
      }
    }
  }
  list(feature = best_feat, threshold = best_thresh)
}

predict_stump <- function(stump, data) {
  vals   <- data[[stump$feature]]
  left_p <- mean(as.integer(
    train_bal$is_fraud[train_bal[[stump$feature]] <= stump$threshold]) - 1)
  right_p <- mean(as.integer(
    train_bal$is_fraud[train_bal[[stump$feature]] > stump$threshold]) - 1)
  ifelse(vals <= stump$threshold, left_p, right_p)
}

set.seed(42)
n_trees   <- 50
boot_preds <- matrix(0, nrow = nrow(test), ncol = n_trees)
stumps     <- vector("list", n_trees)

for (i in seq_len(n_trees)) {
  boot_idx   <- sample(nrow(train_bal), replace = TRUE)
  boot_data  <- train_bal[boot_idx, ]
  feat_sub   <- sample(features, size = max(2, floor(sqrt(length(features)))))
  stump      <- build_stump(boot_data, feat_sub)
  stumps[[i]] <- stump
  boot_preds[, i] <- predict_stump(stump, test)
}

rf_probs <- rowMeans(boot_preds)
rf_roc   <- roc(as.numeric(test$is_fraud) - 1, rf_probs, quiet = TRUE)
rf_auc   <- round(auc(rf_roc), 4)

cat(sprintf("Bagged Stumps (RF proxy) AUC-ROC: %.4f\n", rf_auc))

# -----------------------------------------------------------------------------
# 5. Ensemble: average LR + RF probabilities
# -----------------------------------------------------------------------------
ensemble_probs <- (lr_probs + rf_probs) / 2
ens_roc  <- roc(as.numeric(test$is_fraud) - 1, ensemble_probs, quiet = TRUE)
ens_auc  <- round(auc(ens_roc), 4)

cat(sprintf("Ensemble AUC-ROC: %.4f\n", ens_auc))

# -----------------------------------------------------------------------------
# 6. Optimal threshold (Youden's J)
# -----------------------------------------------------------------------------
youden_idx  <- which.max(ens_roc$sensitivities + ens_roc$specificities - 1)
opt_thresh  <- round(ens_roc$thresholds[youden_idx], 4)
sensitivity <- round(ens_roc$sensitivities[youden_idx], 4)
specificity <- round(ens_roc$specificities[youden_idx], 4)

cat(sprintf("Optimal threshold: %.4f | Sensitivity: %.4f | Specificity: %.4f\n",
            opt_thresh, sensitivity, specificity))

# Confusion matrix at optimal threshold
preds_binary <- as.integer(ensemble_probs >= opt_thresh)
cm <- table(Predicted = preds_binary, Actual = as.integer(test$is_fraud) - 1)
cat("\nConfusion Matrix:\n")
print(cm)

# False positive rate vs rule-based baseline (flag all >$500)
rule_preds <- as.integer(test$log_amount > log1p(500))
rule_fp_rate    <- mean(rule_preds[as.integer(test$is_fraud) - 1 == 0])
model_fp_rate   <- mean(preds_binary[as.integer(test$is_fraud) - 1 == 0])
fp_reduction    <- round((rule_fp_rate - model_fp_rate) / rule_fp_rate * 100, 1)

cat(sprintf("\nFalse Positive Rate — Rule-based: %.3f | Model: %.3f | Reduction: %.1f%%\n",
            rule_fp_rate, model_fp_rate, fp_reduction))

# -----------------------------------------------------------------------------
# 7. Feature importance (logistic regression coefficients)
# -----------------------------------------------------------------------------
coef_tbl <- tibble(
  feature    = names(coef(lr_model))[-1],
  coefficient = round(coef(lr_model)[-1], 4),
  odds_ratio  = round(exp(coef(lr_model)[-1]), 4)
) %>% arrange(desc(abs(coefficient)))

cat("\n--- Feature Importance (LR Coefficients) ---\n")
print(coef_tbl)
write_csv(coef_tbl, "outputs/feature_importance.csv")

# -----------------------------------------------------------------------------
# 8. Save model results
# -----------------------------------------------------------------------------
model_results <- tibble(
  model       = c("Logistic Regression", "Bagged Stumps (RF)", "Ensemble"),
  auc_roc     = c(lr_auc, rf_auc, ens_auc)
)
write_csv(model_results, "outputs/model_results.csv")

# Save test predictions for dashboard
test_preds <- test %>%
  mutate(
    lr_prob       = lr_probs,
    rf_prob       = rf_probs,
    ensemble_prob = ensemble_probs,
    flagged_fraud = preds_binary
  )
write_csv(test_preds, "outputs/test_predictions.csv")

# Save key metrics
metrics <- tibble(
  metric = c("Ensemble AUC-ROC", "Optimal Threshold", "Sensitivity",
             "Specificity", "FP Rate Reduction vs Baseline"),
  value  = c(ens_auc, opt_thresh, sensitivity, specificity,
             paste0(fp_reduction, "%"))
)
write_csv(metrics, "outputs/key_metrics.csv")

cat("\nModeling complete. Outputs saved to outputs/\n")
