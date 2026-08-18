# R-R input integrity audit

Upstream #823 fixed a structural HRV defect: same-second R-R intervals were read in interval-magnitude order, which makes successive values artificially similar and can bias RMSSD downward. The current schema records a nullable batch-local `ord` and reads by:

```sql
ORDER BY ts ASC, ord ASC, rrMs ASC, seq ASC
```

That repair is necessary but it does not make every R-R window trustworthy. A useful audit must distinguish ordering provenance from capture density, duplicate/over-count evidence, beat-timestamp accuracy, cleaning behavior, and the numerical HRV effect.

`RROrderAudit` is that bounded, read-only instrument. It changes no score, schema, BLE command, UI, or stored physiological value.

## Schema

`RROrderAuditReport.currentSchemaVersion = 3`.

The schema version changes when the meaning or serialized shape of the audit changes. Corpus/report tooling carries this version separately and fails closed on a mismatch.

## Exact population

Swift `WhoopStore.rrOrderAuditRows(deviceId:from:to:)` uses the same population and order as the scoring read:

- requested device and inclusive time bounds;
- Oura SpO2-IBI duplicate channel excluded;
- future-stamped/suspect rows excluded;
- current production SQLite ordering retained;
- `seq` and nullable `ord` projected only into a diagnostic row, not added to `RRInterval`.

Android's existing DAO entity already retains `seq` and `ord`, so the Kotlin audit consumes the bounded result of the existing scoring query.

## Structural integrity status

The report exposes a stable machine-readable status:

| Status | Meaning |
|---|---|
| `noData` / `NO_DATA` | No intervals were present |
| `complete` / `COMPLETE` | Every multi-beat second has unique recorded order |
| `partial` / `PARTIAL` | At least one multi-beat second is legacy-unknown or mixed known/unknown |
| `ambiguous` / `AMBIGUOUS` | At least one multi-beat second has duplicate recorded order values |

Unknown `ord` on a single-beat second does not downgrade integrity because there is no within-second permutation to recover.

## Same-second provenance

Classification is per wall-clock second because `ord` is scoped to rows sharing that timestamp.

| Classification | Definition | Interpretation |
|---|---|---|
| Single beat | One surviving interval | Order-insensitive by itself |
| Trustworthy | Multiple rows, every `ord` present and unique | Relative emission order is known |
| All unknown | Multiple rows, every `ord` null | Legacy or otherwise unobserved order |
| Mixed | Some rows have `ord`, some do not | No complete relative order |
| Ambiguous recorded | Every row has `ord`, but a value repeats | Typical split-batch / one-beat-per-insert signature |

Gaps such as `[2, 7]` remain trustworthy because scoring filters can remove rows while preserving relative order.

The report includes interval/second counts, first/last timestamp, wall-clock span, sampled seconds, maximum beats per second, recorded-order fraction, and trustworthy multi-beat interval fraction.

## Native NOOP capture diagnostics

The audit intentionally **reuses**, rather than reimplements, the coverage and over-count primitives that already live in `HRVAnalyzer` on current upstream.

For the exact audited population it records:

- raw R-R coverage (`sum(rr) / wall-clock span`);
- same-second collapsed coverage;
- native `RrCoverageVerdict` as a stable string;
- whether beat spread is trustworthy under that verdict;
- native beat-accurate fraction;
- whether beat values are trustworthy under NOOP's current beat-accuracy gate;
- exact duplicate `(ts, rrMs)` row count;
- rows dropped, coverage, and beat accuracy after the 40 ms same-second shadow collapse;
- rows dropped, coverage, and beat accuracy after the new 40 ms / 1-second cross-second shadow.

The 1-second shadow is explicitly an **aggressive upper bound**, exactly as documented upstream. A steady real 1-second rhythm will cause it to drop legitimate neighbours. The audit therefore reports it as instrumentation and emits `crossSecondUpperBoundDropsRows`; it never treats those drops as a production de-dup recommendation.

Machine-readable flags distinguish:

- under-coverage;
- same-second over-count verdict;
- cross-second over-count verdict;
- beat timing below the native trust gate;
- exact duplicate rows;
- same-second shadow drops;
- aggressive cross-second shadow drops.

This is valuable because order can be perfectly recorded while the input stream is still duplicated, banked/coarsely timestamped, or under-covered.

## Permutation severity

A binary reordered/not-reordered marker is insufficient. For trustworthy groups the audit records:

- trustworthy groups compared;
- groups and intervals whose R-R **value sequence** differs from ascending magnitude order;
- pairwise value inversions;
- number of unequal-valued pairs that could be inverted;
- normalized inversion fraction;
- maximum inversion count in one group;
- largest trustworthy group.

Equal-valued intervals do not count as inversions because swapping identical values cannot change an R-R statistic.

## HRV counterfactual

The same rows are evaluated in two orders:

1. **Current production:** `ts`, nullable `ord`, `rrMs`, `seq`.
2. **Historic counterfactual:** `ts`, `rrMs`, `seq`.

Both pass through the platform's current `HRVAnalyzer`, including physiological range filtering, Malik local-median rejection, gap-aware successive differences, and the 20-clean-beat production gate.

Paired diagnostics cover:

- RMSSD absolute and percent delta;
- SDNN absolute and percent delta;
- mean-NN absolute and percent delta;
- pNN50 percentage-point delta;
- raw RMSSD and raw pNN50;
- raw mean-NN and raw SDNN as order-invariant audit self-checks.

If raw mean or raw SDNN changes after reordering an identical multiset, `rawOrderInvariantFailure` is raised because that is an audit implementation defect, not physiology.

## Cleaning and production-gate diagnostics

The audit preserves two cleaned-beat counts:

- `nClean`: the value returned by the production `HRVResult`, intentionally zero when the minimum-beat gate fails;
- `actualCleanCount`: the number of intervals that truly survive range + ectopic cleaning even below the gate.

It also records rejected count/fraction, contiguous cleaned successive-pair count, production beat-gate state, and whether the counterfactual changes the cleaning outcome itself.

This matters because Malik's local-median filter is sequence-dependent. An ordering defect can affect both successive differences and which intervals survive cleaning.

## Five-beat regression example

```text
emission:   812, 795, 840, 801, 833  -> raw RMSSD about 34.85 ms
magnitude:  795, 801, 812, 833, 840  -> raw RMSSD about 12.72 ms
```

The observed sequence contains four value inversions out of ten unequal-value pairs, normalized inversion fraction 0.40.

This is a regression fixture, not a claim about full-night effect size.

## Cross-platform contract

Swift and Kotlin expose equivalent structural, capture, permutation, cleaning, and HRV fields. Mirrored tests cover:

- the original five-beat example;
- production 20-beat path;
- all core HRV counterfactual outputs;
- every provenance state;
- true clean counts below the production gate;
- cleaning rejection;
- raw mean/SDNN invariants;
- shuffled-input determinism;
- equal-valued beat handling;
- explicit no-data semantics;
- plausible beat-accurate capture;
- exact same-second duplicate/over-count capture;
- banked/coarse timestamp shape below the beat-accuracy trust gate;
- aggressive cross-second shadow behaviour without promoting it to a defect verdict.

Swift store tests separately verify scoring-population parity, batched order, split-batch duplicate order, legacy null order, equal-value `seq` preservation, and SpO2-channel exclusion.

## What this audit does not establish

It does not recover legacy order, infer the correct sequence of duplicate order values, or prove that each emitted interval is a unique real heartbeat.

It does not turn the upstream cross-second shadow into a production de-dup path.

It does not suppress HRV or modify Charge/Readiness. Those are product-policy decisions and must be driven by real-night corpus evidence.
