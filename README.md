# FraudDetect. Financial Transaction Fraud Detection & Risk Analytics

FraudDetect is an end-to-end **R portfolio project** exploring fraud classification, anomaly detection, alert-policy design, and investigation economics using simulated financial transactions. It combines statistical modeling with operational trade-offs and an interactive Shiny dashboard.

> **Data and scope:** The transaction dataset is simulated. Results demonstrate an analytical workflow, not performance on a bank's production data. Financial impact estimates use explicit illustrative assumptions and should not be interpreted as realized losses or validated business savings.

---

## Project objectives

Fraud detection is not only a classification problem. A useful alerting workflow must consider:

- How well a model separates fraudulent from legitimate transactions.
- The precision-recall trade-off when fraud is relatively uncommon.
- Whether an anomaly detector identifies cases missed by a supervised model.
- How alert volume interacts with investigation capacity.
- How review costs and assumed fraud recovery affect policy selection.

This project makes those trade-offs inspectable rather than presenting a single model score as the whole solution.

## Dataset

The project uses 10,000 simulated transactions with fields covering transaction amount, merchant category, geography, time of day, prior fraud indicators, transaction velocity, device mismatch, and account age.

The corrected modeling workflow creates mutually exclusive, stratified partitions:

| Partition | Share | Purpose |
|---|---:|---|
| Training | 60% | Fit supervised models and the Isolation Forest |
| Validation | 20% | Early stopping and decision-threshold selection |
| Test | 20% | Final held-out evaluation |

The test partition is not used to select classification or anomaly thresholds. The test results below are specific to this simulated dataset and this split.

## Corrected modeling results

The corrected pipeline compares Random Forest, XGBoost, and an equal-weight probability blend. The table reports held-out test performance using classification thresholds selected on validation data.

| Model | ROC-AUC | PR-AUC | Precision | Recall | Specificity |
|---|---:|---:|---:|---:|---:|
| Random Forest | 0.694 | 0.165 | 12.42% | 57.14% | 69.68% |
| XGBoost | **0.752** | **0.211** | **16.09%** | 56.43% | **77.85%** |
| Equal-weight blend | 0.745 | 0.190 | 15.68% | 55.00% | 77.74% |

**Interpretation:** XGBoost is the strongest of these three candidates on the reported ROC-AUC and PR-AUC results. It is retained as the primary supervised benchmark for the dashboard, not described as a production-ready fraud model. Its test operating point flags 491 transactions, including 79 fraud cases, with 412 false positives. These results illustrate why precision, recall, and alert volume should be considered alongside AUC.

## Anomaly detection and alert policies

The corrected Isolation Forest workflow:

1. Recreates the same stratified 60/20/20 split.
2. Fits Isolation Forest on training features only, without fraud labels.
3. Derives anomaly-score cutoffs from validation-score quantiles.
4. Applies the frozen cutoffs to the held-out test set.
5. Compares Isolation Forest alone with XGBoost OR Isolation Forest and XGBoost AND Isolation Forest policies.

Selected held-out test comparisons:

| Policy | Alerts | Fraud detected | False alerts | Precision | Recall |
|---|---:|---:|---:|---:|---:|
| XGBoost | 491 | 79 | 412 | 16.1% | 56.4% |
| XGBoost OR Isolation Forest, 1% validation target | 493 | 79 | 414 | 16.0% | 56.4% |
| XGBoost OR Isolation Forest, 2% validation target | 498 | 79 | 419 | 15.9% | 56.4% |
| XGBoost OR Isolation Forest, 5% validation target | 531 | 83 | 448 | 15.6% | 59.3% |
| XGBoost OR Isolation Forest, 10% validation target | 567 | 84 | 483 | 14.8% | 60.0% |

The 5% and 10% OR policies identify additional fraud cases, but also create more alerts. For example, the 5% policy detects four more fraud cases than XGBoost alone while generating 36 additional alerts. Whether that trade-off is worthwhile depends on investigation capacity and the cost of missed fraud.

The validation target percentages are used to set anomaly-score thresholds. They are not guarantees of the exact alert rate on unseen test data.

## Cost-sensitive alert analysis

The cost analysis translates alert policies into illustrative operational scenarios. Its default assumptions are:

| Assumption | Default |
|---|---:|
| Review cost per alert | 25 currency units |
| Loss severity | 100% of transaction amount for missed fraud |
| Recovery share when detected | 80% |

Transaction amount is treated as a **proxy for fraud exposure**, not observed realized loss. The estimated missed-fraud loss combines the exposure of missed fraud with the unrecovered share of detected fraud exposure. These are modeling assumptions, not measured bank costs, loss rates, or recovery outcomes.

The sensitivity analysis varies review cost per alert (5, 25, 50, and 100) and assumed recovery share (50%, 80%, and 95%). The dashboard also applies an editable investigation-capacity limit when displaying feasible policies. With the default capacity of 500 alerts, policies exceeding 500 alerts are excluded from the feasible-policy comparison.

The cost ranking is conditional on these assumptions. It should not be treated as a universal recommendation or a real-world savings estimate.

## Interactive dashboard

The dashboard source is available in [`shiny/app.R`](shiny/app.R). The analytical report source is available in [`frauddetect_report.qmd`](frauddetect_report.qmd). To generate the standalone HTML report locally, run:

```r
quarto::quarto_render("frauddetect_report.qmd")
```


The Shiny dashboard contains six sections:

1. **Executive Overview:** held-out test scope, fraud prevalence, model summary, and high-level patterns.
2. **Fraud Patterns:** fraud rates by merchant category, time of day, and geography, plus transaction amount distributions.
3. **Predictive Modeling:** test ROC-AUC and PR-AUC, model metrics, and Random Forest permutation importance.
4. **Anomaly Policies:** precision-recall trade-offs and test-set comparisons across anomaly and combined alert strategies.
5. **Financial Impact:** editable investigation capacity, cost assumptions, feasible policy comparisons, sensitivity analysis, and model limitations.
6. **Transaction Explorer:** filters and transaction-level inspection of held-out test predictions.

The dashboard reads the corrected pipeline outputs from `corrected_r/outputs/`. Run the analysis scripts before launching it.

## Repository structure

```
frauddetect/
├── data/
│   └── transactions.csv                  # Simulated input data (not committed)
├── corrected_r/
│   ├── scripts/
│   │   ├── 00_setup.R
│   │   ├── 01_modeling.R
│   │   ├── 02_anomaly_detection.R        # Earlier anomaly workflow
│   │   ├── 03_anomaly_incremental_value.R # Earlier exploratory comparison
│   │   ├── 04_optimize_anomaly_thresholds.R
│   │   └── 05_cost_sensitive_alert_optimization.R
│   └── outputs/                          # Generated analysis outputs (not committed)
├── scripts/                              # Original project scripts retained
├── shiny/
│   └── app.R                             # Corrected six-section dashboard
└── README.md
```

The original implementation is retained separately for reference. The `corrected_r/` pipeline and its outputs are the source of truth for the corrected results described in this README.

## Reproducing the corrected analysis

Run commands from the repository root. Ensure `data/transactions.csv` is present. The setup script called by the modeling script installs missing modeling packages.

```r
# 1. Generate the 10,000-row simulated dataset (if data/transactions.csv is absent)
source("scripts/01_simulate_data.R")

# 2. Fit models, select validation thresholds, and export predictions
source("corrected_r/scripts/01_modeling.R")

# 3. Fit Isolation Forest on training features and evaluate validation-derived thresholds
source("corrected_r/scripts/04_optimize_anomaly_thresholds.R")

# 4. Calculate illustrative policy costs and sensitivity scenarios
source("corrected_r/scripts/05_cost_sensitive_alert_optimization.R")

# 5. Launch the dashboard
shiny::runApp("shiny/")
```

The principal outputs are written to `corrected_r/outputs/`, including:

- `model_comparison.csv`
- `validation_predictions.csv` and `test_predictions.csv`
- `validation_thresholds.csv`
- `rf_variable_importance.csv`
- `if_validation_thresholds.csv`
- `if_threshold_policy_comparison.csv`
- `if_validation_scores.csv` and `if_test_scores.csv`
- `cost_sensitive_policy_comparison.csv`
- `cost_sensitivity_analysis.csv`
- `cost_policy_transaction_detail.csv`
- `cost_model_assumptions.csv`

## Methods and tools

- **Language:** R
- **Data preparation and visualization:** tidyverse, ggplot2
- **Supervised learning:** ranger Random Forest, XGBoost
- **Anomaly detection:** isotree Isolation Forest
- **Evaluation:** pROC, PRROC, confusion-matrix-derived metrics
- **Dashboard:** Shiny, bslib, DT

Key methodological choices include stratified data partitioning, validation-based early stopping and threshold selection, training-only anomaly-model fitting, held-out test evaluation, and explicit cost-sensitivity assumptions.

## Limitations and next improvements

- The dataset is simulated and may not reflect real fraud prevalence, feature distributions, adversarial behavior, or operational constraints.
- The test set is relatively small, so performance estimates may be uncertain and sensitive to the simulated split.
- The model features and fraud-generating process are synthetic. High feature importance does not establish a causal relationship.
- Transaction amount is only an exposure proxy. Real financial impact requires institution-specific loss, recovery, and review-cost data.
- The dashboard is an analytical demonstration, not a real-time scoring service or production case-management system.
- Further validation on temporally separated and independently sourced data would be required before operational use.

## Author

**Ludovic Njiosseu** | MS Statistics, NYU | Data Scientist & Statistician

5+ years of experience across clinical research, pharmaceuticals, statistical analysis, and data science.

Interested in risk analytics, applied machine learning, and product data science.
