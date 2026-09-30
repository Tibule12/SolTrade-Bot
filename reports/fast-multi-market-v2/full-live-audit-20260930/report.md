# Full live audit — September 30, 2026

**Finding: FP has lost money overall, its ownership control is intermittently preventing both entries and position management, and the automatic V3 evaluator is behind the tracker.** The frozen strategies and all protected code/configuration hashes still match their earlier receipts. This was a read-only audit: no trading setting, model, threshold, order, position or stop was changed by it.

The figures below have different meanings. FP's **broker balance is realized demo-account P&L**; equity adds the changing value of its open position. The V3 figures are **orderless hypothetical R**, not broker cash. Neither measures FXIFY purchase fees or VPS invoices.

## FP broker result and current exposure

The FP terminal showed balance **$94,456.60** and one **GER40 sell** open at the visual check near **17:59 UTC**. Its floating profit was **$390.67** and equity **$94,847.27** at that instant. Ticket **408708254**, volume **18.63**, entry **25209.75**, original broker stop **25254.40** and current displayed price **25191.25** were visible. There were no pending orders. [Broker screen](fp-broker-ui-20260930.png) · [Fresh runtime and task state](evidence/final-quick-state.json).

From the September 18 flat balance of **$97,103.93**, FP has realized **−$2,647.33 / −2.67623R over 14 completed positions**, six positive and eight negative. The current broker balance reconciles exactly: $97,103.93 − $2,647.33 = $94,456.60. It is **$5,123.04 (5.145%) below** the September 13 $99,579.64 baseline. Equity at the visual check was $4,732.37 below that baseline, but that number changes with GER40. These are demo-account figures; actual fees paid for FXIFY, VPS and development are not present in the captured records and cannot be added honestly.

Six positions completed after the September 24 11:16 UTC audit cutoff: **three positive, three negative, +$695.02 / +0.80924R** as whole-position outcomes. One XAUUSD trade made **+$2,497.95 / +2.68834R**; removing it leaves **−$1,802.93 / −1.87910R**. The six-position subtotal is therefore concentrated in one winner. The carried XAUUSD trade's +$3.22 final result includes a $469.20 partial bank already realized before the cutoff; the $695.02 is not an account-balance change during the interval.

| Entry UTC | Symbol / direction | Final cash / R | Bank1R | Exit |
|---|---|---:|---|---|
| Sep 24 09:37 | XAUUSD.r sell | +$3.22 / +0.00346R | Yes; runner −$465.98 | Runner structural stop |
| Sep 28 01:54 | XAUUSD.r sell | +$2,497.95 / +2.68834R | Yes; 31 stop advances | Runner structural stop |
| Sep 28 15:10 | US100 sell | −$961.86 / −1.00000R | No | Original stop |
| Sep 28 22:09 | XAUUSD.r sell | −$486.42 / −0.51093R | No | Existing pre-bank giveback failure |
| Sep 29 06:49 | AUDUSD.r sell | +$595.08 / +0.62775R | Yes; six stop advances | Runner structural stop |
| Sep 30 02:53 | EURJPY.r sell | −$952.95 / −0.99938R | No | Original stop, about ten minutes |

The newly entered losers had opposing M1 states while M5/M15/H1 were bearish, but the AUDUSD winner also had opposing M1. Losing admission scores were **64.1189–68.4309**; the AUDUSD winner scored **60.8755**. The bot's current admission logic still does not reliably distinguish these losses from wins. The two original-stop losses never banked. The September 28 pre-bank exit limited one loss to about half R; it did not repair directional selection. [Every trade and calculation](fp-findings.md) · [Machine audit](fp-analysis.json) · [Raw FP evidence](evidence/fp-evidence.csv).

## FP ownership and management failure

FP remained connected, scanning, on the **same PID 2892 and same frozen source and binary**, but its fresh runtimes at **17:28** and **17:54 UTC** both reported **`BLOCKED_NO_OWNERSHIP`**, `autonomous_entry=false`, with one open position. The ownership task reported Running. At 17:54 its persisted lease had expired at **17:39:53 UTC**. A Running task therefore did not establish an effective permit. The broker's original stop remained visible on GER40, but a failed ownership check blocks the EA's **Bank1R partial, discretionary exit and runner-stop modification** as well as new entries. [Operational reconciliation](operations.json) · [Ownership lifecycle](evidence/lifecycle-20260928.csv).

This has recurred. The available September 24–30 lifecycle files contain **35 blocked ownership actions**: **23 runner-stop modification attempts** and **12 entry attempts**, plus **16 claim-write failures**. The latest 1,000 ownership-authority audit records span September 30 10:16–17:34 UTC and contain **229 stale-lease expirations**; the median expiration was recorded 18 seconds late, and the longest 168 seconds late. The September 30 GER40 entry succeeded at 15:41:30 after two blocked attempts. The blocked attempts prove lost management authority at those moments; they do not prove a particular missed bank, worse exit price, or counterfactual profit. The exact cause of delayed renewals and failed file writes remains unconfirmed. [Ownership audit tail](evidence/fp-ownership-audit-tail.jsonl) · [Frozen source gates](../../../ops/forexvps/releases/fp-adaptive-payoff-v1-bank1r-giveback-20260912/SolTradeFastMultiMarketV2.mq5).

The September 24 report said FP was ownership-granted. **Its preserved runtime at 11:16 UTC actually said `BLOCKED_NO_OWNERSHIP`.** Entries on later days prove the block was intermittent; that earlier status sentence was wrong. This audit preserves the correction without rewriting historical evidence.

## V3 forward evidence — all 54 completed positions

The orderless tracker recorded **903 independent opportunities** across 19 symbols and ten UTC calendar dates, with a minimum same-symbol gap of exactly four hours. They partition into **849 abandoned and 54 triggered**. All 54 positions reached a terminal baseline outcome; none was right-censored. The raw stream contains **56,593 five-second lifetime observations**, **24 one-time Bank1R events**, and eight positions observed beyond four hours. The median and 95th-percentile observed cadence were five seconds. There were 236 gaps over ten seconds, including market closure/stale periods; a gap is not turned into a trade exit.

**Frozen V3 baseline: −5.99525R / −0.11102R per completed position**, 30 original-stop losses and 24 Bank1R paths. The best winner contributed +5.13884R; without it the total is **−11.13408R**. Removing the best entry day leaves **−13.97770R**. Quality remains unstable: the 0.70–0.80 band lost an average **−0.57180R** across 14 completed positions. These are 54 hypothetical positions, with no claim that the entry model has an edge.

| Frozen invalidation path | Fires | Original-stop losses improved | Later Bank1R / +5R paths interrupted | Final R vs −5.995R baseline |
|---|---:|---:|---:|---:|
| `FROZEN_V3_DIAGNOSTIC` | 49 | 30 | 13 / 5 | **−9.53345R** |
| `STRICT_PRESSURE_RESUMPTION` | 45 | 29 | 10 / 4 | **−6.74330R** |
| `STRUCTURAL_REVERSAL_CONFIRMATION` | 45 | 26 | 13 / 5 | **−12.59604R** |
| `EXPANDING_PULLBACK_FAILURE` | 40 | 23 | 12 / 5 | **−12.65693R** |

The diagnostic saved **18.31770R gross** on improved positions and surrendered **21.85590R gross** on positions it cut; its net change was **−3.53820R**. Its 13 interrupted Bank1R paths include nine +2R, six +3R and five +5R paths reached after invalidation. The more recent 30 completions absent from the September 24 published sample totaled **+0.84662R baseline**, but **−4.29221R without their best winner**. No candidate was retuned or promoted. [Independent raw reconstruction](forward-analysis.json) · [216 candidate comparisons](forward-comparisons.csv) · [Frozen candidates](evidence/frozen-invalidation-candidates.csv).

The tracker has numerically passed the **700-episode and seven-calendar-date** parts of the frozen continuation condition. This audit did not rerun the frozen dataset builder to verify the same episode/validation-fold definitions, and did not rerun the 32-model search. The three-validation-day condition remains to be checked formally against that specification.

## Evaluator, collector and evidence integrity

The automatic evaluator's last completed heartbeat was **September 30 00:48:55 UTC**, with **50 positions / 200 comparisons**. At the 17:28 capture it was **16.66 hours old**; at 17:54 it still showed 50. Its last sampled run was in `LOAD_LIFETIME_OBSERVATIONS` while Task Scheduler showed Running; no fresh publication had completed. Its published per-trade rows match the underlying records they cover, but **four completed positions were missing** from the published set. One missing US100 baseline winner was **+5.13884R** and the diagnostic had cut it to **+0.26029R**; that omission materially changes the displayed candidate result. The captured `CLEAN` sequence and 36-check integrity receipt reflect earlier runs, not a successful fresh publication. [Evaluator heartbeat](evidence/evaluator-heartbeat.json) · [Run progress](evidence/evaluator-run-progress.json) · [Current raw reconstruction](forward-analysis.json).

The original collector was current at 17:54: **17,089,173 ticks**, 19 symbols and zero copy errors, with both MT5 trading permissions false and `order_capability=false`. The tracker was also current: **12,787,000 ticks**, 903 opportunities, 54 completions, zero copy errors, no active hypothetical position and `order_capability=false`. Source scans found no order API in either research EA. All **216 outcome rows** were terminal and complete, none censored; all persisted lifetime rows passed `completed_bars_only`, `feature_window_ready`, orderless and completed-bar cutoff checks. The raw lifetime schema does **not** persist the quote's own timestamp, so its stale-quote gate cannot be independently re-proved for every row from these files alone. [Tracker archive and hash receipt](evidence/tracker-quick-receipt.json) · [Integrity detail](forward-analysis.json).

## FXIFY and protected identities

Both FXIFY startup files still contain **`Enabled=0` and `AllowLiveTrading=0`**, and their startup/preset, source and binary hashes match the preserved pause/deployment receipts. Their terminal processes were present. Their last EA runtimes are from **September 16**; they cannot establish **current broker exposure**, so this audit claims only the freshly verified entry block and unchanged code/settings. FXIFY was not contacted or resumed. FP source/binary, collector source/binary, tracker source/binary/model/candidate and all ten protected startup/preset hashes match September 24. [Fresh hash and settings verification](operations.json) · [Fresh FXIFY code hashes](evidence/fxify-fresh-code-hashes.json).

The audit sent **zero orders**, changed **zero positions or stops**, and made **zero production or research runtime changes**. The broker position and realized trades above belong to the pre-existing FP EA. There is no evidence here of a profitable replacement, and the ownership and evaluator faults require separate operational repair before their status can be described as healthy. [Read-only capture record](evidence/snapshot-before.json) · [Audit source](../../../tools/audit_forward_20260930.py).
