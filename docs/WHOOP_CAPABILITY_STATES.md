# WHOOP deep-data capability states

Issue #761 asks for one Apple/Android capability vocabulary that can distinguish **available**, **unsupported**, **experimental**, and **needs data** across WHOOP deep-data paths.

This document defines the first, pure-model tranche. It does not change BLE behavior, storage, scoring, or UI.

## Two different capability questions

NOOP already has `WhoopLiveCapabilities`. Keep it.

That registry answers:

> Which high-level product metrics can a freshly paired WHOOP contribute over NOOP's live/local path?

For example, it deliberately excludes calibrated SpO2 and adds steps for 5/MG.

`WhoopDeepCapabilities` answers a different question:

> What is the current support/evidence state of each lower-level WHOOP data substrate?

Keeping the two models separate avoids turning a research packet or decoder into an advertised health metric.

## Hardware identity is an input, not a heuristic

This model does not parse device names, registry labels, serial strings, or version-looking substrings.

Upstream now owns generation resolution in `WhoopProtocol.DeviceFamily`, with `Whoop5Variant` separately representing positively identified WHOOP 5.0 versus MG hardware. Callers pass the already-resolved `DeviceFamily?` into this capability model. `nil` stays unknown and receives the generic research reason rather than being guessed into either generation.

`Whoop5Variant` is deliberately not an argument to the current resolver. All current roadmap axes below have the same capability-state semantics for plain 5.0 and MG. If an MG-only axis such as ECG is added later, it should consume the canonical variant explicitly rather than changing `DeviceFamily` or inferring MG from a label.

## Roadmap axes

The cross-platform model covers, in stable order:

1. heart rate
2. HRV / R-R substrate
3. respiration
4. SpO2
5. skin temperature
6. raw deep buffers
7. raw IMU
8. battery
9. body/wear status
10. sync mode

`rawDeepBuffers` is deliberately neutral wording. Some historical large-buffer channels are still not physically identified strongly enough to call them optical. A capability label must not settle an open reverse-engineering question by name.

## States

### `available`

The path is usable under the stated evidence contract.

For ordinary measurement substrates, the resolver requires the caller to say that usable data was actually observed for the current device/session. For sync mode, the transport itself is already a validated capability and does not require a physiological observation.

### `needsData`

NOOP supports the path, but the caller has not supplied evidence of a usable observation yet.

This is different from unsupported. It is the state UI can eventually use for cases such as a newly paired strap, an incomplete night, an unworn interval, or a still-calibrating stream without pretending that a blank value is a bug.

### `unsupported`

NOOP cannot honestly provide the advertised value from this live WHOOP path.

Calibrated SpO2 percentage is currently the explicit example. #548 removed it from `WhoopLiveCapabilities` because NOOP has no validated calibration that turns the available raw/candidate signals into a trustworthy percentage.

Passing `.spo2` in the `observed` set does **not** promote it. Candidate bytes, raw ADC values, or imported observations are not permission to relabel the live WHOOP capability.

### `experimental`

A research/instrumentation path exists, but it is not a generally available product substrate.

Current examples are raw deep buffers and raw IMU. #423 established and hardware-validated the WHOOP 5/MG 1244-byte offload IMU layout, and later work can bank it behind explicit capture gates. That is valuable research capability, but it does not make raw IMU a default-on, continuously available product stream.

Likewise, large deep buffers are kept experimental because capture/decode work remains gated and some channel identities remain unresolved.

Passing an experimental capability in `observed` does **not** promote it to available.

## Reasons

Every status carries a stable, non-clinical reason:

- `observationPresent`
- `awaitingUsableData`
- `calibratedLiveSpo2Unavailable`
- `gatedResearchCapture`
- `gatedRealtimeResearchCapture`
- `gatedOffloadResearchCapture`
- `validatedTransport`

The family-specific research reasons encode an already-established transport difference without claiming more than the evidence supports:

- canonical `DeviceFamily.whoop4` / `WHOOP4`: realtime/gated research capture;
- canonical `DeviceFamily.whoop5` / `WHOOP5`: offload/gated high-rate research capture for both 5.0 and MG;
- unresolved family (`nil` / `null`): generic gated-research reason.

Generation resolution remains owned by `WhoopProtocol`; this model creates no competing model-string heuristic.

## Observation contract

`observed` means:

> The caller has explicit evidence of a **usable** sample/value for this capability on the current device/session.

It does not mean a decoder key happened to be present, a byte had a plausible numerical range, or an imported/cloud value exists somewhere else.

The promotion rule is intentionally one-way:

```text
needsData + observed -> available
unsupported + observed -> unsupported
experimental + observed -> experimental
available -> available
```

This is the safety property the UI and later capability plumbing can rely on.

## Cross-platform parity

Swift and Kotlin expose the same:

- ten capability wire names
- four state wire names
- seven reason wire names
- resolution rules
- canonical family-specific raw-capture reasons
- stable profile order

Mirrored tests pin:

- complete roadmap-axis coverage
- ordinary observation promotion
- SpO2 non-promotion
- experimental raw-data non-promotion
- WHOOP 4 vs WHOOP 5/MG research transport reasons through canonical `DeviceFamily`
- unknown-family abstention
- sync availability without physiological observations

## Deliberate non-changes in this tranche

This foundation does not:

- alter `WhoopLiveCapabilities` or paired-device metric storage
- add a database migration
- change any BLE command or probe
- enable R22 or raw-stream capture
- change any decoder
- infer device generation or MG identity
- claim that the 2140-byte deep buffer is an optical/SpO2 stream
- expose a new health metric
- change Readiness/Charge/Effort/Rest
- change card visibility or empty-state copy

A follow-up can adapt actual stream/session evidence into this model and then use the statuses in diagnostics and empty-state UI. That wiring should preserve the rule that experimental and unsupported paths require an explicit engineering decision, tests, and where applicable hardware validation before promotion.
