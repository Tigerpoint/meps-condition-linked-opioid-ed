# Final Reporting Checklist

**Primary guideline:** STROBE cohort checklist  
**Official checklist:** [STROBE cohort PDF](https://strobe-statement.org/fileadmin/Strobe/uploads/checklists/STROBE_checklist_v4_cohort.pdf)  
**Final verification date:** 2026-07-29  
**Status:** Complete for the scientific Markdown package; author-controlled
declarations remain listed separately.

STROBE is used as a reporting guide rather than a quality score. RECORD is not
the primary guideline because MEPS is a designed household survey rather than
claims or EHR data. RECORD principles were nevertheless used for transparent
linkage algorithms and executable code.

## STROBE final mapping

| Item | Requirement | Final evidence/location | Status |
|---:|---|---|---|
| 1a | Identify design in title/abstract | Title; Abstract Methods | Complete |
| 1b | Balanced abstract | Structured Background, Methods, Results, Conclusions; absolute and relative estimates; principal limitations | Complete |
| 2 | Background/rationale | Introduction, paragraphs 1-4 | Complete |
| 3 | Objectives/hypotheses | Introduction final paragraph | Complete |
| 4 | Key design elements | Materials and Methods: Study Design and Data Sources | Complete |
| 5 | Setting/dates | Materials and Methods: Study Design and Data Sources; Supplement Table S1 | Complete |
| 6a | Eligibility and selection | Materials and Methods: Study Population; Figure 1; Supplement Table S3 | Complete |
| 6b | Matching | No matching performed | Not applicable |
| 7 | Variables | Materials and Methods: Linkage, Exposure, Outcomes, Covariates; Supplement Table S2 | Complete |
| 8 | Data sources/measurement | Materials and Methods; Supplementary Methods and Tables S1-S2 | Complete |
| 9 | Bias | Materials and Methods: Covariates; Discussion: Limitations | Complete |
| 10 | Study size | Census of eligible records in four panels plus frozen support gates; Cohort Results | Complete |
| 11 | Quantitative variables | Materials and Methods: Covariates; Supplement Table S2 | Complete |
| 12a | Statistical/confounding methods | Materials and Methods: Survey Design and Statistical Analysis | Complete |
| 12b | Subgroups/interactions | Direct exposure-by-poverty interaction; Methods, Results, Table 3 | Complete |
| 12c | Missing data | Methods: Missing Data, Diagnostics, and Sensitivity Analyses; Supplement Table S4 | Complete |
| 12d | Loss to follow-up | `ALL5RDS=1`, positive `LONGWT`, target population and weighting explained in Methods and Supplement | Complete |
| 12e | Sensitivity analyses | Methods; Results; Supplement Tables S5-S8 | Complete |
| 13a | Participant numbers | Results: Cohort; Figure 1; Supplement Table S3 | Complete |
| 13b | Reasons for exclusion | Figure 1; Supplement Table S3 | Complete |
| 13c | Flow diagram | Figure 1 | Complete |
| 14a | Descriptive characteristics | Table 1, survey weighted overall and by exposure | Complete |
| 14b | Missing data by variable | Supplement Table S4; `analysis/outputs/missingness.csv` | Complete |
| 14c | Follow-up time | Fixed year-1 exposure and year-2 annual outcome ordering; no person-day claim | Complete |
| 15 | Outcome data | Table 2; weighted and unweighted annual ED summaries | Complete |
| 16a | Unadjusted/adjusted estimates | Tables 2-3; Figure 2; 95% confidence intervals and covariate set | Complete |
| 16b | Category boundaries | Methods: Covariates; Supplement Table S2 | Complete |
| 16c | Absolute estimates | Standardized mean/risk differences accompany ratios in Table 3 | Complete |
| 17 | Other analyses | Results; Supplement Tables S5-S9B; explicitly sensitivity or exploratory | Complete |
| 18 | Key results | Discussion opening and Conclusions; associational wording | Complete |
| 19 | Limitations | Discussion: Limitations | Complete |
| 20 | Interpretation | Discussion: Principal Findings and Comparison With Prior Literature | Complete |
| 21 | Generalizability | Discussion: Limitations and Implications | Complete |
| 22 | Funding | Disclosures: Funding placeholder | Author confirmation required |

## MEPS-specific final mapping

| Requirement | Final evidence/location | Status |
|---|---|---|
| AHRQ MEPS source and PUF families/years | Methods; Supplement Table S1; `research/data_inventory.md` | Complete |
| Civilian noninstitutionalized target population | Abstract and Methods | Complete |
| Panels 22, 23, 25, and 26 | Methods; Supplement Table S1 | Complete |
| Pooling weight `LONGWT/4` and average-panel interpretation | Methods; Supplementary Methods | Complete |
| Common HC-036 variance fields `STRA9623`/`PSU9623` | Methods; Supplementary Methods | Complete |
| Survey design created before domain restriction | Methods; executed R program | Complete |
| Final design degrees of freedom | Results and Supplementary Methods | Complete |
| Panel 24 exclusion | Supplementary Methods | Complete |
| Panel 25 pandemic sensitivity | Methods; Results; Supplement Tables S5-S6 | Complete |
| Linkage keys and `EVENTYPE=8` | Methods; Supplementary Methods | Complete |
| Broad surgery/procedure indicators | Methods and Limitations | Complete |
| Prescription records are not adherence/consumption | Exposure definition and Limitations | Complete |
| Year-level timing; no postoperative or 30-day inference | Abstract, Methods, Discussion, Conclusions | Complete |
| Annual all-cause ED outcome and undercounting boundary | Outcomes and Limitations | Complete |
| Unweighted and survey-weighted support by setting/exposure | `setting_support.csv`; Supplement Table S9A | Complete |
| Reliability and sparse-cell suppression | Methods; Tables 2, S7, S9A-S9B | Complete |
| Public deidentified data ethics wording | Ethics placeholder | Author determination required |
| Public data and code/materials statement | Ethics and Data Availability | Repository selection required |
| No protected or person-level data in package | Reproducibility/privacy statement; ledger verification | Complete |

## Reviewer-driven additions

| Addition | Final evidence/location | Status |
|---|---|---|
| Full design-based uncertainty for standardized margins | R program; Methods; Supplementary Methods; D006 | Complete |
| Calibration diagnostics | `model_calibration.csv`; `model_diagnostics.csv`; Supplement Table S7 | Complete |
| Nested adjustment sequence | `nested_adjustment_results.csv`; Supplement Table S8 | Complete |
| Weighted and unweighted setting support | `setting_support.csv`; Supplement Table S9A; D009 | Complete |
| Setting-restricted exploratory contrasts | `setting_stratified_results.csv`; Supplement Table S9B | Complete |
| Bound annual ED interpretation | Abstract, Methods, Discussion, Conclusions | Complete |
| Neutral Hernandez comparator wording | Introduction; Reference 13 | Complete |
| Author-controlled declarations retained | Manuscript and supplement placeholders | Complete pending authors |

## Final reconciliation

- [x] Every reported quantitative result maps to a stable output key.
- [x] Abstract and main-text estimates agree.
- [x] Tables and figures regenerate from machine-readable outputs.
- [x] Exposure and comparator labels match the frozen binary redesign.
- [x] Adjusted estimates identify the full covariate set.
- [x] Interaction claims use direct interaction tests.
- [x] Absolute estimates accompany relative estimates.
- [x] Null findings and confidence-interval width are reported.
- [x] Sparse or withheld setting cells are not reported as estimates.
- [x] Sensitivity and exploratory findings are labeled and not selectively promoted.
- [x] All 26 model/design/calibration/reliability diagnostics pass.
- [x] All 424 stable result keys are unique.
- [x] Two consecutive clean analysis runs reconcile through the reproducibility ledger.
- [x] The temporary person-level modeling file is deleted.
- [x] All 23 references are cited in first-appearance order.
- [x] No synthetic legacy value or prose-derived estimate is present.

## Author-controlled fields

The scientific package deliberately does not infer these facts:

- final author names, order, degrees, affiliations, and corresponding author;
- ICMJE authorship confirmation and contribution roles;
- institutional human-subjects/not-human-subjects/exemption determination and
  any required documentation;
- funding and sponsor role;
- conflicts of interest for every author;
- acknowledgments and permission to name acknowledged individuals;
- prior presentation, abstract, preprint, or overlapping submission;
- persistent repository and public release for code and aggregate outputs; and
- final substantive-AI use disclosure in Materials and Methods.
