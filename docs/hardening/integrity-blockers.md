# Integrity blockers and release gates

This is a living list of problems that can invalidate downstream conclusions. It is deliberately narrower than the general issue tracker: an item belongs here when getting it wrong can make otherwise-correct analytics confidently wrong.

Status is evaluated against the pinned NOOP baseline in [`source-lock.json`](source-lock.json), not a moving branch.

## P0 — R-R ordering and legacy-data interpretability

Upstream issue: <https://github.com/ryanbr/noop/issues/823>

The original defect sorted same-second R-R intervals by interval magnitude, biasing successive-difference metrics such as RMSSD downward. The structural repair already landed upstream before this fork's pinned baseline: a separate nullable emission-order field is stamped at decode time and leads the read ordering while legacy rows retain their historical deterministic fallback.

Do **not** reimplement the original two-line `ORDER BY ts, seq` proposal. The issue documents why that would make distinct same-second beats tie and can regress determinism/data safety.

Residual gates still worth measuring before claiming the effect is fully characterized:

- legacy rows cannot recover an emission order that was never observed;
- a second split across separate live flushes may restart batch-local order unless a later repair covers it;
- nightly RMSSD effect size must be measured on post-migration data rather than inferred from the percentage of groups that reorder;
- any new HRV method must disclose the fraction of the analyzed window whose beat order is actually known.

**Release rule:** do not describe the historic bias as quantitatively solved for a full night until the corpus experiment measures it on data with recorded emission order.

## P0 — input-source identity and active-device ownership

NOOP supports multiple device records and multiple data sources. Every read feeding a headline metric must resolve through the canonical active-device/source arbitration path rather than a transient BLE identifier or a string comparison of model names.

Audit whenever protocol, storage, or rescore code changes:

- stable serial/device identity across re-pair;
- active strap id threaded through reads;
- day ownership when imports and live devices overlap;
- source arbitration for fused metrics;
- stale device rows after removal;
- rescore fingerprints include the source state that can change the answer.

**Release rule:** a metric whose device/source identity is ambiguous is withheld rather than silently attributed.

## P0 — history durability before acknowledgement

The historical offload invariant is:

```text
CRC-valid frame
  -> decode
  -> durable insert / transaction
  -> durable cursor state
  -> exact history acknowledgement
```

Audit crash/fault behavior around every change to history sync. A successful write call is not sufficient evidence that the strap advanced, and an acknowledgement must never advance the device past data NOOP has not durably saved.

Required scenarios include:

- crash before insert;
- crash after insert but before ACK;
- repeated chunk;
- duplicate response;
- invalid CRC;
- disconnect mid-chunk;
- process restoration;
- full backlog;
- clock discontinuity.

**Release rule:** BLE compile success is not validation. State-machine changes require deterministic tests and real-hardware evidence before being called complete.

## P1 — SleepStagerV2 REM-latency prior

Upstream issue: <https://github.com/ryanbr/noop/issues/930>

The V2 REM prior includes a strong early-night suppression threshold expressed as a fraction of session length. That makes the effective suppression window vary with total session duration, even though first-REM latency is fundamentally an elapsed-time quantity. The issue's ablation also shows that simply deleting the term is worse because the current term is load-bearing for early REM suppression.

**Release rule:** do not tune this constant by intuition. Any replacement must be expressed and justified in elapsed-time terms, scored through the existing sleep benchmark tooling, and evaluated on holdouts, short nights, long nights, naps, sparse-motion cases, and both platform implementations.

## P1 — WHOOP 5/MG deep-data capability truthfulness

Upstream roadmap: <https://github.com/ryanbr/noop/issues/761>

Related probe: <https://github.com/ryanbr/noop/issues/423>

Deep optical/IMU availability differs by device generation, firmware, command path, and whether data is live or banked for history. External projects also disagree on field meanings.

**Release rule:** capability labels must distinguish at least `available`, `needs data`, `unsupported`, and `experimental`. A raw byte or ADC channel is not promoted to an absolute physiological unit without calibration and validation. Probe paths remain default-off and non-destructive.

## P1 — app-target and Android validation gaps

The repository's default active CI does not provide the same coverage as the full validation matrix. `CLAUDE.md` is authoritative for current workflow status.

For changes that touch app-target Swift, Android, migrations, BLE, or shared result semantics, record which of the following actually ran:

- Swift package tests;
- Android unit tests and compile;
- macOS app build;
- iOS app build;
- migration/backup round trip;
- real strap validation.

**Release rule:** do not translate “package tests are green” into “the app compiles” or “BLE works.”

## P1 — external-source licensing and provenance

The pinned source lock currently contains multiple sources whose README describes intended use but whose pinned repository exposes no license artifact. It also contains projects whose documentation explicitly describes decompiled-app provenance.

**Release rule:** follow `license.copy_policy` in `source-lock.json`. `reference_only` means copy nothing. `clean_room_only` means independently reproduce factual behavior and leave implementation/literals/fixtures/private names behind.

## How to close an integrity blocker

A blocker is not closed by a code diff alone. Add the evidence that makes the claim safe:

1. reproducible failing case or measurement;
2. implementation and cross-platform twin where applicable;
3. regression/golden tests;
4. migration/legacy-data behavior if storage changed;
5. benchmark or corpus result when the issue is quantitative;
6. real-hardware evidence for BLE/sensor behavior;
7. update this file with the pinned commit that satisfies the gate.
