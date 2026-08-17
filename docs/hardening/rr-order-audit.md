# R-R order integrity audit

Upstream #823 fixed a structural HRV defect: same-second R-R intervals were read in interval-magnitude order, which makes successive values artificially similar and can bias RMSSD downward. The current schema records a nullable batch-local `ord` and reads by:

```sql
ORDER BY ts ASC, ord ASC, rrMs ASC, seq ASC
```

That repair is necessary but does not make every historical or newly stored window equally trustworthy:

- rows written before the migration have `ord = NULL` because their emission order was never observed;
- a transport that inserts one beat per call restarts the batch-local counter, producing `ord = 0` for every beat in a second;
- an import/merge can place legacy and ordered rows in the same second;
- scoring filters can remove one source or a future-stamped row, leaving gaps in otherwise valid order values.

This audit is a bounded, read-only integrity instrument. It changes no score, schema, BLE command, UI, or stored physiological value.

## Exact population

Swift `WhoopStore.rrOrderAuditRows(deviceId:from:to:)` uses the same population and order as the scoring read:

- requested device and inclusive time bounds;
- Oura SpO2-IBI duplicate channel excluded;
- future-stamped/suspect rows excluded;
- current production SQLite ordering retained;
- `seq` and nullable `ord` projected only into a diagnostic row, not added to `RRInterval`.

Android's existing DAO entity already retains `seq` and `ord`, so the pure Kotlin audit consumes the bounded result of the existing scoring query.

## Structural integrity status

The report exposes a stable machine-readable status:

| Status | Meaning |
|---|---|
| `noData` / `NO_DATA` | No intervals were present in the requested window |
| `complete` / `COMPLETE` | Every multi-beat second has unique recorded order |
| `partial` / `PARTIAL` | At least one multi-beat second is legacy-unknown or mixed known/unknown |
| `ambiguous` / `AMBIGUOUS` | At least one multi-beat second has duplicate recorded order values |

Unknown `ord` on a **single-beat** second does not downgrade integrity because there is no within-second permutation to recover.

The audit also emits machine-readable flags for no data, legacy order, mixed order, duplicate order, production-gate failures, lack of contiguous cleaned pairs, cleaning rejection, counterfactual cleaning changes, production-HRV changes, and raw-order invariant failures.

These flags describe observed facts. They are not clinical or automatic score-withholding rules.

## Provenance classifications

Classification is per wall-clock second because `ord` is scoped to rows sharing that timestamp.

| Classification | Definition | Interpretation |
|---|---|---|
| Single beat | One surviving interval in the second | Order-insensitive by itself |
| Trustworthy | Multiple rows, every `ord` present, all values unique | Relative emission order is known |
| All unknown | Multiple rows, every `ord` null | Legacy or otherwise unobserved order |
| Mixed | Some rows have `ord`, some do not | Import/merge population with no complete relative order |
| Ambiguous recorded | Every row has `ord`, but at least one value repeats | Typical split-batch or one-beat-per-insert signature |

A trustworthy group does **not** require contiguous values. `[2, 7]` still preserves survivor order when scoring filters removed the rows formerly between them.

The report includes both interval and second counts plus first/last timestamp, wall-clock span, distinct sampled seconds, and maximum intervals observed in one second. `recordedOrderFraction` is descriptive only: a duplicate `0, 0, 0` group has 100% non-null values but remains ambiguous. `trustworthyMultiBeatIntervalFraction` is the stronger provenance measure for successive-difference metrics.

## Permutation severity

A binary "changed / unchanged" marker is not enough to characterize a permutation. For trustworthy groups the audit therefore also records:

- number of trustworthy groups compared;
- number of groups and intervals whose R-R **value sequence** differs from magnitude order;
- total pairwise value inversions;
- number of unequal-valued pairs that could be inverted;
- normalized inversion fraction;
- largest inversion count in one group;
- largest trustworthy group size.

Equal-valued intervals do not count as inversions because swapping identical values cannot change an R-R statistic.

This makes two windows distinguishable even if both contain a reordered second: one may contain a single adjacent swap while another is close to a full magnitude reversal.

## HRV counterfactual

`RROrderAudit` and Kotlin `RrOrderAudit` sort the same rows two ways:

1. **Current production:** `ts`, nullable `ord`, `rrMs`, `seq`.
2. **Historic counterfactual:** `ts`, `rrMs`, `seq`.

Both sequences pass through the platform's actual HRV implementation, including:

- physiological range filtering;
- Malik local-median rejection;
- gap-aware RMSSD and pNN50;
- the 20-clean-beat production gate;
- SDNN and mean-NN calculation.

The report now compares every core production HRV output that can change because ordering also changes the local cleaning neighbourhood:

- RMSSD, absolute and percent delta;
- SDNN, absolute and percent delta;
- mean NN, absolute and percent delta;
- pNN50, percentage-point delta.

It also records raw RMSSD, raw pNN50, raw SDNN, and raw mean-NN before filtering. Raw mean and raw SDNN are order-invariant for an identical multiset, so they act as built-in audit self-checks. `rawOrderInvariantPreserved == false` is an implementation-integrity failure, not a physiological finding.

## Cleaning and production-gate diagnostics

The audit preserves two distinct cleaned-beat counts because they answer different questions:

- `nClean` is the count returned by NOOP's production `HRVResult`. By design it is `0` when the 20-beat sufficiency gate fails.
- `actualCleanCount` is how many intervals truly survived range + ectopic cleaning, even below the production gate.

This avoids turning a five-beat clean diagnostic fixture into the misleading statement "zero clean beats."

Each current/counterfactual snapshot also reports:

- rejected interval count and fraction;
- number of contiguous cleaned successive pairs available to RMSSD/pNN50;
- whether the true cleaned count clears the production beat gate;
- whether changing order changes the cleaning outcome itself.

That last point matters because Malik's local-median window is sequence-dependent. A historical ordering bug can therefore influence not just successive differences but also which intervals survive cleaning.

## Five-beat regression example

For the issue's deterministic example:

```text
emission:   812, 795, 840, 801, 833  -> raw RMSSD about 34.85 ms
magnitude:  795, 801, 812, 833, 840  -> raw RMSSD about 12.72 ms
```

The observed sequence contains four value inversions out of ten unequal-value pairs, a normalized inversion fraction of 0.40.

This is a regression fixture, not a claim about full-night effect size.

## Cross-platform contract

Swift and Kotlin expose equivalent fields and classification rules. Mirrored tests cover:

- the issue's five-beat example;
- permutation/inversion severity;
- a 20-beat sequence through the production cleaning/gating path;
- all core HRV counterfactual outputs;
- every provenance classification and structural status;
- true clean counts below the production gate;
- cleaning rejection diagnostics;
- raw mean/SDNN invariants;
- shuffled-input determinism;
- equal-valued beats that change row identity but not the HRV value sequence;
- empty-input absence semantics.

Swift store tests additionally verify:

- batched `0,1,2,…` order;
- split-batch duplicate-zero order;
- legacy null order;
- equal-value `seq` preservation;
- exact scoring-population parity, including SpO2-channel exclusion.

## What this audit does not establish

It does not recover legacy order, infer the correct sequence of duplicate order values, or prove that every emitted interval is a real unique heartbeat. Those are separate source/coverage questions.

It also does not automatically suppress HRV or modify Charge/Readiness. Those are product-policy decisions and should be driven by the real-night corpus tooling rather than a synthetic regression case.

The companion corpus PR quantifies the full-night distribution of provenance, permutation severity, cleaning changes, and HRV deltas before any user-facing policy is proposed.
