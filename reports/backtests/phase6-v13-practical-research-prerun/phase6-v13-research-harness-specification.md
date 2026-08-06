# Phase 6 V13 research harness specification

`SolTradePhase6V13ResearchHarness.mq5` is tester-only and imports the released `StrategyBreakout.mqh`; it does not duplicate the Trend Breakout V1 calculation. Verification refuses optimization, non-FPMarketsSC-Demo servers, symbols other than EURUSD, timeframes other than H1, `PermitOrders=true`, or `CalculateProfitability=true`.

The harness stores only fully completed H1 bars whose timestamps are in `[ResetAt, EligibleTo)`. It evaluates the released strategy only after 221 segment-local bars are present and only for signal bars in `[EligibleFrom, EligibleTo)`. An OnTick cutoff guard runs before new-bar processing. Signal output contains the exact EMA, ATR, Donchian levels, entry/exit decisions, reason codes and signal-only state transition. No trade request API is called.

The production risk, execution and PositionManager modules remain unchanged. They were not called in V13 because the requested verification prohibits strategy trades and P/L. A later separately authorized matrix integration must reuse those approved production modules and must not duplicate or alter their decisions.
