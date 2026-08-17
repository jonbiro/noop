# R-R order corpus tools

This Swift package contains two local measurement commands for the R-R emission-order repair behind #823:

- `rr-order-corpus` opens the NOOP database read-only and emits one aggregate record per stored sleep session;
- `rr-order-summary` reduces schema-v1 JSONL into an aggregate-only Markdown or JSON report.

Neither command changes scoring, writes to the database, or exports raw R-R intervals.

## What the corpus runner measures

For each stored sleep session, `rr-order-corpus` records:

- detected, user-adjusted, and ending session timestamps;
- total R-R intervals used by the production scoring read;
- recorded-order and trustworthy same-second-order coverage;
- legacy, mixed, and duplicate-order group counts;
- the current production HRV result;
- the former `(ts, rrMs, seq)` magnitude-order result as an offline counterfactual;
- absolute and percentage RMSSD differences;
- input and cleaned-beat counts;
- cached nightly HRV as context only.

The tool uses the user-corrected onset when `startTsAdjusted` is present. It preserves the immutable
detected start in the output so the observation can still be tied back to its database row.

## What the summary command reports

`rr-order-summary` calculates:

- deterministic R-7 distribution summaries: mean, sample SD, min, p10, p25, median, p75, p90, and max;
- interval-weighted recorded-order and trustworthy multi-beat-order coverage;
- legacy, mixed, ambiguous, and magnitude-reordered group totals;
- paired current-versus-magnitude production RMSSD differences in milliseconds and percent;
- paired raw diagnostic differences;
- descriptive absolute-effect bins;
- clean-beat fractions;
- cached-value context;
- pseudonymous per-device summaries.

Duplicate observations fail closed instead of silently double-weighting a night. The summary contains no
per-session rows or raw device identifiers, even when the input JSONL was generated with
`--include-device-id`.

## Privacy model

By default, database device identifiers are replaced with deterministic, invocation-local labels:

```text
device-001
device-002
```

Pass `--include-device-id` only when the raw identifiers are genuinely needed in the corpus file. Neither
JSONL nor CSV contains the underlying R-R sequence. The summary command discards raw identifiers and
emits aggregate statistics only.

## Build and test

From this directory:

```bash
swift build
swift test
swift run rr-order-corpus --help
swift run rr-order-summary --help
```

## Run the corpus measurement

The database path is resolved in this order:

1. `--db PATH`;
2. `NOOP_DB_PATH`;
3. the sandboxed production app path;
4. the unsandboxed OpenWhoop application-support path.

Generate schema-v1 JSONL for analysis:

```bash
swift run rr-order-corpus \
  --from 2026-07-01 \
  --to 2026-08-16 \
  --min-duration-min 120 \
  --format jsonl \
  --output rr-order-corpus.jsonl
```

Analyze selected devices by repeating the option:

```bash
swift run rr-order-corpus \
  --device-id my-whoop \
  --device-id oura-api \
  --format jsonl
```

`--from` and `--to` accept either unix seconds or `YYYY-MM-DD` in UTC. A date supplied to `--to`
includes that entire UTC day. The date filter applies to the session's immutable detected start.

CSV remains available for direct spreadsheet work:

```bash
swift run rr-order-corpus --format csv --output rr-order-corpus.csv
```

## Summarize a corpus run

Markdown report:

```bash
swift run rr-order-summary \
  --input rr-order-corpus.jsonl \
  --format markdown \
  --output rr-order-summary.md
```

Machine-readable aggregate JSON:

```bash
swift run rr-order-summary \
  --input rr-order-corpus.jsonl \
  --format json \
  --output rr-order-summary.json
```

Both commands support stdin/stdout pipelines:

```bash
swift run rr-order-corpus --format jsonl \
  | swift run rr-order-summary --format markdown
```

## Interpretation limits

- A non-null `ord` is not automatically trustworthy. Duplicate order values in a multi-beat second are
  classified as ambiguous because `ord` is batch-local.
- Legacy rows remain unknown. The tools do not reconstruct an order the device never recorded.
- The counterfactual is the historic magnitude read over the same stored row population. It is not a
  claim that every old release produced exactly that nightly result after every downstream transform.
- A small synthetic fixture demonstrates the direction of the bug. Only a multi-night, multi-device run
  can estimate real-world full-night effect size.
- Descriptive effect bins are reporting aids, not clinical, release, or score-withholding thresholds.
- No automatic quality threshold or score-withholding rule is introduced here. That decision requires
  corpus evidence and downstream Charge/Readiness sensitivity first.
