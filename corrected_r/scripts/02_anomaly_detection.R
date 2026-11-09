source("corrected_r/scripts/00_setup.R")
library(tidyverse); library(isotree)
dir.create("corrected_r/outputs",recursive=TRUE,showWarnings=FALSE)
d <- read_csv("data/transactions.csv",show_col_types=FALSE)
x <- d |> transmute(log_amount=log1p(amount),velocity_24h,account_age_days,
                    amount_zscore,device_mismatch,prior_fraud_flag)
iso <- isolation.forest(x,ntrees=500,sample_size=min(256,nrow(x)),ndim=1,nthreads=1)
s <- predict(iso,x,type="score")
out <- d |> mutate(anomaly_score=as.numeric(s),
                   anomaly_percentile=percent_rank(anomaly_score),
                   top_decile_anomaly=anomaly_percentile>=.90)
write_csv(out,"corrected_r/outputs/anomaly_scores.csv")
