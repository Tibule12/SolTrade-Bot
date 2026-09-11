# FP ADAPTIVE_PAYOFF_V1 Bank-at-1R deployment

**Status: `DEPLOYED_AND_VERIFIED` on FP demo 7404213 only.**

The one-time profit bank now closes 50% of the original broker position at the first valid crossing of **+1.00R**. The crossing uses marked net trade cash divided by the position's persisted original initial-risk budget. It does not use a fixed $1,000 value. Broker deals remain authoritative for the actual closed volume, commission, banked cash and banked R.

Hard structural invalidation remains first. If the trade reaches +1R, banking is attempted before probation or soft deterioration. A broker-ambiguous partial-close request remains latched across restart and suppresses a competing discretionary close until broker history resolves it. A confirmed bank persists `BANKED`, actual banked volume, remaining runner volume, banked cash and banked R. Subsequent +1R/+2R/+3R observations cannot bank again.

The remaining position enters `STRUCTURAL_RUNNER`. Its completed M5/M15 structure trail, thesis deterioration logic and monotonic stop rule are unchanged. The original broker SL stays active, and a tightened stop cannot widen.

## Deployment baseline

| Field | Value |
|---|---|
| Baseline schema | `FP_ADAPTIVE_PAYOFF_V1_BANK1R_FORWARD_BASELINE` |
| Deployment baseline | 2026-09-11 03:17:22.7629634 UTC / 05:17:22.7629634 SAST |
| Verified runtime | 2026-09-11 03:17:40 UTC |
| Account / server | 7404213 / FPMarketsSC-Demo |
| Balance / equity | $100,581.60 / $100,581.60 |
| Positions / pending orders | 0 / 0 |
| Manager | `ADAPTIVE_PAYOFF_V1_BANK1R` |
| Initial / aggregate risk | 1.00% / 1.50% |
| Bank | 50% of original volume once at +1.00R |
| Source SHA256 | `ffb9494014430db58d0c99c3857b54b432c237bb9795d2422cf33b93eeeb4ce4` |
| Binary SHA256 | `f1a69dbb7dcb3c7f673b0aaeeec5d695463b4d3790c04a42fc77be08d8a4b78c` |
| Source commit | `827a534928c090ac10bfeab70027f58110a64895` |
| Release metadata commit | `d5434a4c39e2bcbefdd3313e1758faf3be16c931` |
| Preflight commit | `9a2c94db33f5b34ff100e2792ea1b057205d3ec9` |

The new scoreboard starts at this timestamp, so previous ADAPTIVE_PAYOFF_V1 trades are excluded. Its initial cohort is empty. It records +1R reaches, `PARTIAL_BANK_1R`, banked cash/R, remaining open runner volume, runner cash/R, total position R, MFE and peak capture, structural losses, probation/pre-bank exits and +2R/+3R/+5R runner outcomes.

## Engineering verification

| Check | Result |
|---|---:|
| Production MQL compile | 0 errors, 0 warnings |
| Bank1R scope/order/persistence tests | 7 passed |
| Broker disposition, restart and volume-step cases | 316 passed |
| All-symbol 1% sizing | 228 passed + 5 boundary cases |
| Ownership lease/race/restart suite | 5 passed |
| Risk arithmetic | Passed |
| PowerShell deployment/scoreboard parsing | 0 errors / 0 errors |
| Historical replay or optimization | None |
| Fake/forced orders | None |

The exact entry, admission, symbol selection, `CalculateLots`, structural-stop construction, portfolio gate, ENTRY_PROBATION criteria, ownership and completed M5/M15 runner structure functions remain identical to the previously deployed source.

## Runtime verification

FP reports connected, scanner active, autonomous entry enabled, risk state known and ownership `GRANTED` to `vps-fp-prod`. Exactly one FP terminal process is running (PID 11076), with one active ownership runtime and zero duplicate senders. The watchdog recorded FP healthy and remains enabled/running.

FXIFY 7196820 and 7198096 remained flat and paused: `DISABLED_DRY_RUN`, autonomous entry false, zero positions and zero orders. Their source, binary, presets, settings, process IDs, instance configuration and watchdog files hash-identically before and after deployment.

Only the FP expert source and binary changed on the VPS:

- `C:\SolTrade\MT5-FP-DEMO\MQL5\Experts\SolTrade\SolTradeFastMultiMarketV2.mq5`
- `C:\SolTrade\MT5-FP-DEMO\MQL5\Experts\SolTrade\SolTradeFastMultiMarketV2.ex5`

[Deployment receipt](deployment.json) · [Permanent baseline](baseline.json) · [Initial live scoreboard](scoreboard.json) · [Preflight](preflight.json) · [Exact local files and hashes](files.json) · [Release tests](../../../ops/forexvps/releases/fp-adaptive-payoff-v1-bank1r-20260911/tests.json)
