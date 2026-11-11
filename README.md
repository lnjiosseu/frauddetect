# FraudDetect: Financial Transaction Fraud Detection & Risk Analytics

An R portfolio project exploring supervised fraud classification, anomaly detection, alert-policy design, and investigation economics using **simulated financial transactions**.

> **Scope:** The dataset is synthetic. Results are a methodological demonstration, not evidence of performance on bank production data. Cost estimates depend on explicit illustrative assumptions and are not realized savings.

## Corrected dataset and evaluation

The corrected workflow evaluates 10,000 simulated transactions, with a stratified 60/20/20 train/validation/test split. The held-out test set contains 2,000 transactions. Thresholds are selected using validation data, not the test set.

## Held-out test results

| Model | ROC-AUC | PR-AUC | Precision | Recall | Specificity |
|---|---:|---:|---:|---:|---:|
| Random Forest | 0.694 | 0.165 | 12.42% | 57.14% | 69.68% |
| XGBoost | **0.752** | **0.211** | **16.09%** | 56.43% | **77.85%** |
| Equal-weight blend | 0.745 | 0.190 | 15.68% | 55.00% | 77.74% |

XGBoost has the strongest ROC-AUC and PR-AUC among the three reported candidates. At its validation-selected operating threshold, it flags 491 test transactions: 79 true positives and 412 false positives. This is a high-alert-volume operating point, not a production recommendation.

The previous README claims of approximately 0.94 ensemble AUC and 31% false-positive-rate reduction are withdrawn. The original implementation used logistic regression and bagged decision stumps, not true Random Forest or XGBoost. Its anomaly scoring was a pedagogical proxy and did not support the claimed false-positive reduction.

## Anomaly policies

The corrected Isolation Forest workflow fits on training features, derives score cutoffs from validation data, and evaluates frozen policies on the held-out test set.

| Test policy | Alerts | Fraud detected | False alerts | Precision | Recall |
|---|---:|---:|---:|---:|---:|
| XGBoost | 491 | 79 | 412 | 16.1% | 56.4% |
| XGBoost OR Isolation Forest, 1% validation target | 493 | 79 | 414 | 16.0% | 56.4% |
| XGBoost OR Isolation Forest, 2% validation target | 498 | 79 | 419 | 15.9% | 56.4% |
| XGBoost OR Isolation Forest, 5% validation target | 531 | 83 | 448 | 15.6% | 59.3% |
| XGBoost OR Isolation Forest, 10% validation target | 567 | 84 | 483 | 14.8% | 60.0% |

The broader OR policies detect more fraud at the cost of additional false alerts. The target percentages define validation score cutoffs; they do not guarantee the same alert rate on test data.

## Cost-sensitive analysis

The corrected cost model uses illustrative assumptions: 25 currency units per alert review, loss severity equal to 100% of transaction amount for missed fraud, and an 80% recovery share when detected. Transaction amount is an exposure proxy, not an observed loss. The resulting rankings are conditional scenario analyses, not measured bank economics.

## Dashboard and report

The corrected six-section Shiny dashboard is in `shiny/app.R` on `main` and reads generated files from `corrected_r/outputs/`. Run the corrected scripts before launching it. The original four-tab dashboard remains available on the audit branch as a historical implementation and should not be used to present corrected metrics.

The Quarto source on this branch documents the corrected analysis. Render locally after running the corrected pipeline:

```r
quarto::quarto_render("frauddetect_report.qmd")
```

## Reproduce the corrected workflow

From the repository root, ensure `data/transactions.csv` exists. Then run:

```r
source("scripts/01_simulate_data.R")
source("corrected_r/scripts/01_modeling.R")
source("corrected_r/scripts/04_optimize_anomaly_thresholds.R")
source("corrected_r/scripts/05_cost_sensitive_alert_optimization.R")
shiny::runApp("shiny/")
```

The corrected pipeline writes generated files to `corrected_r/outputs/`. These outputs are generated locally and are not committed.

## Limitations

- All data are simulated. Performance may not generalize to real transaction streams.
- Test estimates are based on a 2,000-row held-out sample and may be uncertain.
- Synthetic feature importance is not causal evidence.
- Review cost, loss severity, and recovery assumptions require institution-specific calibration.
- The dashboard is an analytical demonstration, not a real-time scoring or case-management service.

## Author

**Ludovic Njiosseu** | MPH (Biostatistics), NYU | Data Scientist & Statistician
