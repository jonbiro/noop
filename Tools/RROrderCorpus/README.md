# R-R order corpus runner

`rr-order-corpus` is a local, read-only measurement tool for the R-R emission-order repair behind #823.
It runs the existing `RROrderAudit` once per stored NOOP sleep session and emits analysis-ready session
aggregates. It does not change scoring, write to the database, or export raw R-R intervals.

## What it measures

For each stored sleep session, the output records:

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

## Privacy model

By default, database device identifiers are replaced with deterministic, invocation-local labels:

```text
device-001
device-002
```

Pass `--include-device-id` only when the raw identifiers are genuinely needed. Neither JSONL nor CSV
contains the underlying R-R sequence. The tool exports aggregate counts and statistics only.

## Build and run

From this directory:

```bash
swift build
swift test
swift run rr-order-corpus --help
```

The database path is resolved in this order:

1. `--db PATH`;
2. `NOOP_DB_PATH`;
3. the sandboxed production app path;
4. the unsandboxed OpenWhoop application-support path.

Example, using UTC calendar-day bounds and CSV output:

```bash
swift run rr-order-corpus \
  --from 2026-07-01 \
  --to 2026-08-16 \
  --min-duration-min 120 \
  --format csv \
  --output rr-order-corpus.csv
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

## Interpretation limits

- A non-null `ord` is not automatically trustworthy. Duplicate order values in a multi-beat second are
  classified as ambiguous because `ord` is batch-local.
- Legacy rows remain unknown. The tool does not reconstruct an order the device never recorded.
- The counterfactual is the historic magnitude read over the same stored row population. It is not a
  claim that every old release produced exactly that nightly result after every downstream transform.
- A small synthetic fixture demonstrates the direction of the bug. Only a multi-night, multi-device run
  can estimate real-world full-night effect size.
- No automatic quality threshold or score-withholding rule is introduced here. That decision requires
  corpus evidence first.
