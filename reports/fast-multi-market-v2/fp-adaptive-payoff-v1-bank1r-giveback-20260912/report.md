# FP PRE_BANK giveback repair — deployed and verified

**Status: `DEPLOYED_AND_VERIFIED` on FP demo 7404213 only.** The new forward baseline began at **2026-09-12 18:14:55 UTC / 20:14:55 SAST** with FP flat at **$99,579.64**. Both FXIFY accounts remain paused and unchanged.

## Defect and correction

The Bank1R manager moved XAUUSD position 399618790 into `PRE_BANK_PROFIT` at peak **+0.56825R**, but that state excluded the position from damage control after profit disappeared. It remained trapped through **-0.50445R** and later reached its original structural stop for **-1.000R**.

The repair adds the durable `PRE_BANK_GIVEBACK` state. Before the +1R bank:

- `PRE_BANK_PROFIT` moves to `PRE_BANK_GIVEBACK` when current R becomes negative;
- negative R alone does not close the position;
- at approximately -0.50R, an exit requires existing causal failure evidence: structural deterioration, or a fresh opposing direction with opposing structure and the existing directional-dominance requirement;
- a causal exit is labelled `PRE_BANK_GIVEBACK_FAILED`;
- recovery to nonnegative R returns to `PRE_BANK_PROFIT`;
- reaching +1R still banks 50% exactly once and enters the existing structural runner;
- the original structural broker SL remains in place throughout.

The state and exit identifiers were appended, preserving all existing persisted state values. The generic pre-bank soft exit does not bypass the new half-risk plus causal-failure rule.

## Live XAU regression

| Step | Expected repaired result | Test result |
|---|---|---|
| Peak reaches +0.568R | Enter `PRE_BANK_PROFIT` | Passed |
| Current R becomes -0.116R | Enter `PRE_BANK_GIVEBACK` | Passed |
| Current R reaches -0.504R without causal failure | Hold; preserve structural SL | Passed |
| Opposing causal evidence develops below half risk | Exit `PRE_BANK_GIVEBACK_FAILED` | Passed |
| Giveback recovers above zero | Return to `PRE_BANK_PROFIT` | Passed |
| Recovery reaches +1R | Bank 50% once; retain runner | Passed |

This is a deterministic manager regression using the recorded live sequence. No historical replay, optimization, fake trade, or forced order was run.

## Engineering verification

| Check | Result |
|---|---|
| Production MetaEditor compile | **0 errors, 0 warnings** |
| New giveback tests | **5 passed, 0 failed** |
| Exact live XAU regression | **Passed** |
| Existing Bank1R regression suite | **7 passed, 0 failed** |
| Existing 1% all-symbol sizing suite | **228 cases + 5 boundary cases passed** |
| Ownership static regression | **Passed** |
| Entry, sizing and structural-stop function parity | **Passed by hash manifest** |
| Fake/forced orders | **None** |

[Release tests](tests.json) · [production compile log](compile.log) · [release manifest and preserved-function hashes](manifest.json) · [exact repository file hashes](files.json)

## Deployment verification

| Check | Observed after deployment |
|---|---|
| Account | 7404213 / FPMarketsSC-Demo |
| Connected / scanner | true / true |
| Autonomous entry | true, `ENABLED_OWNERSHIP_GRANTED` |
| Manager | `ADAPTIVE_PAYOFF_V1_BANK1R_GIVEBACK` |
| Positions / orders | 0 / 0 |
| Equity and flat balance | $99,579.64 |
| FP processes | 1, PID 2892 |
| Ownership | GRANTED; one active runtime |
| Duplicate sender count | 0 |
| Watchdog | healthy, task Ready, last result 0 |
| Initial risk / aggregate cap | 1.00% / 1.50% |
| Bank rule | 50% of original volume at +1.00R |
| Source SHA256 | `4d1980812f3312728d8c8258c6b8b59d4c29013f3f3832128866fbcfcab3c63e` |
| Binary SHA256 | `fa2107a6088cf211d73eee646676cb3d61a6975b5b98eb47a548544c04199fea` |

Only these live FP files changed:

- `C:\SolTrade\MT5-FP-DEMO\MQL5\Experts\SolTrade\SolTradeFastMultiMarketV2.mq5`
- `C:\SolTrade\MT5-FP-DEMO\MQL5\Experts\SolTrade\SolTradeFastMultiMarketV2.ex5`

The prior live hashes were source `ffb9494014430db58d0c99c3857b54b432c237bb9795d2422cf33b93eeeb4ce4` and binary `f1a69dbb7dcb3c7f673b0aaeeec5d695463b4d3790c04a42fc77be08d8a4b78c`. The VPS backup is `C:\SolTrade\backups\fp-adaptive-payoff-v1-20260912-181359`.

[Full deployment receipt](deployment.json) · [new forward baseline](baseline.json) · [flat predeployment inspection](predeployment-inspection.json)

## Scope

FP entry logic, symbol selection, sizing, the 1% initial-risk target, the 1.5% aggregate cap, original structural stops, +1R banking, structural runner behavior, account drawdown controls, ownership and watchdog behavior are unchanged.

FXIFY 10K account 7196820 and FXIFY 100K account 7198096 both remained `DISABLED_DRY_RUN`, autonomous entry false, with zero positions and orders. Their captured source, binary, preset, state and runtime hashes were identical before and after deployment. The existing overlapping Bank1R scoreboard task remains disabled; the immutable forward baseline is stored without restarting that faulty collector.

## Source identity

The implementation commit is `9e8a1aa6b10016729c4cfc47b9cb997aa10f04ef`. Deployment tooling is bound by commits `dc8c876` and `3d21f04`. The deployment receipt and this final report are recorded separately after runtime verification.
