# Trend Breakout V1 versus V2 change register

| Area | V1 | Frozen V2 | Evidence-based purpose |
|---|---|---|---|
| Entry trigger | One completed close beyond Donchian 20 and on the permitted side of EMA 200 | Same event creates a setup only | Prevent one-candle breakouts from immediately becoming positions |
| Confirmation | None | Next completed H1 candle must continue beyond the setup close, frozen channel boundary and EMA 200 | Addresses the 48/94 stop-loss exits and 43 stops within 24 hours |
| Setup lifetime | Not applicable | Exactly one following completed market H1 candle | Prevent stale or discretionary confirmation |
| EMA filter | Price must be on correct side of EMA 200 at entry signal | Price-side test must pass on setup and confirmation | Ensures persistence remains in the original trend-filter direction |
| EMA extension | No maximum distance | Confirmation close must be no farther than 2 ATR14 from EMA 200 | Addresses concentration of loss among entries already at least 2 ATR from EMA; prevents confirmation from buying/selling unlimited extension |
| Volatility filter | ATR 14 used for stop, but no normalized regime guard | ATR14 divided by its preceding 100-value mean must be from 0.50 through 2.00 | Broad deterministic data/regime sanity guard; not a searched profit threshold |
| Minimum history | 222 completed bars | 300 clean segment-local completed bars | Supports EMA 200 and 100 completed ATR observations without pre-segment contamination |
| Entry timing | First tradable tick after the one-bar signal | First tradable tick after the confirmation candle | Implements persistence without intrabar lookahead |
| Donchian exit | Strict completed-close Donchian 10 exit | Unchanged | V14 Donchian-exit subsets were positive; changing them is not evidence-justified |
| Initial stop | 2 × ATR14 | Unchanged multiple, calculated from confirmation candle ATR14 | Full-stop frequency is addressed by entry quality, not by retroactively optimizing stop width |
| Trading hours | Any valid broker session | Unchanged | Hour/weekday groups were small and inconsistent; a time filter would be data mining |
| Risk per trade | 0.25% equity | Unchanged | Risk containment worked correctly |
| Daily/weekly/emergency limits | 1.0% / 2.5% / 5.0% | Unchanged | Frozen risk limits passed |
| Consecutive-loss pause | Three losses; next-broker-day release | Unchanged | Approved risk behavior remains intact |
| Position count | One SolTrade position | Unchanged | Approved safety boundary |
| Spread | Stricter of 30 points and 10% ATR | Unchanged | Spread was not the primary loss cause |
| Exit management | One synchronous attempt, no uncontrolled retry | Unchanged | Approved PositionManager behavior |
| State | V1 signal/execution/risk state | New isolated V2 setup state plus existing approved execution/risk state | Prevent V1/V2 state collisions and duplicate confirmation entries |
| Strategy identifier | Trend Breakout V1 / 1.0.0 | `SOLTRADE_TREND_BREAKOUT_V2_1_0` | Makes the frozen rule set auditable and non-overwriting |

Unchanged prohibitions include martingale, grid, averaging, machine learning, adaptive searching, hidden optimization, take-profit invention and uncontrolled retries.
