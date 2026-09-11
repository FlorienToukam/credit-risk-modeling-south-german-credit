# Credit Risk Modeling — Underwriting Summary

## Objective

I analyzed the South German Credit data set to identify borrower and loan characteristics associated with credit outcomes and to test whether a credit-risk model can prioritize cases for review.

## Data and approach

The data contains 1,000 historical credit observations and 21 fields. I focused on checking status, savings status, loan duration, loan amount, employment duration, age, and observed credit outcome. The baseline analysis combined exploratory analysis, hypothesis testing, and logistic regression. The enhanced workflow adds a fixed-seed, stratified development/holdout design, five-fold cross-validation, risk bands, threshold selection, and a random-forest challenger model.

## Strongest indicators

Checking status was the clearest indicator: the observed bad-credit rate declined from 49.3% for borrowers with no checking account to 11.7% for borrowers with at least 200 DM or salary credited for at least one year. That checking-status category had 6.45 times the estimated odds of a good outcome relative to no checking account. Savings categories of 500–1,000 DM and at least 1,000 DM, plus a 4–<7 year employment duration, were also associated with higher estimated odds of a good outcome. Longer loan duration was associated with lower estimated odds.

## Baseline and validated performance

The baseline full-sample logistic model produced an in-sample AUC of 0.773, accuracy of 74.7%, good-credit recall of 89.6%, and bad-credit recall of 40.0%.

I reserved 200 observations for final evaluation. The logistic model produced a holdout AUC of 0.679. A 20% predicted bad-credit risk threshold was selected from five-fold cross-validation on the development sample, not from the holdout. On the holdout set, that threshold captured 70.0% of bad-credit cases, achieved 58.6% good-credit specificity, 42.0% bad-credit precision, and 62.0% accuracy. It generated 58 false-positive alerts and missed 18 bad-credit cases.

## Risk bands and screening use

I defined Low, Moderate, and High risk bands from development-stage logistic-model predictions and applied them to the holdout set. Observed bad-credit rates were 17.8% in Low risk, 26.6% in Moderate risk, and 47.6% in High risk. The model is therefore useful for prioritizing cases by estimated risk.

I would use the 20% threshold for an initial review queue rather than an automatic approval or decline decision. It places more potentially risky cases into review than a 50% cutoff, with the tradeoff of more false-positive alerts.

## Challenger model

I compared logistic regression with a balanced random forest. Thresholds were selected separately for each model because class-balanced random-forest training can change probability calibration.

On the holdout set, the random forest had a slightly higher AUC of 0.692 and higher accuracy of 71.0%. Its 55% development-selected threshold produced 82.1% good-credit specificity but captured only 45.0% of bad-credit cases. At the development-selected thresholds, logistic regression is better aligned with a broad screening objective because it identifies more bad-credit cases. The balanced random forest is more selective and is better aligned with a narrower alert list.

## Practical interpretation and limitations

Checking status, savings position, employment history, and loan duration provide useful inputs to a structured credit review. The data set is small, uses simplified coded variables, and contains one historical sample. The results support risk ranking and screening, while larger samples and further calibration work would be needed before operational use.
