# SolTrade full live audit — September 24, 2026

**Decision: `FP_LOSSES_CONTINUE__V3_FORWARD_NEGATIVE__EVALUATOR_STALE`.** This was a read-only VPS audit. FP production remains autonomous and unchanged; both FXIFY startup configurations remain disabled; the original collector and V3 tracker are current and orderless. The automatic evaluator is **not current**: it publishes 15 completed hypothetical positions while the tracker has 22. Its displayed `CLEAN` result describes an older run, not a current end-to-end success.

The fresh FP event window starts after the September 18 audit at 19:41 UTC. Through the exported events on September 24, FP closed **8 trades: 3 gains and 5 losses, −$3,342.35 / −3.48547R**. A ninth, XAUUSD.r short, was open at the 11:16 UTC runtime capture. The runtime reported **$94,073.00 equity**, one position and no pending orders; that equity includes the changing open P&L. The terminal showed **$94,228.02 balance** at 11:05 UTC. Compared with the September 18 flat equity of $97,103.93, the observed balance change is −$2,875.91, **$466.44 different from the eight logged exit amounts**. The available EA event export does not explain that difference. Broker deal/balance history is needed before claiming a fully reconciled cash ledger.

## FP loss audit

| Entry UTC | Symbol | Direction | Exit UTC | Result | Peak reported | Bank1R | Exit class |
|---|---|---|---|---:|---:|---|---|
| Sep 21 01:48 | US100 | Buy | Sep 21 01:58 | −$970.93 / −1.0000R | +0.041R | No | Initial structural stop |
| Sep 21 23:36 | XAUUSD.r | Buy | Sep 22 00:30 | +$11.13 / +0.0116R | +3.595R | Yes | Runner structural stop |
| Sep 22 05:39 | US100 | Sell | Sep 22 05:45 | −$961.34 / −1.0000R | +0.038R | No | Initial structural stop |
| Sep 22 08:35 | GER40 | Sell | Sep 22 08:39 | −$951.92 / −1.0003R | +0.067R | No | Initial structural stop |
| Sep 22 10:35 | USDJPY.r | Sell | Sep 22 11:10 | −$626.64 / −0.6651R | +1.168R | No | Pre-bank giveback failure |
| Sep 23 11:57 | GER40 | Sell | Sep 23 12:52 | +$81.27 / +0.0868R | +1.565R | Yes | Runner structural stop |
| Sep 23 14:27 | XAUUSD.r | Sell | Sep 23 14:53 | −$925.20 / −0.9983R | +0.113R | No | Initial structural stop |
| Sep 23 14:54 | AUDUSD.r | Sell | Sep 23 17:45 | +$1,001.28 / +1.0797R | +3.524R | Yes | Runner structural stop |

The cohort averaged **−0.4357R per exit**, with **4.5652R maximum closed-trade drawdown** and **0.253 profit factor**. Removing the AUDUSD winner leaves **−4.5652R**. The four original-stop losses reached only +0.038R to +0.113R before failure; three stopped within eleven minutes. This is an entry-admission problem for those trades, not a runner-exit problem. Losing admission scores spanned **63.41–75.89**, overlapping winning scores **65.45–76.44**. Every entry marked `conflict=false`; seven recorded no-trade score 12 and one losing entry recorded 36. The GER40 full-stop loss had all four recorded timeframes aligned with its sell direction, so an M1-alignment rule would not isolate the losses.

The manager also returned much of the open gain on Bank1R paths: XAUUSD finished +0.0116R after a reported +3.595R peak, GER40 finished +0.0868R after +1.565R, and AUDUSD finished +1.0797R after +3.524R. The USDJPY event reports a +1.168R peak yet `reached_1r=false` and no partial bank; the event's peak, cost treatment and exact Bank1R trigger need a quote/deal replay before calling this a manager defect. No rule was changed from these observations.

[Every FP trade and entry state](fp-trades.csv) · [raw FP events](evidence/fp-events-since-last-audit.csv) · [11:05 terminal capture](evidence/fp-terminal-20260924-1105.png).

## V3 full-lifetime tracker, measured directly

At the 11:16 UTC capture, the tracker heartbeat reported **415 opportunities, 23 hypothetical entries, 22 completed baseline positions, one active position, 21,465 lifetime observations and zero right-censored outcomes**. The independent event export contains 415 `OPPORTUNITY_DETECTED`, 392 `OPPORTUNITY_ABANDONED`, 23 `ENTRY_TRIGGERED`, 22 `POSITION_LIFETIME_COMPLETE`, 11 Bank1R events and 78 candidate invalidation events. All 1,004 captured event rows and 88 candidate outcome rows retain `order_capability=false`; all outcome rows have `completed_bars_only=true`. Three completed positions lasted **5.68, 6.17 and 6.76 hours**, proving that the old four-hour opportunity window did not terminate their tracked position lifetime.

The **first fresh trigger** was US100 short at **2026-09-21 06:01:23 UTC**, entry price **29,849.20**, original stop **29,861.537857**, initial distance **12.337857**. Its baseline hit the initial stop at **06:09:57 UTC**, **−1.021247R**, with zero favorable excursion. The frozen diagnostic invalidation fired at **06:05:08 UTC**, **−0.413362R**, transition score **−0.875**; baseline observation continued to the real hypothetical stop. No real order was associated with that V3 position.

For all 22 completed V3 positions, the frozen baseline has **12 initial-stop losses and 10 Bank1R paths**, **−8.0128R total / −0.3642R per entry**, **9.4768R max drawdown** and **0.352 profit factor**. Its best winner supplies +1.2099R; removing it leaves **−9.2227R**. Recorded entry predictions averaged **+0.4997 expected R** and **34.24% full-loss probability**, while observed net was −0.3642R per entry and 54.55% reached the initial structural stop. This is a small, negative forward cohort, not a calibrated or promotable entry model. The existing seven-day / 700-episode development continuation gate was not rerun; 415 opportunities remain below 700.

| Frozen management path | Fires / 22 | Initial-stop losses exited early | Bank1R paths interrupted | +2R paths interrupted | Net R | Max DD |
|---|---:|---:|---:|---:|---:|---:|
| Baseline structural manager | — | — | — | — | **−8.0128** | 9.4768R |
| `FROZEN_V3_DIAGNOSTIC` | 20 | 12 | 8 | 2 | **−4.0956** | 5.1429R |
| `STRICT_PRESSURE_RESUMPTION` | 17 | 11 | 6 | 1 | **−4.0319** | 5.4224R |
| `STRUCTURAL_REVERSAL_CONFIRMATION` | 20 | 12 | 8 | 2 | **−4.2810** | 5.1460R |
| `EXPANDING_PULLBACK_FAILURE` | 17 | 10 | 7 | 2 | **−4.0806** | 4.6596R |

The diagnostic's gross positive per-trade changes total **+7.1760R**, while interrupted/reduced paths cost **−3.2587R**, leaving +3.9172R versus baseline. That reduction in damage still leaves −4.0956R, and it interrupts eight later Bank1R paths. The other three paths are also negative. These are counterfactual orderless comparisons; no candidate is selected, tuned or deployed.

[All 22 positions × four candidates](v3-trade-comparisons.csv) · [raw tracker events](evidence/tracker-events-all.csv) · [raw terminal outcomes](evidence/tracker-outcomes-all.csv).

## Evaluator integrity failure

The evaluator's last published heartbeat is **2026-09-23 05:24:57 UTC**, with **15** completed positions and 60 candidate rows. Its published entry summary is **−8.3793R on those 15**, not the current 22-position result. The task was enabled and running at both 11:03 and 11:16 UTC on September 24, but the published heartbeat had not advanced. Its last integrity receipt at **00:39:53 UTC** passed **36/36 checks** and had already read **88 outcomes, 882 events and 19,459 lifetime observations**. Thus `CLEAN` proves frozen identity and checked row flags at that earlier run; it does **not** prove the evaluator completed its reporting pass. Inspection of the evaluator source shows repeated array appends and full observation scans during import and per-trade building, consistent with a growing runtime bottleneck, but this audit did not establish the exact task termination cause.

There is also a concrete numeric output defect in the stale per-trade CSV: **all 52 fired candidate rows** round `r_saved_vs_baseline` or `r_lost_vs_baseline_if_interrupted` to whole R. The source uses `[Math]::Max(0, $double_delta)`, which selects integer conversion for this call. For the first trade the actual saved amount is **0.607885R**, while the per-trade CSV says **1R**. The rolling aggregate recomputes deltas from final R and does not share this particular rounding error. The raw final R fields, not those two rounded fields, were used for this audit's current comparison. No evaluator or tracker code was changed during this audit.

The remaining **2,006** lifetime observations after the 00:39 integrity run were represented by a fresh tracker heartbeat but were not independently row-scanned in this audit. The fresh event and outcome exports passed the orderless/completed-bar checks above. A current evaluator integrity receipt and published comparison are still missing.

[Stale evaluator heartbeat](evidence/evaluator-heartbeat.json) · [last integrity receipt](evidence/integrity-receipt.json) · [stale published per-trade rows](evidence/per-trade-evidence.csv) · [machine-readable audit](audit.json).

## Operational boundaries

FP PID **2892**, source SHA-256 `4d1980812f3312728d8c8258c6b8b59d4c29013f3f3832128866fbcfcab3c63e` and binary SHA-256 `fa2107a6088cf211d73eee646676cb3d61a6975b5b98eb47a548544c04199fea` match the frozen baseline. It remains connected, autonomous and ownership-granted. Its existing EA made the real entries above; this audit sent **zero orders** and modified **zero positions**.

FXIFY **7196820** and **7198096** startup files still have `Enabled=0` and `AllowLiveTrading=0`, with the same frozen startup hashes. Their terminal processes remain present. Their last EA runtime rows are dated September 16, so current exposure cannot be proved from those rows; the freshly verified entry block can be proved. Neither account was touched.

The original collector remained at its frozen source/binary hashes and reported **9,658,596 ticks, 2,715,062 feature rows, 19 symbols, zero copy errors** and both MT5 trading permissions false at the 11:16 snapshot. The V3 tracker remained at its frozen source/binary/model/candidate hashes, PID **7848**, with both trading permissions false and `order_capability=false`. No trading logic, threshold, feature, manager rule, Bank1R behavior, collector configuration or production deployment was changed.

[Fresh VPS metadata snapshot](evidence/snapshot.json) · [collector heartbeat](evidence/collector-heartbeat.csv) · [tracker heartbeat](evidence/tracker-heartbeat.csv).
