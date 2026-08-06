# Phase 6 V9 Strategy Tester tail-reconciliation method

Frozen before V9 probes: `2026-08-03T10:51:27Z`.

V8 remains valid historical evidence with outcome `FAIL_TESTER_REAL_TICK_PROBE`, commit `00b011134fcfdbcb0e7ca6820f541b54e34085c0`, and history identity `dcd2f489cc6bd06f6a6e3bc3644179f4348cd54ea7dbad52819611008e2b7f26`. V9 does not edit or replace V4–V8.

The V8 exact-stream-equality assumption is corrected prospectively: connected `CopyTicksRange`, tester-visible `CopyTicksRange`, and tester `OnTick` are treated as distinct streams. A divergence may be accepted only after its exact scope and bar impact are proven. Research remains `[2025-01-02 00:00:00,2025-12-24 00:00:00)` for this capability reconciliation; guard-tail ticks at or after the cutoff are never research observations.

## Probes

- A: `[2025-01-02 00:00:00,2025-12-24 00:00:00)`
- B: `[2025-01-02 00:00:00,2025-12-25 00:00:00)`
- C: `[2025-12-23 00:00:00,2025-12-25 00:00:00)`

All tester probes use H1 and model code 4, “Every tick based on real ticks.” Entry, execution, position-management, and strategy-order inputs are false. Any generated-tick fallback, order, position, non-balance deal, or trade transaction fails the affected probe.

## Deterministic bounded-memory hash

Each `COPY_TICKS_ALL` tick is encoded as one UTF-8 record:

`time_msc|bid(10dp)|ask(10dp)|last(10dp)|volume|flags|volume_real(10dp)\n`

Records are accumulated in fixed 256-tick chunks. A chunk digest is SHA-256 of its exact UTF-8 bytes. A scope chain starts as SHA-256 of `SOLTRADE_PHASE6_V9_STREAM_V1|<scope>|<key>` and is advanced as SHA-256 of `prior_hex|chunk_ordinal|chunk_count|first_time_msc|last_time_msc|chunk_hex`. Probe and source labels are deliberately excluded from the digest so byte-identical streams compare equal. The reported scope hash is the final chain. Scope boundaries force a chunk flush. Memory is bounded by one 256-record buffer per active scope plus one daily `CopyTicksRange` array.

Instrumentation note frozen at `2026-08-03T11:03:22Z`: the first connected attempt was stopped before producing any stream hash because 4,096-record MQL string concatenation was operationally unbounded. No partial hash or data conclusion was used. Chunk size was reduced to 256; canonical records, scopes, source data, and all acceptance conditions are unchanged. All reported V9 evidence must use the 256-record implementation.

Hashes and counts are recorded for the complete probe, every intersecting calendar month, the prefix before `2025-12-23 23:00:00`, research-final day `[2025-12-23,2025-12-24)`, final H1 `[2025-12-23 23:00,2025-12-24)`, and final M1 `[2025-12-23 23:59,2025-12-24)`. Guard-tail `[2025-12-24,2025-12-25)` is separate.

Tester `OnTick` unique minute buckets are compared with tester M1 `CopyRates` counts to detect a bar with no runtime real tick. Tester M1 `2025-12-23 23:59` and H1 `2025-12-23 23:00` OHLC, tick volume, and spread are compared with V8’s directly tick-derived bars. First and final database/runtime ticks are recorded separately.

No strategy statistic is computed. No V9 evidence can authorize the strategy matrix or Phase 7.
