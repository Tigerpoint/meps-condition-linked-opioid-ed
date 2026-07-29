#!/usr/bin/env Rscript

# Complex-survey analysis for the frozen longitudinal MEPS protocol.
# This script consumes an identifier-free person-level table in the
# nonversioned cache and writes aggregate outputs only.

suppressPackageStartupMessages({
  library(survey)
  library(readr)
  library(dplyr)
  library(tidyr)
  library(ggplot2)
  library(jsonlite)
  library(splines)
  library(digest)
})

options(survey.lonely.psu = "adjust")
options(stringsAsFactors = FALSE)

args <- commandArgs(trailingOnly = TRUE)
project_dir <- if (length(args) >= 1) normalizePath(args[[1]], mustWork = TRUE) else getwd()
model_input <- if (length(args) >= 2) {
  normalizePath(args[[2]], mustWork = TRUE)
} else {
  normalizePath(
    Sys.getenv(
      "MEPS_MODEL_INPUT",
      "C:/Users/nimmi/.codex-data/meps-opioid-sparing/model_input.csv"
    ),
    mustWork = TRUE
  )
}
output_dir <- file.path(project_dir, "analysis", "outputs")
dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)
prior_ledger_path <- file.path(output_dir, "reproducibility_ledger.csv")
prior_ledger <- if (file.exists(prior_ledger_path)) {
  readr::read_csv(prior_ledger_path, show_col_types = FALSE)
} else {
  tibble(artifact = character(), current_sha256 = character())
}

stop_with <- function(message) {
  stop(paste0("T007 STOP: ", message), call. = FALSE)
}

write_csv_stable <- function(x, name) {
  readr::write_csv(x, file.path(output_dir, name), na = "")
}

markdown_table <- function(x) {
  x <- as.data.frame(x)
  escape <- function(value) {
    value <- ifelse(is.na(value), "", as.character(value))
    value <- gsub("\\|", "\\\\|", value)
    gsub("[\r\n]+", " ", value)
  }
  headers <- vapply(names(x), escape, character(1))
  lines <- c(
    paste0("| ", paste(headers, collapse = " | "), " |"),
    paste0("| ", paste(rep("---", length(headers)), collapse = " | "), " |")
  )
  if (nrow(x) > 0) {
    body <- apply(x, 1, function(row) {
      paste0("| ", paste(vapply(row, escape, character(1)), collapse = " | "), " |")
    })
    lines <- c(lines, body)
  }
  paste(lines, collapse = "\n")
}

safe_numeric <- function(x) suppressWarnings(as.numeric(x))

collapse_health <- function(x) {
  factor(
    case_when(
      x %in% c(1, 2) ~ "excellent_very_good",
      x == 3 ~ "good",
      x %in% c(4, 5) ~ "fair_poor",
      TRUE ~ NA_character_
    ),
    levels = c("excellent_very_good", "good", "fair_poor")
  )
}

binary_factor <- function(x, yes_value = 1, labels = c("no", "yes")) {
  factor(
    ifelse(x == yes_value, labels[[2]], ifelse(x > 0, labels[[1]], NA_character_)),
    levels = labels
  )
}

raw <- readr::read_csv(model_input, show_col_types = FALSE, na = c("", "NA"))

required_columns <- c(
  "PANEL", "ALL5RDS", "AGEY1X", "SEX", "RACETHX", "REGIONY1",
  "ERTOTY1", "ERTOTY2", "IPDISY1", "OPTOTVY1", "OBTOTVY1",
  "POVCATY1", "INSCOVY1", "RTHLTH1", "MNHLTH1", "WLKLIM1",
  "ACTLIM1", "IADLHP1", "ADLHLP1", "CANCERY1", "LONGWT",
  "domain_eligible", "opioid_binary", "all_opioid_y1",
  "surgery_inpatient", "surgery_emergency_room", "surgery_outpatient",
  "surgery_office_based", "surgical_event_count",
  "linked_surgical_condition_count", "all_condition_count_y1",
  "STRA9623", "PSU9623"
)
missing_columns <- setdiff(required_columns, names(raw))
if (length(missing_columns) > 0) {
  stop_with(paste("model input lacks:", paste(missing_columns, collapse = ", ")))
}
if (any(c("DUPERSID", "RXNAME", "RXNDC", "ICD10CDX") %in% names(raw))) {
  stop_with("protected identifier/detail fields are present in model input")
}

d <- raw %>%
  mutate(
    PANEL = factor(PANEL, levels = c(22, 23, 25, 26)),
    pool_weight = safe_numeric(LONGWT) / 4,
    domain_eligible = as.integer(domain_eligible),
    opioid_binary = factor(opioid_binary, levels = c("no_opioid", "any_opioid")),
    all_opioid_binary = factor(
      ifelse(all_opioid_y1 == 1, "any_opioid", "no_opioid"),
      levels = c("no_opioid", "any_opioid")
    ),
    any_year2_ed_num = as.integer(ERTOTY2 > 0),
    poverty_2 = factor(
      case_when(
        POVCATY1 %in% c(1, 2, 3) ~ "below_200_fpl",
        POVCATY1 %in% c(4, 5) ~ "200_plus_fpl",
        TRUE ~ NA_character_
      ),
      levels = c("200_plus_fpl", "below_200_fpl")
    ),
    poverty_3 = factor(
      case_when(
        POVCATY1 %in% c(1, 2, 3) ~ "below_200_fpl",
        POVCATY1 == 4 ~ "200_to_399_fpl",
        POVCATY1 == 5 ~ "400_plus_fpl",
        TRUE ~ NA_character_
      ),
      levels = c("400_plus_fpl", "200_to_399_fpl", "below_200_fpl")
    ),
    sex = factor(SEX, levels = c(1, 2), labels = c("male", "female")),
    race_ethnicity = factor(
      RACETHX,
      levels = 1:5,
      labels = c(
        "hispanic", "non_hispanic_white", "non_hispanic_black",
        "non_hispanic_asian", "non_hispanic_other_multiple"
      )
    ),
    race_model = factor(
      case_when(
        RACETHX == 1 ~ "hispanic",
        RACETHX == 2 ~ "non_hispanic_white",
        RACETHX == 3 ~ "non_hispanic_black",
        RACETHX %in% c(4, 5) ~ "non_hispanic_asian_other_multiple",
        TRUE ~ NA_character_
      ),
      levels = c(
        "non_hispanic_white", "hispanic", "non_hispanic_black",
        "non_hispanic_asian_other_multiple"
      )
    ),
    region = factor(
      REGIONY1,
      levels = 1:4,
      labels = c("northeast", "midwest", "south", "west")
    ),
    insurance = factor(
      INSCOVY1,
      levels = 1:3,
      labels = c("any_private", "public_only", "uninsured")
    ),
    insurance_model = factor(
      ifelse(
        INSCOVY1 == 1, "any_private",
        ifelse(INSCOVY1 %in% c(2, 3), "no_private", NA_character_)
      ),
      levels = c("any_private", "no_private")
    ),
    physical_health_3 = collapse_health(RTHLTH1),
    mental_health_3 = collapse_health(MNHLTH1),
    walk_limitation = factor(
      ifelse(WLKLIM1 == 1, "yes", ifelse(WLKLIM1 == 2, "no", NA_character_)),
      levels = c("no", "yes")
    ),
    activity_limitation = factor(
      ifelse(ACTLIM1 == 1, "yes", ifelse(ACTLIM1 == 2, "no", NA_character_)),
      levels = c("no", "yes")
    ),
    iadl_limitation = factor(
      ifelse(IADLHP1 == 1, "yes", ifelse(IADLHP1 == 2, "no", NA_character_)),
      levels = c("no", "yes")
    ),
    adl_limitation = factor(
      ifelse(ADLHLP1 == 1, "yes", ifelse(ADLHLP1 == 2, "no", NA_character_)),
      levels = c("no", "yes")
    ),
    cancer_y1 = factor(
      ifelse(CANCERY1 == 1, "yes", ifelse(CANCERY1 == 2, "no", NA_character_)),
      levels = c("no", "yes")
    ),
    highest_surgery_setting = factor(
      case_when(
        surgery_inpatient == 1 ~ "inpatient",
        surgery_emergency_room == 1 ~ "emergency_room",
        surgery_outpatient == 1 ~ "outpatient",
        surgery_office_based == 1 ~ "office_based",
        TRUE ~ NA_character_
      ),
      levels = c("office_based", "outpatient", "emergency_room", "inpatient")
    ),
    age_category = factor(
      case_when(
        AGEY1X >= 18 & AGEY1X <= 34 ~ "18_34",
        AGEY1X <= 49 ~ "35_49",
        AGEY1X <= 64 ~ "50_64",
        AGEY1X >= 65 ~ "65_plus",
        TRUE ~ NA_character_
      ),
      levels = c("18_34", "35_49", "50_64", "65_plus")
    )
  )

main_covariates <- c(
  "AGEY1X", "sex", "race_model", "region", "poverty_2", "insurance_model",
  "ERTOTY1", "IPDISY1", "OPTOTVY1", "OBTOTVY1",
  "physical_health_3", "mental_health_3", "walk_limitation", "cancer_y1",
  "surgery_inpatient", "surgery_emergency_room", "surgery_outpatient",
  "surgery_office_based", "surgical_event_count", "PANEL"
)
main_required <- c("opioid_binary", "ERTOTY2", main_covariates)
d$complete_case <- as.integer(
  d$domain_eligible == 1 & complete.cases(d[, main_required])
)

if (nrow(d) != 41427) stop_with(paste("unexpected positive-weight universe N:", nrow(d)))
if (sum(d$domain_eligible == 1) != 4468) {
  stop_with(paste("unexpected eligible N:", sum(d$domain_eligible == 1)))
}
eligible_check <- d %>% filter(domain_eligible == 1)
if (sum(eligible_check$opioid_binary == "any_opioid") != 820) {
  stop_with("any-opioid count does not reconcile to 820")
}
if (sum(eligible_check$opioid_binary == "no_opioid") != 3648) {
  stop_with("no-opioid count does not reconcile to 3648")
}
if (sum(eligible_check$any_year2_ed_num) != 1042) {
  stop_with("year-2 ED-positive count does not reconcile to 1042")
}
if (sum(eligible_check$ERTOTY2) != 1658) {
  stop_with("year-2 ED visit count does not reconcile to 1658")
}
if (any(is.na(d$pool_weight)) || any(d$pool_weight <= 0)) {
  stop_with("pooled weights are missing or nonpositive")
}
if (any(is.na(d$STRA9623)) || any(is.na(d$PSU9623))) {
  stop_with("HC-036 design fields are missing")
}

full_design <- survey::svydesign(
  ids = ~PSU9623,
  strata = ~STRA9623,
  weights = ~pool_weight,
  data = d,
  nest = TRUE
)
eligible_design <- subset(full_design, domain_eligible == 1)
analysis_design <- subset(full_design, domain_eligible == 1 & complete_case == 1)
analysis_data <- analysis_design$variables

eligible_n <- sum(d$domain_eligible == 1)
analysis_n <- nrow(analysis_data)
complete_case_loss_pct <- 100 * (eligible_n - analysis_n) / eligible_n
if (complete_case_loss_pct > 5) {
  stop_with(sprintf("complete-case loss %.2f%% exceeds 5%%", complete_case_loss_pct))
}
if (survey::degf(analysis_design) <= 100) {
  stop_with(paste("analysis design df too small:", survey::degf(analysis_design)))
}

model_formula_text <- paste(
  "ERTOTY2 ~ opioid_binary + ns(AGEY1X, 3) + sex + race_model +",
  "region + poverty_2 + insurance_model + log1p(ERTOTY1) + log1p(IPDISY1) +",
  "log1p(OPTOTVY1) + log1p(OBTOTVY1) + physical_health_3 +",
  "mental_health_3 + walk_limitation + cancer_y1 + surgery_inpatient +",
  "surgery_emergency_room + surgery_outpatient + surgery_office_based +",
  "log1p(surgical_event_count) + PANEL"
)
m1_formula <- as.formula(model_formula_text)
m2_formula <- update(m1_formula, . ~ . + opioid_binary:poverty_2)
m3_formula <- update(m1_formula, any_year2_ed_num ~ .)

m1 <- survey::svyglm(
  m1_formula, design = analysis_design,
  family = quasipoisson(link = "log"), influence = TRUE
)
m2 <- survey::svyglm(
  m2_formula, design = analysis_design,
  family = quasipoisson(link = "log"), influence = TRUE
)
m3 <- survey::svyglm(
  m3_formula, design = analysis_design,
  family = quasibinomial(link = "logit"), influence = TRUE
)

models <- list(M1 = m1, M2 = m2, M3 = m3)
for (model_name in names(models)) {
  fit <- models[[model_name]]
  if (!isTRUE(fit$converged)) stop_with(paste(model_name, "did not converge"))
  if (any(!is.finite(coef(fit))) || any(!is.finite(vcov(fit)))) {
    stop_with(paste(model_name, "has nonfinite coefficient/covariance"))
  }
  influence_covariance <- survey::svyrecvar(
    attr(fit, "influence"),
    fit$survey.design$cluster,
    fit$survey.design$strata,
    fit$survey.design$fpc,
    postStrata = fit$survey.design$postStrata
  )
  if (!isTRUE(all.equal(
    unname(influence_covariance), unname(vcov(fit)),
    tolerance = 1e-8, check.attributes = FALSE
  ))) {
    stop_with(paste(model_name, "coefficient influence covariance mismatch"))
  }
}

model_matrix_aligned <- function(model, newdata) {
  terms_no_response <- delete.response(terms(model))
  x <- model.matrix(
    terms_no_response,
    data = newdata,
    contrasts.arg = model$contrasts,
    xlev = model$xlevels
  )
  beta_names <- names(coef(model))
  missing <- setdiff(beta_names, colnames(x))
  if (length(missing) > 0) {
    zeros <- matrix(0, nrow = nrow(x), ncol = length(missing))
    colnames(zeros) <- missing
    x <- cbind(x, zeros)
  }
  x[, beta_names, drop = FALSE]
}

design_variance <- function(influence, design) {
  influence <- matrix(as.numeric(influence), ncol = 1)
  as.numeric(survey::svyrecvar(
    influence, design$cluster, design$strata, design$fpc,
    postStrata = design$postStrata
  ))
}

standardized_mean <- function(
  model, design, data, modifications, link, standardization_mask = NULL
) {
  newdata <- data
  for (variable in names(modifications)) {
    value <- modifications[[variable]]
    if (is.factor(newdata[[variable]])) {
      newdata[[variable]] <- factor(
        rep(value, nrow(newdata)),
        levels = levels(newdata[[variable]])
      )
    } else {
      newdata[[variable]] <- rep(value, nrow(newdata))
    }
  }
  x <- model_matrix_aligned(model, newdata)
  eta <- as.vector(x %*% coef(model))
  if (link == "log") {
    mu <- exp(eta)
    deriv <- mu
  } else if (link == "logit") {
    mu <- plogis(eta)
    deriv <- mu * (1 - mu)
  } else {
    stop("unsupported link")
  }
  if (is.null(standardization_mask)) {
    standardization_mask <- rep(TRUE, nrow(data))
  }
  standardization_mask <- as.logical(standardization_mask)
  if (
    length(standardization_mask) != nrow(data) ||
      any(is.na(standardization_mask)) ||
      !any(standardization_mask)
  ) {
    stop("invalid or empty standardization mask")
  }
  sampling_weights <- as.numeric(weights(design, type = "sampling"))
  target_weights <- ifelse(standardization_mask, sampling_weights, 0)
  target_weight_total <- sum(target_weights)
  normalized_weights <- target_weights / target_weight_total
  estimate <- sum(normalized_weights * mu)
  gradient <- colSums(x * as.numeric(normalized_weights * deriv))

  coefficient_influence <- attr(model, "influence")
  if (is.null(coefficient_influence)) {
    stop("model must be fitted with influence=TRUE")
  }
  if (nrow(coefficient_influence) != nrow(data)) {
    stop("coefficient influence rows do not align with standardization data")
  }
  coefficient_component <- as.vector(coefficient_influence %*% gradient)
  distribution_component <- normalized_weights * (mu - estimate)
  influence <- coefficient_component + distribution_component

  list(
    estimate = estimate,
    gradient = gradient,
    influence = influence,
    link = link,
    unweighted_n = sum(standardization_mask),
    weighted_millions = target_weight_total / 1e6
  )
}

margin_row <- function(key, label, result, model, design) {
  variance <- design_variance(result$influence, design)
  se <- sqrt(max(variance, 0))
  df <- survey::degf(design)
  crit <- qt(0.975, df = df)
  if (result$link == "log") {
    se_link <- se / result$estimate
    ci_low <- exp(log(result$estimate) - crit * se_link)
    ci_high <- exp(log(result$estimate) + crit * se_link)
  } else {
    ci_low <- max(0, result$estimate - crit * se)
    ci_high <- min(1, result$estimate + crit * se)
  }
  tibble(
    key = key,
    label = label,
    estimand = ifelse(result$link == "log", "standardized_mean_count", "standardized_probability"),
    estimate = result$estimate,
    std_error = se,
    ci_low = ci_low,
    ci_high = ci_high,
    p_value = NA_real_,
    unweighted_n = result$unweighted_n,
    weighted_millions = result$weighted_millions,
    design_df = df,
    model_status = "pass",
    suppressed = FALSE
  )
}

contrast_rows <- function(prefix, label, low, high, model, design) {
  df <- survey::degf(design)
  crit <- qt(0.975, df = df)

  diff_est <- high$estimate - low$estimate
  diff_influence <- high$influence - low$influence
  diff_se <- sqrt(max(design_variance(diff_influence, design), 0))
  diff_p <- 2 * pt(-abs(diff_est / diff_se), df = df)

  log_ratio <- log(high$estimate / low$estimate)
  ratio_influence <- high$influence / high$estimate -
    low$influence / low$estimate
  ratio_se_log <- sqrt(max(design_variance(ratio_influence, design), 0))
  ratio <- exp(log_ratio)
  ratio_p <- 2 * pt(-abs(log_ratio / ratio_se_log), df = df)

  bind_rows(
    tibble(
      key = paste0(prefix, "_RATIO"),
      label = paste(label, "ratio"),
      estimand = "standardized_mean_ratio",
      estimate = ratio,
      std_error = ratio * ratio_se_log,
      ci_low = exp(log_ratio - crit * ratio_se_log),
      ci_high = exp(log_ratio + crit * ratio_se_log),
      p_value = ratio_p
    ),
    tibble(
      key = paste0(prefix, "_DIFFERENCE"),
      label = paste(label, "difference"),
      estimand = "standardized_mean_difference",
      estimate = diff_est,
      std_error = diff_se,
      ci_low = diff_est - crit * diff_se,
      ci_high = diff_est + crit * diff_se,
      p_value = diff_p
    )
  ) %>%
    mutate(
      unweighted_n = min(low$unweighted_n, high$unweighted_n),
      weighted_millions = min(low$weighted_millions, high$weighted_millions),
      design_df = df,
      model_status = "pass",
      suppressed = FALSE
    )
}

standardize_pair <- function(
  model, design, exposure_variable, prefix, link = "log",
  low_level = "no_opioid", high_level = "any_opioid",
  standardization_mask = NULL
) {
  dat <- design$variables
  low <- standardized_mean(
    model, design, dat, setNames(list(low_level), exposure_variable), link,
    standardization_mask
  )
  high <- standardized_mean(
    model, design, dat, setNames(list(high_level), exposure_variable), link,
    standardization_mask
  )
  bind_rows(
    margin_row(
      paste0(prefix, "_", toupper(low_level), "_MEAN"),
      paste(low_level, "standardized outcome"), low, model, design
    ),
    margin_row(
      paste0(prefix, "_", toupper(high_level), "_MEAN"),
      paste(high_level, "standardized outcome"), high, model, design
    ),
    contrast_rows(prefix, paste(high_level, "versus", low_level), low, high, model, design)
  )
}

coefficient_table <- function(fit, model_id) {
  s <- coef(summary(fit))
  df <- survey::degf(fit$survey.design)
  crit <- qt(0.975, df = df)
  term <- rownames(s)
  estimate <- s[, "Estimate"]
  se <- s[, "Std. Error"]
  p_col <- grep("^Pr\\(", colnames(s), value = TRUE)
  p <- if (length(p_col) == 1) s[, p_col] else rep(NA_real_, length(term))
  tibble(
    key = paste0(model_id, "_COEF_", make.names(term)),
    model = model_id,
    term = term,
    estimate = estimate,
    std_error = se,
    ci_low = estimate - crit * se,
    ci_high = estimate + crit * se,
    p_value = p,
    exponentiated = exp(estimate),
    exponentiated_ci_low = exp(estimate - crit * se),
    exponentiated_ci_high = exp(estimate + crit * se),
    design_df = df,
    converged = isTRUE(fit$converged)
  )
}

model_coefficients <- bind_rows(
  coefficient_table(m1, "M1"),
  coefficient_table(m2, "M2"),
  coefficient_table(m3, "M3")
)

standardized_results <- bind_rows(
  standardize_pair(m1, analysis_design, "opioid_binary", "M1_MARGIN", "log"),
  standardize_pair(m3, analysis_design, "opioid_binary", "M3_ANYED", "logit")
)

interaction_test <- survey::regTermTest(
  m2, ~opioid_binary:poverty_2, method = "Wald"
)
interaction_results <- tibble(
  key = "M2_INT_WALD",
  label = "Exposure by two-level poverty interaction",
  estimand = "wald_interaction_test",
  estimate = as.numeric(interaction_test$Ftest),
  std_error = NA_real_,
  ci_low = NA_real_,
  ci_high = NA_real_,
  p_value = as.numeric(interaction_test$p),
  unweighted_n = analysis_n,
  weighted_millions = sum(weights(analysis_design)) / 1e6,
  design_df = survey::degf(analysis_design),
  model_status = "pass",
  suppressed = FALSE
)
interaction_term <- grep(
  "opioid_binary.*:poverty_2|poverty_2.*:opioid_binary",
  names(coef(m2)), value = TRUE
)
if (length(interaction_term) != 1) {
  stop_with("poverty interaction coefficient was not uniquely identified")
}
interaction_beta <- unname(coef(m2)[interaction_term])
interaction_beta_se <- unname(sqrt(diag(vcov(m2)))[interaction_term])
interaction_crit <- qt(.975, survey::degf(analysis_design))
interaction_results <- bind_rows(
  interaction_results,
  tibble(
    key = "M2_INT_RATIO_OF_RATIOS",
    label = "Opioid-by-poverty ratio of count ratios",
    estimand = "ratio_of_count_ratios",
    estimate = exp(interaction_beta),
    std_error = exp(interaction_beta) * interaction_beta_se,
    ci_low = exp(interaction_beta - interaction_crit * interaction_beta_se),
    ci_high = exp(interaction_beta + interaction_crit * interaction_beta_se),
    p_value = 2 * pt(
      -abs(interaction_beta / interaction_beta_se),
      df = survey::degf(analysis_design)
    ),
    unweighted_n = analysis_n,
    weighted_millions = sum(weights(analysis_design)) / 1e6,
    design_df = survey::degf(analysis_design),
    model_status = "pass",
    suppressed = FALSE
  )
)

for (poverty_level in levels(analysis_data$poverty_2)) {
  poverty_prefix <- paste0("M2_", toupper(poverty_level))
  poverty_rows <- standardize_pair(
    m2, analysis_design, "opioid_binary", poverty_prefix, "log",
    standardization_mask = analysis_data$poverty_2 == poverty_level
  )
  poverty_rows$label <- paste(poverty_level, poverty_rows$label)
  interaction_results <- bind_rows(interaction_results, poverty_rows)
}

mean_from_design <- function(design, variable) {
  result <- svymean(as.formula(paste0("~", variable)), design, na.rm = TRUE)
  c(estimate = as.numeric(coef(result)), se = as.numeric(SE(result)))
}

numeric_description <- function(variable, label) {
  overall_stat <- mean_from_design(analysis_design, variable)
  no_design <- subset(analysis_design, opioid_binary == "no_opioid")
  any_design <- subset(analysis_design, opioid_binary == "any_opioid")
  no_stat <- mean_from_design(no_design, variable)
  any_stat <- mean_from_design(any_design, variable)
  variance <- as.numeric(svyvar(as.formula(paste0("~", variable)), analysis_design, na.rm = TRUE))
  smd <- (any_stat[["estimate"]] - no_stat[["estimate"]]) / sqrt(variance)
  tibble(
    key = paste0("DESC_", toupper(variable), "_MEAN"),
    variable = label,
    level = "mean",
    unit = "mean",
    overall = overall_stat[["estimate"]],
    overall_se = overall_stat[["se"]],
    no_opioid = no_stat[["estimate"]],
    no_opioid_se = no_stat[["se"]],
    any_opioid = any_stat[["estimate"]],
    any_opioid_se = any_stat[["se"]],
    standardized_difference = smd,
    unweighted_n = analysis_n,
    suppressed = FALSE
  )
}

categorical_description <- function(variable, label) {
  levels_present <- levels(analysis_data[[variable]])
  bind_rows(lapply(levels_present, function(level_value) {
    temp <- analysis_design
    temp$variables$.indicator <- as.numeric(temp$variables[[variable]] == level_value)
    no_temp <- subset(temp, opioid_binary == "no_opioid")
    any_temp <- subset(temp, opioid_binary == "any_opioid")
    overall_stat <- mean_from_design(temp, ".indicator")
    no_stat <- mean_from_design(no_temp, ".indicator")
    any_stat <- mean_from_design(any_temp, ".indicator")
    n_level <- sum(temp$variables[[variable]] == level_value, na.rm = TRUE)
    pooled_p <- overall_stat[["estimate"]]
    denom <- sqrt(max(pooled_p * (1 - pooled_p), .Machine$double.eps))
    suppressed <- n_level < 30
    tibble(
      key = paste0("DESC_", toupper(variable), "_", toupper(make.names(level_value))),
      variable = label,
      level = level_value,
      unit = "proportion",
      overall = ifelse(suppressed, NA_real_, overall_stat[["estimate"]]),
      overall_se = ifelse(suppressed, NA_real_, overall_stat[["se"]]),
      no_opioid = ifelse(suppressed, NA_real_, no_stat[["estimate"]]),
      no_opioid_se = ifelse(suppressed, NA_real_, no_stat[["se"]]),
      any_opioid = ifelse(suppressed, NA_real_, any_stat[["estimate"]]),
      any_opioid_se = ifelse(suppressed, NA_real_, any_stat[["se"]]),
      standardized_difference = ifelse(
        suppressed, NA_real_, (any_stat[["estimate"]] - no_stat[["estimate"]]) / denom
      ),
      unweighted_n = n_level,
      suppressed = suppressed
    )
  }))
}

descriptive_table <- bind_rows(
  numeric_description("AGEY1X", "Age, years"),
  categorical_description("sex", "Sex"),
  categorical_description("race_ethnicity", "Race/ethnicity"),
  categorical_description("region", "Census region"),
  categorical_description("poverty_2", "Family income"),
  categorical_description("insurance", "Insurance"),
  numeric_description("ERTOTY1", "Year-1 ED visits"),
  numeric_description("IPDISY1", "Year-1 inpatient discharges"),
  numeric_description("OPTOTVY1", "Year-1 outpatient visits"),
  numeric_description("OBTOTVY1", "Year-1 office-based visits"),
  categorical_description("physical_health_3", "Physical health"),
  categorical_description("mental_health_3", "Mental health"),
  categorical_description("walk_limitation", "Walking limitation"),
  categorical_description("cancer_y1", "Cancer diagnosis"),
  categorical_description("highest_surgery_setting", "Highest-acuity surgery setting"),
  categorical_description("PANEL", "MEPS panel"),
  numeric_description("surgical_event_count", "Year-1 surgical events")
)

unadjusted_rows <- list()
row_number <- 1
for (exposure_level in levels(analysis_data$opioid_binary)) {
  exposure_design <- subset(analysis_design, opioid_binary == exposure_level)
  count_result <- mean_from_design(exposure_design, "ERTOTY2")
  any_result <- mean_from_design(exposure_design, "any_year2_ed_num")
  n_group <- nrow(exposure_design$variables)
  for (outcome_name in c("ed_count", "any_ed")) {
    result <- if (outcome_name == "ed_count") count_result else any_result
    estimate <- result[["estimate"]]
    se <- result[["se"]]
    suppressed <- n_group < 30 || (!is.na(estimate) && estimate != 0 && abs(se / estimate) > .30)
    unadjusted_rows[[row_number]] <- tibble(
      key = paste0("OUTCOME_", toupper(exposure_level), "_", toupper(outcome_name)),
      exposure = exposure_level,
      poverty = "all",
      outcome = outcome_name,
      estimate = ifelse(suppressed, NA_real_, estimate),
      std_error = ifelse(suppressed, NA_real_, se),
      ci_low = ifelse(suppressed, NA_real_, max(0, estimate - qt(.975, degf(exposure_design)) * se)),
      ci_high = ifelse(suppressed, NA_real_, estimate + qt(.975, degf(exposure_design)) * se),
      unweighted_n = n_group,
      weighted_millions = sum(weights(exposure_design)) / 1e6,
      rse_percent = ifelse(estimate == 0, NA_real_, 100 * abs(se / estimate)),
      suppressed = suppressed
    )
    row_number <- row_number + 1
  }
}
for (poverty_level in levels(analysis_data$poverty_2)) {
  for (exposure_level in levels(analysis_data$opioid_binary)) {
    cell_design <- subset(
      analysis_design,
      poverty_2 == poverty_level & opioid_binary == exposure_level
    )
    result <- mean_from_design(cell_design, "ERTOTY2")
    n_group <- nrow(cell_design$variables)
    estimate <- result[["estimate"]]
    se <- result[["se"]]
    suppressed <- n_group < 30 || (estimate != 0 && abs(se / estimate) > .30)
    unadjusted_rows[[row_number]] <- tibble(
      key = paste0(
        "OUTCOME_", toupper(poverty_level), "_", toupper(exposure_level), "_ED_COUNT"
      ),
      exposure = exposure_level,
      poverty = poverty_level,
      outcome = "ed_count",
      estimate = ifelse(suppressed, NA_real_, estimate),
      std_error = ifelse(suppressed, NA_real_, se),
      ci_low = ifelse(suppressed, NA_real_, max(0, estimate - qt(.975, degf(cell_design)) * se)),
      ci_high = ifelse(suppressed, NA_real_, estimate + qt(.975, degf(cell_design)) * se),
      unweighted_n = n_group,
      weighted_millions = sum(weights(cell_design)) / 1e6,
      rse_percent = ifelse(estimate == 0, NA_real_, 100 * abs(se / estimate)),
      suppressed = suppressed
    )
    row_number <- row_number + 1
  }
}
unadjusted_outcomes <- bind_rows(unadjusted_rows)

eligible_variables <- eligible_design$variables
missingness <- bind_rows(lapply(main_required, function(variable) {
  miss <- is.na(eligible_variables[[variable]])
  no_opioid <- eligible_variables$opioid_binary == "no_opioid"
  any_opioid <- eligible_variables$opioid_binary == "any_opioid"
  no_missing_percent <- 100 * mean(miss[no_opioid])
  any_missing_percent <- 100 * mean(miss[any_opioid])
  temp <- eligible_design
  temp$variables$.missing <- as.numeric(miss)
  weighted <- mean_from_design(temp, ".missing")
  tibble(
    key = paste0("MISS_", toupper(variable)),
    variable = variable,
    missing_n = sum(miss),
    missing_percent = 100 * mean(miss),
    weighted_missing_percent = 100 * weighted[["estimate"]],
    no_opioid_missing_percent = no_missing_percent,
    any_opioid_missing_percent = any_missing_percent,
    absolute_exposure_difference_pp = abs(any_missing_percent - no_missing_percent)
  )
}))
if (max(missingness$missing_percent) > 2) {
  stop_with("a main-model field exceeds 2% missingness")
}
if (max(missingness$absolute_exposure_difference_pp) > 5) {
  stop_with("main-model missingness differs by exposure by more than 5 percentage points")
}

level_specs <- list(
  opioid_binary = levels(analysis_data$opioid_binary),
  sex = levels(analysis_data$sex),
  race_model = levels(analysis_data$race_model),
  region = levels(analysis_data$region),
  poverty_2 = levels(analysis_data$poverty_2),
  insurance_model = levels(analysis_data$insurance_model),
  physical_health_3 = levels(analysis_data$physical_health_3),
  mental_health_3 = levels(analysis_data$mental_health_3),
  walk_limitation = levels(analysis_data$walk_limitation),
  cancer_y1 = levels(analysis_data$cancer_y1),
  surgery_inpatient = c(0, 1),
  surgery_emergency_room = c(0, 1),
  surgery_outpatient = c(0, 1),
  surgery_office_based = c(0, 1),
  PANEL = levels(analysis_data$PANEL)
)
model_level_counts <- bind_rows(lapply(names(level_specs), function(variable) {
  bind_rows(lapply(level_specs[[variable]], function(level_value) {
    in_level <- analysis_data[[variable]] == level_value
    n_level <- sum(in_level, na.rm = TRUE)
    ed_positive <- sum(analysis_data$any_year2_ed_num[in_level] == 1, na.rm = TRUE)
    tibble(
      key = paste0(
        "LEVEL_", toupper(variable), "_", toupper(make.names(as.character(level_value)))
      ),
      variable = variable,
      level = as.character(level_value),
      unweighted_n = n_level,
      ed_positive_n = ed_positive,
      passes_n_50 = n_level >= 50,
      passes_ed_positive_30 = ed_positive >= 30,
      pass = n_level >= 50 & ed_positive >= 30
    )
  }))
}))
if (any(!model_level_counts$pass)) {
  failed_levels <- model_level_counts %>%
    filter(!pass) %>%
    transmute(label = paste0(variable, "=", level, " (N=", unweighted_n,
                             ", ED+=", ed_positive_n, ")"))
  stop_with(paste(
    "main-model categorical level threshold failed:",
    paste(failed_levels$label, collapse = "; ")
  ))
}

dispersion_m1 <- as.numeric(summary(m1)$dispersion)
zero_temp <- analysis_design
zero_temp$variables$.zero <- as.numeric(zero_temp$variables$ERTOTY2 == 0)
weighted_zero <- mean_from_design(zero_temp, ".zero")

calibration_design <- analysis_design
calibration_design$variables$.m1_predicted <- as.numeric(
  predict(m1, type = "response")
)
calibration_design$variables$.m1_residual <- with(
  calibration_design$variables, ERTOTY2 - .m1_predicted
)
calibration_summary <- function(design, key, label) {
  stats <- survey::svymean(
    ~ERTOTY2 + .m1_predicted + .m1_residual, design, na.rm = TRUE
  )
  estimates <- coef(stats)
  standard_errors <- SE(stats)
  df <- survey::degf(design)
  crit <- qt(.975, df)
  difference <- unname(estimates[[".m1_residual"]])
  difference_se <- unname(standard_errors[[".m1_residual"]])
  tibble(
    key = key,
    label = label,
    observed_mean = unname(estimates[["ERTOTY2"]]),
    predicted_mean = unname(estimates[[".m1_predicted"]]),
    observed_minus_predicted = difference,
    std_error = difference_se,
    ci_low = difference - crit * difference_se,
    ci_high = difference + crit * difference_se,
    observed_to_predicted_ratio = unname(
      estimates[["ERTOTY2"]] / estimates[[".m1_predicted"]]
    ),
    unweighted_n = nrow(design$variables),
    design_df = df
  )
}

model_calibration <- bind_rows(
  calibration_summary(
    calibration_design, "M1_CAL_OVERALL", "Overall observed versus predicted"
  ),
  calibration_summary(
    subset(calibration_design, opioid_binary == "no_opioid"),
    "M1_CAL_NO_OPIOID", "No observed linked opioid"
  ),
  calibration_summary(
    subset(calibration_design, opioid_binary == "any_opioid"),
    "M1_CAL_ANY_OPIOID", "Any observed linked opioid"
  )
)

calibration_quantiles <- as.numeric(coef(survey::svyquantile(
  ~.m1_predicted, calibration_design,
  quantiles = seq(.1, .9, by = .1), ci = FALSE, na.rm = TRUE
)))
calibration_breaks <- unique(c(-Inf, calibration_quantiles, Inf))
calibration_design$variables$.prediction_group <- cut(
  calibration_design$variables$.m1_predicted,
  breaks = calibration_breaks, include.lowest = TRUE,
  labels = FALSE
)
for (group_value in sort(unique(calibration_design$variables$.prediction_group))) {
  group_design <- subset(
    calibration_design, .prediction_group == group_value
  )
  model_calibration <- bind_rows(
    model_calibration,
    calibration_summary(
      group_design,
      paste0("M1_CAL_PREDICTION_GROUP_", group_value),
      paste("Predicted-mean group", group_value)
    )
  )
}

calibration_design$variables$.log_m1_predicted <- log(pmax(
  calibration_design$variables$.m1_predicted, 1e-8
))
calibration_intercept_model <- survey::svyglm(
  ERTOTY2 ~ offset(.log_m1_predicted),
  design = calibration_design, family = quasipoisson(link = "log")
)
calibration_slope_model <- survey::svyglm(
  ERTOTY2 ~ .log_m1_predicted,
  design = calibration_design, family = quasipoisson(link = "log")
)
calibration_df <- survey::degf(calibration_design)
calibration_crit <- qt(.975, calibration_df)
calibration_intercept <- unname(coef(calibration_intercept_model)[["(Intercept)"]])
calibration_intercept_se <- unname(
  sqrt(diag(vcov(calibration_intercept_model)))[["(Intercept)"]]
)
calibration_slope <- unname(
  coef(calibration_slope_model)[[".log_m1_predicted"]]
)
calibration_slope_se <- unname(
  sqrt(diag(vcov(calibration_slope_model)))[[".log_m1_predicted"]]
)
calibration_intercept_ci <- calibration_intercept +
  c(-1, 1) * calibration_crit * calibration_intercept_se
calibration_slope_ci <- calibration_slope +
  c(-1, 1) * calibration_crit * calibration_slope_se

model_x <- model.matrix(m1)
condition_number <- kappa(model_x, exact = FALSE)
sampling_weights <- as.numeric(weights(analysis_design))
stratum_psu <- unique(d[, c("STRA9623", "PSU9623")])
psu_per_stratum <- table(stratum_psu$STRA9623)

model_diagnostics <- tibble(
  key = c(
    "RELIABILITY_UNIVERSE_N", "RELIABILITY_ELIGIBLE_N",
    "RELIABILITY_ANALYSIS_N", "RELIABILITY_COMPLETE_CASE_LOSS_PCT",
    "RELIABILITY_FULL_STRATA", "RELIABILITY_FULL_PSU_UNITS",
    "RELIABILITY_FULL_DESIGN_DF", "RELIABILITY_ANALYSIS_DESIGN_DF",
    "RELIABILITY_LONELY_STRATA", "M1_DIAG_DISPERSION",
    "M1_DIAG_ZERO_PROPORTION_UNWEIGHTED", "M1_DIAG_ZERO_PROPORTION_WEIGHTED",
    "M1_DIAG_CONDITION_NUMBER", "M1_DIAG_PARAMETER_COUNT",
    "M1_DIAG_ED_POSITIVE_PER_PARAMETER", "M1_DIAG_WEIGHT_MAX_TO_MEDIAN",
    "M1_DIAG_CONVERGED", "M2_DIAG_CONVERGED", "M3_DIAG_CONVERGED"
  ),
  metric = c(
    "Positive-weight pooled universe N", "Eligible N", "Complete-case model N",
    "Complete-case loss percent", "Full design strata", "Full stratum-PSU units",
    "Full design degrees of freedom", "Analysis design degrees of freedom",
    "Lonely strata", "Quasi-Poisson dispersion", "Zero proportion unweighted",
    "Zero proportion weighted", "Model-matrix condition number",
    "M1 parameter count", "ED-positive per M1 parameter",
    "Maximum-to-median sampling weight ratio", "M1 convergence", "M2 convergence",
    "M3 convergence"
  ),
  value = c(
    nrow(d), eligible_n, analysis_n, complete_case_loss_pct,
    length(unique(d$STRA9623)), nrow(stratum_psu), degf(full_design),
    degf(analysis_design), sum(psu_per_stratum == 1), dispersion_m1,
    mean(analysis_data$ERTOTY2 == 0), weighted_zero[["estimate"]],
    condition_number, length(coef(m1)),
    sum(analysis_data$any_year2_ed_num) / length(coef(m1)),
    max(sampling_weights) / median(sampling_weights),
    as.numeric(m1$converged), as.numeric(m2$converged), as.numeric(m3$converged)
  ),
  threshold = c(
    41427, 4468, NA, 5, NA, NA, 100, 100, 0, NA, NA, NA,
    1000, NA, 10, NA, 1, 1, 1
  ),
  pass = c(
    nrow(d) == 41427,
    eligible_n == 4468,
    analysis_n > 0,
    complete_case_loss_pct <= 5,
    TRUE, TRUE,
    degf(full_design) > 100,
    degf(analysis_design) > 100,
    sum(psu_per_stratum == 1) == 0,
    is.finite(dispersion_m1),
    TRUE, TRUE,
    is.finite(condition_number),
    TRUE,
    sum(analysis_data$any_year2_ed_num) / length(coef(m1)) >= 10,
    TRUE,
    m1$converged, m2$converged, m3$converged
  )
)
model_diagnostics <- bind_rows(
  model_diagnostics,
  tibble(
    key = c("M1_DIAG_MIN_LEVEL_N", "M1_DIAG_MIN_LEVEL_ED_POSITIVE"),
    metric = c(
      "Minimum unweighted N across main-model categorical levels",
      "Minimum ED-positive N across main-model categorical levels"
    ),
    value = c(
      min(model_level_counts$unweighted_n),
      min(model_level_counts$ed_positive_n)
    ),
    threshold = c(50, 30),
    pass = c(
      min(model_level_counts$unweighted_n) >= 50,
      min(model_level_counts$ed_positive_n) >= 30
    )
  )
)
model_diagnostics <- bind_rows(
  model_diagnostics,
  tibble(
    key = c(
      "M1_DIAG_CALIBRATION_OVERALL",
      "M1_DIAG_CALIBRATION_BY_EXPOSURE",
      "M1_DIAG_CALIBRATION_PREDICTION_GROUPS",
      "M1_DIAG_CALIBRATION_INTERCEPT",
      "M1_DIAG_CALIBRATION_SLOPE"
    ),
    metric = c(
      "Overall observed-minus-predicted mean includes zero",
      "Exposure-specific observed-minus-predicted means include zero",
      "Prediction-group observed-minus-predicted means include zero",
      "Calibration intercept includes zero",
      "Calibration slope includes one"
    ),
    value = c(
      model_calibration$observed_minus_predicted[
        model_calibration$key == "M1_CAL_OVERALL"
      ],
      max(abs(model_calibration$observed_minus_predicted[
        model_calibration$key %in% c("M1_CAL_NO_OPIOID", "M1_CAL_ANY_OPIOID")
      ])),
      max(abs(model_calibration$observed_minus_predicted[
        grepl("^M1_CAL_PREDICTION_GROUP_", model_calibration$key)
      ])),
      calibration_intercept,
      calibration_slope
    ),
    threshold = c(0, 0, 0, 0, 1),
    pass = c(
      with(
        model_calibration[model_calibration$key == "M1_CAL_OVERALL", ],
        ci_low <= 0 & ci_high >= 0
      ),
      all(with(
        model_calibration[
          model_calibration$key %in% c(
            "M1_CAL_NO_OPIOID", "M1_CAL_ANY_OPIOID"
          ), ],
        ci_low <= 0 & ci_high >= 0
      )),
      all(with(
        model_calibration[
          grepl("^M1_CAL_PREDICTION_GROUP_", model_calibration$key),
        ],
        ci_low <= 0 & ci_high >= 0
      )),
      calibration_intercept_ci[1] <= 0 & calibration_intercept_ci[2] >= 0,
      calibration_slope_ci[1] <= 1 & calibration_slope_ci[2] >= 1
    )
  )
)

fit_sensitivity <- function(id, formula, design, exposure = "opioid_binary") {
  result <- tryCatch({
    model <- svyglm(
      formula, design = design,
      family = quasipoisson(link = "log"), influence = TRUE
    )
    if (!isTRUE(model$converged) || any(!is.finite(coef(model)))) {
      stop("nonconverged or nonfinite")
    }
    rows <- standardize_pair(model, design, exposure, id, "log")
    rows %>%
      filter(grepl("_RATIO$|_DIFFERENCE$", key)) %>%
      mutate(analysis_id = id, converged = TRUE, error = NA_character_)
  }, error = function(e) {
    tibble(
      key = paste0(id, "_FAILED"),
      label = id,
      estimand = "model_failure",
      estimate = NA_real_,
      std_error = NA_real_,
      ci_low = NA_real_,
      ci_high = NA_real_,
      p_value = NA_real_,
      unweighted_n = nrow(design$variables),
      weighted_millions = sum(weights(design)) / 1e6,
      design_df = degf(design),
      model_status = "failed",
      suppressed = TRUE,
      analysis_id = id,
      converged = FALSE,
      error = conditionMessage(e)
    )
  })
  result
}

s04_formula <- update(m1_formula, . ~ . - surgery_emergency_room)
s05_formula <- update(m1_formula, . ~ . - cancer_y1)
sensitivity_results <- bind_rows(
  fit_sensitivity(
    "S01_EXCLUDE_PANEL25", m1_formula,
    subset(analysis_design, PANEL != "25")
  ),
  fit_sensitivity("S04_NON_ER_SURGERY", s04_formula, subset(
    analysis_design,
    surgery_emergency_room == 0 &
      (surgery_inpatient == 1 | surgery_outpatient == 1 | surgery_office_based == 1)
  )),
  fit_sensitivity(
    "S05_EXCLUDE_CANCER", s05_formula,
    subset(analysis_design, cancer_y1 == "no")
  )
)

s06_formula <- update(m1_formula, . ~ . - opioid_binary + all_opioid_binary)
sensitivity_results <- bind_rows(
  sensitivity_results,
  fit_sensitivity(
    "S06_ALL_YEAR1_OPIOIDS", s06_formula, analysis_design,
    exposure = "all_opioid_binary"
  )
)

limitation_specs <- c(
  S07A_ACTIVITY_LIMIT = "activity_limitation",
  S07B_IADL_LIMIT = "iadl_limitation",
  S07C_ADL_LIMIT = "adl_limitation"
)
for (id in names(limitation_specs)) {
  variable <- unname(limitation_specs[[id]])
  formula <- update(m1_formula, paste(". ~ . +", variable))
  sensitivity_mask <- !is.na(analysis_design$variables[[variable]])
  sensitivity_design <- analysis_design[sensitivity_mask, ]
  sensitivity_results <- bind_rows(
    sensitivity_results,
    fit_sensitivity(id, formula, sensitivity_design)
  )
}

s08_formula <- update(m1_formula, . ~ . - ns(AGEY1X, 3) + age_category)
sensitivity_results <- bind_rows(
  sensitivity_results,
  fit_sensitivity("S08_AGE_CATEGORIES", s08_formula, analysis_design)
)

weight_cap <- as.numeric(quantile(
  analysis_data$pool_weight, probs = .99, na.rm = TRUE, names = FALSE
))
d$pool_weight_capped <- pmin(d$pool_weight, weight_cap)
capped_design <- svydesign(
  ids = ~PSU9623, strata = ~STRA9623, weights = ~pool_weight_capped,
  data = d, nest = TRUE
)
capped_analysis <- subset(capped_design, domain_eligible == 1 & complete_case == 1)
sensitivity_results <- bind_rows(
  sensitivity_results,
  fit_sensitivity("S09_WEIGHT_CAP_99", m1_formula, capped_analysis)
)

unadjusted_formula <- ERTOTY2 ~ opioid_binary
minimal_formula <- ERTOTY2 ~ opioid_binary + ns(AGEY1X, 3) + sex +
  race_model + poverty_2 + PANEL
sensitivity_results <- bind_rows(
  sensitivity_results,
  fit_sensitivity("S10A_UNADJUSTED", unadjusted_formula, analysis_design),
  fit_sensitivity("S10B_MINIMAL", minimal_formula, analysis_design)
)

m3_secondary <- standardized_results %>%
  filter(grepl("^M3_ANYED", key)) %>%
  mutate(
    key = sub("^M3_ANYED", "S02_ANY_ED", key),
    analysis_id = "S02_ANY_ED", converged = TRUE, error = NA_character_
  )
sensitivity_results <- bind_rows(sensitivity_results, m3_secondary)

m_pov3 <- tryCatch(
  svyglm(
    update(m1_formula, . ~ . - poverty_2 + poverty_3 + opioid_binary:poverty_3),
    design = analysis_design,
    family = quasipoisson(link = "log")
  ),
  error = function(e) NULL
)
if (!is.null(m_pov3) && isTRUE(m_pov3$converged)) {
  test_pov3 <- regTermTest(m_pov3, ~opioid_binary:poverty_3, method = "Wald")
  sensitivity_results <- bind_rows(
    sensitivity_results,
    tibble(
      key = "S03_POVERTY3_INTERACTION_WALD",
      label = "Three-level poverty interaction",
      estimand = "wald_interaction_test",
      estimate = as.numeric(test_pov3$Ftest),
      std_error = NA_real_,
      ci_low = NA_real_,
      ci_high = NA_real_,
      p_value = as.numeric(test_pov3$p),
      unweighted_n = analysis_n,
      weighted_millions = sum(weights(analysis_design)) / 1e6,
      design_df = degf(analysis_design),
      model_status = "pass",
      suppressed = FALSE,
      analysis_id = "S03_POVERTY3",
      converged = TRUE,
      error = NA_character_
    )
  )
} else {
  sensitivity_results <- bind_rows(
    sensitivity_results,
    tibble(
      key = "S03_POVERTY3_FAILED", label = "Three-level poverty interaction",
      estimand = "model_failure", estimate = NA_real_, std_error = NA_real_,
      ci_low = NA_real_, ci_high = NA_real_, p_value = NA_real_,
      unweighted_n = analysis_n,
      weighted_millions = sum(weights(analysis_design)) / 1e6,
      design_df = degf(analysis_design), model_status = "failed",
      suppressed = TRUE, analysis_id = "S03_POVERTY3",
      converged = FALSE, error = "model failed"
    )
  )
}

primary_sensitivity_failures <- sensitivity_results %>%
  filter(analysis_id %in% c(
    "S01_EXCLUDE_PANEL25", "S04_NON_ER_SURGERY", "S05_EXCLUDE_CANCER",
    "S06_ALL_YEAR1_OPIOIDS", "S08_AGE_CATEGORIES", "S09_WEIGHT_CAP_99",
    "S10A_UNADJUSTED", "S10B_MINIMAL"
  )) %>%
  filter(!converged)
if (nrow(primary_sensitivity_failures) > 0) {
  stop_with(paste(
    "required sensitivity model(s) failed:",
    paste(
      unique(paste0(
        primary_sensitivity_failures$analysis_id,
        " [", primary_sensitivity_failures$error, "]"
      )),
      collapse = ", "
    )
  ))
}

fit_revision_model <- function(id, formula, design, block, timing_note) {
  tryCatch({
    model <- survey::svyglm(
      formula, design = design,
      family = quasipoisson(link = "log"), influence = TRUE
    )
    if (!isTRUE(model$converged) || any(!is.finite(coef(model)))) {
      stop("nonconverged or nonfinite")
    }
    standardize_pair(model, design, "opioid_binary", id, "log") %>%
      filter(grepl("_RATIO$|_DIFFERENCE$", key)) %>%
      mutate(
        model_id = id,
        covariate_block = block,
        timing_note = timing_note,
        converged = TRUE,
        supported = TRUE,
        error = NA_character_
      )
  }, error = function(e) {
    tibble(
      key = paste0(id, "_FAILED"),
      label = id,
      estimand = "model_failure",
      estimate = NA_real_, std_error = NA_real_,
      ci_low = NA_real_, ci_high = NA_real_, p_value = NA_real_,
      unweighted_n = nrow(design$variables),
      weighted_millions = sum(weights(design)) / 1e6,
      design_df = degf(design), model_status = "failed",
      suppressed = TRUE, model_id = id, covariate_block = block,
      timing_note = timing_note, converged = FALSE, supported = FALSE,
      error = conditionMessage(e)
    )
  })
}

nested_formula_1 <- ERTOTY2 ~ opioid_binary + ns(AGEY1X, 3) + sex +
  race_model + region + poverty_2 + insurance_model + PANEL
nested_formula_2 <- update(
  nested_formula_1,
  . ~ . + log1p(ERTOTY1) + log1p(IPDISY1) +
    log1p(OPTOTVY1) + log1p(OBTOTVY1)
)
nested_formula_3 <- update(
  nested_formula_2,
  . ~ . + physical_health_3 + mental_health_3 +
    walk_limitation + cancer_y1
)
nested_adjustment_results <- bind_rows(
  fit_revision_model(
    "R3_N1_STRUCTURAL", nested_formula_1, analysis_design,
    "Structural sociodemographic covariates",
    "Age, sex, race/ethnicity, region, poverty, insurance, and panel; exposure may occur at any point in year 1."
  ),
  fit_revision_model(
    "R3_N2_UTILIZATION", nested_formula_2, analysis_design,
    "N1 plus year-1 utilization",
    "Year-1 utilization accumulates during the exposure year and is not guaranteed to precede the prescription record."
  ),
  fit_revision_model(
    "R3_N3_HEALTH", nested_formula_3, analysis_design,
    "N2 plus year-1 health status",
    "Health measures describe year 1 and are not guaranteed to precede the prescription record."
  ),
  fit_revision_model(
    "R3_N4_FULL", m1_formula, analysis_design,
    "N3 plus surgical/procedure setting and event count",
    "Setting and event-count measures accumulate during the same year as exposure; this is the prespecified primary specification."
  )
)
if (any(!nested_adjustment_results$converged)) {
  stop_with("one or more required nested adjustment models failed")
}

setting_specs <- c(
  inpatient = "surgery_inpatient",
  emergency_room = "surgery_emergency_room",
  outpatient = "surgery_outpatient",
  office_based = "surgery_office_based"
)
setting_support <- bind_rows(lapply(names(setting_specs), function(setting_name) {
  setting_variable <- unname(setting_specs[[setting_name]])
  in_setting <- analysis_data[[setting_variable]] == 1
  setting_weight_total <- sum(analysis_data$pool_weight[in_setting])
  bind_rows(lapply(levels(analysis_data$opioid_binary), function(exposure_level) {
    in_cell <- in_setting &
      analysis_data$opioid_binary == exposure_level
    n_cell <- sum(in_cell)
    ed_positive <- sum(analysis_data$any_year2_ed_num[in_cell] == 1)
    cell_weight_total <- sum(analysis_data$pool_weight[in_cell])
    tibble(
      key = paste0(
        "R4_SUPPORT_", toupper(setting_name), "_", toupper(exposure_level)
      ),
      setting = setting_name,
      exposure = exposure_level,
      unweighted_n = n_cell,
      weighted_millions = cell_weight_total / 1e6,
      weighted_percent_within_setting = 100 * cell_weight_total /
        setting_weight_total,
      ed_positive_n = ed_positive,
      passes_n_50 = n_cell >= 50,
      passes_ed_positive_30 = ed_positive >= 30,
      supported = n_cell >= 50 & ed_positive >= 30
    )
  }))
}))

setting_stratified_results <- bind_rows(lapply(names(setting_specs), function(
  setting_name
) {
  setting_variable <- unname(setting_specs[[setting_name]])
  support_rows <- setting_support %>% filter(setting == setting_name)
  setting_supported <- all(support_rows$supported)
  if (!setting_supported) {
    return(tibble(
      key = paste0("R4_", toupper(setting_name), "_NOT_ESTIMATED"),
      label = paste(setting_name, "setting-specific contrast"),
      estimand = "not_estimated_sparse_support",
      estimate = NA_real_, std_error = NA_real_,
      ci_low = NA_real_, ci_high = NA_real_, p_value = NA_real_,
      unweighted_n = sum(support_rows$unweighted_n),
      weighted_millions = NA_real_, design_df = NA_real_,
      model_status = "not_estimated", suppressed = TRUE,
      model_id = paste0("R4_", toupper(setting_name)),
      covariate_block = paste("Full model excluding constant", setting_variable),
      timing_note = "Setting-specific model withheld because at least one exposure cell had fewer than 30 ED-positive participants.",
      converged = NA, supported = FALSE, error = "sparse ED-positive support"
    ))
  }
  setting_design <- analysis_design[
    analysis_design$variables[[setting_variable]] == 1,
  ]
  setting_formula <- update(
    m1_formula, paste(". ~ . -", setting_variable)
  )
  fit_revision_model(
    paste0("R4_", toupper(setting_name)),
    setting_formula, setting_design,
    paste("Full model within", setting_name, "events"),
    "Participants can have qualifying events in more than one setting; contrasts are setting-restricted, not mutually exclusive strata."
  )
}))

reliability_flags <- bind_rows(
  descriptive_table %>%
    transmute(
      key = paste0("RELIABILITY_", key),
      source_key = key,
      issue = ifelse(suppressed, "unweighted_n_below_30", "none"),
      pass = !suppressed
    ),
  unadjusted_outcomes %>%
    transmute(
      key = paste0("RELIABILITY_", key),
      source_key = key,
      issue = case_when(
        unweighted_n < 30 ~ "unweighted_n_below_30",
        rse_percent > 30 ~ "rse_above_30_percent",
        TRUE ~ "none"
      ),
      pass = !suppressed
    ),
  model_diagnostics %>%
    transmute(
      key = paste0("RELIABILITY_", key),
      source_key = key,
      issue = ifelse(pass, "none", "diagnostic_threshold_failed"),
      pass = pass
    ),
  model_level_counts %>%
    transmute(
      key = paste0("RELIABILITY_", key),
      source_key = key,
      issue = ifelse(pass, "none", "model_level_threshold_failed"),
      pass = pass
    )
)

if (!all(model_diagnostics$pass)) {
  failed <- model_diagnostics$key[!model_diagnostics$pass]
  stop_with(paste("primary diagnostic failure:", paste(failed, collapse = ", ")))
}

flow <- readr::read_csv(
  file.path(output_dir, "cohort_flow.csv"), show_col_types = FALSE
)
flow_long <- bind_rows(
  tibble(stage = "Longitudinal records", n = sum(flow$longitudinal_records)),
  tibble(stage = "Complete-panel adults", n = sum(flow$complete_panel_adults)),
  tibble(stage = "Persons with surgical event", n = sum(flow$persons_with_surgical_event)),
  tibble(
    stage = "Persons with linked surgical condition",
    n = sum(flow$persons_with_linked_surgical_condition)
  ),
  tibble(stage = "Eligible analytic cohort", n = sum(flow$eligible_complete_adults)),
  tibble(stage = "Complete-case analysis cohort", n = nrow(analysis_data))
) %>%
  mutate(stage = factor(stage, levels = rev(stage)))

figure1 <- ggplot(flow_long, aes(x = n, y = stage)) +
  geom_col(fill = "#355C7D", width = .7) +
  geom_text(aes(label = scales::comma(n)), hjust = -0.08, size = 3.5) +
  scale_x_continuous(
    labels = scales::comma,
    expand = expansion(mult = c(0, .17))
  ) +
  labs(
    title = "Aggregate cohort construction across four longitudinal MEPS panels",
    x = "Unweighted persons", y = NULL,
    caption = paste(
      "Panels 22, 23, 25, and 26; totals are summed across panels.",
      "Panel-specific counts appear in Supplementary Table S3."
    )
  ) +
  theme_minimal(base_size = 11)
paper_figures_dir <- file.path(project_dir, "paper", "figures")
dir.create(paper_figures_dir, recursive = TRUE, showWarnings = FALSE)
ggsave(file.path(output_dir, "figure1_cohort_flow.svg"), figure1, width = 8, height = 4.6)
ggsave(file.path(output_dir, "figure1_cohort_flow.png"), figure1, width = 8, height = 4.6, dpi = 300)
ggsave(file.path(paper_figures_dir, "figure1_cohort_flow.svg"), figure1, width = 8, height = 4.6)
ggsave(file.path(paper_figures_dir, "figure1_cohort_flow.png"), figure1, width = 8, height = 4.6, dpi = 300)

figure2_data <- interaction_results %>%
  filter(grepl("_MEAN$", key), grepl("^M2_", key)) %>%
  mutate(
    poverty = case_when(
      grepl("200_PLUS", key) ~ "At or above 200% FPL",
      grepl("BELOW_200", key) ~ "Below 200% FPL",
      TRUE ~ "Unknown"
    ),
    exposure = factor(
      ifelse(grepl("ANY_OPIOID", key), "Any linked opioid", "No linked opioid"),
      levels = c("No linked opioid", "Any linked opioid")
    )
  )
if (nrow(figure2_data) != 4) stop_with("interaction margin figure lacks four cells")
figure2 <- ggplot(
  figure2_data,
  aes(x = exposure, y = estimate, color = poverty, group = poverty)
) +
  geom_point(position = position_dodge(width = .35), size = 2.5) +
  geom_errorbar(
    aes(ymin = ci_low, ymax = ci_high),
    position = position_dodge(width = .35), width = .12
  ) +
  scale_color_manual(values = c("#C44E52", "#355C7D")) +
  labs(
    title = "Adjusted year-2 emergency-department visit counts",
    subtitle = "Survey-standardized means by observed condition-linked opioid prescription and poverty",
    x = NULL, y = "Adjusted mean annual ED visits", color = "Year-1 poverty",
    caption = "Associational estimates from a design-based quasi-Poisson model; 95% CIs."
  ) +
  theme_minimal(base_size = 11) +
  theme(legend.position = "bottom")
ggsave(file.path(output_dir, "figure2_adjusted_means.svg"), figure2, width = 7.5, height = 5)
ggsave(file.path(output_dir, "figure2_adjusted_means.png"), figure2, width = 7.5, height = 5, dpi = 300)
ggsave(file.path(paper_figures_dir, "figure2_adjusted_means.svg"), figure2, width = 7.5, height = 5)
ggsave(file.path(paper_figures_dir, "figure2_adjusted_means.png"), figure2, width = 7.5, height = 5, dpi = 300)

write_csv_stable(missingness, "missingness.csv")
write_csv_stable(model_level_counts, "model_level_counts.csv")
write_csv_stable(descriptive_table, "descriptive_table.csv")
write_csv_stable(unadjusted_outcomes, "unadjusted_outcomes.csv")
write_csv_stable(model_coefficients, "model_coefficients.csv")
write_csv_stable(standardized_results, "standardized_results.csv")
write_csv_stable(interaction_results, "interaction_results.csv")
write_csv_stable(model_diagnostics, "model_diagnostics.csv")
write_csv_stable(model_calibration, "model_calibration.csv")
write_csv_stable(sensitivity_results, "sensitivity_results.csv")
write_csv_stable(nested_adjustment_results, "nested_adjustment_results.csv")
write_csv_stable(setting_support, "setting_support.csv")
write_csv_stable(setting_stratified_results, "setting_stratified_results.csv")
write_csv_stable(reliability_flags, "reliability_flags.csv")

table1_display <- descriptive_table %>%
  mutate(
    overall_display = ifelse(
      unit == "proportion",
      sprintf("%.1f%%", 100 * overall),
      sprintf("%.2f", overall)
    ),
    no_opioid_display = ifelse(
      unit == "proportion",
      sprintf("%.1f%%", 100 * no_opioid),
      sprintf("%.2f", no_opioid)
    ),
    any_opioid_display = ifelse(
      unit == "proportion",
      sprintf("%.1f%%", 100 * any_opioid),
      sprintf("%.2f", any_opioid)
    )
  ) %>%
  select(variable, level, overall_display, no_opioid_display, any_opioid_display,
         standardized_difference, unweighted_n, suppressed)
writeLines(
  c("# Table 1. Weighted characteristics", "", markdown_table(table1_display)),
  file.path(output_dir, "table1.md"), useBytes = TRUE
)

table2_display <- unadjusted_outcomes %>%
  mutate(
    estimate_ci = ifelse(
      suppressed, "Suppressed",
      sprintf("%.3f (95%% CI %.3f to %.3f)", estimate, ci_low, ci_high)
    )
  ) %>%
  select(exposure, poverty, outcome, estimate_ci, unweighted_n,
         weighted_millions, rse_percent, suppressed)
writeLines(
  c("# Table 2. Unadjusted year-2 ED outcomes", "", markdown_table(table2_display)),
  file.path(output_dir, "table2.md"), useBytes = TRUE
)

table3_data <- bind_rows(
  standardized_results,
  interaction_results %>% filter(
    key %in% c("M2_INT_WALD", "M2_INT_RATIO_OF_RATIOS") |
      grepl("_RATIO$|_DIFFERENCE$", key)
  )
) %>%
  mutate(
    estimate_ci = ifelse(
      estimand == "wald_interaction_test",
      sprintf("F=%.3f; p=%.4f", estimate, p_value),
      sprintf("%.3f (95%% CI %.3f to %.3f)", estimate, ci_low, ci_high)
    )
  ) %>%
  select(key, label, estimand, estimate_ci, p_value, unweighted_n, design_df)
writeLines(
  c("# Table 3. Adjusted associations and standardized outcomes", "",
    markdown_table(table3_data)),
  file.path(output_dir, "table3.md"), useBytes = TRUE
)

all_key_sources <- bind_rows(
  missingness %>% transmute(key, file = "missingness.csv"),
  model_level_counts %>% transmute(key, file = "model_level_counts.csv"),
  descriptive_table %>% transmute(key, file = "descriptive_table.csv"),
  unadjusted_outcomes %>% transmute(key, file = "unadjusted_outcomes.csv"),
  model_coefficients %>% transmute(key, file = "model_coefficients.csv"),
  standardized_results %>% transmute(key, file = "standardized_results.csv"),
  interaction_results %>% transmute(key, file = "interaction_results.csv"),
  model_diagnostics %>% transmute(key, file = "model_diagnostics.csv"),
  model_calibration %>% transmute(key, file = "model_calibration.csv"),
  sensitivity_results %>% transmute(key, file = "sensitivity_results.csv"),
  nested_adjustment_results %>% transmute(key, file = "nested_adjustment_results.csv"),
  setting_support %>% transmute(key, file = "setting_support.csv"),
  setting_stratified_results %>% transmute(key, file = "setting_stratified_results.csv"),
  reliability_flags %>% transmute(key, file = "reliability_flags.csv")
) %>%
  arrange(key) %>%
  mutate(row_number = row_number())
if (anyDuplicated(all_key_sources$key)) {
  duplicates <- unique(all_key_sources$key[duplicated(all_key_sources$key)])
  stop_with(paste("duplicate stable output keys:", paste(duplicates, collapse = ", ")))
}
write_csv_stable(all_key_sources, "results_index.csv")

environment <- list(
  r_version = R.version.string,
  python_version = paste(
    system2("python", "--version", stdout = TRUE, stderr = TRUE),
    collapse = " "
  ),
  platform = R.version$platform,
  packages = list(
    survey = as.character(packageVersion("survey")),
    readr = as.character(packageVersion("readr")),
    dplyr = as.character(packageVersion("dplyr")),
    tidyr = as.character(packageVersion("tidyr")),
    ggplot2 = as.character(packageVersion("ggplot2")),
    jsonlite = as.character(packageVersion("jsonlite")),
    digest = as.character(packageVersion("digest"))
  ),
  survey_lonely_psu_option = getOption("survey.lonely.psu"),
  model_input_md5 = unname(tools::md5sum(model_input)),
  model_input_sha256 = digest::digest(
    file = model_input, algo = "sha256", serialize = FALSE
  ),
  python_script_sha256 = digest::digest(
    file = file.path(project_dir, "analysis", "meps_analysis.py"),
    algo = "sha256", serialize = FALSE
  ),
  r_script_sha256 = digest::digest(
    file = file.path(project_dir, "analysis", "meps_analysis.R"),
    algo = "sha256", serialize = FALSE
  ),
  person_level_output_in_workspace = FALSE
)
jsonlite::write_json(
  environment, file.path(output_dir, "analysis_environment.json"),
  pretty = TRUE, auto_unbox = TRUE
)

source_metadata <- list(
  dataset = "AHRQ Medical Expenditure Panel Survey Household Component",
  panels = c(22, 23, 25, 26),
  year_pairs = c("2017-2018", "2018-2019", "2020-2021", "2021-2022"),
  pooled_design_file = "HC-036 1996-2023",
  extraction_script = "analysis/meps_analysis.py",
  model_script = "analysis/meps_analysis.R",
  protocol = "research/analysis_protocol.md",
  aggregate_outputs_only = TRUE
)
jsonlite::write_json(
  source_metadata, file.path(output_dir, "source_metadata.json"),
  pretty = TRUE, auto_unbox = TRUE
)

get_result <- function(frame, key) frame %>% filter(.data$key == !!key) %>% slice(1)
primary_ratio <- get_result(standardized_results, "M1_MARGIN_RATIO")
primary_difference <- get_result(standardized_results, "M1_MARGIN_DIFFERENCE")
anyed_difference <- get_result(standardized_results, "M3_ANYED_DIFFERENCE")
interaction_row <- get_result(interaction_results, "M2_INT_WALD")

primary_interpretation <- if (
  primary_ratio$ci_low <= 1 && primary_ratio$ci_high >= 1
) {
  "The adjusted interval included no association on the ratio scale."
} else if (primary_ratio$estimate > 1) {
  "Observed condition-linked opioid prescriptions were associated with higher subsequent annual ED counts."
} else {
  "Observed condition-linked opioid prescriptions were associated with lower subsequent annual ED counts."
}
interaction_interpretation <- if (interaction_row$p_value < .05) {
  "The direct exposure-by-poverty interaction was statistically distinguishable from zero."
} else {
  "The direct exposure-by-poverty interaction did not provide clear evidence of different associations."
}

summary_lines <- c(
  "# Survey-weighted analysis summary",
  "",
  "## Cohort and design",
  "",
  sprintf(
    "The analytic cohort contained %s complete cases from %s eligible adults (%.2f%% excluded for main-covariate missingness).",
    scales::comma(analysis_n), scales::comma(eligible_n), complete_case_loss_pct
  ),
  sprintf(
    "The full pooled survey design had %s strata, %s stratum-PSU units, and %s design degrees of freedom.",
    length(unique(d$STRA9623)), nrow(stratum_psu), degf(full_design)
  ),
  "",
  "## Primary adjusted association",
  "",
  sprintf(
    "The standardized adjusted mean count ratio was %.3f (95%% CI %.3f to %.3f), and the adjusted mean difference was %.3f visits (95%% CI %.3f to %.3f).",
    primary_ratio$estimate, primary_ratio$ci_low, primary_ratio$ci_high,
    primary_difference$estimate, primary_difference$ci_low,
    primary_difference$ci_high
  ),
  primary_interpretation,
  "",
  "## Poverty interaction and any-ED outcome",
  "",
  sprintf(
    "The prespecified exposure-by-poverty interaction had p=%.4f. %s",
    interaction_row$p_value, interaction_interpretation
  ),
  sprintf(
    "For any year-2 ED use, the standardized adjusted risk difference was %.3f (95%% CI %.3f to %.3f).",
    anyed_difference$estimate, anyed_difference$ci_low, anyed_difference$ci_high
  ),
  "",
  "## Interpretation boundary",
  "",
  paste(
    "These are associational estimates for observed condition-linked opioid",
    "prescriptions and subsequent annual all-cause ED use. They do not measure",
    "postoperative timing, opioid consumption, opioid-sparing care, or a causal effect."
  ),
  ""
)
writeLines(summary_lines, file.path(output_dir, "analysis_summary.md"), useBytes = TRUE)

reproducibility_outputs <- c(
  "missingness.csv", "model_level_counts.csv", "descriptive_table.csv",
  "unadjusted_outcomes.csv", "model_coefficients.csv",
  "standardized_results.csv", "interaction_results.csv",
  "model_diagnostics.csv", "model_calibration.csv",
  "sensitivity_results.csv", "nested_adjustment_results.csv",
  "setting_support.csv", "setting_stratified_results.csv",
  "reliability_flags.csv", "results_index.csv",
  "table1.md", "table2.md", "table3.md",
  "figure1_cohort_flow.png", "figure1_cohort_flow.svg",
  "figure2_adjusted_means.png", "figure2_adjusted_means.svg",
  "analysis_summary.md", "analysis_environment.json", "source_metadata.json"
)
reproducibility_paths <- file.path(output_dir, reproducibility_outputs)
if (any(!file.exists(reproducibility_paths))) {
  stop_with(paste(
    "reproducibility output missing:",
    paste(reproducibility_outputs[!file.exists(reproducibility_paths)], collapse = ", ")
  ))
}
code_artifacts <- c("analysis/meps_analysis.py", "analysis/meps_analysis.R")
code_paths <- file.path(project_dir, code_artifacts)
ledger <- tibble(
  artifact = c(reproducibility_outputs, code_artifacts),
  artifact_type = c(
    rep("aggregate_output", length(reproducibility_outputs)),
    rep("analysis_code", length(code_artifacts))
  ),
  current_sha256 = vapply(
    c(reproducibility_paths, code_paths),
    function(path) digest::digest(
      file = path, algo = "sha256", serialize = FALSE
    ),
    character(1)
  )
) %>%
  left_join(
    prior_ledger %>%
      select(artifact, prior_run_sha256 = current_sha256),
    by = "artifact"
  ) %>%
  mutate(
    identical_to_prior_run = !is.na(prior_run_sha256) &
      prior_run_sha256 == current_sha256
  ) %>%
  select(
    artifact, artifact_type, prior_run_sha256, current_sha256,
    identical_to_prior_run
  )
write_csv_stable(ledger, "reproducibility_ledger.csv")

if (Sys.getenv("MEPS_DELETE_MODEL_INPUT", "1") == "1") {
  unlink(model_input)
}

cat(jsonlite::toJSON(
  list(
    status = "complete",
    universe_n = nrow(d),
    eligible_n = eligible_n,
    analysis_n = analysis_n,
    primary_ratio = primary_ratio$estimate,
    primary_ratio_ci = c(primary_ratio$ci_low, primary_ratio$ci_high),
    poverty_interaction_p = interaction_row$p_value,
    output_keys = nrow(all_key_sources)
  ),
  auto_unbox = TRUE, pretty = TRUE
))
cat("\n")
