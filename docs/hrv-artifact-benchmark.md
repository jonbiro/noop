# HRV artifact-cleaning differential benchmark

This tool exists to answer a narrow roadmap question before production code changes:

> Does a more elaborate R-R artifact classifier/corrector improve recovery of known HRV signals compared with NOOP's current range + Malik + gap-aware pipeline, without damaging clean physiological variability?

The answer must come from benchmark evidence, not from the fact that another project has a more sophisticated-looking algorithm.

## Compared paths

### Current NOOP

The benchmark calls the shipped `HRVAnalyzer.analyzeRaw(...)` path. It therefore measures the same physiological range filtering, local Malik-style rejection, minimum-beat gate, and gap-aware successive-difference handling used by current analytics.

### Candidate

`ArtifactCandidate` is **tool-only**. It is a NOOP-owned comparison implementation inspired by the Lipponen-Tarvainen beat-classification family and the MIT-licensed OpenStrap analytics reference pinned at:

`OpenStrap/analytics@cef6fe4d11c4b4a15ae626350304e882882405e1`

The candidate uses:

- dRR and local-median deviation streams;
- sliding signed quartile-deviation thresholds;
- normal / ectopic / long-short / missed / extra labels;
- compensatory recovery-beat reconciliation;
- interpolation only for an isolated artifact with usable anchors;
- **drop, never interpolate**, for multi-beat artifact runs.

It is not linked into StrandAnalytics, Readiness, Charge, imports, or any app target.

## Built-in scenarios

The default CLI creates a deterministic 300-beat respiratory-variability signal, then evaluates:

1. untouched clean variability;
2. isolated long interval;
3. isolated short interval;
4. gross high outlier;
5. a two-beat artifact run;
6. a moderate ectopic-like jump.

For every scenario the clean signal is known, so the report can calculate absolute RMSSD error rather than merely comparing two disagreeing algorithms with no ground truth.

The clean scenario is a mandatory negative control: a candidate that "improves" artifact cases by flattening ordinary respiratory variability is not acceptable.

## Output

`hrv-artifact-bench` emits Markdown by default or sorted JSON with `--json`.

Each result includes:

- truth RMSSD;
- shipped NOOP RMSSD;
- candidate RMSSD;
- absolute error for each path;
- candidate error improvement (positive means lower error);
- candidate clean fraction;
- corrected and dropped counts;
- per-class beat counts.

The report counts candidate-vs-NOOP wins descriptively. It does not declare a new production winner or statistical significance.

## Release gate for any future production proposal

This synthetic suite is necessary but not sufficient. Promotion of any candidate cleaner would still require:

- cross-platform Swift/Kotlin implementation and golden vectors;
- real R-R sequences with trustworthy beat order and coverage;
- multiple wearers/devices or a suitable public reference dataset;
- ECG/reference-device comparison where claims depend on true beat timing;
- separate evaluation of RMSSD, SDNN, pNN50, frequency-domain outputs, and downstream score effects;
- failure cases, especially high physiological RSA and rhythm irregularity;
- explicit handling of multi-beat gaps without silently bridging them;
- proof that improvements generalize outside the tuning scenarios.

Until those gates are met, the candidate stays under `Tools/`.

## Run

```bash
cd Tools/HRVArtifactBench
swift test
swift run hrv-artifact-bench
swift run hrv-artifact-bench --json
```

Swift Packages CI builds and tests the tool whenever its package or the shared workflow changes.
