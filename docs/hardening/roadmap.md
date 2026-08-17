# Evidence-driven hardening roadmap

This roadmap is ordered by dependency and evidentiary value, not feature visibility. Every implementation item should be a small PR with its own validation record.

## Tranche 0 — governance that can fail closed

**Status: implemented on `agent/evidence-hardening`.**

Deliverables:

- immutable external-source lock;
- machine-enforced licensing/provenance policy;
- source-lock unit tests;
- production reachability matrix;
- integrity-blocker register;
- active-fork/Rust-core differential rules;
- item-level provenance ledger;
- contributor/agent instructions;
- CI validation of the source lock.

Acceptance:

- all source records use 40-character SHAs and SHA permalinks;
- unlicensed sources cannot be marked copyable;
- decompiled-origin sources cannot be marked anything except clean-room-only;
- moving refs are not accepted as evidence pins;
- future external work has an explicit place to record provenance.

This tranche intentionally changes no biometric formula and sends no BLE command.

## Tranche 1 — quantify R-R integrity after the structural ordering fix

Upstream context: #823 and the already-landed emission-order migration.

Goal: measure what is still unknown rather than reopening the old fix.

Work:

1. add a diagnostic that reports, per analyzed HRV window:
   - total R-R intervals;
   - percentage with known emission order;
   - percentage from legacy rows;
   - number of same-second multi-beat groups;
   - groups whose stored order differs from magnitude order;
   - groups that appear split across separate live flushes if detectable;
2. build a corpus experiment comparing nightly RMSSD/SDNN using:
   - recorded emission order where known;
   - historical deterministic fallback;
   - former magnitude-order behavior as an offline counterfactual only;
3. run on multiple nights and, where available, more than one wearer/device;
4. produce Swift/Kotlin golden vectors for the ordering semantics;
5. surface a quality/withheld reason if a window's ordering provenance is too weak for a claimed downstream use.

Do not change headline HRV again unless this measurement shows a remaining material bias with a repairable cause.

Acceptance:

- quantified full-night effect, not only synthetic five-beat examples;
- legacy behavior documented;
- no data-loss migration;
- platform-identical ordering semantics;
- downstream Charge/Readiness impact measured.

## Tranche 2 — complete the production reachability audit

Goal: find value already implemented in NOOP that is unreachable, recomputed inconsistently, stale, or platform-skewed.

Start with:

- Charge / recovery;
- Effort / strain;
- Readiness;
- HRV frequency domain;
- Circadian/body clock;
- illness signal;
- fusion/arbitration;
- workout detector/classifier overlap;
- rhythm instrumentation;
- local MCP access.

For each row in `reachability-matrix.csv`, replace `audit-needed` with exact symbols for:

```text
caller -> input read -> engine -> result mapping -> persistence -> rescore -> UI -> export/MCP
```

Prioritize fixes in this order:

1. output already computed but discarded;
2. engine exists but has no production caller;
3. platform twin missing;
4. result persisted but never recalculated;
5. view recomputes a weaker approximation;
6. duplicate engine whose production ownership is unclear.

Acceptance:

- no “shipped” classification without an actual production caller;
- no duplicate replacement before identifying current ownership;
- exact Apple and Android paths recorded;
- stale-day/source behavior tested.

## Tranche 3 — confidence, provenance, and machine-readable absence

Goal: evolve existing NOOP confidence semantics rather than bolt on a parallel system.

Compare existing:

- `ScoreConfidence`;
- capture completeness;
- HRV quality/integrity states;
- fusion trust and arbitration;
- sleep confidence;
- experimental capability labels;

against useful OpenStrap concepts:

- evidence tier;
- `inputs_used`;
- ranked drivers;
- exact insufficient-baseline reason;
- zero confidence for absent results.

Prefer small domain-specific additions over a giant generic persistence migration.

Candidate absence reasons:

```text
need_baseline:have=5,need=14
insufficient_rr_coverage:have=0.42,need=0.80
unsupported_source:whoop4_spo2
withheld_quality:rr_order_unknown
experimental_unvalidated:spo2_candidate_82
```

Acceptance:

- no nonzero confidence on absent data;
- Swift/Kotlin semantics match;
- `.noopbak` impact explicitly tested if persisted;
- UI can distinguish calibrating, building, solid, unsupported, withheld, and experimental without fabricating a number.

## Tranche 4 — SleepStagerV2 temporal-prior benchmark

Upstream context: #930.

Goal: repair the structural “fraction of session length” REM-latency prior only if an elapsed-time alternative improves out-of-sample behavior.

Work:

1. preserve current implementation as benchmark baseline;
2. implement candidate absolute-elapsed-time priors behind benchmark/experimental selection first;
3. run current SleepBench/reference tooling on:
   - existing holdouts;
   - short nights;
   - long nights;
   - naps;
   - fragmented nights;
   - sparse-motion WHOOP 4-like cases;
   - multiple subjects where available;
4. report per-stage precision/recall/F1, confusion matrix, macro metrics, first-REM latency distribution, and total-stage bias;
5. reject a candidate that improves its fit set but regresses holdouts.

Acceptance:

- no hand-tuned release based on one user's stage proportions;
- exact constant provenance documented;
- Swift/Kotlin outputs parity-tested;
- manual-edit and session-reclip behavior preserved.

## Tranche 5 — external differential test harness

Goal: harvest evidence without importing architectures.

Build reusable, NOOP-owned fixtures for:

- protocol decoder parity;
- malformed/short frames;
- CRC failures;
- unknown record versions;
- history ACK state-machine faults;
- duplicate/replayed chunks;
- physiological multiple-value synthetic sweeps;
- sleep ablations;
- gap-heavy HRV windows.

External projects may suggest cases, but fixture bytes must have usable provenance and comply with the source lock.

Acceptance:

- every fixture has source/provenance metadata;
- multiple injected values for signal-recovery methods;
- platform twins consume the same canonical vectors;
- tests exercise production symbols, not unused copies.

## Tranche 6 — WHOOP 5/MG capability matrix and guarded deep-data probes

Upstream context: #423 and #761.

Goal: turn inconsistent external claims into explicit, firmware-scoped NOOP capabilities.

Work:

- capability model: `available`, `needs data`, `unsupported`, `experimental`;
- record device family + firmware + validation source;
- schema-first candidate decoder work;
- default-off, bounded, reversible probes;
- no destructive commands;
- raw persistence only after schema/migration review;
- no downstream physiological score until validation supports it.

External `whoop-vault`/`whoop-local` claims are clean-room hypotheses only.

Acceptance:

- real-device captures independently reproduce a promoted wire fact;
- CRC and malformed-path fixture coverage;
- Apple/Android decoder parity;
- unsupported raw signals are explained rather than filled with guessed values.

## Tranche 7 — BLE fault injection and restoration

Goal: prove lifecycle invariants without waiting for random real-world failures.

Evaluate whether NOOP can gain a native fake peripheral/mock transport seam inspired by external projects without adopting their architecture.

Fault cases:

- delayed characteristic discovery;
- authentication failure;
- stale subscription;
- duplicate command response;
- disconnect during history batch;
- response after timeout;
- process restoration;
- full backlog;
- low battery;
- repeated pair/forget cycle.

Acceptance:

- deterministic state-machine tests;
- no duplicate non-idempotent command execution;
- real-hardware validation for behavior that mocks cannot prove;
- battery/reconnect loops bounded.

## Tranche 8 — architecture/scope decisions only after evidence

These are not ordinary implementation tickets.

### Shared Rust core

Requires an ADR. Default is **no migration** until measured parity/reliability benefits justify build/FFI/maintenance cost.

### Self-hosted continuous export

Requires an explicit scope decision before implementation because continuous network export touches NOOP's offline constraints. Do not smuggle it in through MCP or backup work.

### New device families

Require capability, identity, source arbitration, storage, analytics-substrate, and validation plans before UI work.

## PR rule

One concern per PR. Every PR records:

- pinned evidence;
- problem and current behavior;
- exact NOOP symbols;
- license/provenance decision;
- implementation layer;
- Swift/Kotlin impact;
- migration/backup impact;
- deterministic tests;
- required app builds;
- required hardware evidence;
- user-visible behavior;
- limitations and rollback.

A flashy new metric never outranks a known integrity defect that can corrupt the metric's inputs.
