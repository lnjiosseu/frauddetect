# Corrected R Baseline

This directory contains the audited R analysis pipeline. The original scripts are retained in `scripts/` for historical reference; the corrected pipeline writes its outputs to `corrected_r/outputs/`.

## Data

The analysis uses 10,000 simulated financial transactions. The dataset is synthetic and does not represent transactions from a financial institution. Place the generated/source file at `data/transactions.csv`.

## Pipeline

Run the following scripts in order from the repository root:

1. `scripts/00_setup.R` is sourced by the modeling script to install missing packages.
2. `scripts/01_modeling.R` creates a stratified 60/20/20 train/validation/test split, fits a weighted Random Forest (`ranger`) and XGBoost model, selects thresholds on validation data, and evaluates models on the held-out test set.
3. `scripts/04_optimize_anomaly_thresholds.R` fits Isolation Forest (`isotree`) on training features only, derives score thresholds from validation data, and evaluates alert policies on validation and test sets.
4. `scripts/05_cost_sensitive_alert_optimization.R` estimates alert-review and missed-fraud exposure costs under explicit user-editable assumptions, and runs a sensitivity analysis.

```r
source("corrected_r/scripts/01_modeling.R")
source("corrected_r/scripts/04_optimize_anomaly_thresholds.R")
source("corrected_r/scripts/05_cost_sensitive_alert_optimization.R")
```

## Methodological safeguards

- The train, validation, and test partitions are mutually exclusive and stratified.
- Supervised model fitting and class weighting use training data.
- XGBoost early stopping and classification thresholds use validation data.
- Isolation Forest is fitted on training features without fraud labels.
- Anomaly thresholds are selected from validation-score quantiles.
- Final model and anomaly-policy metrics are evaluated on held-out test records.
- Cost estimates use transaction amount as an exposure proxy, not observed realized loss.

## Principal outputs

The scripts write the following files to `corrected_r/outputs/`:

- `model_comparison.csv`
- `validation_predictions.csv`, `test_predictions.csv`
- `validation_thresholds.csv`
- `rf_variable_importance.csv`
- `if_validation_thresholds.csv`
- `if_threshold_policy_comparison.csv`
- `if_validation_scores.csv`, `if_test_scores.csv`
- `cost_sensitive_policy_comparison.csv`
- `cost_sensitivity_analysis.csv`
- `cost_policy_transaction_detail.csv`
- `cost_model_assumptions.csv`

Launch the Shiny dashboard from the repository root after generating all outputs:

```r
shiny::runApp("shiny/")
```

## Interpretation

The corrected results are specific to this simulated dataset and split. They should not be interpreted as evidence of production fraud-detection performance. The cost outputs are scenario analyses based on assumptions, not actual bank loss or savings estimates. See the root README for model results, dashboard sections, and limitations.
