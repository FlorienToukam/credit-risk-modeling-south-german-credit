# Methodology Notes

## Baseline Full-Sample Analysis

The baseline analysis uses all 1,000 observations to examine relationships between borrower characteristics and credit outcomes. It includes descriptive analysis, chi-square testing, a Welch t-test, ANOVA with Tukey comparisons, Pearson and Spearman correlation, and an interpretable logistic-regression model.

This version reproduces the core analysis and preserves its reported in-sample results. The workflow is focused on the core tests, model, and validation outputs.

## Data Preparation

The analysis reads the public UCI South German Credit data set. The outcome is coded as bad or good credit. Checking status, savings status, and employment duration are treated as categorical variables. Loan duration, loan amount, and age remain numeric.

## Development and Holdout Design

A fixed seed (555) creates a stratified 80/20 split. The 800-observation development sample is used for model development, five-fold cross-validation, threshold selection, risk-band design, and challenger-model comparison. The 200-observation holdout sample is used only for final evaluation after those choices are fixed.

## Threshold Selection

For each model, I evaluate a development-stage cross-validated threshold grid from 10% to 90% predicted bad-credit risk. I select the threshold with the highest Youden's J, which balances bad-credit recall and good-credit specificity.

The selected logistic-regression threshold is 20%. The selected balanced-random-forest threshold is 55%. These thresholds are model-specific because balanced random-forest training can change probability calibration.

## Risk Bands

Low, Moderate, and High logistic-model risk bands use the 33rd and 67th percentiles of development-stage, out-of-fold predicted bad-credit risk. The final bands are applied unchanged to the holdout sample and reported with observation count, average predicted risk, and observed bad-credit rate.

## Challenger Comparison

The balanced random forest is the challenger model. Five-fold, stratified cross-validation produces out-of-fold predictions for both models. ROC/AUC is compared directly because it evaluates ranking across thresholds. Threshold-dependent metrics use each model's own development-selected threshold before final holdout evaluation.

## Reproducibility

Both R scripts use fixed seeds, portable project-relative paths, and the same public UCI source file. Run the baseline analysis first, then run the model-enhancement script to generate the final tables and figures.
