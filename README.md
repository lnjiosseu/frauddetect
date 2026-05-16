# FraudDetect: Financial Transaction Fraud Detection & Risk Analytics

A portfolio project replicating production risk workflows in financial services — built end-to-end in R, covering feature engineering, class-imbalance correction, ensemble modeling, anomaly scoring, and risk segmentation.

---

## Why This Project Exists

Fraud detection in financial services sits at the intersection of statistical rigor, operational constraints, and business cost trade-offs. False negatives (missed fraud) cost money; false positives (wrongly flagged transactions) cost customers. Most production pipelines balance both through ensemble models, optimal threshold selection, and layered anomaly scoring.

This project replicates that full stack — from raw transaction data to a risk-scored dashboard — using only R and standard statistical methods.

---

## What It Does

**Module 1 — Data Simulation**
- Generates 10,000 realistic financial transactions with merchant category, geography, time-of-day, device signals, and velocity features
- Embeds fraud-generating logic (international transactions, night activity, device mismatch, prior fraud history) at controlled rates

**Module 2 — EDA & Feature Engineering**
- Fraud rate profiling by merchant category, geography, and time of day
- Amount z-score computation within merchant category groups
- Feature correlation analysis against fraud label

**Module 3 — Modeling**
- Logistic regression and bagged decision stump ensemble (RF proxy)
- SMOTE-style oversampling to address class imbalance (~5–8% fraud rate)
- Youden's J threshold optimization for classification
- Confusion matrix, sensitivity, specificity, and FP rate comparison vs rule-based baseline

**Module 4 — Anomaly Scoring & Risk Segmentation**
- Isolation forest-inspired anomaly scoring (pure base R)
- Dual-signal anomaly flag (isolation score + amount z-score)
- Risk tier assignment (High / Medium / Low) and segment-level profiling

**Deliverables**
- Interactive Shiny dashboard (4 tabs: Overview, Model Performance, Risk Segmentation, Transaction Explorer)
- Quarto HTML report with reproducible code, tables, and figures

---

## Key Results

| Finding | Value |
|---|---|
| Ensemble AUC-ROC | ~0.94 |
| FP Rate Reduction vs Amount Rule | ~31% |
| Risk Tiers | High / Medium / Low segmentation |
| Top fraud drivers | Device mismatch, international, night, prior flag |
| Anomaly flags | Top 10% isolation score + \|z\| > 3 |

---

## Methods

| Component | Method |
|---|---|
| Class imbalance | Oversampling (SMOTE proxy) |
| Classification | Logistic regression + bagged stumps ensemble |
| Threshold selection | Youden's J statistic |
| Anomaly scoring | Isolation forest proxy (random recursive splits) |
| Z-score flagging | Within-category amount standardization |
| Risk segmentation | Merchant × geography × time cross-tabulation |
| Visualization | ggplot2, Shiny, DT |

---

## Project Structure

```
frauddetect/
├── R/
│   ├── 01_simulate_data.R      # Transaction dataset generation
│   ├── 02_eda_features.R       # EDA, fraud profiling, feature correlations
│   ├── 03_modeling.R           # LR + RF ensemble, AUC-ROC, threshold selection
│   └── 04_anomaly_risk.R       # Isolation forest, risk scoring, segmentation
├── data/                       # Generated datasets (git-ignored)
├── outputs/                    # CSVs: metrics, segments, predictions (git-ignored)
├── shiny/
│   └── app.R                   # Interactive dashboard (4 tabs)
├── frauddetect_report.qmd      # Quarto HTML report
└── README.md
```

---

## Reproducing the Project

```r
# Install dependencies
install.packages(c("tidyverse", "pROC", "shiny", "bslib", "bsicons", "DT"))

# Run in order from project root
source("R/01_simulate_data.R")
source("R/02_eda_features.R")
source("R/03_modeling.R")
source("R/04_anomaly_risk.R")

# Launch dashboard
shiny::runApp("shiny/")

# Render report
quarto::quarto_render("frauddetect_report.qmd")
```

---

## Why This Matters for Risk Teams

The statistical problems this project addresses — class imbalance correction, threshold calibration, layered anomaly scoring, and risk segmentation — are foundational to production fraud and AML pipelines. Building them from first principles in R, without leaning on black-box AutoML packages, demonstrates both the statistical reasoning and the engineering discipline required for regulatory-grade risk work.

---

## Author

**Ludovic Njiosseu** | MS Biostatistics, NYU | Data Scientist & Statistician  
5+ years across healthcare, pharma, financial analytics, and consumer products  
Open to roles in risk analytics, product data science, and applied ML
