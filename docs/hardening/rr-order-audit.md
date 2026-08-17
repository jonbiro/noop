# R-R order integrity audit

Upstream #823 fixed a structural HRV defect: same-second R-R intervals were read in interval-magnitude order, which makes successive values artificially similar and biases RMSSD downward. The current schema records a nullable batch-local `ord` and reads by:

```sql
ORDER BY ts ASC, ord ASC, rrMs ASC, seq ASC
```

That repair is necessary but does not make every historical or newly stored window equally trustworthy:

- rows written before the migration have `ord = NULL` because their emission order was never observed;
- a transport that inserts one beat per call restarts the batch-local counter, producing `ord = 0` for every beat in a second;
- an import/merge can place legacy and ordered rows in the same second;
- scoring filters can remove one source or a future-stamped row, leaving gaps in otherwise valid order values.

This tranche adds a bounded, read-only audit. It changes no score, schema, BLE command, UI, or stored physiological value.

## Exact population

Swift `WhoopStore.rrOrderAuditRows(deviceId:from:to:)` uses the same population and order as the scoring read:

- requested device and inclusive time bounds;
- Oura SpO2-IBI duplicate channel excluded;
- future-stamped/suspect rows excluded;
- current production SQLite ordering retained;
- `seq` and nullable `ord` projected only into a diagnostic row, not added to `RRInterval`.

Android's existing DAO entity already retains `seq` and `ord`, so the pure Kotlin audit consumes the bounded result of the existing scoring query.

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

The report includes both interval and second counts. `recordedOrderFraction` is descriptive only: a duplicate `0, 0, 0` group has 100% non-null values but remains ambiguous. `trustworthyMultiBeatIntervalFraction` is the quality-oriented measure for successive-difference metrics.

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

The report also includes unfiltered raw RMSSD so a small deterministic fixture can demonstrate the ordering effect without pretending it passes the production sufficiency gate.

For the five-beat issue example:

```text
emission:   812, 795, 840, 801, 833  -> raw RMSSD about 34.85 ms
magnitude:  795, 801, 812, 833, 840  -> raw RMSSD about 12.72 ms
```

This is a regression fixture, not a claim about full-night effect size.

## Cross-platform contract

Swift and Kotlin expose the same fields and classification rules. Mirrored tests cover:

- the issue's five-beat example;
- a 20-beat sequence through the production cleaning/gating path;
- every provenance classification;
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

It does not recover legacy order, infer the correct sequence of duplicate order values, or prove that every emitted beat is a real unique heartbeat. Those are separate coverage/source-quality questions already handled by other R-R diagnostics.

It also does not yet answer the main empirical question: how much full-night RMSSD, Charge, or Readiness changes across real users and devices. The next step is a multi-night corpus run that records:

- order-provenance fractions;
- current and magnitude-counterfactual RMSSD;
- raw and cleaned deltas;
- source/device/firmware context;
- coverage and beat-accuracy verdicts;
- downstream daily-score sensitivity.

Until that corpus exists, the audit reports evidence without changing or suppressing a headline score.
