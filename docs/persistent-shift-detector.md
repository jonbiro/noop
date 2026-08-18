# Persistent personal-baseline shift detection

`PersistentShiftDetector` adds a generic one-sided longitudinal CUSUM primitive. It detects persistence across observations instead of creating another one-night anomaly score.

It is domain-neutral. The engine never calls a shift illness, infection, stress, overtraining, or any other cause. A caller chooses whether an upper or lower shift matters for its metric and combines the result with the domain's existing context.

## Why this is additive to NOOP

NOOP already has strong point-in-time and multivariate anomaly tools, including `IllnessSignalEngine` and `IllnessDistance`. Those answer questions such as "are several signals unusual tonight?" and "how far is this multivariate observation from a personal baseline?"

A cumulative shift detector answers a different question: has a modest or strong deviation persisted enough across observations that the accumulated evidence is no longer a single-night excursion?

That temporal state can later be combined with NOOP's existing confounder-aware illness logic rather than replacing it.

## Personalized trailing baseline

For each observed point, the detector builds a trailing baseline from prior **observed** values only, up to `baselineWindow` positions (default 28).

The default minimum is 7 valid prior observations. Before then, an observed point is `calibrating`.

`nil` / `null` is an explicitly missing observation. A missing point is emitted as `missing` and neither advances nor resets the CUSUM, alert run, or recovery run.

Non-nil non-finite values fail the whole evaluation rather than being silently converted into missing data.

## Robust standardization

Baseline location is the median.

Scale is:

```text
normalized_scale = 1.4826022185 * MAD
```

The 1.4826 factor makes MAD approximately standard-deviation-equivalent under a normal distribution. This is intentional: the oriented deviation exposed as `orientedZ` should have a clear standard-deviation-like scale rather than being divided by raw MAD.

If MAD is exactly zero, the detector falls back to sample SD so a quantized-but-not-constant baseline can still be evaluated. If both robust scale and SD are zero, the point is `degenerateBaseline`; no magic 1-unit floor is invented and no CUSUM is accumulated.

## Direction

The same engine handles metrics where concern/interest is an increase or a decrease:

```text
upper: orientedZ = (x - baselineMedian) / baselineScale
lower: orientedZ = -(x - baselineMedian) / baselineScale
```

Positive `orientedZ` therefore always means movement in the requested shift direction.

Examples of possible future callers, without implying any product decision:

- RHR: upper
- respiration: upper
- HRV: lower
- sleep duration: lower or upper depending on the question

## One-sided CUSUM

The state accumulator is a transparent Page-style one-sided CUSUM:

```text
C[t] = max(0, C[t-1] + orientedZ[t] - k)
```

Defaults:

```text
reference k = 0.5
threshold h = 4.0
```

These are configurable engineering defaults, not universal clinical cutoffs. A production caller should validate/calibrate thresholds for its metric, cadence, device, and desired false-positive behavior.

When `C > h`, the point enters `watch`. After `persistObservations` consecutive evaluated threshold crossings (default 2), it becomes `sustained`.

## Recovery

A shift should not remain latched indefinitely after the underlying metric returns near personal baseline.

When `orientedZ < recoveryZ` (default 0.5) for `recoveryObservations` consecutive **observed/evaluable** points (default 2), the accumulator and alert run reset to zero.

Missing, calibrating, and degenerate-baseline points do not count toward recovery.

## Output states

```text
missing
calibrating
degenerateBaseline
normal
watch
sustained
```

Each evaluated point also exposes:

- index
- oriented z
- CUSUM
- trailing baseline median
- baseline scale
- valid baseline count
- observed flag

This is enough for future diagnostics, Local Access, export, or UI to explain the state without reconstructing the detector.

## Relationship to wearable illness-alert literature

Wearable studies have used personalized sliding baselines and cumulative-deviation methods to detect persistent physiological shifts. Those studies also show that alerts can be triggered by non-illness causes such as stress, alcohol, travel, exercise, vaccination, and other physiological changes.

For that reason this engine is intentionally a **shift detector**, not an illness detector. If used by `IllnessSignalEngine` in the future, its temporal evidence should remain subject to the existing corroboration and confounder logic.

`OpenStrap/analytics@cef6fe4d11c4b4a15ae626350304e882882405e1` was reviewed as a differential implementation reference. This implementation differs materially by using normalized MAD, supporting upper and lower shifts generically, exposing missing/calibrating/degenerate states explicitly, and omitting illness-specific green/yellow/red semantics.

## Cross-platform parity

Swift and Kotlin mirror:

- trailing valid-value baseline construction
- normalized-MAD and sample-SD fallback
- upper/lower orientation
- CUSUM recurrence
- watch/sustained persistence
- recovery reset
- missing-state preservation
- degenerate-baseline abstention
- configuration validation

Golden tests cover:

- upper shift progressing normal -> watch -> sustained
- two-observation recovery reset
- lower shifts oriented positive
- a missing point preserving an in-progress shift
- degenerate constant baselines
- zero-MAD/nonconstant SD fallback
- valid baseline counts with missing history
- configurable sensitivity
- invalid configuration and non-finite input

## Deliberate non-changes

This tranche does not:

- change `IllnessSignalEngine`
- change `IllnessDistance`
- send notifications
- name a disease or cause
- create a health-risk tier
- persist detector state
- feed Readiness/Charge/Effort/Rest
- add UI

A future integration should first choose a metric and desired false-positive rate, validate the detector against real longitudinal data, and only then combine it with NOOP's existing availability, provenance, and confounder-aware semantics.
