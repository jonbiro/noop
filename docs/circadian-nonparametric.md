# Nonparametric circadian rhythm analytics

`NonparametricCircadianEngine` adds the standard nonparametric rest-activity rhythm family as a pure, deterministic Swift/Kotlin primitive.

It is additive. It does not replace `CircadianEngine`, change sleep staging, change Vitality, change Readiness, or alter any headline score.

## Why this is different from existing NOOP analytics

NOOP's existing circadian engine fits a parametric 24-hour cosinor and uses that fit for a body-clock phase estimate and timing guidance. The new engine asks a different set of questions without assuming that the daily waveform is sinusoidal:

- How strongly does the signal repeat at the same time of day?
- How fragmented is the signal within the day?
- What is the strongest contiguous 10-hour portion of the average day?
- What is the weakest contiguous 5-hour portion?
- How large is the contrast between those active and inactive windows?

Those are complementary descriptors rather than alternative implementations of the existing cosinor.

## Metrics

For a complete fixed-grid series `x` with `n` total epochs and `p` epochs per day:

### Interdaily Stability (IS)

```text
IS = n * sum_h(mean_h - grand_mean)^2
     / (p * sum_i(x_i - grand_mean)^2)
```

`mean_h` is the mean at epoch-of-day slot `h` across days. A perfectly repeated daily profile evaluates to 1. Lower values indicate weaker coupling to time of day.

### Intradaily Variability (IV)

```text
IV = n * sum_i(x_i - x_i-1)^2
     / ((n - 1) * sum_i(x_i - grand_mean)^2)
```

Lower values describe smoother rhythms; higher values describe more rapid alternation/fragmentation. The engine does not clamp the upper bound because IV can exceed 2 for strongly alternating or non-Gaussian sequences.

### M10 and L5

The engine first builds the average daily profile, then searches it circularly:

- `M10`: highest mean over any contiguous 10-hour window
- `L5`: lowest mean over any contiguous 5-hour window

Circular search matters because a valid window can cross midnight. The result includes both start epoch and start local-clock hour.

### Relative Amplitude (RA)

```text
RA = (M10 - L5) / (M10 + L5)
```

For the nonnegative substrates accepted by this engine, RA is constrained to 0...1.

## Strict observation contract

The reference formulas assume a fixed regularly sampled grid. The first NOOP implementation therefore fails closed instead of silently inventing a missing-data variant.

Requirements:

- at least 2 complete nominal 24-hour days
- total epoch count must be an exact multiple of `epochsPerDay`
- `epochsPerDay` must be divisible by 24 so 5-hour and 10-hour windows contain exact integer epoch counts
- every epoch must be observed
- every value must be finite and nonnegative
- total signal variance must be nonzero

`nil` / `null` means missing and causes no result. It is never imputed as zero, local mean, previous value, sleep, or wake.

### DST and local-clock grids

A daylight-saving transition can create a 23-hour or 25-hour local calendar day. This engine does not silently squeeze or stretch such a day. The caller must normalize observations onto an explicitly declared nominal 24-hour grid and retain the provenance of that normalization.

That keeps the analytics layer deterministic and prevents the same raw data from receiving different results merely because one platform handled a DST boundary differently.

## Observation count, not an invented maturity tier

The formulas are mathematically defined once the engine has at least two complete days, but the amount of history appropriate for a product interpretation depends on substrate, use case, missingness policy, and validation target.

The result therefore reports only `daysObserved`. It does **not** label an arbitrary number of days as "established" or convert history length into a confidence tier. A future consumer must choose and justify any stricter history requirement in its own evidence contract.

## Signal substrate

The classic nonparametric circadian literature is primarily built around actigraphy/rest-activity signals. The formulas themselves are generic numerical descriptors and can be applied to another nonnegative rhythm signal such as heart rate, but that does not make the evidence base interchangeable.

A future product surface must preserve the substrate identity. If NOOP computes these descriptors from heart rate because motion data are unavailable or sparse, it should say so rather than label the result as an actigraphy-derived metric.

The pure engine intentionally accepts only the numerical signal. Source/provenance belongs to the caller and NOOP's existing source/arbitration layer.

## Cross-platform parity

Swift and Kotlin mirror:

- data gates
- fixed-grid interpretation
- IS formula
- IV formula
- average-day construction
- circular M10/L5 search
- deterministic tie-breaking
- RA calculation
- start-epoch and start-hour conversion
- 2-day mathematical minimum
- raw `daysObserved` reporting without a maturity label

Golden tests include:

- a perfectly repeated two-day step rhythm with IS = 1
- an exact IV value for that step rhythm
- M10 = 10, L5 = 0, RA = 1 on the known step profile
- M10 crossing midnight
- 15-minute epoch grids with exact 5-hour/10-hour windows
- raw history-count reporting
- one-day and partial-day rejection
- invalid epoch grids
- missing, non-finite, negative, and constant-signal rejection

## Scientific provenance

The implementation follows the standard nonparametric rest-activity analysis family described in the actigraphy/circadian literature, including interdaily stability, intradaily variability, L5, M10, and relative amplitude. The nparACT methodology and related validation literature were used to verify formula and interpretation details.

`OpenStrap/analytics@cef6fe4d11c4b4a15ae626350304e882882405e1` was reviewed as an MIT-licensed differential implementation reference. NOOP's observation gates are intentionally stricter: the sibling implementation permits one full day, while this engine requires at least two because interdaily stability is specifically a between-day regularity construct.

## Deliberate non-changes

This tranche does not:

- change `CircadianEngine`
- change Vitality's existing sleep-duration consistency factor
- change Readiness, Charge, Effort, or Rest
- substitute IS for SRI
- infer sleep/wake state
- interpolate missing epochs
- normalize DST days automatically
- claim HR-derived metrics are actigraphy-equivalent
- invent a data-maturity/confidence tier
- persist new database fields
- add UI

A later integration PR should identify the best fixed-grid substrate available on each supported device, carry explicit source/provenance, and surface data availability/history directly rather than quietly substituting these metrics into an existing score.
