# Install packages required by the corrected analysis pipeline and Shiny dashboard.
pkgs <- c(
  "tidyverse", "ranger", "xgboost", "pROC", "PRROC", "isotree",
  "shiny", "bslib", "bsicons", "DT", "scales"
)

missing <- pkgs[
  !vapply(pkgs, requireNamespace, logical(1), quietly = TRUE)
]

if (length(missing)) {
  install.packages(missing)
}

message("Required analysis and dashboard packages are available.")
