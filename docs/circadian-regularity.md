# Circadian regularity and social-clock analytics

This tranche adds `CircadianRegularityEngine` as an additive analytics primitive. It does not replace `CircadianEngine`, change Vitality, change Readiness, or alter any headline score.

## Why this is a real gap

Current NOOP already has a capable circadian phase engine with a generalized cosinor fit and a light/sleep timing planner. Vitality also has a simple sleep-consistency factor based on the coefficient of variation of sleep duration.

That duration-CV factor is useful as a transparent first-order proxy, but it is not the same quantity as day-to-day sleep/wake regularity. This tranche therefore adds metrics with different information content rather than duplicating existing analytics.

## 1. Sleep Regularity Index

`CircadianRegularityEngine.sleepRegularityIndex(...)` implements the Phillips-style Sleep Regularity Index over an epoch-aligned sleep/wake series.

For a 24-hour lag:

```text
agreement = matching comparable sleep/wake pairs / comparable pairs
SRI = -100 + 200 * agreement
```

This scaling is important. Perfect day-to-day state agreement is 100. Chance-level agreement for a random schedule is 0. The theoretical lower bound is -100 for complete state reversal.

### Missing data

The engine accepts three states per epoch:

```text
asleep
awake
unobserved
```

An unobserved epoch is never treated as awake. A pair contributes only when both endpoints are observed. The result therefore exposes:

- `comparablePairs`
- `possiblePairs`
- `coverage = comparablePairs / possiblePairs`
- `matchingPairs`
- `spanDays`

Coverage is a data-completeness quantity, not physiological confidence.

The current primitive returns no result when the grid is invalid, the record is not longer than the requested lag, or no pair is actually comparable. It does not invent a minimum-quality threshold. A later product surface can combine `coverage` and observation span with NOOP's availability/confidence semantics.

## 2. Social jetlag

`socialJetLag(...)` computes the signed shortest circular difference between representative free-day and work-day mid-sleep:

```text
signed social jetlag = MSF - MSW on the shortest 24 h arc
absolute social jetlag = abs(signed social jetlag)
```

Positive means the free-day midpoint runs later. The result is constrained to the shortest arc, so its absolute magnitude cannot exceed 12 hours.

Clock time is circular. The engine therefore summarizes each side using a circular median: samples are unwrapped around their circular mean, medianed on that local axis, then wrapped back to `[0, 24)`. This correctly handles schedules that straddle midnight.

The engine fails closed when either side has too few observations, contains non-finite values, or has no meaningful circular direction.

### Product rule: do not equate weekend with free day

A Saturday or Sunday is not necessarily a free day, and a weekday is not necessarily a work day. Shift workers, part-time workers, caregivers, students, and people with nonstandard schedules make that shortcut wrong.

Before surfacing this metric, the app should obtain work/free classification from an explicit schedule, journal, calendar-derived classification with user review, or another source whose meaning is clear. The analytics engine deliberately takes already-classified observations and does not guess.

## 3. Sleep-debt-corrected free-day midpoint

`correctedFreeDayMidSleep(...)` provides the timing substrate used by MCTQ sleep-corrected mid-sleep on free days.

The engine uses:

- circular-median free-day mid-sleep
- median free-day sleep duration
- average workday sleep duration
- average weekly sleep duration

The standard correction rule is conditional:

```text
if free-day sleep duration <= workday sleep duration:
    corrected midpoint = free-day midpoint
else:
    correction = (free-day sleep duration - average weekly sleep duration) / 2
    corrected midpoint = free-day midpoint - correction
```

The output exposes the uncorrected midpoint, corrected midpoint, durations used, correction magnitude, and free-day observation count.

### This is not automatically a chronotype diagnosis

The MCTQ interpretation of sleep-corrected free-day mid-sleep as a chronotype proxy assumes free-day sleep timing is sufficiently unconstrained. In particular, standard MCTQ guidance does not chronotype a person from MSFsc when free-day waking is alarm-constrained.

Wearable timing alone cannot reliably infer that condition. For that reason this engine returns a transparent corrected timing value and deliberately does not assign an early/intermediate/late chronotype label.

## Cross-platform contract

Swift and Kotlin mirror:

- SRI scaling and pair accounting
- missing-epoch semantics
- clock wrapping
- circular mean/median behavior
- shortest-arc sign convention
- minimum work/free sample counts
- MSFsc correction condition
- invalid-input behavior

Golden tests include:

- perfect repeated-day SRI = 100
- complete state reversal SRI = -100
- 50 percent agreement SRI = 0
- missing epochs reducing coverage without becoming wake
- midnight wraparound
- positive and negative social jetlag
- antipodal/undefined circular schedules
- oversleep correction
- no correction when free-day sleep does not exceed workday sleep
- invalid/malformed duration inputs

## Scientific provenance

The formulas are independently implemented from published definitions, with external open-source projects used as comparative references rather than copied as production code.

Primary/reference methods reviewed for this tranche:

- Phillips et al., Scientific Reports (2017), introduction of the Sleep Regularity Index.
- Lunsford-Avery et al., Scientific Reports (2018), explicit SRI equation and external validation.
- Wittmann et al. / Roenneberg framework for social jetlag as the work-free versus workday mid-sleep difference.
- Munich ChronoType Questionnaire guidance for MSFsc and its sleep-debt correction.
- `OpenStrap/analytics@cef6fe4d11c4b4a15ae626350304e882882405e1`, MIT, used as a differential implementation reference.

One useful result of verifying the primary methods was catching two tempting but incorrect simplifications before merge: unscaled agreement is not the published SRI, and the MSFsc oversleep correction is not applied merely because free-day sleep exceeds the weekly average.

## Deliberate non-changes

This tranche does not:

- replace the existing Vitality sleep-duration consistency proxy
- change any existing score
- automatically infer work days or free days
- label a user with a chronotype
- infer alarm use
- claim circadian phase from sleep timing alone
- persist new database fields
- change sleep staging
- alter `CircadianEngine`

A later integration PR should first identify the trustworthy source for epoch sleep/wake state and work/free-day classification, then expose these analytics with explicit coverage and availability rather than quietly substituting them into an existing score.
