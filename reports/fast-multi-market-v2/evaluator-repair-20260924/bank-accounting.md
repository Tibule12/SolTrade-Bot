# FP Bank1R accounting investigation — September 24, 2026

**The apparent USDJPY +1R contradiction is a confirmed mismatch between two R definitions. A missed eligible Bank1R action is not established by the preserved evidence.** The prior cash reconciliation also omitted the ninth open position's confirmed partial bank. Exact opening deal charges remain necessary to finish both broker-level reconciliations.

Only preserved local files were read. FP, FXIFY and the collector were not contacted or changed; this investigation sent zero orders.

## USDJPY 404406045

The frozen deployed source hash is `4d1980812f3312728d8c8258c6b8b59d4c29013f3f3832128866fbcfcab3c63e`.

| Quantity | Actual source definition | Observed value |
|---|---|---:|
| `RUNNER_PEAK_R` | Maximum executable price movement / original structural price distance | 1.16832 |
| Cash MFE / `RUNNER_PEAK_DOLLARS` | Position profit + swap + previously closed gross; commission excluded | $1,008.18 |
| Bank1R trigger | (Position profit + swap + closed gross + actual opening costs) / initial dollar risk | No threshold crossing recorded |
| Initial dollar risk | Frozen initial cash risk | $942.19 |
| Commission/fees at final close | Total across the position's deals | −$80.46 |

The 10:45 UTC event records `current_r=1.10891`, `peak_r=1.16832` and pre-bank state. The final event records `reached_1r=false` and `partial_banking=false`. These fields are not internally contradictory because price R and bank-trigger R are different calculations. Source locations: price R line 2438; peak cash lines 2442–2446; peak price R line 2449; opening charges line 2152; Bank1R money calculation lines 2485–2488; bank threshold line 2207. Event locations: lines 44 and 52 of the [FP event export](../full-live-audit-20260924/evidence/fp-events-since-last-audit.csv).

**Conditional calculation:** if all $80.46 commission was charged at entry, peak bank cash was `$1,008.18 − $80.46 = $927.72`, or **0.984642R**, $14.47 short of Bank1R. The export contains total commission, not its entry/exit split, so this is a plausible reconciliation that requires deal-history confirmation. An opening deduction greater than $65.99 would keep the recorded cash peak below the bank threshold. There is no basis here to change Bank1R or claim it missed an eligible action.

## The $466.44 balance difference

The eight completed trades total **−$3,342.35**. The observed balance moved from **$97,103.93** to **$94,228.02**, a change of **−$2,875.91**, leaving **+$466.44** outside those eight completed trade totals.

A ninth position, XAUUSD.r 405640859, had already banked half at **2026-09-24 10:23:21 UTC**. Event line 144 confirms 0.46 lots closed, 0.46 lots remaining and **$469.20 banked net**. The terminal screenshot confirms the remaining position and $94,228.02 balance. The prior audit's statement that the event export does not explain any of the difference was too strong: it contains this partial realization.

The source allocates opening costs to `banked_net` only in proportion to the closed volume (line 2162). Account balance has already incurred the entire opening charge. Thus the remaining half's allocated opening cost must also be included when comparing balance with closed-trade totals.

The arithmetic reconciles exactly if the total opening charge was $5.52 (0.92 lots × $6), leaving $2.76 allocated to the still-open half:

`$97,103.93 − $3,342.35 + $469.20 − $2.76 = $94,228.02`.

The $5.52 opening charge is **inferred**, not directly present in the exported events. A narrow broker deal export for positions 404406045 and 405640859, plus any non-trade balance movements, is required to call this a fully verified ledger reconciliation.

## Confirmed telemetry defects

1. **An unbanked loser can show negative `banked_cash`.** `APReadBankedCash` takes the first half-volume of any closing deal, even a single full terminal close. USDJPY therefore logs −$313.09 as banked cash while `partial_banking=false`. This is allocation at reporting time, not evidence that a partial bank occurred. Source lines 2331–2360 and 3232; event line 52.
2. **`opposite_direction=false` is misleading in the giveback exit record.** The causal decision is computed using the original score direction at lines 2475–2478. Line 2481 then replaces that direction with the held direction; the log recomputes the opposite-direction flag at line 2527, so it becomes false. This explains event line 51 without proving the decision lacked opposing evidence.
3. **`PARTIAL_EXIT_DEAL.entry` is not an actual broker fill price.** That row uses the current cached market score without reading the transaction's deal price. It must not be used to reconstruct partial-close profit. Source lines 3183–3187; event line 146.

The machine receipt preserves the formulas, exact event fields, file hashes, proven findings and conditional calculations separately: [bank-accounting.json](bank-accounting.json). No production fix was made.
