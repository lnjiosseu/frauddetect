pkgs <- c("tidyverse","ranger","xgboost","pROC","PRROC","isotree")
missing <- pkgs[!vapply(pkgs, requireNamespace, logical(1), quietly=TRUE)]
if (length(missing)) install.packages(missing)
