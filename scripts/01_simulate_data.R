# =============================================================================
# FraudDetect: Financial Transaction Fraud Detection & Risk Analytics
# 01_simulate_data.R — Simulate transaction dataset
# =============================================================================

# Clear environment
rm(list = ls())

set.seed(42)
library(tidyverse)

N <- 10000  # transactions

# Merchant categories
merchant_cats <- c("grocery", "electronics", "travel", "restaurant",
                   "gas_station", "online_retail", "ATM", "luxury")

# Time of day buckets
time_buckets <- c("morning", "afternoon", "evening", "night")

# Simulate base features
transactions <- tibble(
  transaction_id   = paste0("TXN", str_pad(1:N, 6, pad = "0")),
  amount           = round(abs(rnorm(N, mean = 120, sd = 200)), 2),
  merchant_category = sample(merchant_cats, N, replace = TRUE,
                             prob = c(0.20, 0.10, 0.08, 0.18, 0.12, 0.15, 0.10, 0.07)),
  time_of_day      = sample(time_buckets, N, replace = TRUE,
                            prob = c(0.20, 0.30, 0.30, 0.20)),
  geography        = sample(c("domestic", "international"), N, replace = TRUE,
                            prob = c(0.82, 0.18)),
  account_age_days = round(runif(N, 30, 3650)),
  prior_fraud_flag = rbinom(N, 1, 0.04),
  velocity_24h     = rpois(N, lambda = 3),
  device_mismatch  = rbinom(N, 1, 0.08)
)

# Fraud probability — higher for: high amount, night, international, device mismatch, prior flag
fraud_logit <- with(transactions,
  -5.5 +
  0.004  * amount +
  0.8    * (time_of_day == "night") +
  1.2    * (geography == "international") +
  1.5    * prior_fraud_flag +
  0.3    * velocity_24h +
  1.8    * device_mismatch +
  0.6    * (merchant_category %in% c("ATM", "luxury"))
)

fraud_prob <- plogis(fraud_logit)
transactions$is_fraud <- rbinom(N, 1, fraud_prob)

# Risk score (continuous, 0–100) — correlated with fraud probability
transactions$risk_score <- round(
  pmin(100, pmax(0, 100 * fraud_prob + rnorm(N, 0, 5))), 1
)

# Anomaly z-score based on amount deviation within merchant category
transactions <- transactions %>%
  group_by(merchant_category) %>%
  mutate(
    cat_mean_amount = mean(amount),
    cat_sd_amount   = sd(amount),
    amount_zscore   = round((amount - cat_mean_amount) / cat_sd_amount, 3)
  ) %>%
  ungroup()

cat(sprintf("Dataset: %d transactions | Fraud rate: %.2f%%\n",
            N, 100 * mean(transactions$is_fraud)))

dir.create("data", showWarnings = FALSE)
write_csv(transactions, "data/transactions.csv")
cat("Saved: data/transactions.csv\n")
