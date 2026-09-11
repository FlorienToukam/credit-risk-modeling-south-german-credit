# Credit Risk Modeling: Model Enhancements
#
# Adds development-stage threshold selection, risk bands, driver interpretation,
# and a cross-validated challenger-model comparison.

if (!requireNamespace("pROC", quietly = TRUE) ||
    !requireNamespace("randomForest", quietly = TRUE)) {
  stop("Install pROC and randomForest before running this script.", call. = FALSE)
}

find_project_root <- function() {
  locations <- c(getwd(), dirname(getwd()))
  root <- locations[file.exists(file.path(locations, "README.md"))][1]
  if (is.na(root)) stop("Run this script from the project root or the R folder.", call. = FALSE)
  normalizePath(root)
}

create_stratified_folds <- function(outcome, folds = 5, seed = 556) {
  set.seed(seed)
  fold_id <- integer(length(outcome))
  for (level in levels(outcome)) {
    index <- which(outcome == level)
    fold_id[index] <- sample(rep(seq_len(folds), length.out = length(index)))
  }
  fold_id
}

calculate_metrics <- function(actual, risk, threshold) {
  predicted <- factor(ifelse(risk >= threshold, "bad", "good"), levels = c("bad", "good"))
  matrix <- table(actual = actual, predicted = predicted)
  tn <- matrix["good", "good"]; fp <- matrix["good", "bad"]
  fn <- matrix["bad", "good"]; tp <- matrix["bad", "bad"]
  data.frame(
    auc = as.numeric(pROC::auc(pROC::roc(actual, risk, levels = c("good", "bad"),
                                          direction = "<", quiet = TRUE))),
    recall_bad = tp / (tp + fn),
    specificity_good = tn / (tn + fp),
    precision_bad = tp / (tp + fp),
    accuracy = (tp + tn) / sum(matrix),
    false_positives = fp,
    false_negatives = fn
  )
}

evaluate_threshold_grid <- function(actual, risk, grid) {
  results <- do.call(rbind, lapply(grid, function(threshold) {
    metric <- calculate_metrics(actual, risk, threshold)
    data.frame(threshold = threshold, metric)
  }))
  results$youden_j <- results$recall_bad + results$specificity_good - 1
  results
}

project_root <- find_project_root()
data_path <- file.path(project_root, "data", "raw", "SouthGermanCredit.asc")
output_dir <- file.path(project_root, "outputs")
figure_dir <- file.path(output_dir, "figures")
dir.create(figure_dir, recursive = TRUE, showWarnings = FALSE)

credit_data <- read.table(data_path, header = TRUE, sep = "", stringsAsFactors = FALSE)
credit_data$kredit <- factor(credit_data$kredit, levels = c(0, 1), labels = c("bad", "good"))
credit_data$laufkont <- factor(credit_data$laufkont)
credit_data$sparkont <- factor(credit_data$sparkont)
credit_data$beszeit <- factor(credit_data$beszeit)
model_formula <- kredit ~ laufkont + sparkont + laufzeit + hoehe + beszeit + alter

# The fixed holdout set is reserved for final evaluation only.

set.seed(555)
training_index <- unlist(lapply(split(seq_len(nrow(credit_data)), credit_data$kredit), function(index) {
  sample(index, size = floor(0.80 * length(index)))
}), use.names = FALSE)
training_data <- credit_data[sort(training_index), ]
holdout_data <- credit_data[-sort(training_index), ]

# Five-fold cross-validation on the training sample drives threshold and band selection.

fold_id <- create_stratified_folds(training_data$kredit)
logistic_oof_risk <- numeric(nrow(training_data))
forest_oof_risk <- numeric(nrow(training_data))

for (fold in seq_len(5)) {
  fold_train <- training_data[fold_id != fold, ]
  fold_validation <- training_data[fold_id == fold, ]

  fold_logistic <- glm(model_formula, data = fold_train, family = binomial())
  logistic_oof_risk[fold_id == fold] <- 1 - predict(
    fold_logistic, newdata = fold_validation, type = "response"
  )

  set.seed(555 + fold)
  minority_size <- min(table(fold_train$kredit))
  fold_forest <- randomForest::randomForest(
    model_formula,
    data = fold_train,
    ntree = 500,
    strata = fold_train$kredit,
    sampsize = rep(minority_size, 2)
  )
  forest_oof_risk[fold_id == fold] <- predict(
    fold_forest, newdata = fold_validation, type = "prob"
  )[, "bad"]
}

threshold_grid <- seq(0.10, 0.90, by = 0.05)
logistic_threshold_grid <- evaluate_threshold_grid(
  training_data$kredit, logistic_oof_risk, threshold_grid
)
forest_threshold_grid <- evaluate_threshold_grid(
  training_data$kredit, forest_oof_risk, threshold_grid
)

# Youden's J selects each model's threshold from development data by balancing recall and specificity.

logistic_threshold <- logistic_threshold_grid$threshold[
  which.max(logistic_threshold_grid$youden_j)
]
forest_threshold <- forest_threshold_grid$threshold[
  which.max(forest_threshold_grid$youden_j)
]

logistic_cv_metrics <- calculate_metrics(
  training_data$kredit, logistic_oof_risk, logistic_threshold
)
forest_cv_metrics <- calculate_metrics(
  training_data$kredit, forest_oof_risk, forest_threshold
)

# Risk-band boundaries also come from development-stage logistic predictions.

risk_band_cutoffs <- as.numeric(quantile(logistic_oof_risk, probs = c(1 / 3, 2 / 3), names = FALSE))

# Refit each model on all training observations, then evaluate once on the untouched holdout.

logistic_holdout_model <- glm(model_formula, data = training_data, family = binomial())
logistic_holdout_risk <- 1 - predict(logistic_holdout_model, newdata = holdout_data, type = "response")

set.seed(560)
training_minority_size <- min(table(training_data$kredit))
forest_holdout_model <- randomForest::randomForest(
  model_formula,
  data = training_data,
  ntree = 500,
  strata = training_data$kredit,
  sampsize = rep(training_minority_size, 2)
)
forest_holdout_risk <- predict(forest_holdout_model, newdata = holdout_data, type = "prob")[, "bad"]

logistic_holdout_metrics <- calculate_metrics(
  holdout_data$kredit, logistic_holdout_risk, logistic_threshold
)
forest_holdout_metrics <- calculate_metrics(
  holdout_data$kredit, forest_holdout_risk, forest_threshold
)

# Logistic risk bands describe the holdout set using development-stage boundaries.

risk_band <- cut(
  logistic_holdout_risk,
  breaks = c(-Inf, risk_band_cutoffs[1], risk_band_cutoffs[2], Inf),
  labels = c("Low risk", "Moderate risk", "High risk"),
  include.lowest = TRUE
)
risk_band_results <- aggregate(
  data.frame(predicted_risk = logistic_holdout_risk, actual_bad = as.numeric(holdout_data$kredit == "bad")),
  by = list(risk_band = risk_band),
  FUN = function(x) c(observations = length(x), average = mean(x))
)
risk_band_results <- data.frame(
  risk_band = risk_band_results$risk_band,
  observations = risk_band_results$predicted_risk[, "observations"],
  average_predicted_risk = risk_band_results$predicted_risk[, "average"],
  actual_bad_credit_rate = risk_band_results$actual_bad[, "average"]
)

# Model drivers use the full-sample logistic model, matching the baseline analytical scope.

original_model <- glm(model_formula, data = credit_data, family = binomial())
coefficient_table <- summary(original_model)$coefficients
odds_ratio_table <- data.frame(
  term = rownames(coefficient_table),
  odds_ratio = exp(coefficient_table[, "Estimate"]),
  ci_lower = exp(coefficient_table[, "Estimate"] - 1.96 * coefficient_table[, "Std. Error"]),
  ci_upper = exp(coefficient_table[, "Estimate"] + 1.96 * coefficient_table[, "Std. Error"]),
  p_value = coefficient_table[, "Pr(>|z|)"],
  row.names = NULL
)
driver_labels <- c(
  laufkont2 = "Checking status: < 0 DM vs. no account",
  laufkont3 = "Checking status: 0–200 DM vs. no account",
  laufkont4 = "Checking status: ≥ 200 DM / salary vs. no account",
  sparkont4 = "Savings: 500–1,000 DM vs. no / unknown",
  sparkont5 = "Savings: ≥ 1,000 DM vs. no / unknown",
  laufzeit = "Loan duration: each additional month",
  beszeit4 = "Employment duration: 4–<7 years vs. unemployed"
)
driver_table <- odds_ratio_table[odds_ratio_table$term %in% names(driver_labels), ]
driver_table$driver <- unname(driver_labels[driver_table$term])
driver_table$interpretation <- ifelse(
  driver_table$odds_ratio > 1,
  "Higher estimated odds of a good credit outcome",
  "Lower estimated odds of a good credit outcome"
)
driver_table <- driver_table[, c("driver", "odds_ratio", "ci_lower", "ci_upper", "p_value", "interpretation")]
driver_table <- driver_table[order(-abs(log(driver_table$odds_ratio))), ]

# Visual summaries

png(file.path(figure_dir, "observed-bad-credit-rate-by-risk-band.png"),
    width = 1100, height = 750, res = 150)
barplot(
  100 * risk_band_results$actual_bad_credit_rate,
  names.arg = risk_band_results$risk_band,
  xlab = "Logistic-model risk band",
  ylab = "Observed bad-credit rate (%)",
  main = "Observed Bad-Credit Rate by Holdout Risk Band",
  col = c("#72a8d3", "#f2c14e", "#c84b4b"),
  ylim = c(0, max(100 * risk_band_results$actual_bad_credit_rate) * 1.15)
)
dev.off()

png(file.path(figure_dir, "credit-screening-threshold-tradeoff.png"),
    width = 1200, height = 750, res = 150)
par(mar = c(5, 4, 4, 11))
plot(logistic_threshold_grid$threshold, logistic_threshold_grid$recall_bad, type = "b", pch = 16,
     col = "#c84b4b", xlim = c(0.10, 0.90), ylim = c(0, 1), xlab = "Bad-credit risk threshold",
     ylab = "Cross-validated metric", main = "Logistic Model: Development-Stage Threshold Tradeoff")
lines(logistic_threshold_grid$threshold, logistic_threshold_grid$specificity_good, type = "b",
      pch = 16, col = "#245b8a")
lines(logistic_threshold_grid$threshold, logistic_threshold_grid$precision_bad, type = "b",
      pch = 16, col = "#4a7c59")
abline(v = logistic_threshold, lty = 2, col = "gray40")
legend(x = 0.915, y = 1, legend = c("Bad-credit recall", "Good-credit specificity",
                                   "Bad-credit precision", "Selected threshold"),
       col = c("#c84b4b", "#245b8a", "#4a7c59", "gray40"),
       lty = c(1, 1, 1, 2), pch = c(16, 16, 16, NA), cex = 0.72, bty = "n", xpd = NA)
dev.off()

logistic_holdout_roc <- pROC::roc(holdout_data$kredit, logistic_holdout_risk,
                                  levels = c("good", "bad"), direction = "<", quiet = TRUE)
roc_points <- pROC::coords(logistic_holdout_roc, "all", ret = c("specificity", "sensitivity"),
                           transpose = FALSE)
png(file.path(figure_dir, "validated-model-roc-curve.png"),
    width = 1000, height = 800, res = 150)
plot(1 - roc_points[, "specificity"], roc_points[, "sensitivity"], type = "s",
     xlim = c(0, 1), ylim = c(0, 1), xlab = "False positive rate",
     ylab = "True positive rate", main = "Logistic Model: Holdout ROC Curve",
     col = "#245b8a", lwd = 2)
abline(a = 0, b = 1, lty = 2, col = "gray50")
legend("bottomright", legend = paste("Holdout AUC =", round(logistic_holdout_metrics$auc, 3)), bty = "n")
dev.off()

development_model_comparison <- rbind(
  cbind(model = "Logistic regression", threshold = logistic_threshold, logistic_cv_metrics),
  cbind(model = "Balanced random forest", threshold = forest_threshold, forest_cv_metrics)
)
holdout_model_comparison <- rbind(
  cbind(model = "Logistic regression", threshold = logistic_threshold, logistic_holdout_metrics),
  cbind(model = "Balanced random forest", threshold = forest_threshold, forest_holdout_metrics)
)
threshold_selection <- data.frame(
  model = c("Logistic regression", "Balanced random forest"),
  selected_threshold = c(logistic_threshold, forest_threshold),
  selection_method = "Five-fold cross-validated Youden's J"
)

write.csv(risk_band_results, file.path(output_dir, "validated-risk-band-results.csv"), row.names = FALSE)
write.csv(logistic_threshold_grid, file.path(output_dir, "logistic-development-threshold-analysis.csv"), row.names = FALSE)
write.csv(forest_threshold_grid, file.path(output_dir, "random-forest-development-threshold-analysis.csv"), row.names = FALSE)
write.csv(threshold_selection, file.path(output_dir, "model-threshold-selection.csv"), row.names = FALSE)
write.csv(driver_table, file.path(output_dir, "interpretable-risk-drivers.csv"), row.names = FALSE)
write.csv(development_model_comparison, file.path(output_dir, "five-fold-cv-model-comparison.csv"), row.names = FALSE)
write.csv(holdout_model_comparison, file.path(output_dir, "holdout-model-comparison.csv"), row.names = FALSE)

cat("Development-stage threshold selection\n")
print(threshold_selection)
cat("\nHoldout logistic-model results\n")
print(logistic_holdout_metrics)
cat("\nHoldout risk-band results\n")
print(risk_band_results)
cat("\nFive-fold cross-validation comparison\n")
print(development_model_comparison)
cat("\nHoldout model comparison\n")
print(holdout_model_comparison)
