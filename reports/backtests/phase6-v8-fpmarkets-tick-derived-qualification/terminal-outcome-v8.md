# Phase 6 V8 terminal outcome

## `FAIL_TESTER_REAL_TICK_PROBE`

The tick-derived construction itself passed. The connected FP Markets stream contained 20,682,267 real ticks and deterministically produced 365,245 non-empty M1 bars and 6,097 non-empty H1 bars. No bar was created for an empty bucket, and no generated, synthetic, interpolated, or forward-filled price was used.

All three unresolved gaps remain unresolved. Five overlapping H1 bars are excluded, indicator state is reset after each gap, and 200 subsequent clean completed H1 bars per gap are quarantined (600 total). The remaining manifest contains 2,526 eligible development H1 bars, 1,238 validation bars, and 1,488 out-of-sample bars.

The inert Strategy Tester controller confirmed `generating based on real ticks` and did not emit a generated-tick fallback message during the V8 run. However, the frozen expectation was an exact match to the 20,682,267 connected ticks through `2025-12-23 23:59:59.877`. The tester delivered 20,682,265 ticks and stopped at `23:59:58.664`. A connected tail query confirmed that the two omitted ticks at `23:59:59.369` and `.877` both carried changed bid/ask prices. The mismatch is preserved and the gate fails closed.

The authoritative strategy matrix remains unauthorized. No strategy run, profitability calculation, optimization, replica, demo trade, live trade, or Phase 7 action occurred. Profitability remains unknown. Phase 1–5 trading logic was not changed.

The exact derived CSVs are retained under the isolated FP Markets Wine prefix and identified by SHA-256 in the source manifest; broker tick caches and derived bulk CSVs are not committed.
