# StrandAnalytics differential gap audit

Audit baseline: `ryanbr/noop@4e85a35f4a7ada3b5998cb7f683a380de3858900`

External comparison points pinned for this pass:

- `OpenStrap/analytics@cef6fe4d11c4b4a15ae626350304e882882405e1` (MIT)
- `satayutata/geniemax-core@476550124c9e3fa08de40dbc99b11db4bd3186eb` (MIT)

This is a differential audit, not a feature-count exercise. A capability is not labeled missing merely because another project has a file with a different name. Existing NOOP engines are the starting point and external implementations are used to identify concrete improvements, tests, or genuinely absent capabilities.

## Executive finding

NOOP already has a much broader analytics surface than a README-level comparison suggests. In particular, the current tree already contains recovery/Charge, Effort/strain, Readiness, robust baselines, ACWR, training monotony, time- and frequency-domain HRV, circadian analysis, stress, illness signals, correlations, dose-response analysis, source fusion/arbitration, heart-rate recovery, sleep staging, rhythm instrumentation, workout detection/classification, fitness age, vitality, and other longitudinal tooling.

The clearest high-value analytics gap found in this pass is the **long-horizon fitness-fatigue training-load state** usually expressed as:

- CTL: chronic training load / longer-horizon fitness proxy
- ATL: acute training load / shorter-horizon fatigue proxy
- TSB: training stress balance, `CTL - ATL`, a descriptive load-balance/form proxy

NOOP's existing ACWR and monotony answer related but different questions and should remain unchanged.

## Capability matrix

| Capability family | NOOP status at audit baseline | External differential | Recommendation |
|---|---|---|---|
| Daily strain / Effort | Existing: `StrainScorer.swift` | OpenStrap exposes TRIMP-based load options; NOOP already has its own transparent strain model | Retain NOOP. Do not relabel Effort as TRIMP. |
| Acute:chronic workload ratio | Existing in `ReadinessEngine.swift` and Android twin | OpenStrap also derives acute/chronic ratios | **Do not duplicate.** Audit definitions only if a product problem appears. |
| Training monotony | Existing in `ReadinessEngine.swift` and Android twin | Same general Foster-style family exists externally | **Do not duplicate.** |
| CTL / ATL / TSB | **Genuine gap found** | OpenStrap implements normalized 42d/7d EWMA with a first-week seed; GenieMax implements a zero-seeded impulse-state variant | Implement a NOOP-native normalized model with explicit seed, calendar-gap, and sufficiency semantics. This PR does so. |
| Recovery / readiness composites | Existing: `RecoveryScorer`, `ReadinessEngine`, `HRVReadiness`, Charge drivers | External projects have their own composites | Do not add another headline composite without a demonstrated user problem and benchmark advantage. |
| Time-domain HRV | Existing and actively hardened in `HRVAnalyzer.swift` | OpenStrap has additional artifact-correction/derived methods | Differential benchmark later. Fix input integrity before replacing cleaning. |
| Frequency-domain HRV | Existing: `HRVFreqDomain.swift` | OpenStrap provides overlapping spectral metrics | Not greenfield. First prove production reachability and compare exact methods/quality gates. |
| HRV readiness | Existing: `HRVReadiness.swift` plus Readiness HRV signal | External projects have lnRMSSD-style readiness methods | Not greenfield. Compare definitions before adding anything. |
| Stress index / daytime stress | Existing: `StressIndex.swift`, `DaytimeStress.swift`, `StressOnsetDetector.swift` | OpenStrap exposes overlapping autonomic/stress metrics | Not greenfield. Differential validation only. |
| Circadian analytics | Existing: `CircadianEngine.swift` | OpenStrap has non-parametric/cosinor-derived circadian metrics | Next differential audit candidate. Compare exact inputs and methods instead of adding a second circadian stack. |
| Illness / anomaly intelligence | Existing: `IllnessDistance.swift`, `IllnessSignalEngine.swift` | OpenStrap exposes CUSUM/change-point/anomaly families | Differential audit needed. Preserve descriptive, non-diagnostic language. |
| Correlations / behavior effects | Existing: `CorrelationEngine`, `BehaviorInsights`, `DoseResponseEngine`, `EffectRanker` | External projects provide related longitudinal analyses | Not greenfield. Audit sample-size, lag, multiple-comparison, and missing-answer semantics. |
| Source fusion / arbitration | Existing: `FusionResolver`, `FusionTypes`, `MetricArbitrationPolicy` | OpenStrap's metric envelope makes confidence/evidence more explicit | Extend existing NOOP source/confidence concepts instead of building a parallel data model. |
| Metric confidence / evidence | Partial but substantial: `ScoreConfidence`, `CaptureCompleteness`, fusion trust, metric arbitration, per-engine quality flags | OpenStrap has a useful generic `value + confidence + tier + inputs_used + note` pattern | High-value consolidation candidate after this PR. Reconcile existing structures first. |
| Heart-rate recovery | Existing: `HeartRateRecovery.swift` | Overlap externally | No new engine needed. |
| Rhythm analysis | Existing: `RhythmScreener.swift`, `RhythmExport.swift` | Some external projects expose more diagnostic-style verdicts | Retain NOOP's non-diagnostic boundary. |
| Sleep staging / architecture | Extensive existing stack: `SleepStager`, `SleepStagerV2`, stage totals, debt, edit guards, reclipping, wake-motion refinement | GenieMax/OpenStrap contain alternative heuristics and fixtures | Benchmark individual stages/priors. Do not wholesale replace NOOP sleep. |
| Workout detection / classification | Existing: `AutoWorkoutDetector`, `WorkoutDetector`, `WorkoutTypeClassifier` | External overlap | First resolve ownership/reachability of overlapping NOOP detectors. |
| Fitness age / vitality | Existing: `FitnessAgeEngine.swift`, `VitalityEngine.swift` | External overlap | Not greenfield. |
| Raw sensor-derived physiology | Depends on device/protocol capability | GenieMax and WHOOP research projects make additional WHOOP 5/MG claims | Keep in protocol/hardware roadmap. Do not manufacture analytics from unvalidated raw fields. |

## First implementation: `TrainingLoadEngine`

This branch adds a pure Swift/Kotlin engine for CTL, ATL, and TSB without changing the existing Readiness score.

### Why this model

OpenStrap and GenieMax both confirm the utility of a 42-day chronic / 7-day acute fitness-fatigue model, but they use materially different state definitions and initialization:

- OpenStrap uses normalized EWMA state and primes both states from the first seven days.
- GenieMax starts an impulse-state recurrence from zero, which yields a different scale from the daily input.

NOOP's implementation is intentionally explicit instead of silently inheriting either project:

```text
alpha = 1 - exp(-1 / tauDays)
state[t] = state[t-1] + alpha * (load[t] - state[t-1])
CTL tau = 42 days
ATL tau = 7 days
TSB = CTL - ATL
```

The first seven contiguous observed loads seed both states using their mean. This keeps CTL/ATL in the same units as the supplied load and avoids the artificial early low bias of zero initialization.

### Data sufficiency and calendar semantics

The engine deliberately distinguishes:

- **0 load:** an observed rest day; included in the model.
- **missing load:** no trustworthy observation; breaks the contiguous history.
- **missing calendar day:** breaks the contiguous history rather than compressing time.

Default states:

- fewer than 14 contiguous observed days: `unavailable`
- 14 to 41 days: `building`
- 42+ days: `established`

No injury-risk interpretation is attached to CTL, ATL, TSB, ACWR, or monotony. They are descriptive training-load signals.

### Why it does not alter Readiness

TSB is not automatically a recovery score. A negative TSB means short-horizon load is above long-horizon load under this model; it does not prove that a user is physiologically unrecovered. NOOP already has direct recovery/readiness inputs for that purpose.

The first PR therefore supplies chart-ready deterministic training-load state and cross-platform parity without creating a new hidden penalty in Readiness.

## Prioritized next analytics work

### 1. Metric evidence / absence consolidation

Map `ScoreConfidence`, `CaptureCompleteness`, HRV integrity, fusion trust, source arbitration, experimental capability states, and existing unavailable reasons into a coherent common semantic model. The useful external idea is not a new score; it is consistent provenance such as:

```text
value
source
confidence
coverage
quality flags
missing / withheld reason
inputs used
algorithm version
```

Avoid a giant generic persistence migration until the minimum common contract is known.

### 2. Advanced HRV differential benchmark

Compare NOOP's current range + Malik + gap-aware pipeline against well-supported external techniques such as stronger artifact correction and additional HRV descriptors. Frequency-domain HRV already exists, so this should be a quality/validation project, not a new `HRVFreqDomain2`.

Required before adoption:

- trustworthy R-R ordering and coverage
- multiple signal patterns / holdouts
- Swift/Kotlin parity
- failure cases
- proof that cleaning changes improve reference agreement rather than merely making numbers look plausible

### 3. Circadian method differential

Compare current `CircadianEngine` against external non-parametric and cosinor methods. First verify that each production caller supplies the domain the engine documents. Add only metrics that provide distinct value and have a defensible input substrate.

### 4. Longitudinal anomaly / change-point differential

Compare existing illness-distance/signal and behavior engines against external CUSUM/change-point/Mahalanobis-style methods. Keep outputs descriptive and avoid condition prediction or causal language unsupported by wearable data.

### 5. Sleep benchmark improvements

Use external fixtures and individual algorithmic ideas to challenge NOOP's existing sleep pipeline. Changes should be accepted only through the existing sleep benchmark/release-gate process and should cover short/long nights, naps, fragmented nights, sparse motion, and holdouts.

## Explicit non-goals of this audit

- Import every external formula.
- Create duplicate engines for features already present under different names.
- Change headline Recovery, Readiness, Effort, or Rest scores as a side effect of adding descriptive analytics.
- Turn training-load ratios into injury-risk or medical claims.
- Treat README feature claims as stronger evidence than code, tests, and production callers.
- Mix WHOOP 5/MG protocol research into a pure analytics PR.

This document should be refreshed against the current upstream SHA before each subsequent analytics tranche because NOOP is moving quickly.
