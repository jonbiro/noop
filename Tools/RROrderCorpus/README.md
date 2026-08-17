# R-R ordering corpus analysis

`RROrderCorpus` is a read-only measurement and analysis package for the R-R ordering integrity work around #823.

It answers the progression of questions needed before changing any user-facing HRV policy:

1. **Is same-second order structurally trustworthy?** `RROrderAudit` answers this per window.
2. **How often does the problem occur on real stored nights?** `rr-order-corpus` measures every eligible sleep session.
3. **How large is the effect on NOOP's actual HRV pipeline?** Current and historical-magnitude order are run through the same cleaning and sufficiency path.
4. **Is the effect related to provenance/permutation severity?** `rr-order-summary` stratifies and correlates the results.
5. **Could it change a downstream interpretation?** The summary measures Readiness HRV signal transitions and a bounded Charge HRV sensitivity envelope.

The package does not write the NOOP database, does not change a score, and never exports the raw R-R sequence.

## Executables

### `rr-order-corpus`

Reads the local NOOP database with GRDB `readonly = true`, validates the expected schema, discovers stored sleep sessions, and emits one schema-v2 observation per session.

Each observation includes:

- immutable detected and effective user-adjusted sleep bounds;
- pseudonymous device key by default;
- SQLite `user_version` in the run summary;
- rows in the sleep window and how many survive NOOP's exact scoring filters;
- SpO2-IBI duplicate-channel and suspect-timestamp exclusion counts;
- structural order status and machine-readable audit flags;
- legacy/mixed/duplicate-order provenance;
- first/last R-R timestamp, span, sampled-second count, maximum beats per second;
- permutation severity, including normalized value-inversion fraction;
- current and magnitude-order RMSSD, SDNN, mean NN, and pNN50;
- raw RMSSD/pNN50 plus raw mean/SDNN audit invariants;
- actual cleaned-beat count even below the 20-beat production gate;
- production `nClean`, rejected count/fraction, contiguous successive-pair count, and gate status;
- whether the counterfactual changes the cleaning outcome.

JSONL and CSV are supported. CSV is intentionally flat for spreadsheets/statistical tools. JSONL preserves the nested audit structure.

### `rr-order-summary`

Consumes schema-v2 JSONL and produces aggregate Markdown or JSON. It never carries raw database device IDs or per-session records into the aggregate output.

The report includes:

- corpus scope and session-duration distribution;
- scoring-filter exclusion totals;
- structural status and audit-flag counts;
- raw invariant failures;
- aggregate permutation/inversion severity;
- RMSSD, SDNN, mean-NN, and pNN50 effect distributions;
- cleaning/rejection/gate effects;
- deterministic bootstrap 95% intervals for mean and median RMSSD delta;
- Spearman association of order quality/permutation severity with absolute RMSSD impact;
- integrity, trustworthy-coverage, session-duration, and sparse-staging strata;
- pseudonymous per-device aggregates;
- downstream HRV sensitivity described below.

## Downstream sensitivity

### Readiness HRV signal

The analyzer reproduces the **HRV component** of `ReadinessEngine`, not the full multi-signal Readiness synthesis:

- current-order RMSSD from prior nights forms the personal baseline;
- trailing 30 observations;
- at least 7 prior observations;
- lnRMSSD transform;
- `Baselines.readinessHRVLnCfg`;
- hard-outlier rejection disabled, matching `ReadinessEngine`'s trailing-window fold;
- the same z-score flag cutoffs: `good >= +0.5`, `neutral >= -0.5`, `watch >= -1`, otherwise `bad`.

The report counts nights where current versus magnitude-order HRV would cross one of those HRV-signal boundaries and records the transition matrix.

It does **not** claim the entire Readiness level/headline would necessarily change, because RHR, respiration, load, and monotony are separate signals.

### Charge HRV envelope

Charge is a weighted multi-driver model. The corpus cannot honestly reconstruct every historical non-HRV input from the R-R record alone, so it does not pretend to.

Instead it isolates HRV and reports two transparent neutral-context scenarios with all other driver z-scores held at baseline:

- **full-driver-set HRV share:** the smallest current normalized HRV share, when every optional Charge driver is present. With current weights this is `0.55 / 1.10 = 0.50`.
- **HRV-only share:** upper-bound scenario where HRV is the only available driver, normalized share `1.0`.

Both use the raw-ms personal baseline spine (`Baselines.hrvCfg`) and the exact public Charge logistic constants. The interval between the two is a sensitivity envelope for the HRV contribution, not the user's historical actual Charge delta.

## Deterministic uncertainty

For paired production RMSSD deltas the summary provides non-parametric bootstrap 95% intervals for the corpus mean and median. Sampling is driven by a fixed local PRNG seed, so identical input and iteration count produce byte-stable results.

These intervals describe uncertainty from the observed corpus. They are not clinical confidence intervals and are not a hypothesis test.

Use `--bootstrap-iterations 0` to disable resampling, or increase it up to 100,000 for a more stable descriptive interval.

## Strata

The aggregate report automatically splits the corpus by:

- structural integrity: complete / partial / ambiguous / no data;
- trustworthy multi-beat interval coverage: complete, 90–99%, 50–89%, below 50%, or no multi-beat seconds;
- session duration: under 4 h, 4–6 h, 6–8 h, 8 h+;
- staging density: sparse, dense, unknown.

This helps distinguish an order effect from confounding properties of short/fragmented/sparse nights.

## Privacy

By default device database identifiers are replaced with invocation-local labels:

```text
device-001
device-002
```

`--include-device-id` is an explicit diagnostic escape hatch for the **session corpus only**. The aggregate summary never emits the raw identifier even if the input JSONL contains it.

Neither output contains raw R-R rows or the beat sequence.

## Usage

Build and test:

```bash
cd Tools/RROrderCorpus
swift build
swift test
```

One-shot overnight corpus plus Markdown report:

```bash
swift run rr-order-corpus \
  --from 2026-07-01 \
  --to 2026-08-16 \
  --output corpus.jsonl \
  --summary summary.md
```

The overnight-oriented default excludes sessions shorter than 120 minutes. Include naps/short sessions explicitly:

```bash
swift run rr-order-corpus --min-duration-min 0 --output all-sessions.jsonl
```

Create CSV for an external statistical package:

```bash
swift run rr-order-corpus --format csv --output corpus.csv
```

Re-summarize a saved JSONL corpus with more bootstrap iterations:

```bash
swift run rr-order-summary \
  --input corpus.jsonl \
  --bootstrap-iterations 10000 \
  --format json \
  --output summary.json
```

Database discovery order:

1. `--db PATH`;
2. `NOOP_DB_PATH`;
3. production sandbox path;
4. unsandboxed OpenWhoop application-support path.

## Fail-closed behavior

The package rejects:

- an incompatible/missing database schema;
- an invalid time range or session limit;
- malformed JSONL;
- old/future corpus schema versions;
- an audit schema version that does not match the analyzer;
- duplicate observation keys;
- an attempt to send both corpus rows and the summary to stdout in one invocation.

## What this does not do

It does not:

- mutate or migrate the user's database;
- infer legacy beat order that was never recorded;
- invent an order for duplicate batch-local `ord` values;
- export raw R-R sequences;
- set a quality threshold automatically;
- suppress HRV;
- change Charge or Readiness;
- claim statistical or clinical significance.

The tool exists so those future product decisions can be made from reproducible real-night evidence instead of from one synthetic example.
