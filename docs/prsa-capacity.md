# Experimental phase-rectified signal averaging (PRSA)

`PhaseRectifiedSignalAveraging` adds deceleration-capacity (DC) and acceleration-capacity (AC) calculations as an unwired research analytics primitive.

It does not change HRV, Readiness, Recovery/Charge, sleep, strain, rhythm screening, or any headline score.

## Why this is experimental

PRSA/DC originated in long-duration ECG/Holter research. NOOP's wearable R-R substrate can be PPG-derived pulse-rate variability rather than ECG NN intervals, and its ordering/coverage/artifact properties are device-specific.

The mathematical method is useful to expose for research and future validation, but this PR deliberately does not transfer clinical interpretation from ECG cohorts onto wearable PRV.

## Input contract

The engine accepts **already-cleaned NN/R-R intervals in milliseconds**.

It does not perform a second competing ectopic-cleaning algorithm. Callers should use NOOP's existing R-R integrity and cleaning path first, then pass only finite positive cleaned intervals.

Dirty input fails closed.

## Anchor selection

For each candidate interval `RR(i)` with preceding interval `RR(i-1)`:

```text
DC anchor: RR(i) > RR(i-1)
AC anchor: RR(i) < RR(i-1)
```

A directional change is rejected as an anchor when:

```text
abs(RR(i) / RR(i-1) - 1) > anchorRatioCap
```

The default cap is 5%, matching a common conventional PRSA/DC artifact-suppression criterion in the published literature. The cap is parameterized so future validation can compare variants without changing the API.

The rejected-large-change count is surfaced in the result rather than hidden.

## Phase-rectified profile

For each retained anchor, the engine extracts a symmetric profile window with offsets:

```text
-radius ... radius-1
```

and averages corresponding offsets across all anchors to produce `X(k)`.

The minimum radius is 2 because the conventional scale-2 Haar contrast requires `X(-2)`, `X(-1)`, `X(0)`, and `X(1)`.

## Capacity

Both DC and AC use the same central coefficient:

```text
capacity = [X(0) + X(1) - X(-1) - X(-2)] / 4
```

With deceleration anchors, ordinary clean data generally produce a positive DC. With acceleration anchors, ordinary clean data generally produce a negative AC. The engine does not force either sign and does not convert the value into a health category.

## Data sufficiency

The result exposes `anchorCount`. `minimumAnchors` is a caller-controlled gate and defaults to one only so the pure mathematical primitive remains testable and composable.

One anchor is **not** asserted to be a stable personal physiological estimate. Product or research integration should set an evidence-driven sufficiency rule for the actual recording duration, device, and cleaned-RR substrate.

## No mortality or risk tiers

Some PRSA/DC literature defines risk strata in post-myocardial-infarction ECG populations. Those thresholds are intentionally absent here.

This engine does not emit:

- high/intermediate/low mortality risk
- autonomic dysfunction labels
- cardiac diagnoses
- recovery/readiness penalties
- clinical alerts

A wearable PPG-derived PRSA value must not inherit those meanings by analogy.

## Cross-platform parity

Swift and Kotlin mirror:

- DC/AC directional anchor selection
- 5% default anchor cap
- rejected-large-change accounting
- radius/window behavior
- phase-aligned averaging
- scale-2 Haar coefficient
- minimum-anchor gating
- invalid-input behavior

Golden tests include:

- a linear increasing RR series with exact DC = +20 ms
- a linear decreasing RR series with exact AC = -20 ms
- opposite-kind no-anchor behavior
- >5% directional-jump rejection
- stricter custom anchor caps
- explicit minimum-anchor gating
- radius >2 preserving the same central Haar coefficient
- invalid/dirty cleaned-NN rejection

## Scientific provenance

Primary methods reviewed include Bauer et al. (Lancet, 2006) and Kantelhardt et al. (Chaos, 2007), which established deceleration capacity and PRSA for long-term ECG recordings. Later methodological descriptions confirm the conventional scale-2 central coefficient and the use of a 5% relative-change guard in common DC/AC implementations.

`OpenStrap/analytics@cef6fe4d11c4b4a15ae626350304e882882405e1` was reviewed as an MIT-licensed differential implementation reference. NOOP intentionally omits that project's clinical risk-tier output.

## Deliberate non-changes

This tranche does not:

- modify NOOP's RR cleaner
- replace RMSSD/SDNN/pNN50/frequency-domain HRV
- add clinical risk tiers
- add UI
- add persistence
- feed a score
- claim ECG equivalence

A future benchmark should compare PRSA stability across NOOP devices, cleaned-RR quality levels, real overnight records, and reference ECG before this metric is considered for a consumer-facing surface.
