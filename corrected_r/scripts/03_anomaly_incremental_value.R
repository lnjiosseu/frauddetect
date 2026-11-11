# Incremental value of Isolation Forest over XGBoost
# Run from repository root after scripts 01_modeling.R and 02_anomaly_detection.R.
# Compares anomaly flags on exactly the same held-out test transactions.

library(tidyverse)

pred_path <- "corrected_r/outputs/test_predictions.csv"
anomaly_path <- "corrected_r/outputs/anomaly_scores.csv"
out_dir <- "corrected_r/outputs"

if (!file.exists(pred_path)) stop("Missing test_predictions.csv. Run 01_modeling.R first.")
if (!file.exists(anomaly_path)) stop("Missing anomaly_scores.csv. Run 02_anomaly_detection.R first.")

pred <- readr::read_csv(pred_path, show_col_types = FALSE)
anomaly <- readr::read_csv(anomaly_path, show_col_types = FALSE)

required_pred <- c("transaction_id", "actual", "xgboost_predicted",
                   "xgboost_probability")
required_anomaly <- c("transaction_id", "anomaly_score",
                      "anomaly_percentile", "top_decile_anomaly")
if (length(setdiff(required_pred, names(pred)))) {
  stop("test_predictions.csv is missing required fields.")
}
if (length(setdiff(required_anomaly, names(anomaly)))) {
  stop("anomaly_scores.csv is missing required fields.")
}
if (anyDuplicated(pred$transaction_id) || anyDuplicated(anomaly$transaction_id)) {
  stop("Duplicate transaction_id values detected; refusing a many-to-many join.")
}

matched <- pred |>
  inner_join(anomaly |> select(all_of(required_anomaly)),
             by = "transaction_id")

if (nrow(matched) != nrow(pred)) {
  stop("Not all held-out transactions matched to anomaly scores. Check IDs and data versions.")
}

matched <- matched |>
  mutate(
    actual = as.integer(actual),
    xgboost_predicted = as.integer(xgboost_predicted),
    anomaly_flag = as.logical(top_decile_anomaly),
    either_flag = xgboost_predicted == 1L | anomaly_flag,
    both_flag = xgboost_predicted == 1L & anomaly_flag
  )

evaluate_flags <- function(data, flag, label) {
  y <- data$actual
  p <- data[[flag]]
  tp <- sum(p & y == 1L)
  fp <- sum(p & y == 0L)
  tn <- sum(!p & y == 0L)
  fn <- sum(!p & y == 1L)
  tibble(
    strategy = label,
    transactions_flagged = sum(p),
    true_positives = tp,
    false_positives = fp,
    true_negatives = tn,
    false_negatives = fn,
    precision = ifelse(tp + fp > 0, tp / (tp + fp), NA_real_),
    recall = ifelse(tp + fn > 0, tp / (tp + fn), NA_real_),
    specificity = ifelse(tn + fp > 0, tn / (tn + fp), NA_real_),
    false_positive_rate = ifelse(fp + tn > 0, fp / (fp + tn), NA_real_)
  )
}

comparison <- bind_rows(
  evaluate_flags(matched, "xgboost_predicted", "XGBoost"),
  evaluate_flags(matched, "anomaly_flag", "Isolation Forest top decile"),
  evaluate_flags(matched, "either_flag", "XGBoost OR Isolation Forest"),
  evaluate_flags(matched, "both_flag", "XGBoost AND Isolation Forest")
)

xgb_misses <- matched |>
  filter(actual == 1L, xgboost_predicted == 0L)
incremental <- xgb_misses |>
  summarise(
    fraud_missed_by_xgboost = n(),
    additional_fraud_flagged_by_isolation_forest = sum(anomaly_flag),
    share_of_xgboost_missed_fraud_recovered =
      ifelse(n() > 0, sum(anomaly_flag) / n(), NA_real_)
  )

xgb_negative_alerts <- matched |>
  filter(xgboost_predicted == 0L, anomaly_flag)
incremental_alerts <- xgb_negative_alerts |>
  summarise(
    additional_alerts = n(),
    additional_fraud_cases = sum(actual == 1L),
    additional_false_alerts = sum(actual == 0L),
    incremental_alert_precision =
      ifelse(n() > 0, sum(actual == 1L) / n(), NA_real_)
  )

readr::write_csv(comparison, file.path(out_dir, "anomaly_incremental_comparison.csv"))
readr::write_csv(incremental, file.path(out_dir, "anomaly_fraud_recovery.csv"))
readr::write_csv(incremental_alerts, file.path(out_dir, "anomaly_incremental_alerts.csv"))
readr::write_csv(
  matched |> select(transaction_id, actual, xgboost_probability,
                    xgboost_predicted, anomaly_score, anomaly_percentile,
                    anomaly_flag),
  file.path(out_dir, "xgboost_anomaly_matched_test.csv")
)

print(comparison)
cat("\nFraud recovery among XGBoost misses:\n")
print(incremental)
cat("\nAdditional alerts created by anomaly detection:\n")
print(incremental_alerts)
