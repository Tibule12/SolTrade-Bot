# Phase 6 V10 tester-runtime bar and signal-equivalence method

Frozen before the V10 tester run: `2026-08-03T13:40:51+02:00`.

V9 remains valid historical evidence with outcome `FAIL_PERSISTENT_PRE_CUTOFF_TICK_DIVERGENCE`, commit `88757dd006d6d9589d9c0b54efdf30a8f161cdb3`. V10 does not edit or replace V4–V9. This prospective amendment was made before any strategy-profitability result was viewed.

Exact full-`MqlTick`-record hash equality is not a V10 gate. The qualification target is equality of eligible completed H1 OHLC bars at the EURUSD point (`0.00001`) and exact equality of frozen signal decisions after applying the existing quarantines and state resets. Tick volume, spread, and runtime first/final ticks remain diagnostics.

## Frozen inputs and sources

- Tester window: `[2025-01-02 00:00:00,2025-12-25 00:00:00)` using H1, model 4, “Every tick based on real ticks.”
- Research cutoff: `2025-12-24 00:00:00` exclusive.
- Source A: V8 connected-real-tick-derived H1 CSV, SHA-256 `7bebaec4b2e7e91170e9fc0ef3f6af46bb7232cb1089e094400901f4e7f820ee`.
- Source B: H1 `CopyRates` bars visible after the inert tester guard-tail run, with runtime `OnTick` first/final timestamps joined diagnostically.
- Frozen production strategy source: `MQL5/Include/SolTrade/StrategyBreakout.mqh`, SHA-256 `5a7bd101bb9c81703a08537c95664c392e1c33a07112e0e0ce2da4f6eb111555`.
- Clean-segment manifest SHA-256: `94d1fc9a32d0af1d99a67ac0150e0a9e2bfb1d7b3232d6e7b4ced3275b06caab`.
- Gap-quarantine manifest SHA-256: `97edfbb77abe30639e5e6448c537045167c9b40b5cf286ecd10a3d3a8922a03c`.

No Source B bar with timestamp at or after the cutoff is exported as research. The final research H1 bar is `2025-12-23 23:00:00`; its signal-evaluation timestamp is exactly the research cutoff, so it participates in bar equivalence but cannot create a research signal record. Guard-day ticks may complete that bar but cannot seed or alter any earlier evaluation.

## Frozen quarantine and state model

The three V8 unresolved gaps, five contaminated H1 bars, 200 successive completed clean warm-up bars after each gap, 600 total post-gap warm-up bars, and four V8 clean-segment boundaries are copied without reclassification. Strategy state is reset to flat after each unresolved gap. No bar, indicator state, or position state crosses a gap.

Both Source A and Source B are evaluated independently with a direct numerical port of `SolTradeEvaluateCompletedBars`: EMA 200; Donchian 20 entry; Donchian 10 exit; Wilder ATR 14; initial stop distance `2 × ATR`; strict lower-bound equality guard; and the production 221-completed-bar rolling history. A post-gap eligible bar with fewer than 221 clean bars since reset remains eligible for bar comparison but cannot generate a strategy event.

The one-position signal-only state begins flat in each clean segment. When flat, an approved BUY or SELL entry opens only the corresponding simulated state. When long, only `EXIT_LONG` returns it to flat; when short, only `EXIT_SHORT` returns it to flat. No same-bar reversal occurs. This state is an in-memory signal classifier only: it has no price, size, order, trade, or P&L fields and calls no trade API.

Signal records contain bar timestamp, evaluation timestamp, direction, event type, EMA, ATR, both Donchian entry and exit bounds plus the direction-relevant levels, two-ATR stop distance, and clean-segment ID. Indicator comparison tolerance is `1e-12` absolute; signal timestamps, event types, directions, and segment IDs require exact equality.

Passing requires all 5,252 eligible timestamps in both sources, OHLC equality after rounding each price to integer points, no signal divergence, intact quarantines/resets, final H1 close `1.17938`, real-tick tester mode, no fallback, no silent generated minute, and zero trading activity. Any OHLC mismatch fails even when signals agree.

No strategy matrix, replica, optimization, profitability statistic, or Phase 7 action is authorized by V10.
