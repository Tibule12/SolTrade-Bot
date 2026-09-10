# FP `ADAPTIVE_PAYOFF_V1` implementation and deployment

**Status: `DEPLOYED_AND_VERIFIED` on FP demo 7404213 only.** The permanent live cohort starts at **2026-09-10 14:28:45.1888371 UTC / 16:28:45.1888371 SAST**. FP was flat before deployment. Both FXIFY accounts remain paused and byte-for-byte unchanged across deployment.

## 1. Management logic implemented

One manager owns each position through `ENTRY_PROBATION → HEALTHY_POSITION → PRE_BANK_PROFIT → STRUCTURAL_RUNNER → EXIT`.

- The original broker structural stop remains installed and is never widened. It is the maximum emergency loss boundary.
- A touch of approximately −0.5R records damage evidence but never closes by itself. `ENTRY_PROBATION_FAILED` requires current R at or below −0.50R, peak R below +0.15R, and at least two completed M5 bars of causal structural deterioration. Healthy structure is classified as normal noise and held. Hard structural reversal exits as `THESIS_INVALIDATION`.
- Probation becomes healthy after +0.15R peak or when the thesis independently requalifies. The pre-bank state begins after +0.50R peak. Before +2R, profit is exited only after two completed M5 deterioration bars while current R remains positive, as `PRE_BANK_PROFIT_DERIORATION_EXIT`.
- The old continuously tightening monetary peak-R floor is absent.
- At +2R, the manager closes 50% of original volume, normalized to broker minimum/step, records `PARTIAL_BANK_2R`, allocates opening and closing costs, and persists the bank intent/result before allowing another action.
- The remaining half becomes `STRUCTURAL_RUNNER`. Its stop is based on completed M5/M15 favorable structure with breathing allowance. It must be profitable, broker-valid, and tighter than the current stop; it cannot widen. Thesis or structural deterioration ends it as `RUNNER_STRUCTURAL_EXIT` or the applicable hard-risk reason.
- Missing adaptive state fails closed on restart. Unknown portfolio exposure blocks new risk as `PORTFOLIO_RISK_UNKNOWN_DENY_NEW_RISK`. A one-hour, order-free shadow records post-probation-exit recovery evidence.

Entry scoring, admission, room thresholds, symbol selection, `EntryQuoteStillValid`, `CalculateLots`, structural-stop construction, correlation controls, ownership and duplicate-order protection are preserved from the frozen FP banking base.

## 2. Files changed

Strategy release commit: `971f4e88c72f05d37efa66ddd69396e728028154` (`Build FP adaptive payoff manager`). Scoreboard commit: `c5d77db39e908972fc57c5d2a53fbedc52ed820b` (`Expand FP adaptive payoff scoreboard`). [Every repository path and SHA256](files.json) is recorded.

The only live MT5 files changed were:

- `C:\SolTrade\MT5-FP-DEMO\MQL5\Experts\SolTrade\SolTradeFastMultiMarketV2.mq5`
- `C:\SolTrade\MT5-FP-DEMO\MQL5\Experts\SolTrade\SolTradeFastMultiMarketV2.ex5`

The deployment also installed the FP-only scoreboard publisher/scheduled task and created its baseline/equity state. No FXIFY source, binary, preset, configuration or runtime setting changed.

## 3. Essential tests

| Check | Result |
|---|---:|
| Production compilation | 0 errors, 0 warnings |
| Adaptive manager static/scope | 7 passed, 0 failed |
| Banking broker dispositions and restart | 321 passed, 0 failed |
| Banked-cash allocation excludes runner exit | 1 passed |
| All-symbol 1% sizing | 228 cases + 5 boundaries passed |
| Ownership lease | 5 passed, 0 failed |
| Entry revalidation fixture | 1 passed |
| Risk arithmetic | Passed |

The expanded scheduled scoreboard then produced two successive valid live snapshots, including all requested metrics, without order capability. No historical replay, threshold search or profitability gate was used for FP deployment. [Test record](tests.json).

## 4. Source and binary identity

- Source SHA256: `8e5fcce13b770aa84c0487f3e178710e535a2c05088161be59bbbffc4411e1b2`
- Binary SHA256: `fb4f08f4d4ac39024f0211120866715192116f33db0cc9c1fbb9f3fd72bec9f6`
- Exact manager version: `ADAPTIVE_PAYOFF_V1`
- Backup: `C:\SolTrade\backups\fp-adaptive-payoff-v1-20260910-142717`

## 5. FP deployment proof

The deployment result is `DEPLOYED_AND_VERIFIED`. Before replacement, account 7404213 had zero positions and zero orders. After restart, the installed source/binary hashes matched the release, the account remained flat, one FP MT5 process was present, one ownership runtime was granted, and duplicate sender count was zero. [Full deployment evidence](deployment.json).

## 6. FP runtime/account proof

The first verified runtime after deployment reported account **7404213**, server **FPMarketsSC-Demo**, connected, scanner active, autonomous entry enabled, ownership `GRANTED`, `ADAPTIVE_PAYOFF_V1` active, zero positions and orders, and equity **$100,466.65**. The scheduled scoreboard later reconfirmed the same identity and health.

## 7. Risk proof

The installed release pins maximum initial risk to **1.00%** and aggregate open risk to **1.50%**. `CalculateLots` is byte-preserved and all 228 symbol-sizing cases plus five boundary cases passed. Runtime reported portfolio risk known and 0.00% while flat. Unknown exposure denies new entries rather than being treated as zero.

## 8. Partial-close and restart proof

The broker-disposition/restart suite passed **321/321** cases. It covers valid min/step volume, persisted intent before the request, broker-history reconciliation, ambiguous request latching across restart, no double banking, actual remaining volume, and costed banked cash/R. The separate banked-cash allocation test passed and proves the later runner exit is not counted as banked cash.

## 9. Structural-stop proof

Static/scope checks verify the original structural stop constructor and entry functions are unchanged. Runtime management only accepts a proposed stop when it is tighter, profitable and broker-valid. The original broker SL remains active through probation, banking requests and any failed manager action; no code path may widen it.

## 10. FXIFY proof

- 10K **7196820**: `DISABLED_DRY_RUN`, autonomous trading false, zero positions/orders.
- 100K **7198096**: `DISABLED_DRY_RUN`, autonomous trading false, zero positions/orders.

Both FXIFY MT5 processes, EA source/binary hashes, preset hashes, account INI hashes and shared instance configuration matched before and after deployment. Neither terminal was restarted for this release. The deployment evidence records `fxify_unchanged=true`.

## 11. Permanent forward baseline

`FP_ADAPTIVE_PAYOFF_V1_FORWARD_BASELINE` is **2026-09-10T14:28:45.1888371Z / 2026-09-10T16:28:45.1888371+02:00**. FP was flat at **$100,466.65**, so flat-account balance equals the exported equity; open positions/orders were **0/0**. Older trades are excluded from this manager cohort. [Complete baseline](baseline.json).

## 12. Live scoreboard

The VPS scheduled publisher updates the live scoreboard every minute. The captured scoreboard starts with zero closed positions and zero net R because no post-baseline trade had closed at verification; undefined winner/loss statistics remain null until evidence exists. It tracks every requested trade, R, drawdown, MAE/MFE, probation, structural-loss, target, banking, runner and peak-capture field. Reporter order capability is explicitly false. [Current captured scoreboard](scoreboard.json); live transfer path: `ops/forexvps/remote-output/fp-adaptive-payoff-v1-scoreboard.json`.
