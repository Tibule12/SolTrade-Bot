# Fast Multi V2.200 — preserved admission regression

Classification uses only evidence available at entry. MFE is displayed as a regression observation and is never an input to a gate.

Counts: ACCEPT 0, REJECT 6, UNKNOWN 8.

| Trade | Symbol | Direction | Classification | Exact gate | Score / no-trade | Spread ATR % | Reward R | MFE R (unused) |
|---:|---|---|---|---|---:|---:|---:|---:|
| 1 | XAUUSD.r | SELL | UNKNOWN | INSUFFICIENT_RETAINED_PRE_ENTRY_EVIDENCE | 84.51 / 36.00 | 1.14 | 1.601 | 0.968 |
| 2 | XAUUSD.r | SELL | REJECT | SAME_SYMBOL_CHURN_COOLDOWN | 68.89 / 12.00 | 3.93 | 1.315 | 0.003 |
| 3 | US100 | BUY | UNKNOWN | INSUFFICIENT_RETAINED_PRE_ENTRY_EVIDENCE | 74.43 / 12.00 | 3.09 | 1.271 | 1.393 |
| 4 | GER40 | BUY | UNKNOWN | INSUFFICIENT_RETAINED_PRE_ENTRY_EVIDENCE | 81.35 / 12.00 | 3.10 | 1.358 | 0.000 |
| 5 | US100 | BUY | REJECT | SAME_SYMBOL_CHURN_COOLDOWN | 93.33 / 36.00 | 3.04 | 1.332 | 0.324 |
| 6 | XAUUSD.r | SELL | UNKNOWN | INSUFFICIENT_RETAINED_PRE_ENTRY_EVIDENCE | 82.98 / 36.00 | 2.84 | 1.254 | 2.069 |
| 7 | XAGUSD.r | SELL | REJECT | HIGH_SPREAD_RELATIVE_TO_M5_ATR | 69.69 / 36.00 | 17.08 | 1.409 | 0.926 |
| 8 | US100 | BUY | UNKNOWN | INSUFFICIENT_RETAINED_PRE_ENTRY_EVIDENCE | 79.28 / 12.00 | 2.02 | 1.311 | 2.761 |
| 9 | GER40 | BUY | UNKNOWN | INSUFFICIENT_RETAINED_PRE_ENTRY_EVIDENCE | 75.41 / 12.00 | 2.48 | 1.333 | 1.033 |
| 10 | GER40 | BUY | REJECT | SAME_SYMBOL_CHURN_COOLDOWN | 107.90 / 12.00 | 2.50 | 1.323 | 0.822 |
| 11 | GER40 | BUY | REJECT | SAME_SYMBOL_CHURN_COOLDOWN | 75.55 / 12.00 | 3.03 | 1.401 | 0.352 |
| 12 | GER40 | BUY | REJECT | SAME_SYMBOL_CHURN_COOLDOWN | 70.15 / 36.00 | 2.95 | 1.276 | 1.061 |
| 13 | US100 | BUY | UNKNOWN | INSUFFICIENT_RETAINED_PRE_ENTRY_EVIDENCE | 103.40 / 36.00 | 2.99 | 1.324 | 0.134 |
| 14 | XAUUSD.r | SELL | UNKNOWN | INSUFFICIENT_RETAINED_PRE_ENTRY_EVIDENCE | 73.56 / 36.00 | 1.49 | 1.259 | 0.051 |

UNKNOWN is mandatory where the old V3 audit did not retain the new absolute-score components, nearest-opposing-swing selection, impulse/breakout extension, or setup-specific confirmation timing. No future outcome was substituted.
