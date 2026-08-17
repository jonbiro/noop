# Primary-sleep vs wake heart-rate contrast

`SleepHeartRateContrast` is a small descriptive analytics primitive that compares heart rate during an explicitly supplied wake window with heart rate during an explicitly supplied primary-sleep window.

It is intentionally **not** another resting-heart-rate definition and does not change NOOP's shipped RHR, primary-session RHR shadow metric, recovery, strain, workout detection, energy, or any headline score.

## Why this is separate from RHR

NOOP already has active upstream work around the definition of nightly resting HR:

- the shipped value remains a low sustained sleep-HR floor used by existing scores;
- #1174 added a pure primary-session arithmetic-mean RHR candidate;
- #1188 began collecting that primary-session mean as `rhr_primary_session` for validation while leaving the shipped floor as the sole scoring input;
- #1169 remains the validation anchor before any display or score re-baselining.

The same #1169 evaluation explicitly considered a lowest-30-minute RHR window and found it less promising than primary-session mean HR. This tranche therefore does **not** introduce a third RHR candidate.

The new metric answers a different question: how different is HR in the caller's primary-sleep window from HR in the caller's wake window?

## Inputs

The engine accepts two fixed-grid sequences:

```text
wakeHR
primarySleepHR
```

Each element represents an expected equal-duration epoch:

```text
valid bpm        observed HR
nil / null       unobserved epoch
out-of-range HR  invalid for this metric
```

The validity range is 30...220 bpm inclusive, matching the pure primary-session RHR candidate's worn-HR range.

The engine deliberately does not infer which periods are wake, daytime, night, or primary sleep. Window selection belongs to the caller, where detected sessions, explicit local-time semantics, and source provenance are available.

That avoids a hidden assumption that "night" always means sleep or that "day" always means wake, which is especially important for shift workers and irregular schedules.

## Fixed-grid requirement

Means are unweighted arithmetic means across valid epochs. That has a clean time interpretation only when each expected epoch represents the same duration.

Callers with irregular raw observations should first aggregate onto an explicitly declared fixed cadence and represent missing epochs as `nil` / `null`. They should retain the cadence and source provenance outside this pure engine.

This design also makes the reported coverage meaningful:

```text
coverage = valid epochs / expected epochs in that window
```

rather than pretending raw sample count alone is a time-coverage estimate.

## Outputs

For valid wake mean `W` and primary-sleep mean `S`:

```text
sleepMinusWakeBpm = S - W
sleepReductionPercent = 100 * (W - S) / W
```

Interpretation is deliberately directional only:

- positive `sleepReductionPercent`: mean HR was lower in the supplied primary-sleep window;
- zero: supplied window means were equal;
- negative: mean HR was higher in the supplied primary-sleep window.

The result also carries:

- wake mean bpm
- primary-sleep mean bpm
- valid sample count for each window
- expected sample count for each window
- fixed-grid coverage for each window

## Minimum valid samples

The default gate requires 30 valid epochs in each window. This mirrors the provisional 30-valid-sample floor used by NOOP's primary-session mean RHR experiment so the new primitive does not invent a second arbitrary default.

The threshold is parameterized because 30 samples is not claimed to be a clinically validated coverage rule. In particular, the elapsed duration represented by 30 epochs depends on the caller's fixed cadence. Product integration should consider both coverage fraction and represented duration before surfacing a result.

## No medical dipping classification

This primitive does not emit:

- dipper / non-dipper / reverse-dipper / riser labels
- cardiovascular-risk categories
- autonomic dysfunction claims
- diagnostic thresholds

Those labels are frequently associated with blood-pressure dipping literature and should not be transferred to wearable HR contrast by analogy.

The raw descriptive values are useful without attaching a medical interpretation that the current evidence does not justify.

## Cross-platform parity

Swift and Kotlin mirror:

- 30...220 bpm validity range
- fixed-grid missingness
- arithmetic means
- independent sample gates for wake and sleep
- per-window coverage
- signed bpm change
- percentage reduction formula
- invalid-configuration behavior

Golden tests cover:

- lower sleep HR producing positive reduction
- higher sleep HR producing negative reduction without classification
- missing and invalid epochs reducing coverage
- inclusive validity-range edges
- independent minimum-valid-sample gates
- empty/invalid configuration
- unequal wake/sleep window lengths with independent coverage

## External-project relationship

OpenStrap Analytics includes nocturnal RHR and day/night HR-dip concepts. NOOP already has substantially more nuanced RHR-definition work upstream, so only the genuinely distinct contrast concept is carried forward here.

The implementation is NOOP-native and intentionally uses primary-sleep versus wake terminology rather than nocturnal versus daytime terminology.

## Deliberate non-changes

This tranche does not:

- change the shipped RHR floor
- change `rhr_primary_session`
- add a 30-minute RHR candidate
- choose the primary sleep session
- infer wake periods
- alter recovery or any other score
- persist a new database field
- add UI
- classify the result medically

A later integration PR can use the existing primary-session selection plus a clearly defined wake window, then pair this result with NOOP's metric-availability/provenance concepts before surfacing it.
