# Active-fork differential audit

Pinned states are authoritative; see [`source-lock.json`](source-lock.json).

## `tanarchytan/noop`

This is not merely an Android patch queue anymore. At the pinned `noop-tan` commit, its own documentation records a material architecture divergence: formulas, protocol decoding, and scoring have moved behind a Rust core and UniFFI boundary, while upstream NOOP continues to maintain native Swift and Kotlin implementations.

That makes the useful unit of comparison **behavior**, not file similarity.

### Harvest first

Before considering architecture adoption, compare and selectively upstream:

- protocol facts backed by real captures;
- golden fixtures and replay vectors with usable provenance;
- bug fixes with a reproducible upstream failure;
- BLE state-machine invariants;
- physiological benchmark methods;
- migration/data-integrity findings;
- safety gates;
- performance findings that reproduce in upstream architecture.

### Do not transplant casually

Do not import the Rust/UniFFI architecture into this fork as a side effect of adopting a bug fix. A shared core would alter build, release, debugging, FFI, contributor, and migration assumptions across iOS, macOS, and Android.

Any shared-Rust proposal requires an ADR answering at minimum:

- which measured parity failures it eliminates;
- how iOS/macOS and Android consume the core;
- generated-binding lifecycle and stale-binary hazards;
- error/threading/cancellation semantics across FFI;
- binary-size and release-pipeline impact;
- how existing Swift package consumers migrate;
- database and `.noopbak` compatibility;
- contributor and maintenance cost;
- rollback path;
- whether fixtures/specifications solve the same problem without an architecture migration.

Default decision: **harvest evidence and isolated fixes first; architecture remains upstream NOOP's native model unless an ADR demonstrates a net win.**

## `tanarchytan/whoop-rs`

The pinned repository exposes a broad Rust workspace including protocol, physiological algorithms, BLE abstractions, a client, storage, CLI tooling, and UniFFI surfaces. It is therefore a valuable differential oracle for architecture, tests, and protocol adjudication.

However, at the pinned commit GitHub exposes no repository `LICENSE` file even though the README describes PolyForm Noncommercial use. The source lock consequently marks it `reference_only`.

Until a license artifact is verified:

- do not copy source;
- do not copy test fixtures;
- do not copy comments or documentation prose;
- independently reproduce any protocol observation;
- use benchmark/test *ideas* as methodology, not copied implementation.

High-value comparison areas:

| Area | Upstream question |
|---|---|
| Wire codec | Does a fixture expose a decoder difference in NOOP? |
| Offload state machine | Does its pure state machine encode an invariant NOOP lacks? |
| BLE transport abstraction | Can upstream gain mock/fault coverage without adopting Rust? |
| Physiology algorithms | Is any method measurably better on NOOP's own benchmark substrate? |
| Calibration storage | Does it solve a concrete source/device calibration problem upstream? |
| UniFFI | Would a shared core reduce real parity bugs enough to justify the architecture cost? |
| CLI/capture tools | Can the diagnostic workflow be reimplemented cleanly in existing NOOP tools? |

## Reconciliation procedure

For every fork-only candidate:

1. identify the exact commit and affected behavior;
2. search current upstream NOOP for an equivalent fix under another implementation;
3. search upstream issues/PRs for prior adjudication;
4. reproduce the upstream failure against the pinned target baseline;
5. classify the candidate as protocol fact, implementation, fixture, BLE fix, storage/migration, analytics, test infrastructure, performance, safety, UI, or architecture;
6. record license/provenance in `provenance-ledger.csv`;
7. choose one outcome:
   - already upstream;
   - small native port;
   - independent reimplementation;
   - test methodology only;
   - experimental comparison;
   - ADR required;
   - reject.

A commit existing in a fork is not evidence that upstream needs it. A behavior that reproduces a current upstream failure is.
