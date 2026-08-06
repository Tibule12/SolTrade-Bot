# Phase 6 V9 terminal outcome

`FAIL_PERSISTENT_PRE_CUTOFF_TICK_DIVERGENCE`

V9 confirms that the two V8 tail ticks are deterministic Strategy Tester end-boundary behavior: Probe A omits `2025-12-23 23:59:59.369` and `.877`, while both guard-tail Probes B and C deliver them through `OnTick` and tester `CopyTicksRange`. B and C independently produce the same 39-tick final M1 and 918-tick final H1 database scopes. Extending the test through Dec 25 also moves the omission to the new terminal boundary: the tester ends at `2025-12-24 23:59:56.583`, one connected tick before `23:59:59.608`. Dec 24 remains guard-only and is not research data.

The final-bar impact is resolved. Under Probe A the missing ticks leave both final M1 and H1 closes at `1.17942`; the complete connected stream and Probes B/C close both bars at `1.17938`, a four-point difference. M1/H1 open, high, and low are unchanged; H1 high and low are therefore unaffected. The instantaneous close spread remains 19 points, and the MT5 bar spread field is unchanged across A/B/C. No completed bar before the final H1 and no V8 clean-segment boundary can be changed by those two later ticks.

V9 nevertheless fails the pre-registered pass rule. For `[2025-01-02 00:00:00,2025-12-23 23:00:00)`, connected `CopyTicksRange`, tester `CopyTicksRange`, and tester `OnTick` have the same count (20,681,349) and the same first/final timestamps, but their canonical full-record hashes do not agree. Worse, tester `CopyTicksRange` produces hash `dc5e...fd86` in Probe A and `cace...431b` in Probe B for that identical prefix. Probe C independently shows a connected/tester canonical hash mismatch in `[2025-12-23 00:00:00,23:00:00)`. The evidence does not prove that the differing canonical fields are price-irrelevant, so the divergence is not ignored or reclassified as harmless.

The V8 clean-segment counts remain recorded but are not reapproved: development 2,526, validation 1,238, and out-of-sample 1,488 eligible H1 bars. The final-H1 quarantine rule is not triggered because the two research-tail ticks are restored under both guard probes; no coverage recount is applicable. The unresolved earlier canonical divergence keeps the entire dataset and strategy matrix unauthorized.

All three probes used `COPY_TICKS_ALL` and “Every tick based on real ticks.” Their controller windows reported real-tick generation and no generated-tick fallback. Runtime unique-minute counts exactly matched tester M1 bar counts. Every probe reported zero orders, historical orders, positions, non-balance deals, and trade transactions. No strategy was loaded or run, no profitability was calculated, no optimization or replica ran, and no demo or live trade occurred.

Phase 1–5 trading logic and all V4–V8 evidence remain unchanged. The strategy matrix and Phase 7 remain unauthorized.
