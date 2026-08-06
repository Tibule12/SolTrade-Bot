# Trend Breakout V3.1 isolated research implementation

`SolTradeV31TesterHarness.mq5` is a tester-only theoretical state machine. It never imports or calls a trade API. `SolTradeV31RestartFixtures.mq5` exercises the versioned persistence field set. Both are isolated from released production sources.

The harness fails initialization when its eligible interval crosses the `2026-08-01 00:00:00` research cutoff and rejects ticks at or beyond it. Its outputs contain only signals, state transitions, spread decisions, and structural exits.
