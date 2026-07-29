# Analysis deviations and implementation decisions

**Protocol frozen:** 2026-07-28  
**Comparative models first run:** 2026-07-28  
**Current status:** No change to the approved population, exposure, comparator,
primary outcome, estimand, poverty interaction, covariate set, or claim boundary.

## D001 — Survey environment implementation

- **Date:** 2026-07-28
- **Timing relative to results:** Before successful comparative modeling.
- **Decision:** Use the official CRAN Windows build of R 4.6.1 with binary CRAN
  packages in an isolated user-local library. The executed versions are recorded
  in `analysis/outputs/analysis_environment.json`.
- **Reason:** Both the existing Conda installation and a portable micromamba
  environment failed while extracting the same Windows compiler archive. The
  official R distribution avoids that archive and provides the required
  design-based `survey` implementation.
- **Affected outputs:** Execution environment only.
- **Effect on analysis:** None. The prespecified models and survey design were
  unchanged.

## D002 — Full-universe HC-036 identifier harmonization

- **Date:** 2026-07-28
- **Timing relative to results:** Before comparative modeling.
- **Decision:** For Panel 22 HC-036 records carrying legacy eight-character
  2017 person identifiers, prepend `22`, verify that transformed duplicate keys
  have identical `STRA9623` and `PSU9623`, and then deduplicate.
- **Reason:** HC-036 contains both legacy 2017 and harmonized 2018 representations
  for some Panel 22 people. This tested transformation was required to construct
  the full positive-weight survey universe before domain subsetting.
- **Affected outputs:** Survey-universe linkage and all variance estimates.
- **Effect on analysis:** Restored complete HC-036 coverage: 41,427 of 41,427
  positive-weight universe records and 4,468 of 4,468 eligible records matched.
  The approved estimand was unchanged.

## D003 — Exclude-cancer sensitivity formula

- **Date:** 2026-07-28
- **Timing relative to results:** After the analysis code first attempted the
  sensitivity, but before any successful complete analysis run or result review.
- **Decision:** In S05, remove `cancer_y1` from the adjustment formula after
  restricting the domain to people without cancer.
- **Reason:** The restricted domain contains only one cancer level, so retaining
  the constant factor causes a model-matrix contrast error. A constant cannot
  confound the exposure-outcome association within that domain.
- **Affected outputs:** S05 sensitivity estimates only.
- **Effect on analysis:** The primary model and all primary/secondary estimands
  were unchanged.

## D004 — Nonanalytic implementation corrections

- **Date:** 2026-07-28
- **Timing relative to results:** During failed test runs and before the first
  successful complete run.
- **Decision:** Correct local-name shadowing in generated coefficient and
  descriptive tables; preserve S07 sensitivity identifiers during iteration;
  and explicitly order the figure exposure axis as no linked opioid followed by
  any linked opioid.
- **Reason:** These were software-output and presentation defects, not statistical
  specification changes.
- **Affected outputs:** Generated tables, stable keys, and Figure 2 ordering.
- **Effect on analysis:** No estimate, model, cohort, or interpretation changed.

## D005 — T008 fallback audit corrections

- **Date:** 2026-07-28
- **Timing relative to results:** Made with knowledge of the first provisional
  T007 estimates, before manuscript drafting and before T008 approval.
- **Decision 1:** Replace the single highest-acuity surgical-setting covariate
  with the four prespecified inpatient, emergency-room, outpatient, and
  office-based setting indicators.
- **Reason 1:** The fallback T008 audit found that the implemented single
  category did not match the frozen protocol’s setting-indicator specification.
- **Decision 2:** Apply the protocol’s sparse-level rule by combining
  non-Hispanic Asian with non-Hispanic other/multiple race for adjustment and
  combining public-only with uninsured coverage as `no private coverage`.
  Descriptive Table 1 retains the released five-level race/ethnicity and
  three-level insurance categories.
- **Reason 2:** The complete-case non-Hispanic Asian level had 83 people and 6
  ED-positive people; the uninsured level had 70 people and 17 ED-positive
  people. Both failed the frozen minimum of 30 ED-positive people per modeled
  categorical level. The collapsed adjustment levels have minimum N 210 and
  minimum ED-positive N 44.
- **Decision 3:** Tighten S04 to exclude anyone with an emergency-room surgical
  event and omit the now-constant emergency-room indicator from that
  sensitivity formula.
- **Reason 3:** This more directly operationalizes the prespecified non-ER
  surgical-setting sensitivity.
- **Decision 4:** Add automated output and stop rules for model-level N,
  ED-positive N, overall missingness, and exposure-specific missingness
  differences.
- **Affected outputs:** All M1–M3 adjusted estimates, S04, diagnostics,
  missingness, model-level counts, tables, figures, and stable-key index.
- **Effect on analysis:** The approved population, exposure, primary outcome,
  estimands, interaction, and interpretation boundary did not change. The
  corrected primary ratio changed only from provisional 0.977 to 0.975; the
  substantive null/imprecise interpretation was unchanged.

## D006 — Full design-based standardization variance

- **Date:** 2026-07-29
- **Timing relative to results:** After independent review of the complete
  scientific draft.
- **Decision:** Reimplement standardized margins and contrasts with Taylor
  influence functions that combine regression-coefficient uncertainty and
  sampling variability in the survey-weighted empirical covariate
  distribution.
- **Reason:** The prior coefficient-only delta calculation omitted the latter
  source of design uncertainty.
- **Affected outputs:** Standardized means, differences, ratios, poverty
  contrasts, binary-outcome contrasts, sensitivities, tables, and figures.
- **Effect on analysis:** The primary ratio and ratio CI were unchanged to the
  reported precision (0.975, 95% CI 0.784-1.211). Mean and absolute-difference
  confidence limits changed slightly. The substantive interpretation was
  unchanged.

## D007 — Reviewer-requested calibration and exploratory analyses

- **Date:** 2026-07-29
- **Timing relative to results:** After independent review.
- **Decision:** Add observed-versus-predicted calibration overall, by exposure,
  and across weighted prediction groups; add nested adjustment blocks; and add
  setting-restricted contrasts subject to the existing N and ED-positive
  support thresholds.
- **Reason:** Independent reviewers requested clearer evidence about model
  calibration, contemporaneous adjustment, and setting support.
- **Affected outputs:** `model_calibration.csv`,
  `nested_adjustment_results.csv`, `setting_support.csv`,
  `setting_stratified_results.csv`, diagnostics, results index, manuscript, and
  supplement.
- **Effect on analysis:** These additions did not replace the primary model or
  inferential hierarchy. Nested ratios crossed the null as adjustment blocks
  were added. The outpatient-restricted contrast was below one, but setting
  analyses are exploratory, overlap by construction, lack a direct
  heterogeneity test, and were not adjusted for multiplicity.

## D008 — Descriptive setting hierarchy and cohort figure

- **Date:** 2026-07-29
- **Timing relative to results:** After independent review.
- **Decision:** Correct the descriptive highest-acuity hierarchy to inpatient,
  emergency room, outpatient, then office based; label Figure 1 as an aggregate
  cohort summary; and add the complete-case analysis cohort.
- **Reason:** The prior descriptive hierarchy and figure legend could be
  misread. Adjusted models already used the four concurrent setting indicators.
- **Affected outputs:** Descriptive Table 1 and Figure 1 only.
- **Effect on analysis:** No model, estimand, or interpretation changed.

## D009 — Weighted setting-support reporting

- **Date:** 2026-07-29
- **Timing relative to results:** After the final scientific-integrity audit.
- **Decision:** Add survey-weighted population totals and within-setting
  weighted exposure shares to every setting-by-exposure support row.
- **Reason:** The accepted reviewer criterion required both unweighted and
  survey-weighted support. The first revision reported unweighted N and
  ED-positive N but omitted weighted cell size.
- **Affected outputs:** `setting_support.csv`, the results index,
  reproducibility ledger, and Supplementary Table S9A.
- **Effect on analysis:** This is a reporting-only addition. It does not alter
  the cohort, support thresholds, models, estimates, confidence intervals, or
  interpretation.

## Reproducibility confirmation

After all decisions, the full Python extraction and R analysis were run from
the verified source files. SHA-256 hashes for the final aggregate artifacts and
both analysis programs are recorded in
`analysis/outputs/reproducibility_ledger.csv` and compared with the immediately
preceding clean run. The temporary identifier-free person-level modeling file
was deleted after each successful run.
