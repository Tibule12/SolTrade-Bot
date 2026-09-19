# V3 automatic forward-evidence evaluator — September 19, 2026

**Status: `DEPLOYED_CLEAN_WAITING_FOR_FIRST_COMPLETED_HYPOTHETICAL_TRADE`.** The automatic evaluator is installed at `C:\SolTrade\Research\SolTrade-Forward-Evidence-Evaluator-V1`. It reads the orderless full-lifetime tracker, produces forward comparisons for the four frozen invalidation candidates, and reruns under Windows Task Scheduler every five minutes and at startup. The current heartbeat has **zero completed positions**, integrity is **CLEAN**, and the evaluator is waiting for the first fresh completed hypothetical trade. It does not tune, select, promote, compile or deploy a candidate.

## Frozen identity and contamination boundary

Forward sequence `V3_FORWARD_EVIDENCE_20260919_A` is bound to:

| Frozen artifact | SHA-256 |
|---|---|
| Tracker source | `9daaeccc44fef63d67c8b9fc1c11270beda3a9a8ad8e21a976e7692273a9e56e` |
| Tracker binary | `60918ce78fdb8624bf23e8837468ceeef429d92b1f0382bc811129b10b6c9513` |
| V3 model include | `d3a91f5b10b6d9c99b88939a90f5710e314b082e31ea22f77bbef76e57bf29a2` |
| Frozen model JSON | `55761589de93b64e11162cb36dccd143d66f685ddcf6d20485643e16c701d0e0` |
| Deployed invalidation receipt | `064ebf44ac8026700bf9cabac58acb9107e3b8ae6ee1a2d7ca4a38f9578205af` |
| FP source / binary | `4d1980812f3312728d8c8258c6b8b59d4c29013f3f3832128866fbcfcab3c63e` / `fa2107a6088cf211d73eee646676cb3d61a6975b5b98eb47a548544c04199fea` |
| Collector source / binary | `a2a2faa3c7a2f6b307258b52630aeb728699c24b6065d61b60d3433a8d56a261` / `f80aedd723efc80471f5ea87bad8fee41b3b12c3c90b089b5dad7efc53d4963c` |

The invalidation receipt hash is the deployed Windows CRLF byte identity. Its four candidate rows and thresholds are unchanged from the frozen repository receipt. Each run checks the model, tracker, receipt, FP, FXIFY and collector identities. A mismatch sets sticky status `EVIDENCE_CONTAMINATED`; later clean runs do not silently clear it or merge sequences.

## Evaluator outputs

The evaluator writes:

- `per-trade-evidence.csv`: one row for each known-terminal hypothetical position × frozen candidate, with 41 fields covering baseline path, candidate fire state, causal evidence, aftermath, R saved and R lost from interrupted recovery;
- `rolling-invalidation-summary.csv` and JSON: loss avoidance, severity, recovery interruption, expectancy/drawdown change, payoff, robustness, symbol and session concentration for each frozen candidate;
- `rolling-v3-entry-summary.json`: OPPORTUNITY/WAIT/ENTER/ABANDON counts, direction, full-loss/Bank1R/tail rates, net R, drawdown, robustness and the frozen quality bands;
- `integrity-receipt.json`: every frozen-identity and causality check;
- `daily/YYYYMMDD-snapshot.json`: the complete daily view;
- `status/heartbeat.json`: runtime status and completed-position count.

Only `TERMINAL` rows with `baseline_final_r_known=true` and `aftermath_complete=true` enter performance calculations. `RIGHT_CENSORED` rows are checked for forbidden populated results and excluded. Entry quality is the frozen diagnostic transform `1 / (1 + exp(-2 × expected_net_R))`; the fixed development calibration bands are preserved. [Exact output schema](schema.json) · [empty forward ledger with full header](per-trade-evidence.csv) · [rolling invalidation baseline](rolling-invalidation-summary.csv) · [rolling V3 baseline](rolling-v3-entry-summary.json).

## Automatic integrity result

The live run passed **36/36** checks. These cover tracker source/binary/model/receipt hashes, model/version/manifest semantics, absence of tracker order APIs, FP hashes, both FXIFY startup hashes and disabled flags, collector hashes and trade permissions, orderless row flags, completed-bar flags, stale/noncausal observation rejection, and right-censor isolation. [Integrity receipt](integrity-receipt.json).

The task `SolTrade-V3-Forward-Evidence-Evaluator-V1` runs as SYSTEM at startup and every five minutes, ignores overlapping launches, and has a four-minute execution limit. Deployment verification recorded task state **Ready** and last result **0**. The heartbeat reports `order_capability=false`, `deployment_capability=false`, `tuning_enabled=false` and `WAITING_FOR_FIRST_COMPLETED_HYPOTHETICAL_TRADE`. [Deployment and schedule proof](deployment.json) · [fresh heartbeat](heartbeat.json) · [daily snapshot](daily/20260919-snapshot.json).

## Tests and implementation

Seven local regression tests pass. The VPS deterministic self-test passes four reference assertions, including a saved full loss and a deliberately interrupted +3R recovery whose damage is counted negatively. The live output contract contains all 41 per-trade columns even with zero completed positions.

Evaluator source SHA-256 is `04d183c3c6d26b2199e780757cf480acdc58bdaa6240271ccc591f817155316b`; deployment source matches it exactly. The schema hash is `8808d50fa1050c918d78cfbb3b95fee130464c0dade3faec5128d4c0fe66c4f1`. The implementation begins at commit `95a30256f0c87c8b61c0ddeaabb8d28c9b8081d9` and the final deployed source is commit `0db08f6ef5611e1bca67e607d9ad348619d904dd`. [Test receipt](test-results.json).

## Production isolation

The before/after deployment capture shows FP source/binary hashes unchanged and PID **2892** unchanged. Both FXIFY startup hashes are unchanged and retain `Enabled=0` plus `AllowLiveTrading=0`. The original collector source/binary and PID are unchanged and remain orderless. The full-lifetime tracker source/binary/model/receipt hashes and PID **7848** are unchanged. Deployment sent **zero orders**, modified **zero positions**, changed **zero thresholds**, and changed **no trading logic**.
