# Phase 6 V10 terminal outcome

`TESTER_BAR_SIGNAL_EQUIVALENCE_PASSED`

The inert FP Markets tester run used H1 and “Every tick based on real ticks” over `[2025-01-02,2025-12-25)`. The V10 controller window reported real-tick generation and no generated-tick fallback. It delivered 6,121 runtime H1 hours and 366,685 unique runtime minutes; the latter exactly matched 366,685 tester M1 bars. The pre-cutoff export contains exactly the 6,097 V8 Source A timestamps and no Dec 24 guard bar.

All 5,252 eligible H1 timestamps exist in both sources. After normalization to the EURUSD `0.00001` point, 5,252 bars match exactly, with zero OHLC mismatches, zero missing bars, and zero extra bars. All 6,097 pre-cutoff bars used as potential indicator inputs also match at point precision.

Both independent signal-only streams applied the frozen Trend Breakout V1 calculation and the same one-position state model. Each evaluated 5,191 eligible decisions and emitted 211 state-approved signal records: 53 BUY, 54 SELL, 50 EXIT_LONG, and 54 EXIT_SHORT. Timestamps, directions, entry/exit types, segment identifiers, and state transitions match exactly. Complete divergence count is zero, and every recorded EMA, ATR, Donchian, and two-ATR stop-distance delta is `0.0`, within the preregistered `1e-12` tolerance.

The three unresolved gaps, five contaminated H1 bars, 200 clean post-gap warm-up bars per gap, 600 total post-gap warm-up bars, four clean-segment boundaries, and all state resets remain intact. No state crosses a gap. Development, validation, and OOS eligible counts remain 2,526, 1,238, and 1,488.

The guard tail makes the final pre-cutoff H1 bar complete: `2025-12-23 23:00`, OHLC `1.17890 / 1.17960 / 1.17878 / 1.17938`, with 918 runtime ticks from `23:00:00.628` through `23:59:59.877`. The 24 Dec 24 bars and every guard-tail signal are excluded. The final bar's nominal evaluation time is the cutoff itself and is therefore also excluded from research signals.

The probe recorded zero orders, historical orders, positions, non-balance deals, trade transactions, and trade API calls. No formal strategy matrix, replica, optimization, profitability calculation, or Phase 7 action occurred. Phase 1–5 logic and all V4–V9 evidence remain unchanged.

V10 passing does not authorize the strategy matrix or Phase 7. Separate approval remains mandatory.
