# V3.0 versus V3.1 change register

| Field | V3.0 | V3.1 | Status |
|---|---:|---:|---|
| Specification | `TREND_BREAKOUT_V3_RETEST_HOLD_1_0` | `TREND_BREAKOUT_V3_RETEST_HOLD_1_1` | Versioned amendment |
| ATR spread fraction | `0.10` | `0.20` | **Only behavioral change** |
| Absolute spread ceiling | 30 points | 30 points | Unchanged |
| Entry opportunity | First real tick, once | First real tick, once | Unchanged |
| Retry or waiting | None | None | Unchanged |
| All signal, stop, exit, sizing, risk and state rules | Frozen V3 | Frozen V3 | Unchanged by immutable reference |
| Formal OOS acceptance window | Retired three-month interval | Fresh dynamic 50-cycle interval, hard maximum one year | Research-plan correction; not a trading-rule change |

No threshold alternatives were compared. No V3.0 artifact was overwritten.
