# MEPS variable and linkage dictionary

## Binding use

This dictionary maps every field used in the T005 cohort and feasibility audit
to its public-use file and operational meaning. It is not yet a final model
covariate dictionary; covariates will be frozen only after the redesigned
estimand is approved.

## Person, panel, and survey design

| Construct | Variable(s) | File(s) | Operational use | Validation and cautions |
|---|---|---|---|---|
| Person identifier | `DUPERSID` | All files | Person component of every linkage key | Panel 22 HC-210 uses a ten-character form; Panel 22 is prepended to 2017 legacy eight-character IDs only after filtering annual files to Panel 22. |
| Panel | `PANEL` | All files | Select Panel 22, 23, 25, or 26 and complete person-panel joins | Annual files contain two panels and must be filtered before ID transformation. |
| Complete panel participation | `ALL5RDS` | HC-210/217/234/244 | Require value 1 | Restricts the cohort to people with all five rounds; paired with positive `LONGWT`. |
| Age | `AGEY1X` | Longitudinal PUF | Require age ≥18 in year 1 | Adult cohort definition. |
| Longitudinal weight | `LONGWT` | Longitudinal PUF | Person weight; divide by four for pooled average-panel descriptive totals | Do not substitute annual full-year weights. |
| Released panel design | `VARSTR`, `VARPSU` | Longitudinal PUF | Retained for validation only | Do not combine these fields with HC-036 fields in the pooled design. |
| Common pooled design | `STRA9623`, `PSU9623` | HC-036 (`h36u23.dta`) | Final pooled stratum and PSU, linked by `DUPERSID` + `PANEL` | 4,468/4,468 eligible records matched with no missing design values. |

Official sources:
[HC-210](https://meps.ahrq.gov/data_stats/download_data/pufs/h210/h210doc.shtml),
[HC-217](https://meps.ahrq.gov/data_stats/download_data/pufs/h217/h217doc.shtml),
[HC-234](https://meps.ahrq.gov/data_stats/download_data/pufs/h234/h234doc.shtml),
[HC-244](https://meps.ahrq.gov/data_stats/download_data/pufs/h244/h244doc.shtml), and
[HC-036](https://meps.ahrq.gov/data_stats/download_data_files_detail.jsp?cboPufNumber=HC-036).

## Surgical-event identification

| Setting | Flag | Event file suffix | Positive code | Event key | Timing available |
|---|---|---|---:|---|---|
| Inpatient | `ANYOPER` | D | 1 | `DUPERSID` + `EVNTIDX` | `IPBEGYR`, `IPBEGMM` exist, but exact day is unavailable |
| Emergency room | `SURGPROC` | E | 1 | `DUPERSID` + `EVNTIDX` | `ERDATEYR`, `ERDATEMM`; no exact day |
| Outpatient department | `SURGPROC` | F | 1 | `DUPERSID` + `EVNTIDX` | `OPDATEYR`, `OPDATEMM`; no exact day |
| Office based | `SURGPROC` | G | 1 | `DUPERSID` + `EVNTIDX` | `OBDATEYR`, `OBDATEMM`; no exact day |

The event files are HC-197D/E/F/G (2017), HC-206D/E/F/G (2018),
HC-220D/E/F/G (2020), and HC-229D/E/F/G (2021). The flags indicate that a
surgical procedure occurred in the event; they do not identify a standardized
operative index date or postoperative window.

Official examples:
[HC-229 inpatient](https://meps.ahrq.gov/data_stats/download_data/pufs/h229d/h229ddoc.shtml),
[HC-229 ER](https://meps.ahrq.gov/data_stats/download_data/pufs/h229e/h229edoc.shtml),
[HC-229 outpatient](https://meps.ahrq.gov/data_stats/download_data/pufs/h229f/h229fdoc.shtml), and
[HC-229 office based](https://meps.ahrq.gov/data_stats/download_data/pufs/h229g/h229gdoc.shtml).

## Condition and medicine linkage

| Construct | Variable(s) | File(s) | Operational use | Limitation |
|---|---|---|---|---|
| Condition key | `CONDIDX` | I link PUF and conditions PUF | Identify conditions linked to a surgical event | Links are many-to-many. |
| Event/medicine link key | `EVNTIDX` | I link PUF | Match surgical events; for `EVENTYPE == 8`, match Rx `LINKIDX` | An event can link to multiple conditions and vice versa. |
| Event type | `EVENTYPE` | I link PUF | Value 8 identifies prescribed-medicine links | Other documented values include office, outpatient, ER, and inpatient events. |
| Rx link key | `LINKIDX` | A prescribed-medicine PUF | Match a medicine record to I-file `EVNTIDX` | Same-condition linkage does not establish temporal ordering relative to surgery. |
| Diagnosis descriptors | `ICD10CDX`, `CCSR1X`, `CCSR2X`, `CCSR3X` | HC-199/207/222/231 | Validate that each linked condition exists in its conditions PUF; reserve clinical grouping for the protocol | Public-use condition coding is not a procedure code and should not be used to invent an operation type. |
| Medicine timing/context | `PURCHRD`, `RXBEGMM`, `RXBEGYRX`, `RXNAME`, `RXNDC` | A prescribed-medicine PUF | Available for future checks; not exported person-by-person | Does not provide an exact fill date suitable for a 30-day postoperative window. |

Official linkage documentation:
[HC-229I condition-event link](https://meps.ahrq.gov/data_stats/download_data/pufs/h229i/h229idoc.shtml)
and
[HC-229A prescribed medicines](https://meps.ahrq.gov/data_stats/download_data/pufs/h229a/h229adoc.shtml).
The same linkage pattern is applied to the corresponding 2017, 2018, and 2020
PUF series.

## Prescription analgesic exposure

All `TC*` fields in each A file are searched because Multum therapeutic classes
can appear at multiple hierarchy positions.

| Exposure component | Multum class codes | Feasibility definition |
|---|---|---|
| Opioid | 60 (narcotic analgesics), 191 (narcotic analgesic combinations) | Any matching class on a linked medicine record |
| Narrow prescription nonopioid | 61 (nonsteroidal anti-inflammatory agents) | Any matching class on a nonopioid linked medicine record |
| Broad nonopioid sensitivity | 59 (miscellaneous analgesics), 61, or 63 (analgesic combinations) | Any matching class on a nonopioid linked medicine record |
| Not automatically included | 64 (anticonvulsants) | Excluded because indication is too ambiguous for an analgesic exposure without further validation |

Opioid classification takes precedence within a single medicine record. A
person is classified as `both` only when person-level records support both
opioid and nonopioid exposure, not merely because one opioid combination record
contains hierarchical analgesic labels.

The four person-level categories are `opioid_only`, `nonopioid_only`, `both`,
and `neither`. `Neither` means no opioid or qualifying nonopioid medicine was
observed through the selected condition links; it does not prove that no
analgesic was used.

## Outcome and equity variables

| Construct | Variable | File | Coding used | Interpretation |
|---|---|---|---|---|
| Year-2 ED count | `ERTOTY2` | Longitudinal PUF | Nonnegative annual count | Subsequent-year all-cause ED utilization; not a 30-day revisit |
| Any year-2 ED use | Derived from `ERTOTY2` | Longitudinal PUF | `ERTOTY2 > 0` | Feasibility event count and potential secondary binary outcome |
| Five-level poverty | `POVCATY1` | Longitudinal PUF | Valid values 1–5 | Used exactly for the prespecified cell audit |
| Two-level poverty candidate | Derived from `POVCATY1` | Longitudinal PUF | 1–3: `<200% FPL`; 4–5: `≥200% FPL` | Prespecified primary poverty contrast for the candidate binary exposure; requires redesign approval |
| Three-level poverty sensitivity | Derived from `POVCATY1` | Longitudinal PUF | 1–3: `<200% FPL`; 4: `200–399%`; 5: `≥400%` | Candidate sensitivity only |
| Continuous poverty percentage | `POVLEVY1` | Longitudinal PUF | Available, not used in T005 cells | Candidate covariate or sensitivity, not yet frozen |
| Insurance category | `INSCOVY1` | Longitudinal PUF | Valid values 1–3 | Five-panel labels are confirmed in codebooks; empirical interaction cells are sparse |
| Detailed insurance | `INSURCY1` | Longitudinal PUF | Available, not used in T005 cells | Reserved for protocol review; avoid overparameterization |

Negative MEPS values represent inapplicable, not ascertained, cannot-be-computed,
or other nonresponse states depending on the field and year. T005 does not
impute them. Invalid poverty/insurance codes are treated as missing in cell
tables; the final protocol must specify covariate missing-data handling.

## Non-identifiable constructs

The following constructs remain prohibited because these public-use variables
do not measure them:

- exact surgery date;
- opioid fill or ED revisit within 30 days after surgery;
- institutional multimodal analgesia protocol adoption;
- perioperative administration of nonopioid agents;
- adherence to a prescribed medicine;
- causal effect of opioid-sparing care;
- an interrupted-time-series intervention breakpoint.
