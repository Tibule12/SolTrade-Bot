# FXIFYInactivityGuard configuration

This is a separate EA. It neither includes nor calls V28 code. The default symbol `EURUSD` resolves first as an exact broker symbol and then as `EURUSD.r`, matching the captured FXIFY RAW specification.

Captured specification source: `reports/backtests/fxify-2phase-pro-10k-v28-rule-simulation/final-raw-lifecycle-completion/raw-specification-capture/raw-symbol-specifications.csv`. The EURUSD RAW snapshot records `.r`, 0.01 minimum/step volume, 100-lot maximum, 5 digits, 0.00001 point/tick size, USD 1 tick value per lot, zero stops/freeze levels, and a 0.6-pip snapshot spread. The live snapshot is not historical spread evidence.

| Input | Default | Purpose |
|---|---:|---|
| `GuardEnabled` | `true` | Enables monitoring. |
| `WarningDay` | `45` | First elapsed-calendar-day alert. |
| `MaintenanceDay` | `50` | First safe maintenance-entry attempt. |
| `CriticalAlertDay` | `55` | Critical escalation if no entry has executed. |
| `MaintenanceSymbol` | `EURUSD` | Canonical symbol; `.r` is the captured RAW suffix fallback. |
| `MaximumVolume` | `0.01` | Hard cap; broker minimum is used and must not exceed this. |
| `StopLossPips` | `10.0` | Real server-side stop distance, rounded to tick size and broker minimum. |
| `TakeProfitPips` | `5.0` | Small real server-side take-profit. |
| `MaximumHoldingMinutes` | `60` | Time-based close trigger. |
| `MaximumSpreadPips` | `1.5` | Entry refusal above this spread. |
| `MaximumSlippagePips` | `1.0` | Deviation limit and projected-risk component. |
| `EstimatedCommissionPerLot` | `6.0` | Official RAW Forex round-turn commission estimate. |
| `MaximumStopRiskUSD` | `1.10` | Hard cap on stop-only risk after broker-distance adjustment. |
| `MaximumProjectedLossUSD` | `2.0` | Cap including stop, spread, slippage, and commission. |
| `ReferenceInitialBalance` | `10000.0` | FXIFY static-loss reference. |
| `DailyLossLimitPercent` | `4.0` | Daily floor percentage at fixed 17:00 UTC-5 boundary. |
| `MaximumLossLimitPercent` | `8.0` | Static maximum-loss percentage. |
| `LossLimitSafetyBuffer` | `50.0` | USD clearance required above both loss floors. |
| `GuardMagicNumber` | `608055001` | Dedicated order/deal identity. |
| `GuardOrderComment` | `FXIFY_INACT_GUARD` | Dedicated order/deal/log comment. |
| `RetryIntervalMinutes` | `15` | Safe-condition recheck interval after day 50. |
| `DryRunMode` | `true` | Calculates and logs but cannot send orders. |

Direction is independent of V28: BUY when the last completed EURUSD H1 candle closes at or above its open; otherwise SELL.
