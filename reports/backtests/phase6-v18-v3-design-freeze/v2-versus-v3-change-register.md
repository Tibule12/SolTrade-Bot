# Trend Breakout V2 versus V3 change register

| Area | Frozen V2 | Frozen V3 | Status and rationale |
|---|---|---|---|
| Strategy identity | `SOLTRADE_TREND_BREAKOUT_V2_1_0` | `TREND_BREAKOUT_V3_RETEST_HOLD_1_0` | New version and state namespace |
| Setup ATR regime | Checked at confirmation | Required at setup and retest confirmation | Explicit V3 setup-data sanity gate |
| Confirmation timing | Immediate next completed candle only | First valid retest-hold among next six completed market candles | Replaces continuation timing with evidence-based retest window |
| Directional continuation | Confirmation must continue beyond setup close | Removed | Retest confirmation need not exceed setup close |
| Frozen boundary | Confirmation close remains beyond boundary | Candle must touch/revisit boundary intrabar and close strictly beyond it | Converts breakout persistence to retest-and-hold evidence |
| EMA trend side | Strict side at setup and confirmation | Strict side at setup and retest confirmation | Retained |
| EMA distance | Confirmation within 2 ATR of EMA | Removed without replacement threshold | Avoids structural conflict with continuation; no arbitrary enlarged cap |
| ATR regime bounds | 0.50–2.00 inclusive | 0.50–2.00 inclusive | Retained, also applied at setup |
| Active setup duration | One next market candle | Six completed market candles | Frozen from V1 six-hour failure evidence |
| Same-direction breakout | Setup expires after next candle | Does not restart or extend active setup | Deterministic anti-extension rule |
| Opposite breakout | Contradictory breakout clears setup | Accepted opposite breakout cancels; may create opposite setup after full candle evaluation | Ordering specified |
| Wrong EMA-side retest close | Failed immediate confirmation | Cancels active setup | No postponement after trend-side failure |
| Risk/spread block | Cancels/no entry, no retry | Cancels/no entry, no retry | Retained |
| Initial stop | 2 × confirmation ATR | 2 × retest-confirmation ATR | Retained structurally |
| Position sizing | 0.25% equity risk | 0.25% equity risk | Unchanged |
| Exit | Completed-close Donchian 10 plus initial stop | Same | Unchanged |
| Risk limits and spread | Phase 1–5 limits; min(30 points, 10% ATR) | Same | Unchanged |
| Magic number | `2607202601` | `2607202601` | Unchanged |
| State | Versioned V2 setup state | Separate V3 namespace with retest count and terminal status | Prevents collision and restart duplication |
| Authorization | Retired, never profitability-tested | Design-only freeze; no testing in V18 | No production or trading authorization |

No other V2 or Phase 1–5 rule changes are made.
