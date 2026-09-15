# FP entry repair candidate — locked M1 timing gate

**Decision: `CANDIDATE_BUILT_BUT_NOT_SAFE_TO_DEPLOY`.** The M1 setup-timing rule frozen on September 3 would have rejected all four FP losses opened on September 14–15. Across all ten later FP trades, however, it retains only one of three winners and still accepts the September 8 GER40 loss. This is a concrete improvement over the deployed admission path, but it does not satisfy the rule's predeclared promotion gate.

No live account was changed. FP 7404213 and both FXIFY accounts remain on their deployed configuration and autonomous state. No live position, stop, order, risk setting or terminal was touched. No MT5 tester or historical replay ran.

## Forward result

The rule was defined before every trade in this table. Features use completed FP broker M1 bars only; the forming entry-minute bar and later bars are excluded.

| FP trade | Actual result | Production setup family | Locked timing decision |
|---|---:|---|---|
| Sep 8 AUDJPY sell | -$246.97 | Continuation | Reject |
| Sep 8 NZDUSD sell | +$93.67 | Continuation | Reject |
| Sep 8 GER40 sell | -$246.60 | Breakout | **Accept** |
| Sep 9 USDJPY sell | -$246.28 | Continuation | Reject |
| Sep 9 XAUUSD buy | +$1,088.10 | Continuation | **Accept** |
| Sep 9 GER40 sell | +$198.79 | Continuation | Reject |
| Sep 14 XAUUSD sell | -$990.00 | Continuation | Reject |
| Sep 14 USDJPY sell | -$985.77 | Continuation | Reject |
| Sep 15 US100 sell | -$975.83 | Continuation | Reject |
| Sep 15 GER40 sell | -$965.49 | Continuation | Reject |

Actual fixed-ledger net is **-$3,276.38**. Keeping only accepted trades changes that attribution to **+$841.50**. This is not a portfolio replay: rejected holdings could change later capacity, signals, equity and sizing.

The candidate rejects **6/7 losses (85.71%)** and all four losses from the current week. It retains **$1,088.10 of $1,380.56 winning cash (78.82%)**, below the locked 80% minimum, and admits one loser where the gate allowed no accepted losses. Winner count retention is 1/3. The promotion result is therefore **false**.

## Exact candidate

The staged candidate adds only the September 3 setup-family timing rule before admission persistence:

- continuation requires the last completed M1 candle or the completed three-candle change to resume in the trade direction;
- pullback/reversal requires a completed M1 reclaim through the detected pullback level;
- breakout requires two completed M1 closes to retain the completed M5 breakout anchor.

An unready setup reports `M1_SETUP_TIMING_NOT_READY`. Existing entry score, cost/room gates, confirmation, symbols, 1% risk, 1.5% aggregate cap, original structural stops, Bank1R management and giveback state remain unchanged.

The candidate source compiles with **0 errors and 0 warnings**. Six focused deterministic checks pass, including the four newest-loss decisions, setup-key behaviour decoding, no-look-ahead feature cutoff, unchanged inputs and gate placement before persistence.

- Candidate source SHA256: `359a471d8783e0433382799d1f3a5bdf5442fec64bd0ba9a0cbc3baf9e42a10b`
- Candidate binary SHA256: `e6055011fcb437fc2492c7499e2e85ff8ba0a5fb6112f6c3573be8f03387afce`
- Read-only M1 export: 10/10 cases passed; 17.421 seconds; order capability absent; live trading disabled.

[Trade decisions and features](trade-features.csv) · [Machine-readable audit](audit.json) · [Read-only export receipt](export-receipt.json) · [Candidate source](../../../ops/forexvps/releases/fp-m1-timing-v1-candidate-20260915/SolTradeFastMultiMarketV2.mq5) · [Compiler log](../../../ops/forexvps/releases/fp-m1-timing-v1-candidate-20260915/compile.log)

## What this resolves

The deployed manager is not the main cause of this week's losses: the four FP entries never reached +1R. The locked M1 gate shows that the losing admissions lacked the completed lower-timeframe timing evidence it requires. That gives a specific entry-side repair, rather than another exit rule.

It is still not a proven profitable release. Deploying it now would knowingly discard two observed winners and violate the acceptance standard fixed before this evaluation. The code is staged and reviewable; it is withheld from all live accounts because its own forward gate failed.
