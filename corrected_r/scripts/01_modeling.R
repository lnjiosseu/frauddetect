source("corrected_r/scripts/00_setup.R")
library(tidyverse); library(ranger); library(xgboost); library(pROC); library(PRROC)
set.seed(2026)
dir.create("corrected_r/outputs", recursive=TRUE, showWarnings=FALSE)
d <- read_csv("data/transactions.csv", show_col_types=FALSE) |>
  mutate(is_fraud=as.integer(is_fraud),
         international=as.integer(geography=="international"),
         is_night=as.integer(time_of_day=="night"),
         high_risk_category=as.integer(merchant_category %in% c("ATM","luxury","electronics")),
         log_amount=log1p(amount)) |>
  select(is_fraud,log_amount,international,is_night,high_risk_category,
         prior_fraud_flag,velocity_24h,device_mismatch,account_age_days,amount_zscore)
# Stratified 60/20/20 split.
stratified <- function(y,p) unlist(lapply(split(seq_along(y),y),function(ix) sample(ix,floor(length(ix)*p))))
tr <- stratified(d$is_fraud,.60); rem <- setdiff(seq_len(nrow(d)),tr)
va <- rem[stratified(d$is_fraud[rem],.50)]; te <- setdiff(rem,va)
train <- d[tr,]; valid <- d[va,]; test <- d[te,]
x <- setdiff(names(d),"is_fraud"); counts <- table(factor(train$is_fraud,levels=c(0,1)))
cw <- c("0"=1,"1"=as.numeric(counts[1]/counts[2]))
rf <- ranger(is_fraud~.,data=train|>mutate(is_fraud=factor(is_fraud)),
             probability=TRUE,num.trees=500,class.weights=cw,seed=2026,
             importance="permutation")
rfv <- predict(rf,data=valid)$predictions[,"1"]; rft <- predict(rf,data=test)$predictions[,"1"]
dm <- xgb.DMatrix(as.matrix(train[,x]),label=train$is_fraud)
dv <- xgb.DMatrix(as.matrix(valid[,x]),label=valid$is_fraud)
dt <- xgb.DMatrix(as.matrix(test[,x]),label=test$is_fraud)
xgb <- xgb.train(params=list(objective="binary:logistic",eval_metric="aucpr",
 max_depth=3,eta=.04,subsample=.8,colsample_bytree=.8,
 scale_pos_weight=as.numeric(counts[1]/counts[2])),
 data=dm,nrounds=500,watchlist=list(validation=dv),early_stopping_rounds=30,verbose=0)
xv <- predict(xgb,dv); xt <- predict(xgb,dt)
pv <- (rfv+xv)/2; pt <- (rft+xt)/2
rv <- roc(valid$is_fraud,pv,quiet=TRUE,direction="<")
threshold <- as.numeric(coords(rv,"best",best.method="youden",ret="threshold")[1])
pred <- as.integer(pt>=threshold); rt <- roc(test$is_fraud,pt,quiet=TRUE,direction="<")
pr <- pr.curve(scores.class0=pt[test$is_fraud==1],scores.class1=pt[test$is_fraud==0],curve=FALSE)
tp <- sum(pred==1 & test$is_fraud==1); fp <- sum(pred==1 & test$is_fraud==0)
tn <- sum(pred==0 & test$is_fraud==0); fn <- sum(pred==0 & test$is_fraud==1)
metrics <- tibble(metric=c("test_roc_auc","test_pr_auc","validation_threshold","precision","recall","specificity","false_positive_rate"),
 value=c(as.numeric(auc(rt)),pr$auc.integral,threshold,tp/(tp+fp),tp/(tp+fn),tn/(tn+fp),fp/(fp+tn)))
write_csv(metrics,"corrected_r/outputs/model_metrics.csv")
write_csv(tibble(actual=test$is_fraud,rf_probability=rft,xgb_probability=xt,
                 ensemble_probability=pt,predicted=pred),"corrected_r/outputs/test_predictions.csv")
saveRDS(list(rf=rf,xgboost=xgb,threshold=threshold),"corrected_r/outputs/models.rds")
print(metrics)
