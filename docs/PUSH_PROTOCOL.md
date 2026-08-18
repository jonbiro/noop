# Self-hosted push protocol

Status: **Experimental, version 1**. This protocol belongs to the opt-in, one-way export approved in #1314.
It is not a cloud-sync API and NOOP does not ship or operate a receiver.

## Trust boundary

Nothing is sent unless the user explicitly enables self-hosted push and configures a destination. The
receiver is owned or chosen by the user. NOOP only sends data out; it never reads state, commands, scores,
or configuration back from the receiver, and the app must never depend on receiver availability.

The push job runs only after local strap offload work is complete and outside the Bluetooth sync path.
Receiver failure must not slow, fail, or change strap sync. Wi-Fi-only is the default.

Public destinations require HTTPS. Plain HTTP is accepted only for loopback, `.local`, link-local,
RFC1918 IPv4, and IPv6 ULA destinations. A configured bearer token is sent in the `Authorization` header.
The Apple client stores that token in Keychain, not UserDefaults. Redirects are not followed so a token
cannot be carried to a different URL by a 3xx response.

## Request

The client sends `POST` with:

```text
Content-Type: application/x-ndjson
Accept: application/json
Authorization: Bearer <user-generated token>
```

The body is newline-delimited JSON. Line 1 is the batch header; every following line is one record.
Each line ends in `\n`.

Header example:

```json
{"type":"batch","protocolVersion":1,"batchId":"7D...","stream":"hrSample","previousCursor":"opaque-1","cursor":"opaque-2","generatedAtMs":1787000000000,"recordCount":2}
```

Record examples:

```json
{"type":"record","id":"whoop-1|1786999999","observedAtMs":1786999999000,"values":{"bpm":72}}
{"type":"record","id":"whoop-1|1787000000","observedAtMs":1787000000000,"values":{"bpm":73}}
```

Fields:

- `protocolVersion`: integer wire version. Version 1 is defined by this document.
- `batchId`: unique id for this delivery attempt.
- `stream`: stable source stream name supplied by the stream adapter.
- `previousCursor`: the last delivery state acknowledged for this stream, or null on first delivery.
- `cursor`: opaque adapter-owned delivery state covering the records in this batch.
- `generatedAtMs`: Unix milliseconds when the client assembled the batch.
- `recordCount`: number of record lines that follow.
- `id`: stable record identity derived from the source row's complete primary key. Receivers should use
  `(stream, id)` as their upsert/deduplication key.
- `observedAtMs`: optional source timestamp for querying and display. It is not the delivery cursor.
- `values`: typed JSON values from the source row.

Cursors are intentionally opaque to receivers and to the transport layer. A stream adapter may need more
state than one source timestamp or primary key. In particular, NOOP historical offload can insert an older
sample after a newer realtime sample already exists. A timestamp-only or forward-only source-key watermark
can therefore strand late historical rows, the same failure mode documented by the old uploader around the
v5 `synced` migration. Every stream adapter must use a late-arrival-safe strategy, such as a proven forward
watermark plus reconciliation replay, or another scheme with equivalent coverage. The exact strategy and
its coverage bound must be documented and tested with out-of-order inserts before that stream ships.

The client does not use the legacy per-row `synced` column for this feature.

## Acknowledgement

A 2xx status alone does **not** advance the client's high-water state. The response body must be JSON:

```json
{"protocolVersion":1,"batchId":"7D...","stream":"hrSample","acceptedCursor":"opaque-2"}
```

All four values must exactly match the request batch. Only then does NOOP persist `acceptedCursor` as the
stream's new delivery state. A missing, malformed, mismatched, redirected, non-2xx, or timed-out response
is a failed attempt and leaves the prior cursor unchanged.

## Delivery semantics

Delivery is **at least once**. A receiver can persist a batch and lose its acknowledgement, or NOOP can
terminate after the receiver commits but before the local cursor is written. Reconciliation of late-arriving
source rows also deliberately re-sends records. The same source record may therefore appear again in a later
batch. Receivers must upsert or ignore duplicates by `(stream, id)`.

NOOP makes one quiet attempt per eligible post-offload job. Failures are exponentially backed off, capped
at 15 minutes between opportunities; repeated failures trigger a longer temporary suspension. There is no
retry loop inside strap sync.

## Stream evolution

Version 1 establishes the transport and acknowledgement contract before individual database adapters are
added. Append-only sensor adapters must prove that their cursor/reconciliation scheme cannot strand
out-of-order historical inserts. Editable/recomputed entities such as daily metrics, sleep sessions,
workouts, and journal rows should be exported by a rolling window and upserted by stable primary key rather
than treated as immutable append-only events.

Adding a stream does not require a wire-version bump when it follows the record shape above. A wire-version
bump is required for an incompatible change to framing, acknowledgement semantics, or existing field
meaning.

## Receiver requirements

A compatible receiver should:

1. authenticate the user-generated bearer token;
2. reject unsupported protocol versions;
3. validate `recordCount` and parse every record before acknowledging;
4. commit/upsert the complete batch transactionally when practical;
5. return the exact acknowledgement only after durable acceptance;
6. tolerate duplicate batches and duplicate records;
7. never assume it can send data or commands back to NOOP.

A receiver implementation is intentionally outside this repository. This document is the interoperability
contract so a user can target a small personal service, Grafana adapter, local data vault, MCP bridge, or
another user-owned system without making any one server part of NOOP.
