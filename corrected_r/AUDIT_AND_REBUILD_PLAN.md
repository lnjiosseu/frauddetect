# Corrected R implementation: FraudDetect

This directory is a new, separate implementation. The original scripts and their historical outputs remain unchanged.

## Evidence-based baseline

The supplied source and saved output files describe 10,000 simulated transactions. The saved model metrics report:

| Model | Saved test AUC |
|---|---:|
| Logistic regression | 0.8249 |
| Bagged decision stumps | 0.7694 |
| Averaged ensemble | 0.8256 |

These are historical saved outputs, not independently reproduced results. The README claims of approximately 0.94 AUC and 31% false-positive-rate reduction are not supported by those outputs.

## Corrections required

1. Retain logistic regression as a baseline.
2. Replace the bagged-stump proxy with a genuine Random Forest.
3. Add XGBoost only as a separately evaluated candidate, not as an assumed winner.
4. Use a stratified train/validation/test split. Fit preprocessing and resampling on training data only.
5. Replace random duplication mislabeled as SMOTE with explicitly named strategies (class weights, random oversampling, and optionally SMOTE) evaluated on the same untouched validation/test sets.
6. Select thresholds on validation data using a stated business objective. Do not optimize the threshold on the final test set.
7. Report PR-AUC, ROC-AUC, precision, recall, specificity, FPR, confusion matrix, calibration, and threshold.
8. Replace the custom isolation-score approximation with a tested Isolation Forest implementation and evaluate it as an unsupervised anomaly score. Do not call it a fraud classifier without a separately validated threshold.
9. Recompute the amount-rule comparison from the same held-out observations and report the absolute FPRs alongside any relative change.
10. Document feature availability and leakage checks. Exclude post-transaction or target-derived fields.

## Reproducibility contract

- Input: `data/transactions.csv` at the repository root.
- Outputs: `corrected_r/outputs/`.
- All random operations use explicit seeds.
- Final test metrics are generated once after model and threshold selection.
- No performance claim is published until the corrected scripts have been run and their outputs reviewed.

## Current status

This folder is an audit/rebuild specification. Corrected executable scripts and verified metrics will be added after implementation and execution testing. The original `scripts/`, `shiny/`, report, and historical outputs are not modified by this work.
