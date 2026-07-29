# MEPS data inventory and feasibility audit

## Status

T005 is complete with a **stop-and-redesign-before-modeling** result. The
required public-use files are available and link successfully, but the approved
four-category opioid/nonopioid exposure cannot support the prespecified
socioeconomic analysis. No outcome model has been run.

## Provenance and storage

The connected Google Drive folder
[`meps-2021-and-2022-full-year-consolidate`](https://drive.google.com/drive/folders/1JpdMPSZbdNQ1zjCxH9ZclNn6jSZ1itC_)
contained only a saved AHRQ download webpage (`download_data_files.jsp`), not
MEPS data files. Therefore, official public-use Stata archives were downloaded
directly from AHRQ.

- Read-only extracted cache:
  `<DATA_ROOT>\dta`
- Original downloaded ZIP cache:
  `<DATA_ROOT>\raw-dta`
- Versioned project: aggregate outputs and documentation only.
- Exact input sizes and SHA-256 hashes:
  `analysis/outputs/file_manifest.csv`

The original `sources/` directory and the raw/extracted caches were not edited.

## Selected independent panels

| Panel | Year 1 → year 2 | Longitudinal PUF | Year-1 Rx / events / link / conditions |
|---|---:|---|---|
| 22 | 2017 → 2018 | HC-210 (`h210.dta`) | HC-197A/D/E/F/G/I and HC-199 |
| 23 | 2018 → 2019 | HC-217 (`h217.dta`) | HC-206A/D/E/F/G/I and HC-207 |
| 25 | 2020 → 2021 | HC-234 (`h234.dta`) | HC-220A/D/E/F/G/I and HC-222 |
| 26 | 2021 → 2022 | HC-244 (`h244.dta`) | HC-229A/D/E/F/G/I and HC-231 |

Panel 24 was not mixed into this set because
[HC-245](https://meps.ahrq.gov/data_stats/download_data/pufs/h245/h245doc.shtml)
is a special nine-round, four-year 2019–2022 panel rather than a standard
independent two-year panel comparable to the four selected files. Panel 25 is
retained for the main audit and excluded in a specified pandemic sensitivity.

Official longitudinal documentation:

- [HC-210 Panel 22, 2017–2018](https://meps.ahrq.gov/data_stats/download_data/pufs/h210/h210doc.shtml)
- [HC-217 Panel 23, 2018–2019](https://meps.ahrq.gov/data_stats/download_data/pufs/h217/h217doc.shtml)
- [HC-234 Panel 25, 2020–2021](https://meps.ahrq.gov/data_stats/download_data/pufs/h234/h234doc.shtml)
- [HC-244 Panel 26, 2021–2022](https://meps.ahrq.gov/data_stats/download_data/pufs/h244/h244doc.shtml)

Official event/link/condition documentation can be reached from the AHRQ PUF
detail records:

- [2017 HC-197 series](https://meps.ahrq.gov/data_stats/download_data_files_detail.jsp?cboPufNumber=HC-197A)
  and [HC-199 conditions](https://meps.ahrq.gov/data_stats/download_data_files_detail.jsp?cboPufNumber=HC-199)
- [2018 HC-206 series](https://meps.ahrq.gov/data_stats/download_data_files_detail.jsp?cboPufNumber=HC-206A)
  and [HC-207 conditions](https://meps.ahrq.gov/data_stats/download_data_files_detail.jsp?cboPufNumber=HC-207)
- [2020 HC-220 series](https://meps.ahrq.gov/data_stats/download_data_files_detail.jsp?cboPufNumber=HC-220A)
  and [HC-222 conditions](https://meps.ahrq.gov/data_stats/download_data_files_detail.jsp?cboPufNumber=HC-222)
- [2021 HC-229 series](https://meps.ahrq.gov/data_stats/download_data_files_detail.jsp?cboPufNumber=HC-229A)
  and [HC-231 conditions](https://meps.ahrq.gov/data_stats/download_data_files_detail.jsp?cboPufNumber=HC-231)
- [HC-036 1996–2023 pooled common variance structure](https://meps.ahrq.gov/data_stats/download_data_files_detail.jsp?cboPufNumber=HC-036)

## Empirical cohort and linkage audit

| Panel | Complete adults | Surgical events | People with a surgical event | People with a linked surgical condition | Eligible complete adults | People with linked Rx | Year-2 ED positive | Year-2 ED visits |
|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| 22 | 10,258 | 3,730 | 2,016 | 1,825 | 1,507 | 900 | 345 | 529 |
| 23 | 10,084 | 4,072 | 2,069 | 1,832 | 1,481 | 887 | 359 | 590 |
| 25 | 4,599 | 2,186 | 1,045 | 923 | 646 | 419 | 145 | 227 |
| 26 | 5,193 | 2,479 | 1,243 | 1,089 | 834 | 508 | 193 | 312 |
| **Pooled** | — | — | — | — | **4,468** | — | **1,042** | **1,658** |

All 7,772 unique surgical-condition links matched the corresponding condition
PUF. All 4,468 eligible people matched HC-036 by `DUPERSID` and `PANEL`, with
nonmissing `STRA9623` and `PSU9623`. For the final domain analysis, all 41,427
positive-weight pooled-universe records also matched HC-036; this full universe
was used to construct the survey design before restricting to the eligible
domain.

The first exploratory pass exposed and corrected an important linkage risk:
annual event files contain two panels. Every annual file is now filtered to the
target panel *before* any identifier transformation. For Panel 22 only, `22` is
then prepended to legacy 2017 eight-character person IDs to match HC-210. The
HC-036 file itself contains both legacy eight-character 2017 and harmonized
ten-character 2018 identifiers for some Panel 22 people. The analysis prepends
`22` to the legacy HC-036 keys, asserts that any resulting duplicate keys carry
identical `STRA9623` and `PSU9623`, and only then deduplicates. The corrected
Panel 26 flow reproduces the original single-panel audit exactly.

## Exposure feasibility

The narrow definition uses Multum class 61 for a nonopioid record. The broad
sensitivity uses classes 59, 61, or 63. Both definitions use classes 60 or 191
for opioids, with opioid precedence within a medicine record.

| Definition | Opioid only | Nonopioid only | Both | Neither | Smallest ED-positive group | Smallest primary two-level poverty cell |
|---|---:|---:|---:|---:|---:|---:|
| Narrow | 700 | 100 | 120 | 3,548 | 27 | 32 |
| Broad sensitivity | 678 | 135 | 142 | 3,513 | 34 | 39 |

The required thresholds were at least 100 people per primary exposure category,
30 ED-positive people per category, and 50 people per treatment-by-poverty
cell using the prespecified `<200%` versus `≥200%` contrast. The narrow
definition fails the ED and poverty gates; the broad definition still fails the
poverty gate. The raw five-level poverty diagnostic is sparser still, with
minimum cells of 6 and 7. Insurance cells are also sparse, including a zero
cell.

## Candidate binary redesign

| Candidate exposure | N | ED-positive | ED visits |
|---|---:|---:|---:|
| Any condition-linked opioid | 820 | 195 | 319 |
| No condition-linked opioid | 3,648 | 847 | 1,339 |

For the prespecified two-level year-1 poverty variable (`<200%` versus `≥200%`
of the federal poverty level), the smallest binary-exposure cell is 252 and the
smallest ED-positive cell is 81. A three-level sensitivity (`<200%`,
`200–399%`, and `≥400%`) also passes, with minimum counts of 223 and 56.

This fallback changes the scientific question. The no-opioid group includes
people with neither an opioid nor an observed condition-linked prescription
nonopioid, so it cannot measure adoption of multimodal or opioid-sparing
analgesia. A Judge decision is required before protocol freezing.

## Timing and interpretation boundary

- Public-use event dates are month/year, not exact dates.
- Prescribed-medicine timing and condition links cannot establish a fill within
  30 days after a specific operation.
- A shared condition link does not prove that a medicine was prescribed because
  of, or after, the linked surgery.
- `ERTOTY2` is annual all-cause ED utilization in the subsequent panel year.
- The feasible estimand is associational. Causal, postoperative, protocol
  adoption, interrupted-time-series, and joinpoint claims remain prohibited.

## Reproducibility

Run `python analysis\meps_analysis.py` from the project root. The script
recreates every aggregate file under `analysis/outputs/`, checks required
variables and person-panel uniqueness, verifies condition and HC-036 matches,
and refuses to proceed when a required file or design field is missing.
