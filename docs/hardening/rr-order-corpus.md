# R-R emission-order corpus methodology

## Question

The structural #823 repair proved that sorting same-second R-R intervals by value can bias a
successive-difference metric downward. The remaining question is empirical:

> Across real stored sleep sessions, how often was same-second order known, and how much did the current
> production ordering change nightly HRV relative to the former magnitude-order read?

This document defines the measurement instrument. It does not define a new score or release threshold.

## Unit of analysis

One record equals one stored `sleepSession` row for one device.

The R-R window is:

```text
[startTsAdjusted ?? startTs, endTs]
```

The output also retains the immutable detected `startTs`. Sessions with a non-positive effective duration
are counted as invalid and omitted. A caller may apply an explicit minimum duration, but the default is
zero so the tool does not silently redefine the corpus.

## R-R population

The read is the diagnostic twin of production scoring:

```sql
SELECT ts, rrMs, seq, ord
FROM rrInterval
WHERE deviceId = ? AND ts >= ? AND ts <= ?
  AND (srcChannel IS NULL OR srcChannel <> SPO2_IBI)
  AND (tsSuspect IS NULL OR tsSuspect <> 1)
ORDER BY ts ASC, ord ASC, rrMs ASC, seq ASC
```

The tool's read-only query is parity-tested against `WhoopStore.rrOrderAuditRows` on a migrated database.
If the current audit columns are absent, the run fails closed rather than silently changing semantics.

## Per-session comparison

`RROrderAudit` evaluates the identical row population twice:

1. current production ordering: `(ts, nullable ord, rrMs, seq)`;
2. historic magnitude counterfactual: `(ts, rrMs, seq)`.

Both sequences pass through the existing `HRVAnalyzer` cleaning and 20-beat sufficiency gate. Raw
unfiltered RMSSD is retained as a diagnostic so a small fixture can demonstrate ordering behavior without
being mislabeled as a production-valid nightly HRV reading.

## Order provenance classes

For every multi-beat second:

- **trustworthy**: every row has a unique recorded `ord`;
- **legacy unknown**: every row has `ord = NULL`;
- **mixed**: only some rows have recorded order;
- **ambiguous recorded**: all rows have order values, but at least one value repeats.

Gapped unique values remain trustworthy because filtering can remove a row while preserving survivor
order. Duplicate values are ambiguous because `ord` is batch-local and can restart when a second is split
across inserts.

## Privacy and output

The default output replaces database IDs with invocation-local pseudonyms. Raw device IDs require an
explicit flag. No R-R row, interval value sequence, stage segment, note, or journal entry is serialized.

Supported formats:

- JSON Lines for scripted analysis;
- flat CSV for spreadsheet/statistical workflows.

Every record carries `schemaVersion = 1` so future output changes can be detected rather than blended.

## Required corpus analysis

A useful report should include at minimum:

- number of devices and sessions;
- session-duration distribution;
- fraction of intervals with any recorded order;
- trustworthy fraction among multi-beat intervals;
- prevalence of legacy, mixed, and ambiguous groups;
- distribution of current-minus-magnitude RMSSD in milliseconds and percent;
- the same distribution restricted to sessions that clear the production HRV gate;
- sensitivity by device/source and by order-provenance coverage;
- outlier inspection without publishing raw private rows;
- downstream Charge and Readiness sensitivity, calculated in a later isolated tranche.

Synthetic five-beat fixtures remain regression tests, not estimates of population effect size.

## Decision rule

Do not change headline HRV, withhold a score, or set a provenance threshold solely because this tool
exists. A behavioral change requires:

1. multiple real nights;
2. more than one device or wearer where available;
3. a material and reproducible effect;
4. a repairable cause;
5. Swift/Kotlin parity;
6. explicit downstream score sensitivity.
