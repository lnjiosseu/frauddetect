# FraudDetect: Corrected R Baseline

This folder is separate from the original implementation. Original scripts, Shiny app, report, and historical outputs remain unchanged.

## Data and claims
The supplied project uses 10,000 simulated transactions. Do not describe this repository as 590K+ transactions unless a separate auditable dataset and analysis are supplied. Historical saved ensemble AUC is 0.8256, not the approximately 0.94 previously advertised. Historical false-positive results do not support the claimed reduction.

## Corrected methodology
- Stratified train/validation/test split.
- Training-only class weighting.
- Genuine Random Forest via `ranger`.
- Genuine gradient boosting via `xgboost`.
- Validation-only threshold selection, final evaluation on untouched test set.
- ROC-AUC, PR-AUC, precision, recall, specificity, FPR, confusion matrix.
- Genuine Isolation Forest via `isotree`.
- New outputs written only to `corrected_r/outputs/`.

## Run
From repository root, put `transactions.csv` in `data/`, install packages with `source("corrected_r/scripts/00_setup.R")`, then run `source("corrected_r/scripts/01_modeling.R")` and `source("corrected_r/scripts/02_anomaly_detection.R")`.

No corrected performance metrics are claimed until these scripts are executed and independently checked.
