# Cost-sensitive fraud alert policy analysis
# Run after 01_modeling.R and 04_optimize_anomaly_thresholds.R.
# IMPORTANT: transaction amount is used as a proxy for fraud exposure, not
# observed realized loss. Replace assumptions below with institution-specific
# estimates before making operational decisions.

library(tidyverse)

data_path <- "data/transactions.csv"
score_path <- "corrected_r/outputs/if_test_scores.csv"
threshold_path <- "corrected_r/outputs/if_validation_thresholds.csv"
out_dir <- "corrected_r/outputs"

# ---------------- USER-EDITABLE BUSINESS ASSUMPTIONS ----------------
# Illustrative defaults only. These are not estimates from the simulated data.
cost_per_alert_review <- 25       # currency units per alert investigated
loss_severity <- 1.00             # share of transaction amount lost if fraud is missed
recovery_share_when_detected <- 0.80 # share of exposure prevented/recovered after detection
# --------------------------------------------------------------------

required_files <- c(data_path, score_path, threshold_path)
missing_files <- required_files[!file.exists(required_files)]
if (length(missing_files)) {
  stop("Missing required file(s): ", paste(missing_files, collapse = ", "),
       ". Run 01_modeling.R and 04_optimize_anomaly_thresholds.R first.")
}

raw <- readr::read_csv(data_path, show_col_types = FALSE)
scores <- readr::read_csv(score_path, show_col_types = FALSE)
thresholds <- readr::read_csv(threshold_path, show_col_types = FALSE)

if (!all(c("transaction_id", "amount") %in% names(raw))) {
  stop("Source data must contain transaction_id and amount.")
}
if (!all(c("transaction_id", "actual", "anomaly_score",
           "xgboost_predicted") %in% names(scores))) {
  stop("if_test_scores.csv is missing required columns.")
}
if (anyDuplicated(raw$transaction_id) || anyDuplicated(scores$transaction_id)) {
  stop("Duplicate transaction IDs found. Cost analysis requires one row per transaction.")
}
if (!all(c("target_validation_alert_rate", "anomaly_threshold") %in% names(thresholds))) {
  stop("if_validation_thresholds.csv is missing required columns.")
}
if (any(!is.finite(raw$amount)) || any(raw$amount < 0, na.rm = TRUE)) {
  stop("Transaction amounts must be finite and non-negative.")
}

test <- scores |>
  mutate(transaction_id = as.character(transaction_id)) |>
  left_join(raw |>
              transmute(transaction_id = as.character(transaction_id),
                        transaction_amount = amount),
            by = "transaction_id")

if (nrow(test) != nrow(scores) || anyNA(test$transaction_amount)) {
  stop("Could not match every test score to a transaction amount.")
}
if (anyNA(test$actual) || anyNA(test$xgboost_predicted) ||
    anyNA(test$anomaly_score)) {
  stop("Missing labels, predictions, or anomaly scores in test data.")
}

# Construct policies using thresholds selected from validation data.
policy_rows <- list()
add_policy <- function(label, flag, target = NA_real_) {
  policy_rows[[length(policy_rows) + 1L]] <<- test |>
    transmute(
      transaction_id, actual = as.integer(actual),
      transaction_amount,
      alert = as.logical(flag),
      strategy = label,
      target_validation_alert_rate = target
    )
}

xgb_flag <- as.integer(test$xgboost_predicted) == 1L
add_policy("XGBoost", xgb_flag)

for (i in seq_len(nrow(thresholds))) {
  target <- thresholds$target_validation_alert_rate[i]
  cutoff <- thresholds$anomaly_threshold[i]
  if_flag <- test$anomaly_score >= cutoff
  pct <- format(target * 100, trim = TRUE, scientific = FALSE)
  add_policy(paste0("Isolation_Forest_top_", pct, "pct"), if_flag, target)
  add_policy(paste0("XGBoost_OR_IF_top_", pct, "pct"),
             xgb_flag | if_flag, target)
  add_policy(paste0("XGBoost_AND_IF_top_", pct, "pct"),
             xgb_flag & if_flag, target)
}

policies <- bind_rows(policy_rows) |>
  mutate(
    outcome = case_when(
      actual == 1L & alert ~ "true_positive",
      actual == 0L & alert ~ "false_positive",
      actual == 1L & !alert ~ "false_negative",
      TRUE ~ "true_negative"
    )
  )

summarise_cost <- function(dat, review_cost, severity, recovery_share) {
  dat |>
    group_by(strategy, target_validation_alert_rate) |>
    summarise(
      n = n(),
      alerts = sum(alert),
      true_positives = sum(outcome == "true_positive"),
      false_positives = sum(outcome == "false_positive"),
      false_negatives = sum(outcome == "false_negative"),
      missed_fraud_exposure = sum(transaction_amount[outcome == "false_negative"]),
      detected_fraud_exposure = sum(transaction_amount[outcome == "true_positive"]),
      total_alert_review_cost = alerts * review_cost,
      estimated_missed_fraud_loss =
        missed_fraud_exposure * severity +
        detected_fraud_exposure * severity * (1 - recovery_share),
      estimated_total_cost = total_alert_review_cost +
        estimated_missed_fraud_loss,
      .groups = "drop"
    ) |>
    mutate(
      review_cost_per_alert = review_cost,
      loss_severity = severity,
      recovery_share_when_detected = recovery_share,
      estimated_cost_per_test_transaction = estimated_total_cost / n
    )
}

base_costs <- summarise_cost(
  policies, cost_per_alert_review, loss_severity,
  recovery_share_when_detected
) |>
  arrange(estimated_total_cost)

# Sensitivity analysis: vary review cost and assumed recovery after detection.
sensitivity <- tidyr::crossing(
  review_cost_per_alert = c(5, 25, 50, 100),
  recovery_share_when_detected = c(0.50, 0.80, 0.95)
) |>
  mutate(results = purrr::map2(
    review_cost_per_alert, recovery_share_when_detected,
    ~ summarise_cost(policies, .x, loss_severity, .y)
  )) |>
  select(-review_cost_per_alert, -recovery_share_when_detected) |>
  unnest(results)

# Per-policy operational details, including exposure totals, for auditability.
readr::write_csv(base_costs, file.path(out_dir, "cost_sensitive_policy_comparison.csv"))
readr::write_csv(sensitivity, file.path(out_dir, "cost_sensitivity_analysis.csv"))
readr::write_csv(policies, file.path(out_dir, "cost_policy_transaction_detail.csv"))

assumptions <- tibble(
  assumption = c("cost_per_alert_review", "loss_severity",
                 "recovery_share_when_detected",
                 "transaction_amount_interpretation"),
  value = c(as.character(cost_per_alert_review),
            as.character(loss_severity),
            as.character(recovery_share_when_detected),
            "Transaction amount is a proxy for exposure, not observed realized loss.")
)
readr::write_csv(assumptions, file.path(out_dir, "cost_model_assumptions.csv"))

cat("\nIllustrative business assumptions:\n")
print(assumptions)
cat("\nCost comparison, sorted from lowest estimated cost:\n")
print(base_costs, n = Inf, width = Inf)
cat("\nSensitivity analysis:\n")
print(sensitivity, n = Inf, width = Inf)
message("Saved cost-sensitive policy comparison, sensitivity analysis, assumptions, and transaction-level details.")
