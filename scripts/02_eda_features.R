# =============================================================================
# FraudDetect: 02_eda_features.R — Exploratory Analysis & Feature Engineering
# =============================================================================

# Clear environment
#rm(list = ls())

library(tidyverse)

transactions <- read_csv("data/transactions.csv", show_col_types = FALSE)

dir.create("outputs", showWarnings = FALSE)

# -----------------------------------------------------------------------------
# 1. Fraud rate by merchant category
# -----------------------------------------------------------------------------
fraud_by_cat <- transactions %>%
  group_by(merchant_category) %>%
  summarise(
    n_transactions = n(),
    n_fraud        = sum(is_fraud),
    fraud_rate     = round(mean(is_fraud) * 100, 2),
    avg_amount     = round(mean(amount), 2),
    avg_risk_score = round(mean(risk_score), 2)
  ) %>%
  arrange(desc(fraud_rate))

cat("\n--- Fraud Rate by Merchant Category ---\n")
print(fraud_by_cat)
write_csv(fraud_by_cat, "outputs/fraud_by_category.csv")

# -----------------------------------------------------------------------------
# 2. Fraud rate by time of day
# -----------------------------------------------------------------------------
fraud_by_time <- transactions %>%
  group_by(time_of_day) %>%
  summarise(
    n_transactions = n(),
    fraud_rate     = round(mean(is_fraud) * 100, 2),
    avg_amount     = round(mean(amount), 2)
  ) %>%
  arrange(desc(fraud_rate))

cat("\n--- Fraud Rate by Time of Day ---\n")
print(fraud_by_time)
write_csv(fraud_by_time, "outputs/fraud_by_time.csv")

# -----------------------------------------------------------------------------
# 3. Fraud rate by geography
# -----------------------------------------------------------------------------
fraud_by_geo <- transactions %>%
  group_by(geography) %>%
  summarise(
    n_transactions = n(),
    fraud_rate     = round(mean(is_fraud) * 100, 2),
    avg_amount     = round(mean(amount), 2),
    avg_risk_score = round(mean(risk_score), 2)
  )

cat("\n--- Fraud Rate by Geography ---\n")
print(fraud_by_geo)
write_csv(fraud_by_geo, "outputs/fraud_by_geography.csv")

# -----------------------------------------------------------------------------
# 4. Risk score distribution summary
# -----------------------------------------------------------------------------
risk_summary <- transactions %>%
  group_by(is_fraud) %>%
  summarise(
    n              = n(),
    mean_risk      = round(mean(risk_score), 2),
    median_risk    = round(median(risk_score), 2),
    p90_risk       = round(quantile(risk_score, 0.90), 2),
    mean_amount    = round(mean(amount), 2)
  )

cat("\n--- Risk Score by Fraud Label ---\n")
print(risk_summary)
write_csv(risk_summary, "outputs/risk_score_summary.csv")

# -----------------------------------------------------------------------------
# 5. Anomaly flagging — transactions with |z-score| > 3
# -----------------------------------------------------------------------------
anomalies <- transactions %>%
  filter(abs(amount_zscore) > 3) %>%
  select(transaction_id, merchant_category, amount, amount_zscore,
         risk_score, is_fraud, geography, time_of_day)

cat(sprintf("\n--- Anomalies (|z| > 3): %d transactions ---\n", nrow(anomalies)))
write_csv(anomalies, "outputs/anomaly_flagged.csv")

# -----------------------------------------------------------------------------
# 6. Feature correlation summary (numeric features vs is_fraud)
# -----------------------------------------------------------------------------
feature_corr <- transactions %>%
  select(is_fraud, amount, risk_score, velocity_24h, account_age_days,
         amount_zscore, prior_fraud_flag, device_mismatch) %>%
  cor() %>%
  as.data.frame() %>%
  rownames_to_column("feature") %>%
  select(feature, is_fraud) %>%
  filter(feature != "is_fraud") %>%
  arrange(desc(abs(is_fraud))) %>%
  rename(correlation_with_fraud = is_fraud) %>%
  mutate(correlation_with_fraud = round(correlation_with_fraud, 4))

cat("\n--- Feature Correlations with Fraud Label ---\n")
print(feature_corr)
write_csv(feature_corr, "outputs/feature_correlations.csv")

cat("\nEDA complete. Outputs saved to outputs/\n")
