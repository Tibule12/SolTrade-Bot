# Phase 6 V12 methodology amendment audit

V12 resolves the V11 conceptual run-count, open-position disposition, delay-axis and Normal profit-factor conflicts. The proposed formal matrix remains 18 cells assembled from 36 isolated physical Strategy Tester subruns.

The pre-run audit nevertheless fails before compilation or strategy execution. No profitability result was produced or viewed.

## Accepted V12 resolutions

- Six dataset/clean-segment intersections are independent physical research intervals.
- Every physical subrun starts from USD 10,000 with fresh isolated EA, risk, execution and position state.
- A position open at the final eligible tick is right-censored, has no invented exit, contributes no formal P&L and is excluded from closed-trade statistics.
- Matrix cells are reconstructed chronologically from realized net R and a synthetic USD 10,000 equity curve risking 0.25% per trade.
- Native execution uses `ExecutionMode=0`; replicas use `ExecutionMode=200`. MetaTrader's official configuration semantics define `0` as normal/no delay and positive values as milliseconds.
- The Normal profit-factor gate is strictly `> 1.15`.

## Unresolved pre-run blockers

1. **Self-referential seed freeze.** V12 requires hashing the completed manifest, deriving seeds from that hash, and then storing the seeds in the same completed manifest. Inserting the seeds changes the manifest and its SHA-256. No canonical seed-basis projection or fixed-point rule is defined.
2. **V10 indicator-reset equivalence is not guaranteed by starting a new EA.** Production evaluation requires a 221-bar clean window. V10 deliberately skips the first 20 eligible bars after each 200-bar quarantine until 221 post-reset bars exist. MT5 makes pre-test history available to `CopyRates`; a new subrun at the eligible boundary can therefore read pre-gap bars and evaluate values V10 excluded.
3. **Intraday physical boundaries are not executable from the frozen INI definition alone.** MT5's documented `FromDate` and `ToDate` configuration fields are dates and tests start/end at 00:00. Four V12 boundaries are intraday. No frozen tester-only stop/control method is defined, so an open position can receive post-boundary ticks or an SL event before tester termination.
4. **Right-censor capture is not implemented in the frozen reporter.** MT5 closes open positions at test termination. The existing reporter reconstructs any exit deal as naturally closed and reconciles to native tester profit. It does not preserve a pre-forced-close position snapshot or separate tester-forced closure from a Phase 5 close.
5. **Native-delay representation conflicts with the frozen research configuration.** `ResearchFrozenDelayMs` currently rejects zero and the canonical artifact hard-codes `tester_execution_delay_mode=FIXED`. A native `ExecutionMode=0` run cannot be truthfully represented without a Phase 6-only configuration/reporting amendment.
6. **FP Markets Raw commission settings are not frozen.** Earlier cost evidence defines supplementary multipliers and native-friction formulas, but no immutable FP Markets Strategy Tester commission configuration exists. Using a terminal default or current broker schedule would invent a required friction input.

These items require an explicit, pre-performance specification amendment. V12 therefore terminates as `INVALID_TEST_EVIDENCE`. The tag `phase6-v12-matrix-prerun` is deliberately not created because V12 reserves it for a successful audit.

Official tester references used for configuration validation:

- https://www.metatrader5.com/en/terminal/help/start_advanced/start
- https://www.metatrader5.com/en/terminal/help/algotrading/testing
- https://www.metatrader5.com/en/terminal/help/algotrading/tick_generation
