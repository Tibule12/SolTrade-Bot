# Risk Calculation Cases

These acceptance cases govern the Phase 2 implementation. Expected monetary
values must also be checked with broker-provided symbol metadata in MetaTrader.

The implemented deterministic values for $500 and $10,000 fixtures are specified
in `risk-engine-calculation-cases.md` and executed by
`MQL5/Scripts/SolTradeRiskTests.mq5`.

| ID | Condition | Expected result |
|---|---|---|
| RC-01 | Equity 10,000; risk 0.25% | Risk budget exactly 25 account-currency units |
| RC-02 | Valid raw volume between steps | Round down to step; expected loss does not exceed budget |
| RC-03 | Raw volume below broker minimum | Reject; never round up |
| RC-04 | Raw volume above maximum | Cap only after risk recheck |
| RC-05 | Tick size/value zero or missing | Reject |
| RC-06 | Stop distance zero/negative | Reject |
| RC-07 | Buy/sell with different loss tick value | Use correct loss-side value |
| RC-08 | Broker stop level requires wider stop | Widen stop, recalculate smaller volume, or reject |
| RC-09 | Daily equity loss equals 1% | Daily lock activates at equality |
| RC-10 | Weekly equity loss equals 2.5% | Weekly lock activates at equality |
| RC-11 | Baseline loss equals 5% | Persistent emergency state and controlled-position closure required |
| RC-12 | Baseline below/equal zero | Configuration/live approval rejected |
| RC-13 | Third consecutive net losing position | Pause until next broker trading day |
| RC-14 | Duplicate deal callback | Loss counted once |
| RC-15 | Spread passes points but fails ATR ratio | Reject |
| RC-16 | Spread fails points but passes ATR ratio | Reject |
| RC-17 | Normalised expected loss exceeds budget by more than tolerance | Reduce one step or reject |
| RC-18 | NaN/infinity/overflow in any input or result | Reject and journal exact reason |
