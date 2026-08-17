# R-R corpus summary methodology

`rr-order-summary` turns schema-v2 `rr-order-corpus` JSONL into a deterministic, aggregate-only report suitable for review in an issue or pull request.

It is intentionally more than a mean-RMSSD calculator. The report is designed to answer whether an ordering problem is common, measurable, explainable by provenance, and large enough to affect NOOP's downstream HRV interpretation.

## Descriptive distributions

For continuous metrics the report uses R-7 quantiles, matching the common default in R and NumPy-style tooling:

- minimum;
- p10;
- p25;
- median;
- p75;
- p90;
- maximum;
- arithmetic mean;
- sample standard deviation when `n > 1`.

Paired current-minus-counterfactual deltas also report positive, negative, and zero counts.

## Integrity and flag prevalence

The summary counts all structural statuses and machine-readable audit flags. This allows a reviewer to distinguish, for example:

- an effect observed in fully known order;
- legacy order that cannot be reconstructed;
- duplicate batch-local order ambiguity;
- a production beat-gate failure;
- order-dependent cleaning;
- an internal raw-invariant failure.

Any raw-invariant failure should be treated as an analyzer bug and investigated before interpreting physiological deltas.

## Permutation severity

The summary aggregates pairwise R-R value inversions across trustworthy groups and reports:

- trustworthy groups compared;
- reordered groups and fraction;
- observed value inversions;
- possible unequal-valued inversions;
- aggregate normalized inversion fraction;
- per-session inversion-fraction distribution;
- largest trustworthy group and inversion count.

This is the exposure variable used for one of the effect-size association checks.

## Paired HRV effects

The report includes paired current-minus-magnitude-order effect distributions for:

- RMSSD (ms);
- SDNN (ms);
- mean NN (ms);
- pNN50 (percentage points);
- raw RMSSD (ms);
- raw pNN50 (percentage points).

RMSSD is the primary quantity because it is the stored HRV/recovery input, but the other metrics reveal whether the historical ordering changed only successive differences or also interacted with the local cleaning filter strongly enough to alter the surviving sample.

## Cleaning effects

For current and counterfactual order the summary describes:

- true cleaned-beat count;
- rejected fraction;
- contiguous successive-pair count;
- sessions below the production beat gate.

It also counts sessions where order changes the cleaned-beat count itself.

This is kept separate from structural order status. A session can have complete order and still contain a noisy R-R sequence, or ambiguous order with otherwise clean intervals.

## Deterministic bootstrap intervals

The report computes non-parametric 95% bootstrap intervals for:

- mean paired production RMSSD delta;
- median paired production RMSSD delta.

Resampling uses a fixed local LCG seed so the same corpus and iteration count produce identical output. This makes reports reviewable in version control and prevents random CI/report churn.

Default: 2,000 iterations.

```text
--bootstrap-iterations 0       disable
--bootstrap-iterations 10000   higher-resolution descriptive interval
```

The interval describes uncertainty for the observed corpus. It is not a clinical confidence interval and is not a formal hypothesis test.

## Effect associations

Two Spearman rank correlations are reported when at least three paired observations exist:

1. trustworthy multi-beat interval coverage vs absolute RMSSD delta;
2. normalized value-inversion fraction vs absolute RMSSD delta.

These are descriptive diagnostics, not causal claims. They help test whether the measured effect behaves like an ordering problem should behave. For example, a strong effect that has no relationship to any order/permutation property deserves additional investigation before attribution.

## Automatic strata

The summary creates aggregate strata by:

### Structural integrity

- complete;
- partial;
- ambiguous;
- no data.

### Trustworthy multi-beat coverage

- complete;
- 90–99%;
- 50–89%;
- below 50%;
- no multi-beat seconds.

### Session duration

- under 4 hours;
- 4–6 hours;
- 6–8 hours;
- 8+ hours.

### Sleep-staging density

- dense;
- sparse;
- unknown.

Each stratum reports session count, paired production RMSSD count, RMSSD delta distribution, trustworthy coverage, and inversion burden.

## Readiness HRV signal sensitivity

This analysis deliberately reproduces only the **HRV signal** used by `ReadinessEngine`.

For each pseudonymous device independently:

1. sort sessions chronologically;
2. use only prior current-order RMSSD values to build the baseline;
3. keep at most the trailing 30;
4. require at least 7 prior observations;
5. transform to lnRMSSD;
6. fold using `Baselines.readinessHRVLnCfg` with hard-outlier rejection disabled;
7. apply the same robust sigma transform (`1.253 × spread`);
8. classify current and counterfactual z with the same thresholds as Readiness:
   - good `>= +0.5`;
   - neutral `[-0.5, +0.5)`;
   - watch `[-1.0, -0.5)`;
   - bad `< -1.0`.

The report includes:

- evaluated nights;
- current/counterfactual z distributions;
- z delta;
- number of nights crossing an HRV-signal boundary;
- transition matrix such as `neutral->bad`.

This is not the full Readiness level because Readiness also considers resting HR, respiration, ACWR, and monotony.

## Charge HRV sensitivity envelope

`RecoveryScorer.recovery` is a weighted multi-driver score. A corpus record does not contain all historical non-HRV drivers, so the summary refuses to manufacture them.

Instead it answers a narrower causal-mechanics question:

> Holding every non-HRV driver at its personal baseline (`z = 0`), how much could the changed HRV input move the Charge logistic output under the current weight model?

The HRV z-score is built from prior current-order RMSSD using the raw `Baselines.hrvCfg` spine.

Two transparent normalization scenarios are reported:

- **minimum current HRV share:** every current optional driver is present. Current weights sum to 1.10, so HRV's 0.55 weight becomes a normalized share of 0.50.
- **maximum HRV share:** HRV is the only available driver, normalized share 1.0.

Both feed the exact public Charge logistic constants.

The resulting score-delta distributions are an **HRV contribution envelope**, not a recreation of historical Charge. Real Charge deltas depend on which other driver terms were present and their z-scores.

## Per-device summaries

The aggregate JSON includes pseudonymous per-device summaries so one prolific device cannot be mistaken for many independent devices. Each includes:

- session count;
- structural status counts;
- total intervals;
- paired RMSSD count;
- RMSSD delta distribution;
- interval-weighted trustworthy coverage.

Device keys are invocation-local and must not be linked across separately produced corpus files unless the contributor intentionally manages that linkage outside NOOP.

## Privacy guarantees

The summary data structure does not include:

- raw database device ID;
- detected/effective timestamp per session;
- observation key per session;
- raw R-R rows;
- interval sequences.

This remains true if the source JSONL was generated with `--include-device-id`.

## What should trigger follow-up

Potentially meaningful findings include:

- non-trivial paired RMSSD effect on a multi-device corpus;
- Readiness HRV signal transitions on otherwise usable nights;
- a Charge HRV contribution envelope large enough to change interpretation;
- effect concentrated in a specific integrity/coverage stratum;
- strong relationship between permutation burden and effect size;
- frequent order-dependent cleaning changes.

None of those automatically defines a production threshold. The next step would be a narrowly scoped policy proposal with explicit acceptance criteria and regression tests.
