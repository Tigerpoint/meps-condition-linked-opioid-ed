# Condition-Linked Opioid Prescriptions and Subsequent Emergency Department Use

[![DOI](https://zenodo.org/badge/DOI/10.5281/zenodo.21693654.svg)](https://doi.org/10.5281/zenodo.21693654)

Analysis code, protocol, and aggregate results for a longitudinal Medical
Expenditure Panel Survey (MEPS) study of condition-linked opioid prescriptions
and year-2 emergency department (ED) use among United States adults with
surgery-associated conditions.

**Status:** manuscript in preparation for submission to *Cureus Journal of
Medical Science*. This repository holds the computational materials only.

---

## What this study found

Across four pooled MEPS panels (2017-2018, 2018-2019, 2020-2021, 2021-2022),
among 4,468 eligible adults:

| Estimate | Value |
|---|---|
| Adjusted standardized mean ED-visit ratio, any vs. no linked opioid | **0.975** (95% CI 0.784-1.211), p = 0.8165 |
| Adjusted mean difference | **-0.009** visits/year (95% CI -0.082 to 0.065) |
| Exposure-by-poverty interaction | F = 0.284, p = 0.5943 |
| Adjusted any-ED risk difference | -1.9 percentage points (95% CI -5.7 to 1.8) |

**No clear association was detected, and the estimates are imprecise.** The
confidence interval spans a 21.6% lower to a 21.1% higher mean count. That width
is the finding. These results establish neither equivalence, nor the absence of
an association, nor socioeconomic equity.

The exposure is an *observed condition-linked opioid prescription* — not opioid
receipt after surgery. Public-use MEPS does not date prescriptions relative to
procedures, so no postoperative or perioperative claim can be made from these
data.

---

## What is and is not in this repository

**Included**

| Path | Contents |
|---|---|
| `analysis/meps_analysis.py` | Extraction, linkage, cohort construction, feasibility gates |
| `analysis/meps_analysis.R` | Survey design, models, standardization, sensitivity, diagnostics |
| `analysis/outputs/` | All aggregate results (33 files): estimates, diagnostics, tables, figures |
| `research/analysis_protocol.md` | The frozen statistical protocol |
| `research/analysis_deviations.md` | Every post-freeze implementation decision, dated |
| `research/meps_variable_dictionary.md` | Variable and Multum class crosswalk |
| `research/data_inventory.md` | Input file inventory |
| `research/reporting_checklist.md` | STROBE/RECORD reporting map |
| `scripts/fetch_meps_data.ps1` | Downloads and hash-verifies all MEPS inputs |
| `VERIFICATION.md` | Independent reproduction and provenance evidence |

**Deliberately excluded**

- **The MEPS data itself.** ~1.6 GB, and AHRQ is the authoritative distributor.
  `scripts/fetch_meps_data.ps1` retrieves it and verifies every file.
- **Any person-level data.** The pipeline writes a temporary person-level
  modeling table *outside* the repository and deletes it on successful
  completion. Nothing here contains a person identifier, diagnosis, medicine
  name, or NDC.
- **The manuscript text.** Withheld while the paper is under consideration so
  that this repository does not constitute a preprint.

---

## Reproducing the results

Roughly 100 seconds of compute once the data is in place.

### 1. Environment

| Component | Version used |
|---|---|
| Python | 3.10.9 |
| pandas | 2.3.3 |
| NumPy | 2.2.6 |
| R | 4.6.1 |
| R `survey` | 4.5 |

Exact package versions are recorded in `analysis/outputs/analysis_environment.json`.

### 2. Get the data

```powershell
.\scripts\fetch_meps_data.ps1 -DataDir "D:\meps\dta"
```

This downloads 33 public-use files from AHRQ, extracts the Stata versions, and
compares each SHA-256 against `analysis/outputs/file_manifest.csv`. A clean run
proves your inputs are the same bytes the published results were computed from.

MEPS files are public and require no application or DUA:
<https://meps.ahrq.gov/data_stats/download_data_files.jsp>

### 3. Run

```powershell
python analysis\meps_analysis.py `
  --data-dir     "D:\meps\dta" `
  --output-dir   "analysis\outputs" `
  --model-input  "D:\meps\model_input.csv"

$env:R_LIBS_USER = "<your R library path>"
Rscript --vanilla analysis\meps_analysis.R "<path to this repo>" "D:\meps\model_input.csv"
```

Stage 1 writes the cohort and feasibility outputs plus a temporary modeling
table. Stage 2 fits the models and writes every publication artifact, then
deletes the temporary table.

### 4. Confirm

Open `analysis/outputs/reproducibility_ledger.csv`. Every row should read
`identical_to_prior_run = TRUE`. That column is the pipeline comparing your run
against the committed one, artifact by artifact, via SHA-256.

---

## Design notes worth knowing before reading the code

- **Survey design is built on the full pooled universe** (41,427 positive-weight
  records) and the eligible cohort is then analyzed as a *domain* via
  `subset()`. The design is never rebuilt on a filtered dataset — doing so
  would misstate variance.
- **HC-036 pooled linkage variance fields** (`STRA9623`, `PSU9623`) are used
  rather than panel-specific `VARSTR`/`VARPSU`, which are not defined on a
  common structure across panels. Pooled weight is `LONGWT / 4`.
- **Standardization is survey-weighted g-computation.** Each participant is
  predicted under both exposure values with all other covariates left at
  observed values; predictions are averaged with survey weights. Variance uses
  Taylor linearization over influence functions carrying **both** the
  coefficient-estimation and standardization-population components.
- **Poverty-specific estimates are standardized within the poverty domain**, and
  heterogeneity is assessed by a single 1-df interaction Wald test — never by
  comparing subgroup p-values.
- **Panel 24 is excluded** because it is the special nine-round, four-year
  2019-2022 panel, not a standard two-year panel.
- **Setting-restricted contrasts are exploratory.** Participants may appear in
  more than one setting, no direct setting interaction was tested, and no
  multiplicity correction was applied.

---

## A note on hardcoded paths

`meps_analysis.py` and `meps_analysis.R` contain the original author's local
default data paths, and `analysis/outputs/file_manifest.csv` records absolute
input paths from the analysis machine.

**These are preserved deliberately and must not be "cleaned up."** The SHA-256
of both scripts is recorded in `analysis_environment.json` and
`reproducibility_ledger.csv`, and the entire verification chain depends on those
hashes. Editing either file — even to tidy a path — breaks the ability to prove
that the committed code is the code that produced the committed results.

Pass `--data-dir` and `--model-input` to override the defaults. Nothing requires
you to place data where the original author did. Documentation files in this
repository have had those paths genericized; the hash-verified files have not.

---

## Verification

`VERIFICATION.md` records an independent end-to-end reproduction: the full
pipeline re-executed from raw MEPS files in a clean directory, producing 39 of
40 artifacts byte-identical — figures included — with every reported estimate
matching to full floating-point precision. It also documents a provenance check
of the input data against fresh AHRQ downloads.

---

## Limitations

This is an associational analysis. It does not identify a causal effect,
postoperative timing, opioid consumption, analgesic strategy, setting
heterogeneity, or socioeconomic equity. The primary estimate is imprecise, and
lack of statistical evidence is not evidence of a negligible association.

Full limitations are set out in the manuscript and in
`research/analysis_protocol.md`.

---

## Data source and citation

Agency for Healthcare Research and Quality. *Medical Expenditure Panel Survey,
Household Component.* Public-use files.
<https://meps.ahrq.gov/data_stats/download_data_files.jsp>

MEPS public-use files are deidentified and publicly available. This analysis
used no restricted-access data.

---

## TODO before publication

These are author decisions and are intentionally unresolved:

- [x] ~~Mint a DOI.~~ Archived on Zenodo. **Concept DOI
      [10.5281/zenodo.21693654](https://doi.org/10.5281/zenodo.21693654)** always
      resolves to the latest version; cite this one rather than a version-specific
      DOI so future releases do not strand the citation.
- [ ] **Choose and add a LICENSE.** Without one, default copyright applies and
      others cannot legally reuse the code. MIT or Apache-2.0 for code, CC-BY-4.0
      for documentation, are common choices.
- [ ] Add author names, affiliations, ORCIDs, and a corresponding contact.
- [ ] Add the manuscript DOI once published.

## Citation

Until the manuscript is published, cite the archived software record:

> *[Author names]*. Condition-linked opioid prescriptions and subsequent
> emergency department use: analysis code and aggregate results (v1.0.0).
> Zenodo. https://doi.org/10.5281/zenodo.21693654
