# Trend Breakout V2 unseen-data research plan

## Current boundary

V15 freezes design only. It does not authorize implementation, compilation, Strategy Tester execution, profitability calculation, demo-forward testing, live trading or Phase 7.

The next phase must first qualify FP Markets EURUSD real-tick history for the proposed 2026 interval. No V2 signal or profitability result may be viewed during data qualification.

## Data roles

- 2025 V14 evidence: V1 diagnosis and V2 design/development only. It can never be relabelled as unseen V2 validation or OOS evidence.
- Frozen V2 Development segments, if later authorized, are the existing qualified 2025 segments: D1 `[2025-01-16 00:00, 2025-02-05 00:00)`, D2 `[2025-02-18 05:00, 2025-03-07 23:00)`, and D3 `[2025-03-21 04:00, 2025-07-05 00:00)`. Their aggregate is Development only and cannot change V2 rules.
- Proposed 2026 qualification interval: `[2026-01-02 00:00, 2026-07-01 00:00)`, start inclusive and end exclusive.
- Proposed indicator warm-up: `[2026-01-02 00:00, 2026-01-16 00:00)`; no orders or statistics.
- Unseen validation: `[2026-01-16 00:00, 2026-04-09 00:00)`.
- Unseen OOS: `[2026-04-09 00:00, 2026-07-01 00:00)`.

These dates were selected before any 2026 V2 profitability result. If FP Markets cannot supply continuous qualified real ticks and M1 verification bars for the whole interval, qualification must fail closed. A versioned date amendment based only on data availability would require review before any V2 result is viewed.

If later authorized after qualification and implementation gates, the research matrix will aggregate the three 2025 Development segments and compare them with the single 2026 Validation and OOS periods. Each formal dataset/cost/execution cell is a physical Strategy Tester run per clean segment, with Development aggregated only after the D1–D3 evidence passes. Results may be reported but may not be used to change the frozen V2 rules.

## Qualification gate

Qualification must preserve the V7–V10 evidence disciplines:

- isolated `$HOME/.wine-fpmarkets` source, `FPMarketsSC-Demo`, exact EURUSD specification;
- real ticks only, with generated-tick fallback rejected;
- complete beginning and ending coverage;
- real-tick and tick-derived/M1 bar identity, gaps, session conflicts, timezone and DST evidence;
- terminal build, broker server, symbol sessions and immutable aggregate history hash;
- actual first/final ticks and warm-up ticks reported separately;
- retrieval or memory errors fail the affected qualification;
- no strategy EA run during qualification.

## Pre-result implementation gates

After data qualification and separate authorization:

1. implement the exact frozen V2 specification in a new versioned strategy module without editing V1;
2. add deterministic unit tests for every equality boundary, setup expiry, two-candle confirmation, ATR regime boundary, EMA-extension boundary, completed-candle rule and restart state;
3. re-run all Phase 1–5 regression tests with zero failures;
4. compile every affected target with zero errors and zero warnings;
5. prove tester-only environment gates, isolated state and no optimization;
6. commit source and canonical trading-input hashes before viewing any 2026 V2 profitability result.

## Frozen research gates

The following gates are frozen now and may not be relaxed after results:

- Normal: profit factor strictly greater than 1.15, adjusted net profit greater than zero, expectancy greater than zero, relative drawdown less than 8%;
- High: profit factor at least 1.05, adjusted net profit greater than zero, expectancy greater than zero, relative drawdown at most 10%;
- Stress: profit factor at least 1.00, adjusted net profit greater than zero, expectancy greater than zero, relative drawdown at most 12%;
- best-trade contribution at most 20%;
- best registered subperiod contribution at most 40%;
- at least 50 naturally closed unseen OOS trades; fewer is `INCONCLUSIVE_INSUFFICIENT_SAMPLE` and must not cause rule changes merely to increase count;
- normalized expectancy minimum-to-maximum ratio across Development/Validation/OOS at least 0.50 when defined;
- annualized-return minimum-to-maximum ratio at least 0.50 when defined;
- profit-factor range across Development/Validation/OOS at most 0.40;
- any missing report, mismatch, history change, state collision or fixed-delay reproduction failure invalidates the affected run.

The Normal, High and Stress supplementary multipliers remain 0.00, 0.50 and 1.00. External commission remains USD 3 per side per standard lot only if native commission is proven zero; native friction must never be subtracted twice. A native execution layer and fixed 200 ms replica layer remain required. Right-censored positions remain separately reported and excluded from naturally closed statistics.

Bootstrap and Monte Carlo analyses remain reporting-only with the existing assumptions and must not affect V2 decisions.

## Advancement rule

Phase 7 remains unauthorized unless qualified, immutable V2 evidence meets every mandatory evidence, sample, performance, concentration and consistency gate. Passing data qualification alone cannot authorize the strategy matrix or Phase 7.
