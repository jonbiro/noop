# Evidence-driven hardening program

This fork treats interoperability, physiology, storage, and cross-platform parity as evidence problems before they are feature problems.

The program exists to answer four questions before a change is promoted into production:

1. **Is the input trustworthy?** A more sophisticated formula cannot repair corrupted R-R order, duplicate streams, stale device identity, unsafe history acknowledgement, or incomplete sleep sessions.
2. **Does NOOP already implement it?** A source file is not enough. The implementation must be reachable from production, receive real input, persist or intentionally remain ephemeral, recalculate correctly, and reach the intended UI/export surface.
3. **Is the external evidence usable?** Every external repository is pinned to a commit and assigned a license/provenance policy in [`source-lock.json`](source-lock.json).
4. **Can the result be defended?** Physiological outputs need explicit missing-data behavior, confidence, provenance, and validation on a substrate that supports the claim.

This is additive to the repository-wide rules in [`CLAUDE.md`](../../CLAUDE.md), [`docs/CONTRIBUTING.md`](../CONTRIBUTING.md), and [`docs/SCOPE.md`](../SCOPE.md). Those files remain authoritative when there is a conflict.

## The operating rule

Do not ask “which project has this feature?” first.

Ask:

```text
raw input
  -> validated decode
  -> durable storage / intentional ephemerality
  -> source arbitration
  -> deterministic analytics
  -> confidence + absence reason
  -> production caller
  -> UI / export / MCP
  -> Swift/Kotlin parity
  -> fixture / benchmark / hardware evidence
```

A break in that chain is a finding. Adding another implementation around the break is usually the wrong fix.

## Required workflow for external or physiological work

### 1. Pin the evidence

Before relying on another repository, add or refresh it in `source-lock.json` with:

- repository and canonical URL
- branch inspected
- exact 40-character commit SHA
- SHA permalink
- commit date
- role in the audit
- verified license state
- permitted copy policy
- provenance class

Run:

```bash
python3 Tools/source_lock.py
```

Moving `main`/`master` references are discovery aids, not durable evidence.

### 2. Apply the provenance firewall

Copy policy has four states:

- `adapt_with_notice` — a verified permissive license exists. Adaptation is possible after differential review and required notice handling.
- `review_required` — same-project or otherwise compatible source where attribution/license details still need explicit review.
- `reference_only` — code, tests, fixtures, comments, and prose must not be copied. It may inform architecture or independently testable hypotheses.
- `clean_room_only` — use only independently reproducible factual behavior. Do not carry over implementation, literals, fixtures, private names, or decompiled structures.

A README statement is not a license artifact. A permissive wrapper license does not sanitize decompiled proprietary material.

### 3. Prove production reachability

Before calling a capability missing or complete, trace it through [`reachability-matrix.csv`](reachability-matrix.csv).

Status vocabulary:

- `absent`
- `placeholder`
- `test-only`
- `implemented-unwired`
- `wired-not-persisted`
- `persisted-not-recalculated`
- `calculated-not-displayed`
- `platform-skew`
- `experimental`
- `fixture-tested`
- `hardware-tested`
- `shipped`
- `deprecated`
- `duplicated`
- `known-wrong`
- `audit-needed`

Do not collapse these to a single “present” flag.

### 4. Pass Integrity Gate Zero

Before changing a downstream headline metric, check the relevant items in [`integrity-blockers.md`](integrity-blockers.md).

Examples of blockers:

- R-R emission order, duplication, source identity, gaps, or coverage
- unstable active-device identity
- history ACK before durable persistence
- duplicate or partial sleep sessions
- stale-day scoring
- uncertain raw-field semantics
- platform migration divergence

When input integrity is unresolved, the safe deliverable is instrumentation, a fixture, a benchmark, an issue, or a default-off experiment, not a more confident score.

### 5. Differentially compare implementations

For a candidate improvement, compare NOOP and the external implementation on:

- exact input substrate and sampling assumptions
- formula and constants
- baseline window, weighting, and outlier policy
- gap and missing-data behavior
- artifact rejection/correction
- output semantics and units
- confidence and evidence tier
- tests and fixture provenance
- validation population and holdout behavior
- downstream consumers
- license and provenance

Prefer, in order:

1. repair or wire NOOP's existing implementation
2. import a test methodology or independently reproducible fixture
3. adapt a small better method under a compatible license
4. clean-room reimplement a verified fact
5. reject the external approach

### 6. Keep the cross-platform contract

Analytics, decoders, migrations, persisted values, confidence semantics, and `.noopbak` keys must remain aligned across Swift and Kotlin unless a PR explicitly documents why the change is platform-specific.

A green Swift package suite does not validate Kotlin. A green package suite also does not compile app-target Swift. Follow `CLAUDE.md` for the actual build gates.

## Scientific release rules

A physiological method is not promoted because one night “matches WHOOP.” It must demonstrate that it tracks variation.

Prefer evidence from:

- multiple subjects
- multiple devices or firmware versions
- multiple injected synthetic values
- a public reference dataset
- an external reference device
- predeclared holdouts
- ablation studies
- documented failure cases

Distinguish measurement from interpretation:

- PPG-derived intervals are PRV unless ECG provenance exists.
- relative ADC is not an absolute temperature or oxygen saturation.
- rhythm instrumentation is not a diagnosis.
- a multivariate anomaly is not proof of illness.

If the substrate cannot support the claim, return an absent/withheld result rather than fabricating symmetry in the UI.

## Audit artifacts

This directory is intentionally machine- and human-readable:

- [`source-lock.json`](source-lock.json) — immutable external source snapshot and copy policy
- [`reachability-matrix.csv`](reachability-matrix.csv) — production execution map
- [`integrity-blockers.md`](integrity-blockers.md) — known substrate/reliability blockers and release gates
- [`fork-audit.md`](fork-audit.md) — active fork and Rust-core differential notes
- [`provenance-ledger.csv`](provenance-ledger.csv) — item-level record of ideas, facts, fixtures, formulas, and adaptations actually considered
- [`roadmap.md`](roadmap.md) — PR-sized implementation sequence

The source lock is validated by `Tools/source_lock.py` and its unit tests.

## Definition of done for an incorporated capability

A capability is complete only when its scope, source, license, provenance, reachability, input integrity, missing-data behavior, confidence behavior, algorithm versioning needs, Swift/Kotlin parity, migrations, backup/export behavior, deterministic tests, required app builds, hardware validation, privacy impact, battery/storage cost, accessibility, and documentation have all been addressed.

Anything less must be labeled honestly as partial, experimental, instrumentation-only, platform-limited, unvalidated, or blocked.
