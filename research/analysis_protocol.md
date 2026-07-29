# Frozen statistical analysis protocol

**Protocol version:** 1.0  
**Freeze date:** 2026-07-28  
**Status:** Frozen before adjusted exposure–outcome modeling  
**Target design:** Longitudinal observational cohort analysis of pooled MEPS
panels  
**Reporting framework:** STROBE cohort checklist

Any change after comparative models are first run must be recorded in
`research/analysis_deviations.md` with the date, reason, affected outputs, and
whether the change was made with knowledge of results.

## 1. Approved question and title

### Working title

> **Condition-Linked Opioid Prescriptions and Subsequent Emergency Department
> Use Among U.S. Adults With Surgery-Associated Conditions: A Longitudinal MEPS
> Study**

### Research question

> Among U.S. adults with a year-1 surgical event linked to a condition, is any
> prescription opioid linked to that same condition during year 1 associated
> with year-2 annual all-cause emergency-department utilization, and does this
> association differ between people below versus at or above 200% of the
> federal poverty level?

This is not an opioid-sparing, multimodal-analgesia, postoperative, 30-day, or
causal study.

## 2. Design and target population

The study pools four independent two-year MEPS longitudinal cohorts:

- Panel 22: 2017 exposure year, 2018 outcome year;
- Panel 23: 2018 exposure year, 2019 outcome year;
- Panel 25: 2020 exposure year, 2021 outcome year; and
- Panel 26: 2021 exposure year, 2022 outcome year.

The target population is U.S. civilian noninstitutionalized adults represented
by these panels who meet the eligibility definition below. Estimates average
across the four included two-year panel periods; they are not single-calendar-
year postoperative rates.

### Inclusion criteria

1. Target panel member.
2. `ALL5RDS == 1`.
3. `AGEY1X >= 18`.
4. `LONGWT > 0`.
5. At least one year-1 event with `ANYOPER == 1` in inpatient care or
   `SURGPROC == 1` in ER, outpatient, or office-based care.
6. At least one condition-event link for that surgical event whose
   `DUPERSID + CONDIDX` key exists in the year-1 conditions PUF.

### Exclusions

- Records failing any inclusion criterion.
- Records with a missing exposure or year-2 ED outcome after linkage; none were
  observed in T005, but the code must stop if they occur.
- Hospice/end-of-life exclusion is **not** frozen because a consistent
  cross-panel public-use definition has not yet been verified.
- Cancer is retained in the main cohort and adjusted using `CANCERY1`; a
  cancer-excluded sensitivity is planned.

### Cohort facts available before modeling

- Eligible N: 4,468.
- Year-2 ED-positive N: 1,042.
- Year-2 total ED visits: 1,658.
- All 7,772 surgical-condition links matched their condition PUF.
- All 4,468 eligible records matched HC-036 design fields.

## 3. Exposure

### Primary binary exposure

`any_condition_linked_opioid_y1`:

- **1, any opioid:** one or more year-1 prescribed-medicine records with Multum
  class 60 or 191 linked through `EVENTYPE == 8` to a condition also linked to
  a year-1 surgical event.
- **0, no observed opioid:** no such linked opioid record.

All available `TC*` hierarchy fields are searched. A medicine record is
classified as opioid when any field contains 60 or 191.

The comparator includes both people with linked nonopioid medicines and people
with no observed qualifying linked prescription analgesic. It must be labeled
“no observed condition-linked opioid,” never “opioid-sparing,” “nonopioid
treatment,” “untreated,” or “no opioid use.”

### Descriptive-only treatment patterns

The four categories `opioid_only`, `nonopioid_only`, `both`, and `neither` may
be tabulated descriptively. They are prohibited as adjusted primary models
because the T005 precision gates failed.

## 4. Outcomes

### Primary outcome

Year-2 annual all-cause ED visit count, `ERTOTY2`.

### Secondary outcome

Any year-2 ED use, defined as `ERTOTY2 > 0`.

No outcome is described as a revisit after surgery. MEPS underreporting and the
lack of day-level timing must be stated.

## 5. Estimands and inferential hierarchy

### Primary association estimands

From one fully adjusted count model:

1. survey-standardized mean ratio of year-2 ED counts for any observed linked
   opioid versus no observed linked opioid; and
2. survey-standardized mean difference in year-2 ED counts for the same
   contrast.

Both are reported with 95% confidence intervals. The overall adjusted Wald test
for the exposure term is the primary inferential test.

### Prespecified secondary equity estimand

Year-1 poverty is:

- `<200% FPL`: `POVCATY1` values 1–3; and
- `>=200% FPL`: values 4–5.

The secondary model adds exposure × poverty. Report:

- the one-degree-of-freedom interaction Wald test;
- standardized exposure contrasts within each poverty group; and
- adjusted mean counts for all four exposure-by-poverty combinations.

Differences between subgroup estimates may be claimed only from the direct
interaction contrast, not from one subgroup being statistically significant
and another not.

### Secondary binary-outcome estimands

For any year-2 ED use:

- standardized adjusted probability by exposure;
- adjusted risk difference; and
- adjusted probability ratio when stable.

Odds ratios are supplemental and cannot replace absolute estimates.

### Exploratory analyses

- Three-level poverty: `<200%`, `200–399%`, `>=400%`.
- Five-level poverty and insurance interactions, only when suppression and RSE
  rules pass.
- Four-category treatment patterns descriptively.

Exploratory p-values are labeled and are not used to redefine the primary
conclusion.

## 6. Covariates

Covariates are selected a priori from clinical and utilization domains used by
the closest MEPS comparators. Because opioid exposure accumulates throughout
year 1, some year-1 covariates are contemporaneous rather than strictly
pre-exposure. They improve association adjustment but do not identify a causal
effect.

| Domain | Field / derivation | Main coding | T005 missingness |
|---|---|---|---:|
| Age | `AGEY1X` | Natural spline, 3 df; report categories descriptively | 0% |
| Sex | `SEX` | Male / female as released | 0% |
| Race/ethnicity | `RACETHX` | Five released mutually exclusive categories | 0% |
| Region | `REGIONY1` | Northeast, Midwest, South, West | 0% |
| Poverty | `POVCATY1` | Binary `<200%` / `>=200%`; effect modifier | 0% |
| Insurance | `INSCOVY1` | Any private, public only, uninsured | 0% |
| Baseline ED use | `ERTOTY1` | `log1p(count)`; also descriptive categories 0/1/2+ | 0% |
| Baseline inpatient use | `IPDISY1` | `log1p(discharges)` | 0% |
| Baseline outpatient use | `OPTOTVY1` | `log1p(visits)` | 0% |
| Baseline office use | `OBTOTVY1` | `log1p(visits)` | 0% |
| Physical health | `RTHLTH1` | Excellent/very good, good, fair/poor | 0.11% |
| Mental health | `MNHLTH1` | Excellent/very good, good, fair/poor | 0.07% |
| Functional limitation | `WLKLIM1` | Yes / no | 0.16% |
| Cancer | `CANCERY1` | Yes / no | 0.02% |
| Surgical setting | Derived from event PUFs | Inpatient, outpatient, office, ER indicators; collapse if sparse | Derived |
| Surgical-event burden | Count of unique year-1 surgical events | `log1p(count)` | Derived |
| Panel | `PANEL` | Four-category fixed effect | 0% |

`ACTLIM1`, `IADLHP1`, and `ADLHLP1` are reserved as functional-limitation
sensitivities because they overlap conceptually with `WLKLIM1`.

`ADPAIN2`, `VPCS2`, and `VMCS2` are excluded from the main model. They are adult
self-administered questionnaire measures with 9.6%–12.8% missingness and
questionnaire-specific weighting considerations. A separate SAQ-weighted
sensitivity requires a written deviation and verified pooled `LSAQWT` method.

### Parameter discipline

Before fitting:

- tabulate unweighted N and ED-positive N for every categorical level;
- combine clinically defensible levels with N <50 or ED-positive N <30;
- require model residual design degrees of freedom >100;
- require at least 10 ED-positive people per fitted parameter as a conservative
  diagnostic, although the primary count model uses all counts; and
- stop rather than use automated stepwise selection.

## 7. Missing data

The main covariate profile is nearly complete. Primary analysis uses complete
cases if:

- cumulative exclusion is <=5% of eligible records;
- no main covariate has >2% missingness; and
- missingness does not differ by exposure by more than 5 percentage points.

Report missing N by variable and the final model N. If any threshold fails,
comparative modeling stops until a survey-compatible multiple-imputation plan
is approved. Missing-category indicators are not the default. MEPS edited or
imputed variables must be identified as such.

## 8. Survey design and pooling

### Design object

Create the complex-survey object on the full positive-`LONGWT` pooled
longitudinal universe, then use a survey-domain subset for the analytic cohort.
Do not construct variance estimation from the eligible rows alone.

- IDs: HC-036 `PSU9623`.
- Strata: HC-036 `STRA9623`.
- Weight: `LONGWT / 4`.
- Nesting: verify stratum/PSU uniqueness; set nesting only if required by the
  software after inspection.
- Panel indicators: included in every adjusted model.
- Panel-file `VARSTR`/`VARPSU`: never combined with HC-036 fields.

The verified full positive-weight universe has 117 strata, 400 stratum-PSU
units, approximately 283 design degrees of freedom, and no lonely strata. The
eligible domain spans 117 strata and 378 units.

### Software gate

The primary implementation will use an isolated R environment with:

- R version recorded;
- `survey` package version recorded;
- `svyglm()` with `quasipoisson(link = "log")` for counts; and
- `svyglm()` with `quasibinomial(link = "logit")` for any ED.

The R `survey` documentation states that `svyglm` uses design-robust standard
errors and recommends quasi families for survey-weighted Poisson/binomial
models. R and `survey` are not currently installed. T007 must create or locate
an isolated environment and pass validation before modeling.

Validation must reproduce:

- the T005 weighted eligible-population total;
- exposure-group weighted totals;
- the known unweighted cohort and event counts;
- identical estimates on two clean reruns; and
- one hand-checkable survey-weighted proportion and standard error.

No ordinary GLM with weights alone is an acceptable substitute for stratified,
clustered design-based variance.

### Lonely PSUs

No lonely strata were observed in the current pooled universe. Code must still
set and record an explicit policy (preferred: `survey.lonely.psu = "adjust"`)
and confirm it is not invoked. If design changes create lonely strata, report
the count and rerun with at least one alternative policy.

## 9. Models

### M1: primary count association

Design-based quasi-Poisson log-mean model:

```text
ERTOTY2 ~ opioid_binary
         + ns(AGEY1X, 3)
         + SEX + RACETHX + REGIONY1 + poverty_2 + INSCOVY1
         + log1p(ERTOTY1) + log1p(IPDISY1)
         + log1p(OPTOTVY1) + log1p(OBTOTVY1)
         + physical_health_3 + mental_health_3 + WLKLIM1 + CANCERY1
         + surgical_setting_indicators + log1p(surgical_event_count)
         + factor(PANEL)
```

### M2: poverty interaction

M1 plus `opioid_binary * poverty_2`, with the duplicate main terms represented
once.

### M3: secondary any-ED model

Same covariates as M1 using survey quasibinomial logistic regression. Derive
standardized probabilities and risk differences by averaging person-level
counterfactual predictions over the analytic population with the survey
weights. Use a covariance-aware contrast method; do not calculate confidence
intervals by treating margins as independent.

### Standardization

For each model, predict every eligible person under each exposure level while
holding all other observed covariates fixed. Average predictions with survey
weights. For poverty-specific contrasts, standardize within poverty domains.
Save the prediction algorithm and covariance calculation in code.

## 10. Diagnostics and reliability

Required before interpreting M1–M3:

- model convergence and finite coefficients;
- residual design degrees of freedom;
- Pearson dispersion and observed zero proportion;
- observed versus predicted mean counts overall and by exposure;
- influential sampling weights and coefficient change after a prespecified
  top-1%-weight sensitivity;
- multicollinearity screen for redundant utilization/function variables;
- sparse factor levels and separation for M3;
- confidence-interval width and RSE for weighted descriptive estimates;
- comparison of unadjusted and adjusted direction/magnitude without selecting
  the preferred result; and
- exact reconciliation of all output keys.

Suppression/reliability rules:

- do not report a descriptive cell with unweighted N <30;
- flag N 30–59 as limited precision;
- suppress a weighted estimate with RSE >30%;
- do not interpret a subgroup association with <30 outcome-positive people;
- do not report an unstable coefficient, nonfinite interval, or failed model.

## 11. Sensitivity analyses

| ID | Analysis | Purpose |
|---|---|---|
| S01 | Exclude Panel 25 | Remove 2020 exposure year |
| S02 | Any year-2 ED outcome | Test outcome functional form |
| S03 | Three-level poverty interaction | Test SES grouping |
| S04 | Non-ED surgical settings only | Remove surgeries identified during ER events |
| S05 | Exclude `CANCERY1 == 1` | Reduce cancer-related prescribing heterogeneity |
| S06 | All year-1 opioids rather than condition-linked opioids | Test linkage sensitivity; clearly changes exposure scope |
| S07 | Add `ACTLIM1`, `IADLHP1`, `ADLHLP1` separately | Test functional-status specification |
| S08 | Age categories instead of spline | Test age functional form |
| S09 | Top-1%-weight influence sensitivity | Assess influential design weights without deleting main-analysis records |
| S10 | Unadjusted and minimally adjusted models | Show adjustment impact; not alternative preferred results |

A negative-binomial or zero-inflated survey model is not automatic. It may be
added only if the primary mean model fails prespecified fit diagnostics, the
survey implementation is validated, and the addition is logged before its
comparative estimates are viewed.

## 12. Multiplicity and interpretation

- One primary outcome and one primary exposure association.
- One prespecified secondary interaction.
- One secondary binary outcome.
- Sensitivity and exploratory analyses are interpreted for robustness, not
  declared independently confirmatory.
- Report exact p-values with confidence intervals; do not use “trend” for
  `p > .05`.
- No subgroup claim without a direct interaction.
- Null and imprecise findings are reported without spin.

## 13. Output and reconciliation contract

All results are generated—not hand-entered—with these stable keys:

| Key prefix | Artifact |
|---|---|
| `FLOW_*` | Cohort counts and exclusions |
| `MISS_*` | Variable missingness |
| `DESC_*` | Survey-weighted participant characteristics |
| `OUTCOME_*` | Unadjusted ED summaries |
| `M1_*` | Primary count model coefficients and diagnostics |
| `M1_MARGIN_*` | Overall standardized means, ratios, and differences |
| `M2_INT_*` | Poverty interaction and poverty-specific margins |
| `M3_ANYED_*` | Any-ED model and standardized probabilities/RDs |
| `S01_*`–`S10_*` | Sensitivity results |
| `RELIABILITY_*` | N, RSE, suppression, convergence, and design checks |

Each machine-readable row must include the key, analysis population, exposure,
outcome, estimand, estimate, standard error, 95% CI, p-value when applicable,
unweighted N, weighted denominator, design df, model status, and suppression
flag.

## 14. Planned tables and figures

### Main manuscript

1. Figure 1: cohort flow by panel.
2. Table 1: weighted characteristics overall and by binary exposure, with
   standardized differences rather than significance tests.
3. Table 2: unadjusted year-2 ED outcomes by exposure and poverty.
4. Table 3: primary adjusted standardized mean counts, ratios, differences, and
   any-ED probabilities.
5. Figure 2: adjusted mean year-2 ED counts by exposure and two-level poverty,
   with 95% CIs.

### Supplement

- PUF and variable crosswalk.
- Multum exposure algorithm.
- Missingness table.
- Full model coefficient tables.
- Diagnostics and reliability flags.
- Sensitivity-analysis table.
- STROBE checklist.

## 15. Stop and deviation rules

Stop before interpretation if:

- the survey engine cannot reproduce validation totals/SEs;
- HC-036 coverage, positive weights, strata, or PSUs fail;
- main complete-case loss exceeds 5% without an approved missing-data plan;
- model residual design df are <=100;
- M1 or M3 fails twice after principled diagnostics;
- a core coefficient is nonfinite or dominated by a sparse level;
- primary results cannot be regenerated identically;
- a requested change would alter the population, exposure, primary outcome, or
  estimand; or
- valid reporting would require prohibited postoperative, opioid-sparing, or
  causal language.

## 16. Sources governing this protocol

- [AHRQ HC-036 pooled variance documentation](https://meps.ahrq.gov/data_stats/download_data/pufs/h036/h36u23doc.pdf)
- [R `survey` package reference](https://stat.ethz.ch/CRAN/web/packages/survey/refman/survey.html)
- [STROBE cohort checklist](https://strobe-statement.org/fileadmin/Strobe/uploads/checklists/STROBE_checklist_v4_cohort.pdf)
- [T005 data inventory](data_inventory.md)
- [T005J redesign decision](../docs/goals/meps-opioid-sparing-cureus/notes/T005J-redesign-decision.md)
- [Comparator library](reference_papers.md)

