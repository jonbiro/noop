# Self-hosted push protocol v1

Status: **Experimental**. This protocol belongs to NOOP's optional, one-way export to a user-owned endpoint (issue #1314). It is not cloud sync and it is not required for any NOOP feature.

## Scope and trust boundary

- Disabled by default. With no configured endpoint, NOOP sends nothing.
- Send-only. NOOP never reads state, commands, scores, or configuration back from the receiver.
- The receiver is user-owned. NOOP ships no hosted receiver and has no account/identity service for this feature.
- Export is scheduled after a completed strap offload and is not awaited by the BLE/offload path. Receiver failure must not delay or fail strap sync.
- Protocol v1 is Wi-Fi-only. A satisfied non-Wi-Fi path does not start an export request and there is no cellular override in v1.
- Bearer tokens live in the device Keychain and are not included in `.noopbak` settings metadata.
- HTTPS is required for non-local destinations. Plain HTTP is accepted only for loopback/private-link/RFC1918-style local destinations.

## HTTP request

NOOP sends one stream batch per HTTP `POST`.

```http
POST /your/ingest/path HTTP/1.1
Content-Type: application/x-ndjson
Accept: application/json
Authorization: Bearer <user-generated-token>
X-NOOP-Push-Protocol: 1
X-NOOP-Push-Stream: hrSample
X-NOOP-Push-Mode: append
```

A `2xx` response means **the receiver has durably accepted the complete batch**. NOOP does not parse a response body in protocol v1.

Receivers should return non-2xx for any batch that has not been durably committed. NOOP may retry an identical batch after timeout, crash, or ambiguous network failure, so ingestion MUST be idempotent.

## NDJSON body

The first line is a batch envelope. Every subsequent line is one row.

Append example:

```json
{"cursor":{"fromExclusive":41,"toInclusive":43},"generatedAtMs":1787000000000,"kind":"batch","mode":"append","naturalKey":["deviceId","ts"],"protocol":1,"rowCount":2,"stream":"hrSample"}
{"data":{"bpm":61,"deviceId":"strap-a","ts":1786999980},"kind":"row"}
{"data":{"bpm":62,"deviceId":"strap-a","ts":1786999981},"kind":"row"}
```

Mutable-window example:

```json
{"generatedAtMs":1787000000000,"kind":"batch","mode":"upsertWindow","naturalKey":["deviceId","day"],"protocol":1,"rowCount":1,"stream":"dailyMetric","window":{"field":"day","from":"2026-08-04","through":"2026-08-17"}}
{"data":{"avgHrv":55.0,"day":"2026-08-17","deviceId":"strap-a"},"kind":"row"}
```

JSON object keys are emitted deterministically to keep fixtures/replays diffable. Blob-valued database fields, if any are introduced into a supported stream later, are encoded as Base64 strings.

Internal NOOP transport fields such as `synced` and the private SQLite row cursor are never included inside row data.

## Stream modes

### `append`

For stream-like data NOOP exports rows after a dedicated insertion-order high-water mark.

Protocol v1 append streams:

- `hrSample`
- `rrInterval`
- `event`
- `battery`
- `spo2Sample`
- `skinTempSample`
- `respSample`
- `gravitySample`
- `stepSample`
- `ppgHrSample`

The local cursor is based on SQLite insertion order rather than physiological timestamp. This distinction is intentional. A strap may later offload an older timestamp; that late backfill still has a newer insertion position and therefore remains exportable.

SQLite does not promise that an implicit `rowid` is permanent across every kind of database maintenance. To make that fail safe, NOOP stores a second exporter-only anchor fingerprint derived from the acknowledged row's documented natural key. Before trusting a saved high-water, the sender verifies that the same `rowid` still names the same logical row. If the anchor is missing or differs, the effective high-water becomes zero and the current stream is replayed. Because receiver ingestion is required to be idempotent, replay is safe and preferable to silently skipping rows after a local rowid renumber/reuse.

NOOP commits the stream cursor and its anchor only **after** the matching POST receives a 2xx response. Reading/encoding a batch never advances the cursor.

The cursor values and anchor are sender bookkeeping. Receivers do not need to reproduce or persist them for correctness, although retaining the envelope cursor can help diagnostics.

### `upsertWindow`

Derived or user-editable rows can change after first insertion, so treating them as immutable append streams would be incorrect. NOOP instead repeatedly sends a bounded authoritative recent window.

Protocol v1 mutable streams:

- `dailyMetric`
- `sleepSession`
- `workout`
- `journal`

The default window is the most recent 14 calendar days, bounded by the field named in the envelope. Receivers UPSERT every row by the provided `naturalKey`.

Protocol v1 does **not** carry deletion tombstones. Recomputes and edits propagate through repeated UPSERT, but a row deleted from NOOP is not automatically deleted from a receiver. A future protocol version must add explicit tombstone semantics before claiming deletion mirroring.

## Natural keys

The batch envelope names the key used for idempotency:

| Stream | Natural key |
| --- | --- |
| `hrSample`, `battery`, `spo2Sample`, `skinTempSample`, `respSample`, `gravitySample`, `stepSample`, `ppgHrSample` | `deviceId`, `ts` |
| `rrInterval` | `deviceId`, `ts`, `rrMs` |
| `event` | `deviceId`, `ts`, `kind` |
| `dailyMetric` | `deviceId`, `day` |
| `sleepSession` | `deviceId`, `startTs` |
| `workout` | `deviceId`, `startTs`, `sport` |
| `journal` | `deviceId`, `day`, `question` |

A receiver SHOULD implement these as unique constraints or the equivalent transactionally idempotent UPSERT rule.

## Retry and backoff

Automatic exports are bounded jobs, not an unbounded foreground drain. The macOS worker:

- requires a satisfied Wi-Fi interface before starting any request;
- uses request/resource timeouts and forbids cellular, expensive, and constrained URLSession paths;
- sends mutable summaries before draining append backlog;
- drains append streams round-robin so a large HR backlog does not starve another stream;
- uses bounded batch and per-run POST counts;
- backs off after failures;
- suspends unattended attempts after repeated failures until the user explicitly runs **Push now**.

A failed receiver does not change any NOOP score or strap-sync state.

## Privacy and excluded data

Protocol v1 intentionally excludes `rawBatch` and experimental deep/research buffers from automatic export. Adding a newly decoded research stream to this standing export requires its own explicit product/privacy review rather than inheriting permission from the generic exporter.

The receiver sees the same natural device identifiers stored locally in the exported rows. Users should treat the endpoint as holding sensitive biometric data and secure it accordingly.

## Compatibility

`X-NOOP-Push-Protocol` and the envelope `protocol` field are both `1` in this version. A receiver that does not understand a future version should reject it with a non-2xx response rather than partially ingesting it.

New optional row columns may be added within protocol v1 as NOOP's tables evolve. Receivers should preserve/ignore unknown columns rather than reject an otherwise valid row. Changes to stream semantics, natural keys, deletion behavior, or envelope meaning require a new protocol version.
