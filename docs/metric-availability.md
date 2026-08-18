# Metric availability semantics

`MetricAvailability` answers one narrow question:

> Can this analytics metric honestly return a current value, and if not, why?

It is intentionally not a replacement for existing NOOP concepts:

- `ScoreConfidence` remains the maturity/reliability model for Charge, Effort, Rest, and Readiness.
- `FusionSource`, `FusionTier`, `ContributingSource`, and `MetricArbitrationPolicy` remain the source-selection and provenance/trust model.
- `CaptureCompleteness` remains the Test Centre capture-coverage model.
- engine-specific quality diagnostics remain authoritative for their domain.

The purpose of this layer is to stop representing every unavailable state as an unexplained `nil`, `null`, or blank UI.

## States

| State | Value? | Meaning |
|---|---:|---|
| `available` | yes | Current production value is available. |
| `calibrating` | no | Inputs exist, but the metric still needs baseline/history. |
| `insufficientData` | no | Required inputs or coverage are missing. |
| `unsupported` | no | The current device/source cannot provide the required substrate. |
| `withheldQuality` | no | Inputs exist but fail the metric's quality gate. |
| `experimentalAvailable` | yes | A value exists, but the capability is explicitly experimental/unvalidated. |
| `stale` | no | Data exists but is not current enough for the requested period. |

`hasValue` is intentionally true only for `available` and `experimentalAvailable`.

## Reason codes

Reasons are structured as a code plus optional `have`, `need`, and canonical sorted context items. A stable `wireCode` makes logs, golden vectors, diagnostics, and local-access outputs deterministic without treating the diagnostic string as user-facing copy.

Examples:

```text
need_baseline:have=5;need=14
insufficient_coverage:have=0.42;need=0.8
missing_inputs:items=hrv,rhr
unsupported_source:items=whoop4_spo2
withheld_quality:items=rr_order_unknown
experimental_unvalidated:items=hrv_readiness
stale_input:items=expected=2026-08-17,last=2026-08-16
```

## First pilot: HRV Readiness

The existing experimental `HRVReadiness.evaluate(...)` API remains unchanged.

`evaluateWithAvailability(...)` returns the exact same optional result plus:

- the number of physiologically valid HRV nights after the engine's existing filter;
- `calibrating + need_baseline` below the existing 14-night gate;
- `experimentalAvailable + experimental_unvalidated` when a result exists.

The wrapper deliberately preserves the engine's current documentation that HRV Readiness is opt-in and not yet validated against varying real data. It does not silently upgrade an experimental value to generic `available`.

## Adoption rule

Do not mass-convert every engine in one PR. Add availability-aware facades where an existing user/product surface currently cannot explain a missing, withheld, unsupported, experimental, or stale metric. Keep existing APIs compatible unless there is a separate reason to migrate them.

When adopting this type, reuse the domain's existing quality/source/confidence signal instead of copying its logic into `MetricAvailability`.
