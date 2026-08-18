# Paced-breathing spectral concentration

`PacedBreathingSpectrum` adds a transparent biofeedback primitive for NOOP's guided-breathing workflow.

It intentionally does **not** expose a branded "cardiac coherence" score. Instead it reports the directly inspectable spectral quantities underneath the useful part of that idea: whether cleaned RR/PRV during a breathing session is dominated by one oscillation in the paced-breathing range, where that peak sits, and how closely it matches an optional target breathing rate.

No existing score, stress metric, recovery/readiness metric, sleep metric, or breath-pacer behavior changes.

## Why this framing

OpenStrap Analytics includes a real-time cardiac-coherence feature that searches the RR spectrum for a dominant 0.04...0.26 Hz peak and computes a narrow-peak-power ratio. It then maps that ratio onto its own 0...100 display score.

The potentially useful feature for NOOP is the spectral biofeedback itself, not a proprietary-sounding wellness construct or an arbitrary display transform.

This implementation therefore exposes:

- dominant peak frequency in Hz
- equivalent breaths/minute
- spectral power in a narrow band around the peak
- total analyzed band power
- peak-power fraction
- peak-to-remainder ratio when defined
- optional target breathing rate
- absolute target/peak error in breaths/minute
- RR span and beat count

There is no 0...100 "coherence" score.

## Input contract

The engine accepts an **already-cleaned NN/RR series in milliseconds**.

Requirements:

- at least 50 cleaned intervals
- at least 60 seconds of represented span
- every interval finite and within 300...2000 ms
- nonzero RR variance

The engine does not introduce another artifact cleaner. Callers should use NOOP's existing RR integrity/cleaning path first.

Because wrist wearables can provide pulse-derived beat intervals, this is best described as a PRV/RR spectral biofeedback estimate unless the source is known to be ECG.

## Tachogram and spectrum

Beat time is reconstructed from cumulative cleaned RR duration, producing the naturally uneven tachogram. Each RR value is positioned at its interval start time; the reported `spanSeconds` and the finite-recording resolution floor use the **full represented duration**, equal to the sum of all supplied cleaned intervals, including the final RR interval.

The RR series is mean-centered and analyzed with the same basic normalized Lomb-Scargle approach used elsewhere in StrandAnalytics, avoiding a mandatory interpolation step onto a uniform grid.

The frequency bands are deliberately simple:

```text
peak search:    0.04 ... 0.26 Hz
analyzed band:  max(0.04, 1/span) ... 0.40 Hz
peak window:    peak +/- 0.015 Hz
frequency step: 0.002 Hz
```

The lower analysis edge respects the finite recording span instead of pretending a short guided session can resolve arbitrarily slow oscillations.

## Transparent concentration metrics

```text
peakPowerFraction = peakBandPower / totalBandPower

peakToRemainderRatio = peakBandPower / (totalBandPower - peakBandPower)
```

`peakPowerFraction` is bounded 0...1 and is the easiest direct description of spectral concentration.

The ratio is left unbounded and is returned only when the remaining band power is greater than zero. A degenerate all-peak spectrum is not converted into a sentinel such as 999 or infinity.

Neither quantity is assigned a universal "good" or "bad" threshold in this engine.

## Guided pace

An optional `targetBreathsPerMinute` is context only. It does not constrain the peak search and cannot change the spectral result.

When supplied:

```text
peakBreathsPerMinute = peakHz * 60
paceErrorBreathsPerMinute = abs(peakBreathsPerMinute - target)
```

The pure analytics engine deliberately does not turn that error into a pass/fail or on-pace label. UI can communicate the continuous error directly.

## Cross-platform parity

Swift and Kotlin mirror:

- RR validity gates
- cumulative tachogram construction
- full represented-span accounting
- mean removal and variance
- Lomb-Scargle power
- frequency grid
- dominant-peak selection
- trapezoidal band integration
- peak fraction and ratio
- optional target handling
- failure behavior

Golden tests generate deterministic synthetic RR signals and verify:

- a 0.10 Hz rhythm is recovered near 0.10 Hz / 6 breaths per minute
- reported span equals the sum of all cleaned RR intervals
- target context does not move or reshape the spectrum
- a two-frequency RR signal is less concentrated than a single-frequency signal
- off-pace target error is a direct absolute difference
- short, constant, dirty, out-of-range, and invalid-target inputs fail closed

## Relationship to NOOP's breath pacer

NOOP already has breathing-pacing infrastructure. This primitive is designed to complement it later by answering a feedback question the pacer itself cannot: did the wearer's cleaned RR/PRV become concentrated around a breathing-range oscillation during the session?

A future integration can pair the pacer's declared target rate with this engine's measured peak and concentration without coupling the analytics primitive to UI or session orchestration.

## Deliberate non-changes

This tranche does not:

- modify the breath pacer
- add an emotional-state score
- add a proprietary HeartMath-equivalent score
- diagnose autonomic dysfunction
- change stress/recovery/readiness
- persist a new database field
- add UI
- claim ECG-HRV equivalence for PPG PRV

The first consumer-facing integration should retain RR source/provenance and make recording span/data quality visible rather than presenting the concentration number as a universal health score.
