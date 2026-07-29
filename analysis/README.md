# MEPS analysis workspace

## Current scope

This directory contains the two-file reproducible analysis pipeline for the
approved longitudinal MEPS paper:

- `meps_analysis.py` validates and links the public-use files, recreates the
  cohort/feasibility outputs, and writes a temporary identifier-free modeling
  table outside the versioned workspace.
- `meps_analysis.R` constructs the full-universe complex-survey design, performs
  domain analysis, fits the prespecified models and sensitivities, and writes
  aggregate publication outputs.

The approved analysis is binary `any condition-linked opioid prescription`
versus `no condition-linked opioid prescription`. The failed four-category
opioid/nonopioid design remains preserved in the feasibility outputs.

## Run

Requirements used for the verified two-stage run:

- Python 3.10.9
- pandas 2.3.3
- NumPy 2.2.6
- R 4.6.1
- `survey` 4.5
- exact R package versions in `outputs/analysis_environment.json`

From the project root:

```powershell
python analysis\meps_analysis.py `
  --data-dir "<DATA_ROOT>\dta" `
  --output-dir "analysis\outputs" `
  --model-input "<DATA_ROOT>\model_input.csv"

$env:R_LIBS_USER = "<DATA_ROOT>\r-library-4.6"
& "<DATA_ROOT>\R-4.6.1\bin\Rscript.exe" `
  --vanilla analysis\meps_analysis.R `
  "<PROJECT_ROOT>" `
  "<DATA_ROOT>\model_input.csv"
```

The default input location is:

```text
<DATA_ROOT>\dta
```

To use another read-only directory:

```powershell
$env:MEPS_DATA_DIR = "D:\path\to\meps\dta"
python analysis\meps_analysis.py
```

No source file is changed. The R stage deletes the temporary person-level
modeling table after a successful run. Only aggregate, nonidentifying outputs
remain in the project.

## Cohort algorithm

For each independent two-year longitudinal panel:

1. Keep the target panel before transforming identifiers.
2. Require `ALL5RDS == 1`, age 18 years or older in year 1, and positive
   `LONGWT`.
3. Identify year-1 surgical events using `ANYOPER == 1` for inpatient stays and
   `SURGPROC == 1` for emergency-room, outpatient, and office-based events.
4. Link those events to conditions through the condition-event link PUF.
5. Require each linked condition key to exist in the year-1 conditions PUF.
6. Find prescribed-medicine records linked to the same conditions through
   link-file records with `EVENTYPE == 8`.
7. Classify prescription records using all available Multum `TC*` fields:
   opioid classes 60 or 191; narrow nonopioid class 61; broad sensitivity
   classes 59, 61, or 63. Opioid classification takes precedence within a
   single medicine record.
8. Obtain year-2 annual emergency-department use from `ERTOTY2`.
9. Link the entire positive-weight pooled universe—not only eligible people—to
   `STRA9623` and `PSU9623` in HC-036, construct the survey design, and then
   subset to the eligible analysis domain.

Panel 22 requires a special, tested harmonization: after filtering the 2017
event, condition, and medicine files to Panel 22, the panel number `22` is
prepended to their legacy eight-character `DUPERSID` values. This matches the
ten-character identifier used in HC-210. For HC-036 itself, transformed
Panel 22 duplicate keys must carry identical common-variance fields before
deduplication.

## Survey design

- Person-level longitudinal weight: `LONGWT`.
- Pooled weight for four-panel average-period estimates: `LONGWT / 4`.
- Common pooled variance structure: HC-036 `STRA9623` and `PSU9623`, linked by
  `DUPERSID` and `PANEL`.
- The panel-file `VARSTR` and `VARPSU` fields must not be combined with the
  HC-036 variance fields in the same pooled analysis.
- Panel 25 has 2020 as its exposure year and is retained in the main
  feasibility audit but excluded in a prespecified pandemic sensitivity.

The survey-regression implementation follows the frozen statistical protocol.
The full pooled positive-weight universe contains 117 strata, 400 stratum-PSU
units, and 283 design degrees of freedom. The complete-case analysis domain has
261 design degrees of freedom and no lonely strata.

## Generated outputs

| File | Purpose |
|---|---|
| `outputs/file_manifest.csv` | Input paths, byte sizes, and SHA-256 hashes |
| `outputs/cohort_flow.csv` | Aggregate cohort and linkage counts by panel |
| `outputs/treatment_feasibility.csv` | Treatment counts and ED events by panel, pooled, and pandemic sensitivity |
| `outputs/equity_cells.csv` | Aggregate treatment-by-poverty and treatment-by-insurance cells |
| `outputs/gate_results.csv` | Prespecified feasibility checks |
| `outputs/feasibility_summary.json` | Machine-readable stop/redesign decision |
| `outputs/feasibility_report.md` | Reader-facing summary of the same outputs |
| `outputs/missingness.csv` | Main-model missingness audit |
| `outputs/model_level_counts.csv` | Prespecified modeled-level N and ED-positive checks |
| `outputs/descriptive_table.csv` | Survey-weighted cohort characteristics |
| `outputs/unadjusted_outcomes.csv` | Aggregate unadjusted outcome estimates |
| `outputs/model_coefficients.csv` | Full M1–M3 coefficient output |
| `outputs/standardized_results.csv` | Primary and any-ED standardized margins and contrasts |
| `outputs/interaction_results.csv` | Poverty-interaction test and stratum-specific margins |
| `outputs/model_diagnostics.csv` | Design, convergence, dispersion, calibration, and stability checks |
| `outputs/model_calibration.csv` | Observed-versus-predicted checks overall, by exposure, and by prediction group |
| `outputs/sensitivity_results.csv` | Prespecified sensitivity analyses |
| `outputs/nested_adjustment_results.csv` | Reviewer-requested sequential adjustment blocks |
| `outputs/setting_support.csv` | Cell-support checks for setting-restricted analyses |
| `outputs/setting_stratified_results.csv` | Exploratory setting-restricted contrasts |
| `outputs/reliability_flags.csv` | Disclosure/precision and diagnostic flags |
| `outputs/results_index.csv` | Unique stable result-key index |
| `outputs/table1.md`–`table3.md` | Publication table drafts |
| `outputs/figure1_*`, `outputs/figure2_*` | Publication figures in PNG and SVG |
| `outputs/analysis_summary.md` | Reader-facing validated result summary |
| `outputs/analysis_environment.json` | Executed software versions and input hash |
| `outputs/reproducibility_ledger.csv` | SHA-256 comparison for final outputs and analysis code |

No person identifier, diagnosis, medicine name, NDC, or person-level row is
written to `outputs/`.

## Verified T005 result

The pooled cohort contains 4,468 eligible adults, 1,042 with one or more
year-2 ED visits, and 1,658 total year-2 ED visits.

The approved four-category exposure is not viable for the planned equity
analysis:

- Narrow: opioid only 700; nonopioid only 100; both 120; neither 3,548.
- Narrow ED-positive counts: 164, 27, 31, and 820, respectively.
- The smallest prespecified two-level poverty-by-treatment cell is 32.
- The broad sensitivity improves counts but its smallest primary poverty cell
  is 39.

A binary `any opioid` versus `no opioid` design has 820 and 3,648 people, with
195 and 847 ED-positive people. Its prespecified two-level poverty cells all
have at least 252 people and 81 ED-positive people. A three-level poverty
sensitivity also passes. This design was subsequently approved and modeled, but
it cannot be described as uptake of opioid-sparing therapy because the
`no opioid` group is mostly people with no observed condition-linked
prescription analgesic.

## Verified T007 analysis result

The main model includes 4,454 complete cases (0.31% loss). To satisfy the frozen
sparse-level rule, adjustment combines non-Hispanic Asian with non-Hispanic
other/multiple race and combines public-only with uninsured coverage as
`no private coverage`; released categories remain in descriptive output. The
smallest modeled level has N=210 and 44 ED-positive people.

All prespecified diagnostics pass. The survey-standardized adjusted year-2 ED
count ratio for any versus no condition-linked opioid prescription is **0.975**
(95% CI 0.784 to 1.211), with an adjusted mean difference of **−0.009 visits**
(95% CI −0.082 to 0.065). The exposure-by-poverty interaction is not supported
(`p = 0.5943`). The standardized any-ED risk difference is **−0.019**
(95% CI −0.057 to 0.018).

The standardization variance uses full survey Taylor influence functions for
both coefficient estimation and the empirical covariate distribution.
Observed-versus-predicted calibration checks pass. Reviewer-requested nested
models range from 1.124 after structural adjustment to 0.975 in the full model.
Setting-restricted analyses are explicitly exploratory; the outpatient
contrast is below one, the emergency-room contrast is withheld for sparse
support, and no direct setting-heterogeneity test was performed.

All required sensitivity models converged and retained intervals spanning the
null. All reliability flags pass. The reproducibility ledger records SHA-256
hashes for final aggregate artifacts and both analysis programs. No
person-level modeling file remains after successful execution.

These estimates are associational. They do not measure postoperative timing,
opioid consumption, opioid-sparing care, or a causal effect.
