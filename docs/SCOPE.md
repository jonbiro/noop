# Scope & non-goals

NOOP exists to give you **your own strap data, offline and on-device**. That mission sets hard limits
on what belongs in the app. This page names the WHOOP-app features that stay **out of scope** — and the
local equivalents that stay **in scope** — so a parity proposal has a standing answer before a PR is
opened. It does not change the constraints stated in [CLAUDE.md](../CLAUDE.md), the
[Contributing guide](CONTRIBUTING.md), or the [Disclaimer](../DISCLAIMER.md); it maps them onto specific
features so the boundary is discoverable.

## The constraints this follows from

NOOP is **fully offline, on-device, and anonymous**: no server, no account, no cloud sync, no telemetry,
and **not a medical device** (see the [Disclaimer](../DISCLAIMER.md#5-not-a-medical-device)). Those are
hard constraints, not preferences. Everything below is a consequence of them, not a separate rule.

## Out of scope

These map to features visible in WHOOP-app reverse-engineering, but they conflict with the constraints
above. They are out of scope **unless the project deliberately changes its scope** in a tracked issue.

| Feature (WHOOP parity) | Why it's out of scope | Ref |
|---|---|---|
| Possible-arrhythmia / diagnostic-style alerts | A medical-device-style claim. NOOP is explicitly **not a medical device** and must not tell a user they may have a health condition. | #752 |
| Community feeds, team chat, social graph, leaderboards, cloud messaging | Require a **server, accounts, and an identity** — the opposite of anonymous and offline. | #755 |
| Cloud- or account-dependent coaching / notification parity | Requires cloud identity and server sync. NOOP's coach is strictly bring-your-own-key and on-device. | — |
| Anything requiring telemetry, server sync, user identity, or medical claims | Fails a hard constraint directly. | — |

## In scope — the local, non-diagnostic equivalents

The point of a boundary is to say what *is* welcome. These stay in scope because they run entirely
on-device from NOOP's own data and make no medical claim.

- **Local rhythm instrumentation.** Surfacing RR/IBI or beat-to-beat variability for the user's own
  curiosity is fine **only** as **default-off instrumentation** with explicit **non-diagnostic** wording
  — never an alert, never a health warning, never "possible arrhythmia" language, and never feeding a
  downstream gate. This mirrors the physiological-signal rule in
  [CLAUDE.md](../CLAUDE.md): an unproven derivation lands as instrumentation, not a shipped feature.
- **Local notifications from NOOP's own metrics** — charge, alarm, sync state — computed on-device.
- **Local export / import / reporting** — your data leaves only when *you* export it.
- **Offline insights and explainers** that need no cloud identity.

## Experimental one-way self-hosted export

Issue #1314 deliberately expands the final bullet above with one narrow, opt-in network boundary while
preserving NOOP's local-first model. The Experimental self-hosted push is **export**, not cloud sync:
NOOP remains fully useful with it disabled and never depends on the destination for reads, scoring,
identity, configuration, or strap offload.

The boundary is strict:

- disabled by default; no configured endpoint means no export network request;
- one-way only — NOOP sends versioned batches and never reads application state or commands back;
- the endpoint and bearer token are supplied by the user, and the token is kept in platform secure
  storage rather than SQLite;
- NOOP ships no receiver, hosted service, account system, discovery service, or mandatory server;
- automatic push is scheduled only after local offload and is independent background work, so receiver
  latency/failure cannot delay or fail BLE/offload;
- the initial implementation is Wi-Fi-only and bounded by batch, timeout, and retry/backoff limits;
- transport cursors are separate from the legacy per-row `synced` flags;
- raw/deep experimental buffers are not automatically exported merely because they exist locally.

Any future bidirectional sync, hosted receiver, remote-control plane, mandatory account, or dependency
on receiver state is a new scope change and requires its own tracked proposal. The wire contract is
specified in [PUSH_PROTOCOL.md](PUSH_PROTOCOL.md).

## Proposing a scope change

Scope changes are deliberate, not incidental. If you believe one of the out-of-scope areas should move,
open an issue that names the constraint it touches and how it would be satisfied — don't open the PR
first. A "WHOOP has it" argument, on its own, is not a reason: NOOP is a clean-room, offline, anonymous
tool, not a WHOOP clone.
