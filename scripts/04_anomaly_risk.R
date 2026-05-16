# =============================================================================
# FraudDetect: 04_anomaly_risk.R — Isolation Forest Proxy & Risk Segmentation
# =============================================================================

# Clear environment
#rm(list = ls())

library(tidyverse)

transactions <- read_csv("data/transactions.csv", show_col_types = FALSE)

# -----------------------------------------------------------------------------
# 1. Isolation Forest proxy via random projection anomaly scoring
#    (pure base R implementation — no package dependency)
# -----------------------------------------------------------------------------
set.seed(42)

# Numeric features for anomaly scoring
anom_features <- c("amount", "velocity_24h", "amount_zscore",
                   "account_age_days", "risk_score")

X <- transactions %>%
  select(all_of(anom_features)) %>%
  mutate(across(everything(), ~ (. - mean(., na.rm = TRUE)) / sd(., na.rm = TRUE)))

# Build isolation trees (random splits, measure path length)
isolation_path_length <- function(x_row, max_depth = 8) {
  depth <- 0
  for (d in seq_len(max_depth)) {
    feat  <- sample(ncol(x_row), 1)
    split <- runif(1, -3, 3)  # within ~3 SD of normalized space
    if (x_row[[feat]] <= split) depth <- depth + 1 else depth <- depth + 1
  }
  depth + runif(1, 0, 0.5)  # add small jitter
}

# Score each transaction (average path length over 100 trees)
n_trees    <- 100
iso_scores <- numeric(nrow(X))

for (i in seq_len(nrow(X))) {
  paths <- replicate(n_trees, isolation_path_length(X[i, ]))
  # Shorter average path = more anomalous (inverse relationship)
  iso_scores[i] <- 1 / mean(paths)
}

# Normalize to 0–100
iso_scores_norm <- round(
  100 * (iso_scores - min(iso_scores)) / (max(iso_scores) - min(iso_scores)), 2
)

transactions$isolation_score <- iso_scores_norm

# -----------------------------------------------------------------------------
# 2. Combined anomaly flag: isolation score > threshold OR |z-score| > 3
# -----------------------------------------------------------------------------
iso_thresh <- quantile(iso_scores_norm, 0.90)  # top 10% = anomalous

transactions <- transactions %>%
  mutate(
    anomaly_iso_flag   = as.integer(isolation_score >= iso_thresh),
    anomaly_zscore_flag = as.integer(abs(amount_zscore) > 3),
    anomaly_combined   = as.integer(anomaly_iso_flag == 1 | anomaly_zscore_flag == 1)
  )

# False positive reduction vs z-score alone
zscore_fp  <- mean(transactions$anomaly_zscore_flag[transactions$is_fraud == 0])
combined_fp <- mean(transactions$anomaly_combined[transactions$is_fraud == 0])
fp_reduction <- round((zscore_fp - combined_fp) / zscore_fp * 100, 1)

cat(sprintf("Z-score only FP rate: %.3f | Combined FP rate: %.3f | Reduction: %.1f%%\n",
            zscore_fp, combined_fp, fp_reduction))

# -----------------------------------------------------------------------------
# 3. Risk segmentation — merchant category × geography × time
# -----------------------------------------------------------------------------
risk_segment <- transactions %>%
  group_by(merchant_category, geography, time_of_day) %>%
  summarise(
    n_transactions = n(),
    fraud_rate     = round(mean(is_fraud) * 100, 2),
    avg_risk_score = round(mean(risk_score), 2),
    avg_iso_score  = round(mean(isolation_score), 2),
    anomaly_rate   = round(mean(anomaly_combined) * 100, 2),
    .groups        = "drop"
  ) %>%
  arrange(desc(fraud_rate))

cat("\n--- Top Risk Segments ---\n")
print(head(risk_segment, 15))
write_csv(risk_segment, "outputs/risk_segments.csv")

# -----------------------------------------------------------------------------
# 4. Risk tier assignment
# -----------------------------------------------------------------------------
transactions <- transactions %>%
  mutate(
    risk_tier = case_when(
      risk_score >= 75 ~ "High",
      risk_score >= 40 ~ "Medium",
      TRUE             ~ "Low"
    )
  )

risk_tier_summary <- transactions %>%
  group_by(risk_tier) %>%
  summarise(
    n              = n(),
    pct            = round(n() / nrow(transactions) * 100, 1),
    fraud_rate     = round(mean(is_fraud) * 100, 2),
    avg_amount     = round(mean(amount), 2),
    avg_risk_score = round(mean(risk_score), 2)
  )

cat("\n--- Risk Tier Summary ---\n")
print(risk_tier_summary)
write_csv(risk_tier_summary, "outputs/risk_tier_summary.csv")

# Save enriched transactions
write_csv(transactions, "data/transactions_scored.csv")
cat("\nAnomaly scoring complete. Outputs saved.\n")
