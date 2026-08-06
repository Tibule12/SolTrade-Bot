# V2 confirmation-filter bottleneck analysis

This attribution uses only previously qualified 2025 tick-derived data. The historical date slices are partition equivalents for comparison, not unseen V2 evidence. No rejected setup was evaluated as a winner or loser.

- Largest individual rejection: `ema_distance_at_most_2_atr` (295 setups).
- Largest exclusive rejection: `ema_distance_at_most_2_atr` (89 setups).
- Most common failed-condition combination: `ema_distance_at_most_2_atr|risk_or_spread_entry_state` (49 setups).
- Continued next-candle direction failed 196 setups. The dominant measured bottleneck is `ema_distance_at_most_2_atr`; therefore the immediate confirmation persistence requirement is not the sole main reason for the low confirmation rate.
- BUY's largest failure is `ema_distance_at_most_2_atr` (209/246); SELL's is `ema_distance_at_most_2_atr` (86/119). This shows a shared dominant mechanism.
- Multiple filters failed together on 248 rejected setups, while 112 had one exclusive failure. Overlap demonstrates partial redundancy; non-zero exclusive counts demonstrate that independently restrictive filters also remain.

## Structural connection to the V1 failure mechanism

The immediate-next-candle and continued-direction tests are directly connected: they demand immediate persistence after breakouts that previously reversed before follow-through. Remaining beyond the frozen Donchian boundary is also direct persistence evidence. The EMA-side test preserves trend direction and is indirectly connected. The two-ATR EMA-distance cap limits overextended entries and is indirectly connected to reversal risk. The ATR-regime band is a market-data/volatility sanity guard rather than direct proof of persistence. Equality rejection supplies deterministic strictness rather than a separate economic hypothesis. The 300-bar rule protects indicator integrity, not the reversal mechanism. Position, spread/risk, and other no-trade guards protect operational and risk integrity rather than confirming follow-through.

No condition change is recommended here. Removing a condition to increase signals would be strategy redesign and is outside V17.
