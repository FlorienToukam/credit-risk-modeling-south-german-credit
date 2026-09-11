# Credit Risk Modeling: South German Credit Data
#
# Runs the baseline exploratory analysis, statistical tests,
# logistic-regression model, and an initial holdout baseline.

if (!requireNamespace("pROC", quietly = TRUE)) {
  stop("Install pROC before running this script: install.packages(\"pROC\")", call. = FALSE)
}

find_project_root <- function() {
  locations <- c(getwd(), dirname(getwd()))
  root <- locations[file.exists(file.path(locations, "README.md"))][1]
  if (is.na(root)) stop("Run this script from the project root or the R folder.", call. = FALSE)
  normalizePath(root)
}

project_root <- find_project_root()
data_path <- file.path(project_root, "data", "raw", "SouthGermanCredit.asc")
output_dir <- file.path(project_root, "outputs")
figure_dir <- file.path(output_dir, "figures")
dir.create(figure_dir, recursive = TRUE, showWarnings = FALSE)
if (!file.exists(data_path)) stop("SouthGermanCredit.asc was not found in data/raw.", call. = FALSE)

# Load and prepare the data

credit_data <- read.table(data_path, header = TRUE, sep = "", stringsAsFactors = FALSE)
required_columns <- c("laufkont", "laufzeit", "hoehe", "sparkont", "beszeit", "alter", "kredit")
missing_columns <- setdiff(required_columns, names(credit_data))
if (length(missing_columns) > 0) {
  stop("Missing expected columns: ", paste(missing_columns, collapse = ", "), call. = FALSE)
}

credit_data$kredit <- factor(credit_data$kredit, levels = c(0, 1), labels = c("bad", "good"))
credit_data$laufkont <- factor(credit_data$laufkont)
credit_data$sparkont <- factor(credit_data$sparkont)
credit_data$beszeit <- factor(credit_data$beszeit)
model_formula <- kredit ~ laufkont + sparkont + laufzeit + hoehe + beszeit + alter

# Baseline full-sample analysis

checking_table <- table(checking_status = credit_data$laufkont, outcome = credit_data$kredit)
checking_chi_square <- chisq.test(checking_table, correct = FALSE)
cramers_v <- sqrt(unname(checking_chi_square$statistic) /
                    (sum(checking_table) * (min(dim(checking_table)) - 1)))
bad_rate_by_checking <- prop.table(checking_table, margin = 1)[, "bad"]
checking_labels <- c("No account", "< 0 DM", "0–200 DM", "≥ 200 DM / salary")
savings_labels <- c("No / unknown", "< 100 DM", "100–500 DM", "500–1,000 DM", "≥ 1,000 DM")

amount_t_test <- t.test(hoehe ~ kredit, data = credit_data, var.equal = FALSE)
savings_anova <- aov(hoehe ~ sparkont, data = credit_data)
savings_tukey <- TukeyHSD(savings_anova)
amount_duration_pearson <- cor.test(credit_data$hoehe, credit_data$laufzeit, method = "pearson")
amount_duration_spearman <- cor.test(credit_data$hoehe, credit_data$laufzeit,
                                     method = "spearman", exact = FALSE)

original_model <- glm(model_formula, data = credit_data, family = binomial())
original_probability <- predict(original_model, type = "response")
original_roc <- pROC::roc(credit_data$kredit, original_probability,
                          levels = c("bad", "good"), direction = "<", quiet = TRUE)
original_auc <- as.numeric(pROC::auc(original_roc))
original_prediction <- factor(ifelse(original_probability >= 0.50, "good", "bad"),
                              levels = c("bad", "good"))
original_matrix <- table(actual = credit_data$kredit, predicted = original_prediction)
original_accuracy <- sum(diag(original_matrix)) / sum(original_matrix)
original_good_recall <- original_matrix["good", "good"] / sum(original_matrix["good", ])
original_bad_recall <- original_matrix["bad", "bad"] / sum(original_matrix["bad", ])

# Initial holdout baseline at a 50% cutoff

set.seed(555)
training_index <- unlist(lapply(split(seq_len(nrow(credit_data)), credit_data$kredit), function(index) {
  sample(index, size = floor(0.80 * length(index)))
}), use.names = FALSE)

training_data <- credit_data[sort(training_index), ]
test_data <- credit_data[-sort(training_index), ]

validated_model <- glm(model_formula, data = training_data, family = binomial())
test_probability <- predict(validated_model, newdata = test_data, type = "response")
test_prediction <- factor(ifelse(test_probability >= 0.50, "good", "bad"),
                          levels = c("bad", "good"))
validation_matrix <- table(actual = test_data$kredit, predicted = test_prediction)

# Bad credit is the positive class for these metrics.
tn <- validation_matrix["good", "good"]
fp <- validation_matrix["good", "bad"]
fn <- validation_matrix["bad", "good"]
tp <- validation_matrix["bad", "bad"]

validated_roc <- pROC::roc(test_data$kredit, test_probability,
                           levels = c("bad", "good"), direction = "<", quiet = TRUE)
validated_auc <- as.numeric(pROC::auc(validated_roc))
validation_metrics <- data.frame(
  metric = c("ROC/AUC", "Sensitivity / Recall (bad credit)", "Specificity (good credit)",
             "Precision (bad credit)", "Accuracy"),
  value = c(
    validated_auc,
    tp / (tp + fn),
    tn / (tn + fp),
    tp / (tp + fp),
    sum(diag(validation_matrix)) / sum(validation_matrix)
  )
)

# Visual summaries

png(file.path(figure_dir, "bad-credit-rate-by-checking-status.png"),
    width = 1200, height = 750, res = 150)
barplot(100 * bad_rate_by_checking, names.arg = checking_labels,
        xlab = "Checking-account status category", ylab = "Bad-credit rate (%)",
        main = "Bad-Credit Rate by Checking-Account Status", col = "#245b8a",
        ylim = c(0, max(100 * bad_rate_by_checking) * 1.15))
dev.off()

png(file.path(figure_dir, "credit-amount-by-savings-tier.png"),
    width = 1200, height = 750, res = 150)
boxplot(hoehe ~ sparkont, data = credit_data, names = savings_labels,
        xlab = "Savings status category",
        ylab = "Credit amount", main = "Credit Amount by Savings Status", col = "#9fc5e8")
dev.off()

results_summary <- data.frame(
  measure = c("Sample size", "ROC/AUC", "Accuracy", "Good-credit recall", "Bad-credit recall"),
  baseline_full_sample_analysis = c(
    nrow(credit_data), original_auc, original_accuracy, original_good_recall, original_bad_recall
  ),
  initial_holdout_50_percent_threshold = c(
    nrow(test_data), validated_auc,
    validation_metrics$value[validation_metrics$metric == "Accuracy"],
    validation_metrics$value[validation_metrics$metric == "Specificity (good credit)"],
    validation_metrics$value[validation_metrics$metric == "Sensitivity / Recall (bad credit)"]
  )
)

write.csv(results_summary, file.path(output_dir, "baseline-analysis-and-initial-holdout-summary.csv"), row.names = FALSE)
write.csv(as.data.frame.matrix(validation_matrix),
          file.path(output_dir, "initial-holdout-50-threshold-confusion-matrix.csv"), row.names = TRUE)
write.csv(validation_metrics, file.path(output_dir, "initial-holdout-50-threshold-metrics.csv"), row.names = FALSE)

cat("Baseline full-sample analysis results\n")
cat(sprintf("Chi-square: %.2f | Cramer's V: %.3f | Baseline in-sample AUC: %.3f\n",
            unname(checking_chi_square$statistic), cramers_v, original_auc))
cat(sprintf("Pearson correlation between amount and duration: %.3f\n",
            unname(amount_duration_pearson$estimate)))
cat(sprintf("Baseline accuracy: %.3f | Good-credit recall: %.3f | Bad-credit recall: %.3f\n",
            original_accuracy, original_good_recall, original_bad_recall))
cat("\nHoldout validation results\n")
cat("Training observations:", nrow(training_data), "| Test observations:", nrow(test_data), "\n")
print(validation_matrix)
print(validation_metrics)
