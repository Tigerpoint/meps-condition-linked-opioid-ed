# Verification Record

Independent checks performed on **2026-07-29**, after the analysis was complete
and the manuscript drafted. Recorded here so a reader does not have to take the
reproducibility claims on trust.

---

## 1. End-to-end re-execution from raw MEPS files

The complete pipeline was re-run in a clean scratch directory containing only
the two analysis scripts — verified by SHA-256 to be byte-identical to the
committed versions — plus empty output directories. No file in the original
project was written to.

```
Stage 1   meps_analysis.py   50.5 s   exit 0
Stage 2   meps_analysis.R    48.5 s   exit 0
```

### Cohort figures, derived live from the source files

```
positive_weight_universe_n   41,427      eligible_n          4,468
analysis_n (complete cases)   4,454      year2_ed_positive   1,042
year2_ed_visits               1,658
hc036_universe_matches       41,427      hc036_matches       4,468
source_panels           [22, 23, 25, 26]
```

### Estimates, at full precision

| Result key | Fresh run | Committed |
|---|---|---|
| `M1_MARGIN_RATIO` | 0.9746750419533048 | identical |
| `M1_MARGIN_DIFFERENCE` | −0.00873777935568576 | identical |
| `M3_ANYED_DIFFERENCE` | −0.01945368881116802 | identical |
| `M2_INT_WALD` | 0.2844327766197619 (p 0.5943276514581901) | identical |
| `M2_INT_RATIO_OF_RATIOS` | 1.1124737152418593 | identical |

### Byte-level artifact comparison

| Artifact set | Result |
|---|---|
| 27 ledgered outputs | **27/27 byte-identical** |
| 7 further Python-stage outputs | **7/7 byte-identical** |
| 4 figure files (PNG + SVG) | **4/4 byte-identical** |
| `reproducibility_ledger.csv` | Differs — expected; its `prior_run_sha256` and `identical_to_prior_run` columns are self-referential and a fresh directory has no prior run to compare against |

**39 of 40 artifacts byte-identical, including binary image files.**

The temporary person-level modeling table was deleted by the R stage, as
documented.

---

## 2. Provenance of the input data

The concern this addresses: a hash manifest generated *from* a set of files
cannot prove those files are authentic. If a source file had been altered before
the first run, every subsequent run would faithfully reproduce the altered
result and every internal check would still pass.

Four input files were therefore downloaded fresh from AHRQ and compared against
`analysis/outputs/file_manifest.csv`:

| File | Size | SHA-256 vs. manifest |
|---|---|---|
| `h197d.dta` | 1,348,758 B | **MATCH** |
| `h220d.dta` | 683,922 B | **MATCH** |
| `h229d.dta` | 773,974 B | **MATCH** |
| `h36u23.dta` (HC-036 pooled variance) | 129,325,912 B | **MATCH** |

HC-036 was included specifically because it supplies `STRA9623` and `PSU9623`
and therefore determines every standard error and confidence interval in the
paper.

AHRQ distributes MEPS public-use files directly in Stata format, so no format
conversion sits between the AHRQ release and the analysis inputs, and raw hash
comparison is valid.

`scripts/fetch_meps_data.ps1` performs this check across all 33 input files.

---

## 3. Internal coherence of the result files

Every confidence interval in every result file was tested against its own
reported standard error and design degrees of freedom, by backing out the
implied critical value:

```
raw scale:  t = (ci_high − estimate) / std_error
log scale:  t = (log ci_high − log estimate) / (std_error / estimate)
```

**All 58 interval rows land on the exact t-critical for their own design df:**

| Result family | Rows | Design df | Implied t | t(0.975) |
|---|---:|---:|---|---|
| Primary, interaction, nested | 25 | 261 | 1.9691 | 1.96896 |
| Setting — inpatient | 2 | 196 | 1.9721 | 1.97218 |
| Setting — outpatient | 2 | 204 | 1.9717 | 1.97164 |
| Setting — office-based | 2 | 230 | 1.9703 | 1.97024 |
| Sensitivity S01–S10 | 27 | varies | 1.9691–1.9695 | matches each domain |

Restricted-domain analyses correctly use their own reduced degrees of freedom
rather than the primary model's. Scale convention is consistent throughout:
counts and ratios use log-scale intervals, differences and probabilities use
raw-scale intervals.

Estimand algebra was re-derived independently from the margin rows — ratios,
differences, and the ratio of count ratios all reproduce exactly; poverty-domain
weighted populations and unweighted counts sum to their totals.

---

## 4. Code review

Both analysis programs (2,984 lines) were read against the claims the protocol
and manuscript make. Points confirmed in the implementation:

- Survey design built on the full 41,427-record universe; eligible cohort
  analyzed as a domain via `subset()`, **not** by rebuilding the design on
  filtered data
- `nest = TRUE` on HC-036 `STRA9623` / `PSU9623`; pooled weight `LONGWT / 4`
  applied per record before design construction
- Standardization overwrites only the exposure column, leaving all other
  covariates at observed values, and averages predictions with survey weights
- Influence function carries **both** variance components —
  `coefficient_influence %*% gradient + normalized_weights * (μ − estimate)`
- Design variance computed via `survey::svyrecvar` using the design's own
  cluster, strata, and fpc
- Poverty-specific margins masked to the poverty domain, then renormalized
- Heterogeneity assessed by `regTermTest(m2, ~opioid_binary:poverty_2,
  method = "Wald")` — a single 1-df test, not a subgroup p-value comparison
- Opioid classification uses Multum classes 60 and 191 across all `TC*` fields,
  matching the documented crosswalk, with opioid precedence within a record and
  negative missing codes unable to produce false positives

**No defect was found.**

This confirms the code faithfully implements the prespecified protocol. It is
not an independent endorsement of the protocol's design choices — for example,
whether four-panel equal-weight averaging is the right target of inference is a
design decision, prespecified in `research/analysis_protocol.md`, not something
a code audit can adjudicate.

---

## 5. What remains unverified

Verification is bounded. Reproducibility establishes that a pipeline is
deterministic and that its inputs are authentic. It does not establish that the
research question is well posed, that the covariate set is sufficient, or that
the estimand answers a question anyone should care about. Those are matters for
peer review, and the manuscript's limitations section addresses them directly.

29 of 33 input files have not yet been individually re-downloaded and hashed
against AHRQ; `scripts/fetch_meps_data.ps1` completes that check for anyone who
wants it.
