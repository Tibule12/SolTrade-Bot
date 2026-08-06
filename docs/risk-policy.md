# Risk Policy

Trend Breakout V1 uses conservative, non-negotiable defaults:

- 0.25% of current equity at risk per trade;
- one SolTrade position in total;
- 1% daily equity-loss lock;
- 2.5% weekly equity-loss lock;
- 5% emergency drawdown from a fixed approved production baseline;
- pause after three consecutive losing trades until the next broker day;
- absolute and ATR-relative spread limits;
- a compulsory initial stop at 2 × ATR(14);
- no fixed lot size, martingale, grid, averaging down, or recovery sizing.

The risk engine has veto authority over the strategy. A strategy signal is only a
request for evaluation and creates no entitlement to a trade.

Phase 2 implements these formulas and lock states. Its deterministic acceptance
cases are in `tests/risk-engine-calculation-cases.md`, and no execution work may
begin until both MQL5 files compile with zero warnings and the test script passes.
