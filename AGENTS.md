# AGENTS.md — evidence-first work on this fork

Read [`CLAUDE.md`](CLAUDE.md) first. It is the authoritative high-signal map for NOOP's architecture, build gates, BLE safety, cross-platform parity, migrations, design system, and contribution rules.

This fork adds one requirement on top: **external, protocol, physiological, storage, and BLE changes must be evidence-driven before they are feature-driven.**

## Before external or physiological work

Read:

- [`docs/hardening/README.md`](docs/hardening/README.md)
- [`docs/hardening/source-lock.json`](docs/hardening/source-lock.json)
- [`docs/hardening/integrity-blockers.md`](docs/hardening/integrity-blockers.md)
- [`docs/hardening/reachability-matrix.csv`](docs/hardening/reachability-matrix.csv)
- [`docs/hardening/provenance-ledger.csv`](docs/hardening/provenance-ledger.csv)

Then run:

```bash
python3 Tools/source_lock.py
```

Do not rely on a moving external branch as durable evidence. Pin an exact commit first.

## The order of operations

For a proposed capability or fix, establish this chain before adding another implementation:

```text
real input
  -> CRC/structural validation
  -> decode
  -> durable storage or intentional ephemerality
  -> correct device/source ownership
  -> deterministic analytics
  -> confidence + missing/withheld reason
  -> production caller
  -> UI / export / MCP
  -> Swift/Kotlin parity
  -> fixture / benchmark / hardware evidence
```

A break in this chain is usually the work item.

## Integrity Gate Zero

Do not add or promote downstream analytics when their substrate is known to be unreliable.

Examples:

- suspect R-R emission order or duplicate intervals;
- wrong active-device identity;
- history ACK before durable persistence;
- duplicate/partial sleep sessions;
- stale daily rows feeding today's score;
- uncertain raw-field semantics;
- platform-divergent migrations.

When blocked, produce the next honest artifact: a fixture, replay, diagnostic, benchmark, issue, default-off experiment, or documentation. Do not hide the problem behind a new score.

## Production reachability, not source-file existence

Before calling something absent, inspect NOOP. `Packages/StrandAnalytics` already contains a large set of recovery, readiness, HRV, sleep, circadian, illness, stress, fusion, workout, rhythm, and longitudinal engines.

Before calling something shipped, identify its actual production caller.

Use the detailed statuses in `docs/hardening/reachability-matrix.csv`. Do not reduce them to “present / missing.”

Prefer, in order:

1. fix corrupt inputs;
2. wire existing NOOP output;
3. repair platform skew;
4. import or recreate a better test;
5. improve an existing method with differential evidence;
6. add a genuinely missing capability.

Do not create a second recovery, readiness, sleep, strain, fusion, or MCP architecture merely because an external repository has one.

## Provenance firewall

Obey `license.copy_policy` in `docs/hardening/source-lock.json`.

- `adapt_with_notice`: adaptation may be considered after differential review and notice handling.
- `review_required`: explicitly review project/contributor licensing and attribution before reuse.
- `reference_only`: copy no code, tests, fixtures, comments, or prose.
- `clean_room_only`: independently reproduce factual behavior; carry over no implementation, private literals/names, fixtures, or decompiled structures.

A README license statement is not a license artifact.

An MIT wrapper does not sanitize decompiled proprietary material.

Record any external idea, fact, fixture, formula, or adaptation actually used in `docs/hardening/provenance-ledger.csv`.

## Protocol work

Protocol facts belong in `Packages/WhoopProtocol` / `Packages/OuraProtocol` or their canonical schema, never scattered through UI or BLE callbacks.

For new or changed fields record:

- record/device/firmware scope;
- offset, length, endianness, signedness;
- raw unit versus physiological unit;
- CRC/length behavior;
- plausibility gates;
- provenance;
- fixture;
- hardware-validation state.

An unknown record version is not decoded as a nearby known layout just because the numbers look plausible.

External WHOOP wire facts require independent reproduction before promotion.

## Physiological work

Validate the exact implementation on the exact substrate.

- PPG-derived beat timing is PRV unless ECG provenance exists.
- Relative ADC is not an absolute temperature or oxygen saturation.
- A multivariate anomaly is not proof of illness.
- Rhythm instrumentation is not a diagnosis.
- One matching night is not validation.

Signal-recovery tests must recover multiple varying values, not one convenient target. Prefer holdouts, multiple subjects/devices, public datasets, external references, ablations, and documented failure cases.

Missing/unsupported input means absent or withheld output, not a fabricated fallback for UI symmetry.

## Cross-platform contract

Follow `CLAUDE.md` exactly:

- decoder, analytics, stored-value, migration, confidence, and `.noopbak` semantics stay aligned across Swift and Kotlin;
- UI parity is behavioral, not pixel-level;
- app-target Swift must be built separately because package CI is not sufficient;
- Android must be compiled/tested separately;
- BLE behavior needs real hardware where mocks cannot prove it.

Never hand-edit `Strand.xcodeproj`. Change `project.yml` and regenerate it.

## Architecture changes

A shared Rust/UniFFI core, continuous self-hosted export, new mandatory network behavior, new device-neutral domain layer, or backup-contract redesign requires an ADR or explicit scope decision before implementation.

Do not let a small fork bug fix smuggle in a major architecture migration.

## PR standard

Keep one concern per PR. Record:

- pinned evidence;
- current failure/behavior;
- exact NOOP symbols;
- provenance/license decision;
- implementation layer;
- Swift/Kotlin impact;
- migration/backup impact;
- deterministic tests;
- app builds that actually ran;
- hardware validation if required;
- privacy/battery/storage impact;
- user-visible change;
- known limitations and rollback.

Do not claim a stronger validation state than the evidence supports.
