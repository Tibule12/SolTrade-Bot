# Configuration Model

## Principles

- Inputs are typed MQL5 `input` parameters and become an immutable
  `SolTradeConfig` snapshot at initialisation.
- Invalid settings stop initialisation.
- Runtime account detection cannot be overridden by configuration.
- Live permission is default-deny and requires all gates.
- Strategy and risk settings remain identical between tester, demo, and live;
  only environment approval values may differ.
- Secrets and broker credentials are never configuration fields.

## Phase 6 input groups

### Identity

| Input | Default | Validation/purpose |
|---|---|---|
| `StrategyVersion` | `1.0.0` | Trend Breakout V1 release identity |
| `ApprovedStrategyVersion` | empty | Must exactly match for future live permission |
| `RiskProfile` | `CONSERVATIVE_V1` | Non-empty configured policy identity |
| `ApprovedRiskProfile` | empty | Must exactly match for future live permission |
| `MagicNumber` | `2607202601` | Positive and unique to SolTrade |

### Market

| Input | Default | Validation/purpose |
|---|---|---|
| `TradeSymbol` | `EURUSD` | Must exist and be selectable |
| `SignalTimeframe` | `PERIOD_H1` | Version 1 requires H1 |
| `MinimumHistoryBars` | `222` | Forming bar plus the fixed 221 completed-bar strategy window |
| `MaxTickAgeSeconds` | `120` | Positive stale-price threshold |
| `MaxSpreadPoints` | `30` | Risk Engine absolute spread gate |
| `MaxSpreadAtrPercent` | `10.0` | Risk Engine ATR-relative spread gate |
| `MaxSlippagePoints` | `10` | Maximum deviation included in the one market request |

### Risk policy

| Input | Default | Validation/purpose |
|---|---|---|
| `RiskPerTradePercent` | `0.25` | `(0, 1]` |
| `DailyLossLimitPercent` | `1.0` | `(0, 100)` |
| `WeeklyLossLimitPercent` | `2.5` | `(0, 100)` and not below daily |
| `EmergencyDrawdownPercent` | `5.0` | `(0, 100)` and not below weekly |
| `ProductionBaselineEquity` | `0.0` | Required and positive before future live approval |
| `ConsecutiveLossLimit` | `3` | Positive |
| `ResetEmergencyLock` | `false` | Explicit request to clear a latched emergency lock; it immediately re-locks if equity remains below threshold |

Phase 5 retains the approved risk calculations and lock state. Position size is
calculated from current equity and the final tick-normalised stop distance
before the execution gateway can submit.

### Environment safety

| Input | Default | Purpose |
|---|---|---|
| `ExpectedEnvironment` | `AUTO_DETECT` | Optional strict assertion |
| `EnableDemoExecution` | `false` | Explicit opt-in for connected demo orders |
| `EnablePositionManagement` | `false` | Independent explicit opt-in for connected-demo position closing |
| `ApprovedDemoAccount` | `0` | Exact demo login required when either demo capability is enabled |
| `AllowLiveTrading` | `false` | Must remain false; true is rejected in Phase 5 |
| `ApprovedLiveAccount` | `0` | Reserved for a later formally approved live phase |
| `EmergencyStop` | `false` | Blocks entries and requests emergency closure of an owned SolTrade position when management is enabled |

The `AUTO_DETECT` setting means “accept the detected environment”; it does not
select an environment. Any explicit mismatch stops normal readiness and is
journaled.

### Operations

| Input | Default | Purpose |
|---|---|---|
| `EnableCsvJournal` | `true` | Required for normal initialisation |
| `JournalDirectory` | `SolTradeBot\\logs` | Relative MT5 file-sandbox directory |
| `RiskStateDirectory` | `SolTradeBot\\state` | Relative directory for account/magic-scoped persistent risk state |
| `ExecutionStateDirectory` | `SolTradeBot\\state` | Relative directory for atomically persisted consumed-candle/request state |
| `EnableDashboard` | `true` | Enables the read-only chart panel |
| `DashboardRefreshSeconds` | `1` | Timer/refresh interval |

The production baseline remains optional for demo execution, where `0` means
the emergency percentage is not armed. It is mandatory for future live
approval. Demo entry and position-management opt-ins are independent, but each
requires the exact approved demo login.

## Versioning

A compiled release records its strategy version in configuration and every log
row. Production release metadata must later include the source commit. Changing
settings creates a new test configuration and must be recorded in test reports;
environment parity does not permit silent parameter changes.

### Phase 6 tester research

All three capability inputs default false. When research is enabled,
`ExpectedEnvironment` must be `BACKTEST`; tester execution and position
management must be enabled together; demo/live approvals must be zero/off.

| Input | Required meaning |
|---|---|
| `ResearchManifestId` | Safe reviewed manifest identity |
| `ExecutionInstanceId` | Unique non-trading state/artifact namespace |
| `ResearchDataset` | Development, Validation, or Out of Sample |
| `ResearchCostProfile` | Normal, High, or Stress |
| `ResearchStartInclusive` / `ResearchEndExclusive` | Exact registered interval |
| `ResearchHistoryFingerprint` | Frozen history inventory SHA-256 |
| `ResearchLatencyFingerprint` / sample count | Raw latency evidence SHA-256 and at least 30 observations |
| `ResearchFrozenDelayMs` | Fixed delay, at least 100 ms and aligned to 50 ms |
| `ResearchSourceCommit` / build fingerprint | Git identity plus exact EA-and-Include source aggregate |
| terminal/server/deposit/currency/leverage fields | Exact tester runtime contract |
| `ResearchExpectedTradingInputHash` | Canonical SHA-256 expected at initialization |
| state/artifact roots | Safe relative roots; excluded from trading identity |

`ExecutionInstanceId` and its roots do not enter the canonical trading material.
They are allowed to change only for clean state and artifact isolation. A
non-empty instance namespace rejects initialization.
