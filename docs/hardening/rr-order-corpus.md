# R-R ordering corpus methodology

This document defines the real-night measurement protocol for the R-R ordering integrity audit around #823.

The purpose is not to prove that one synthetic example can move RMSSD. That is already established by the audit regression fixture. The purpose is to measure **prevalence, provenance, effect size, cleaning interactions, and downstream HRV sensitivity across stored sleep sessions** before NOOP changes any user-facing score or confidence rule.

## Observation unit

One observation is one stored `sleepSession` row over its effective window:

```text
start = startTsAdjusted ?? startTs
end   = endTs
```

The immutable detected start remains in the corpus so a user-edited onset does not break row identity.

The default command excludes sessions shorter than 120 minutes because the primary question is overnight HRV. Naps and short sessions remain available with `--min-duration-min 0` and are reported in their own duration strata.

## R-R population

The corpus query mirrors NOOP's scoring population:

```sql
WHERE deviceId = ?
  AND ts >= ? AND ts <= ?
  AND (srcChannel IS NULL OR srcChannel <> spo2Ibi)
  AND (tsSuspect IS NULL OR tsSuspect <> 1)
ORDER BY ts ASC, ord ASC, rrMs ASC, seq ASC
```

The tool separately counts all R-R rows physically present in the same session window before those source/suspect filters. This lets a report distinguish:

- an ordering-provenance issue;
- a source-channel exclusion issue;
- suspect timestamp data;
- cleaning rejection inside `HRVAnalyzer`.

SpO2-IBI and suspect-timestamp counts can overlap. `excludedRows = totalRowsInWindow - scoringRows` is the non-double-counted exclusion total.

## Structural provenance

Every session carries the complete `RROrderAuditReport`, including:

- `noData`, `complete`, `partial`, or `ambiguous` structural status;
- explicit audit flags;
- recorded-order coverage;
- trustworthy multi-beat coverage;
- legacy-unknown groups;
- mixed known/unknown groups;
- duplicate-order ambiguity;
- same-second sampled density.

A non-null order field is never automatically treated as trustworthy. Duplicate batch-local order values remain ambiguous.

## Permutation severity

For trustworthy same-second groups the corpus measures not only whether magnitude sorting changes the value sequence, but how far the observed sequence is from ascending magnitude order:

- reordered group count and fraction;
- reordered intervals;
- pairwise value inversions;
- possible unequal-value inversions;
- normalized inversion fraction;
- maximum inversion count in one group;
- maximum trustworthy group size.

This is important because a single adjacent swap and a heavily permuted group should not be treated as the same exposure.

## HRV effect

Current and historical-magnitude order are evaluated over the **same stored row multiset** using the same production analyzer.

Paired effects are recorded for:

- RMSSD;
- SDNN;
- mean NN;
- pNN50;
- raw RMSSD;
- raw pNN50.

Raw mean NN and raw SDNN are also retained as audit invariants. Reordering an identical multiset cannot change either. A violation is an implementation error and is counted explicitly.

## Cleaning interactions

Because the Malik local-median filter itself depends on neighbourhood order, the counterfactual may change which intervals survive cleaning. The corpus therefore records for both paths:

- actual cleaned intervals;
- production `nClean`;
- rejected count/fraction;
- contiguous cleaned successive-pair count;
- production beat-gate status.

A session where clean counts differ is flagged separately from one where only the successive-difference order changes.

## Schema and reproducibility

Corpus record schema: **v2**.

Each record carries both:

- `schemaVersion` for the corpus envelope;
- `auditSchemaVersion` for the nested R-R audit.

The summarizer fails closed when either does not match its compiled implementation. This avoids silently aggregating incompatible historical definitions.

`observationKey` is deterministic within one corpus run:

```text
device-key:detected-start:end
```

Duplicate keys fail closed so concatenating a file twice cannot silently double-weight nights.

The run summary includes SQLite `PRAGMA user_version` for reproducibility context, while the session output remains aggregate-only.

## Privacy

The default device key is invocation-local and pseudonymous (`device-001`, etc.). Raw database device IDs are included only when the caller explicitly requests `--include-device-id`.

Raw device IDs are never propagated into the aggregate summary, even if present in input JSONL.

Raw R-R rows and the interval sequence are never exported.

## Recommended corpus collection

For a useful project-level analysis, collect:

- multiple nights per device;
- multiple devices/wearers where contributors voluntarily provide aggregate output;
- both pre- and post-order-migration nights when available;
- WHOOP generations/firmwares as separate metadata outside the anonymous corpus if hardware context is being studied;
- short/naps as a deliberately separate run if desired.

Do not concatenate independent corpus runs that reuse `device-001` pseudonyms and then treat that key as a cross-run person identifier. Pseudonyms are intentionally invocation-local.

## Interpretation sequence

The analysis should be read in this order:

1. **Coverage:** How many sessions have sufficient production HRV and how much order is trustworthy?
2. **Integrity:** How many sessions are complete, partial, or ambiguous?
3. **Permutation:** How common/severe is magnitude-order disagreement where order is known?
4. **Cleaning:** Does order change which beats survive the production cleaning pipeline?
5. **Effect:** What are paired metric deltas?
6. **Uncertainty:** How wide are the descriptive bootstrap intervals?
7. **Strata:** Are effects concentrated in low-coverage, short, or sparse-staging sessions?
8. **Downstream sensitivity:** Would the HRV change cross Readiness HRV signal boundaries or materially move the isolated Charge HRV contribution?

Only after those questions are answered should NOOP consider a product policy such as a confidence label or withholding gate.

## Stop conditions

Do not infer a production policy from the corpus when:

- only one user/device is represented;
- paired production-HRV count is very small;
- raw mean/SDNN invariants fail;
- effects are driven entirely by sessions already structurally ambiguous;
- device/firmware changes confound the before/after periods;
- score-sensitivity analysis lacks enough prior nights to build the same baseline spine as the product.

The correct result in those cases is “more evidence needed,” not an invented threshold.
