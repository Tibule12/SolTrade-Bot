# SolTrade V2.202 failure audit — 31 August 2026

Audit cutoff: runtime state captured at 18:01 SAST; scan/structure telemetry captured through approximately 18:20 SAST. Account: FP Markets demo `7404213`.

No strategy code, thresholds, stops, runner logic, deployment, account permissions, or FXIFY runtime was changed during this audit. No order was placed.

## Fixed-format verdict

**TODAY'S VERDICT:** Classification **I — multiple interacting defects**: first-scan final admission instability (B), unstable structural-room selection (C), and the V2.202 `1.15R` admission regression (G) combined to admit three defect-driven losses; ownership did not cause the losses.

**PRIMARY FAILURE:** The 30-second persistence test applies to `directional_core_qualified`, not to the final spread, room, reward, structural-opposition, admission-score, and anti-chase result. All five new orders were submitted on the first 10-second scan on which the complete gate stack passed. Four were no longer eligible ten seconds later.

**SECONDARY FAILURE:** `MinRewardRisk=1.15` admitted US100 SELL at `1.1910R` and XAUUSD SELL at `1.1803R`; both lost `-1R`. It also admitted the GER40 SELL winner at `1.1703R`. Relative to a `1.20R` shadow, the V2.202-only set was net `-$443.94`.

**V2.201 WOULD HAVE TAKEN:** `2` of today's five new trades — GER40 BUY and EURUSD BUY.

**V2.201 WOULD HAVE REJECTED:** `3` — US100 SELL, XAUUSD SELL, and GER40 SELL.

**V2.202-ONLY LOSSES:** US100 SELL `-$247.13`; XAUUSD SELL `-$234.78`.

**VALID BUT LOSING TRADES:** EURUSD BUY. It had fresh data, normal entry spread, `1.3696R` net room, aligned M5/M15/H1, and a structural/volatility stop. Its M1 disagreement and low `63.34` admission score made it borderline, but the entry snapshot does not prove a deterministic rejection defect.

**DEFECT-DRIVEN TRADES:** US100 SELL, XAUUSD SELL, and GER40 BUY. The first two were V2.202-only borderline-room admissions after `1.62` and `1.51` M5 ATR adverse displacement from their persisted references. GER40 BUY was admitted by a one-scan structural-room jump from `0.167R` to `1.530R` and back to `0.167R`.

**RUNNER PERFORMANCE:** Both profitable exits protected money exactly through the coded phase logic, but capture was weak: old XAU captured `38.79%` of peak floating profit; GER40 SELL captured `29.37%`. GER40 never reached the `0.75R` runner threshold and was protected in the `0.50R` confirmed-profit phase. This is poor empirical capture, not a runner execution/ownership failure.

**OWNERSHIP/RUNTIME IMPACT:** No entry, stop, close, or successful protection operation was delayed or blocked by ownership. Four claim-write failures failed closed. Each later broker mutation had a current VPS permit. The old XAU protection had five `10018 / MARKET_CLOSED` rejections from 00:00:11–00:00:50 SAST, then succeeded at 00:01:20; those were broker market-state failures, not ownership failures.

**MOST IMPORTANT FINDING:** V2.202 is not waiting for a stable *complete* setup. It waits for directional persistence, then sends immediately on the first transient scan where the remaining gates happen to line up. The GER40 BUY is the direct proof: a nearby M5 opposing level at `26531.65` limited room to `0.167R`; one tick above that level made the finder jump to `26556.45`, producing `1.530R` and an order; ten seconds later the nearby level reappeared and room returned to `0.167R`. The trade then hit its structural stop in 69 seconds. US100, EURUSD, and GER40 SELL also lost full eligibility ten seconds after entry; XAUUSD lost it at 30 seconds.

**RECOMMENDED NEXT ENGINEERING ACTION:** In a research-only branch, make the existing persistence clock validate the complete final admission state—including the same opposing structure, net room/RR, spread state, admission score, and anti-chase result—for the full required scan/time window before an order can be sent; shadow-replay it before any deployment.

## Scope and accounting

- Five new V2.202 orders were opened and closed: one winner, four losers, `20%` win rate, net `-$935.16`.
- Including the old XAU carryover that closed today: two winners, four losers, net `-$823.19`.
- Captured account state at 18:01 SAST: equity `$97,976.65`, positions/orders `0/0`, approximately `-2.02%` from `$100,000`.
- The old XAU position was opened by the migration-time laptop duplicate sender and later managed/closed by V2.202. It was not admitted by today's V2.202 scanner, so V2.201 entry-shadow and 30-second entry-decay fields are not applicable.

## Complete trade reconstruction

All timestamps below are SAST. R is realized net P/L divided by recorded initial dollar risk. The old XAU risk (`$241.20`) is inferred from its persisted peak dollars/peak R because its original V2.202 ENTRY row does not exist.

| Ticket | Trade | Entry → exit | Entry | Initial SL | Final SL / exit | Lots | Initial risk | Net P/L | Realized R | MFE | MAE | Exact exit |
|---|---|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---|
| 392561195 | XAUUSD SELL carryover | 28 Aug 20:45:40 → 31 Aug 00:02:08 | 4452.11 | 4467.86 | 4444.98 / 4444.98 | 0.15 | ≈$241.20 | +$111.97 | +0.4642R | +1.19683R / +$288.67 | -0.14586R / -$35.18 | `DEAL_REASON_SL`, `PROTECTED_STOP_EXIT` |
| 392697510 | US100 SELL | 02:13:40 → 02:31:30 | 29314.90 | 29350.82 | 29350.82 / 29350.82 | 6.88 | $247.13 | -$247.13 | -1.0000R | +0.21994R / +$54.35 | -0.92845R / -$229.45 | `DEAL_REASON_SL`, `INITIAL_STRUCTURAL_STOP_EXIT` |
| 392852554 | XAUUSD SELL | 04:54:30 → 07:24:47 | 4416.57 | 4434.57 | 4434.57 / 4434.57 | 0.13 | $234.78 | -$234.78 | -1.0000R | +0.17888R / +$42.12 | -0.96014R / -$225.42 | `DEAL_REASON_SL`, `INITIAL_STRUCTURAL_STOP_EXIT` |
| 392939109 | GER40 BUY | 08:02:20 → 08:03:29 | 26531.75 | 26516.01 | 26516.01 / 26516.01 | 13.49 | $246.06 | -$246.04 | -0.9999R | 0.00000R / $0.00 | -0.79438R / -$195.41 | `DEAL_REASON_SL`, `INITIAL_STRUCTURAL_STOP_EXIT` |
| 393009376 | EURUSD BUY | 10:17:10 → 10:56:05 | 1.15984 | 1.15944 | 1.15944 / 1.15944 | 5.33 | $245.18 | -$245.18 | -1.0000R | +0.19922R / +$42.64 | -0.82499R / -$175.89 | `DEAL_REASON_SL`, `INITIAL_STRUCTURAL_STOP_EXIT` |
| 393242284 | GER40 SELL | 17:06:30 → 17:27:15 | 26303.25 | 26342.06 | 26297.23 / 26297.23 | 5.43 | $244.78 | +$37.97 | +0.15512R | +0.52817R / +$129.27 | -0.11598R / -$28.39 | `DEAL_REASON_SL`, `PROTECTED_STOP_EXIT` |

### Entry telemetry for the five new trades

`Score` is candidate score / absolute admission score. `Room R` is the calculated expected movement after modeled costs divided by initial stop distance.

| Trade | Session; regime | Spread; % M5 ATR | M5 / M15 ATR | M5/M15/H1 | Confirmation drift | M5 swing extension | Room R; net move | Score | Conflict / stale | Re-entry | Exact admission |
|---|---|---:|---:|---|---:|---:|---:|---:|---|---|---|
| US100 SELL | ASIA; TREND_PERSISTENT | 0.60; 2.2355% | 26.8393 / 38.1341 | bear / bear / bear | -1.62076 ATR; 0% consumed | 1.06188 ATR | 1.19103R; 42.78 | 89.71 / 79.707 | false / fresh | passed; no prior same-symbol V2 trade | `QUALIFIED_CONTEXT_COST_STRUCTURE` |
| XAUUSD SELL | ASIA; TREND_PERSISTENT | 0.09; 0.9202% | 9.7800 / 16.0493 | bear / bear / bear | -1.51431 ATR; 0% consumed | 1.64213 ATR | 1.18031R; 21.246 | 114.35 / 88.551 | false / fresh | passed; prior XAU closed 4h52m earlier | `QUALIFIED_CONTEXT_COST_STRUCTURE` |
| GER40 BUY | ASIA; DIRECTIONAL_TRANSITION | 0.50; 4.2143% | 11.8643 / 18.1786 | bull / bull / range | -0.01686 ATR; 0% consumed | 1.06201 ATR | 1.53029R; 24.08 | 74.82 / 63.816 | false / fresh | passed; no prior GER40 trade | `QUALIFIED_CONTEXT_COST_STRUCTURE` |
| EURUSD BUY | LONDON; DIRECTIONAL_TRANSITION | 0.00001; 2.9412% | 0.000340 / 0.000458 | bull / bull / bull; M1 bear | +0.32353 ATR; 12.94% consumed | 0.94118 ATR | 1.36965R; 0.000550 | 68.52 / 63.340 | false / fresh | passed; no prior EURUSD trade | `QUALIFIED_CONTEXT_COST_STRUCTURE` |
| GER40 SELL | LONDON/NEW YORK overlap; DIRECTIONAL_TRANSITION | 0.50; 2.3891% | 20.9286 / 37.0571 | bear / bear / bear | -0.23891 ATR; 0% consumed | 1.57679 ATR | 1.17028R; 45.4229 | 107.61 / 85.152 | false / fresh | passed; prior GER40 closed 9h03m earlier; new setup key | `QUALIFIED_CONTEXT_COST_STRUCTURE` |

All five entry ticks were fresh, spread checks passed, `conflict=false`, M5 and M15 were confirmed, and no re-entry/churn gate rejected the order. Negative confirmation drift means price moved against the intended direction from the persisted reference; because the code uses `max(0, confirmation_move)` and checks only positive drift against the chase limit, the `-1.62` and `-1.51` ATR adverse displacements consumed `0%` by definition and could not trip anti-chase.

The old XAU carryover has separately preserved entry evidence: NEWYORK_LATE, `1.66` M5 ATR extension, 0.15 lots, 4452.11/4467.86. Its original entry spread, ATRs, calculated room, score, and final admission snapshot are not present in the current V2.202 ledger because the laptop predecessor opened it before the VPS V2.202 runtime took ownership.

## Losing-entry quality audit

### US100 SELL — defect-driven

- Directional context was strong and aligned, but the signal had persisted for 220 seconds while price moved `1.62076` M5 ATR *against* the sell reference (29271.40 → 29314.90).
- Net room was only `1.19103R`: V2.202 passed it; V2.201's `1.20R` rule would reject it.
- It was the first fully eligible scan. Ten seconds later reward was `1.1317R`; at +30 seconds it was `0.9592R`.
- Stop: M5 anchor 29343.40 plus 7.4185 buffer; 35.9185 points = `1.3383` M5 ATR. Price continued to about 29367.65 after the stop and did not reclaim the entry in the sell direction until approximately 28m40s later. This was not merely a tight stop sweep.
- Classification: stale/adversely displaced persisted reference plus V2.202-only borderline room; not spread, session, conflict, or stop placement.

### XAUUSD SELL — defect-driven

- M5/M15/H1 were bearish and spread was excellent, but entry followed `1.51431` M5 ATR adverse displacement from 4401.76 to 4416.57 after 270 seconds of directional persistence.
- Net room was `1.18031R`: V2.202 passed; V2.201 would reject.
- It was the first fully eligible scan. It stayed eligible for only 20 seconds, reset to confirmation-pending at +30 seconds, requalified at +60/+120 seconds, and collapsed to `0.2723R` by +5 minutes.
- Stop: M5 anchor 4432.63 plus 1.9404 buffer; 18.0004 = `1.8405` M5 ATR. After the stop, price reached about 4441.51 and did not reclaim 4416.57 within 30 minutes. The stop was structurally valid and not too tight.
- Classification: first-window/borderline-room admission with a large adverse signal displacement; not a stop or spread failure.

### GER40 BUY — defect-driven false structural clearance

- At 08:02:00 and 08:02:10 SAST, nearby M5 opposition at 26531.65 limited room to `0.1671R`.
- At 08:02:20, the proposed buy price printed 26531.75—only 0.10 above that level. The nearest-opposition finder then discarded the now-behind level and selected 26556.45, causing room to flash to `1.5303R`; the bot entered.
- At 08:02:30, price was back at 26528.75, the 26531.65 level was again selected, and room returned to `0.1671R`.
- It had zero favorable excursion and stopped after 69 seconds. The structural anchor 26519.15 was breached; the stop at 26516.01 was 3.1356 points beyond it and `1.3263` M5 ATR from entry.
- Price reached about 26513.75, then reclaimed the 26531.75 entry at 08:06:00—2m31s after the stop—and reached about 26542.75. This was sweep-like price action, but the stop itself did exactly mark the model's M5 invalidation. The defect was treating a one-tick clearance of nearby opposing structure as durable room, not placing the stop inside the chosen structure.

### EURUSD BUY — valid but losing / borderline

- Entry snapshot: fresh, normal 1-point spread, M5/M15/H1 bullish, `1.36965R` net room, `0.32353` ATR positive drift, and 12.94% opportunity consumption. M1 was bearish and admission score was only `63.34`, but neither violates the intended rules.
- Ten seconds later spread was 2x baseline and the trade was no longer eligible; at +30 seconds reward was `1.1149R`; at +2/+5 minutes spread remained abnormal.
- Stop: M5 anchor 1.15952, stop 1.15944, `1.1811` M5 ATR and just above the `1.15` ATR volatility floor. Price reached about 1.15936 after the stop and reclaimed the entry approximately 8m55s later. It was vulnerable to a sweep/reclaim, but it did breach both the anchor and buffered stop.
- Evidence does not isolate a deterministic stop defect. It is the one loss best classified as a valid, low-margin setup that lost.

## `would_open_now` decay

The scanner's `eligible/decision` fields are the exact reconstructed `would_open_now` condition for the original direction.

| Trade | +30 sec | +1 min | +2 min | +5 min | First false after entry |
|---|---|---|---|---|---|
| US100 SELL | false — room `0.9592R` | false — `0.9592R` | false — `0.7694R` | false — `0.2250R` | +10s, room `1.1317R` |
| XAUUSD SELL | false — confirmation reset; room `1.4981R` | true — room `1.6161R` | true — room `1.6038R` | false — room `0.2723R` | +30s; transient reset, not permanent invalidation |
| GER40 BUY | false — room `0.2404R` | false — stale tick; room `0.8267R` | false — net move insufficient | false — movement weak; room `0.3883R` | +10s, room returned to `0.1671R` |
| EURUSD BUY | false — room `1.1149R` | false — final decision still no-trade | false — abnormal spread 3x median | false — abnormal spread 2x median | +10s, abnormal spread and `1.0891R` |
| GER40 SELL | false — room `0.0375R` | false — net move insufficient, `0.0106R` | false — room `1.0863R` | false — room `0.8998R` / score 57.58 | +10s, room `0.0375R` |

This proves that V2.202 often entered at the last transient moment of full validity. The persisted object was the directional core, while final room and spread could be valid for only one scan.

## V2.201 shadow replay

The V2.201 and V2.202 admission calculation is the same after normalizing account/runtime namespaces; the material strategy input difference is `MinRewardRisk=1.20` versus `1.15`. Reapplying `1.20R` to the exact entry snapshots gives:

| New trade | V2.202 | Entry room | V2.201 shadow | Exact V2.201 result |
|---|---|---:|---|---|
| US100 SELL | admitted | 1.19103R | reject | `INITIAL_CLEAN_ROOM_TOO_SMALL_AFTER_COSTS` |
| XAUUSD SELL | admitted | 1.18031R | reject | `INITIAL_CLEAN_ROOM_TOO_SMALL_AFTER_COSTS` |
| GER40 BUY | admitted | 1.53029R | admit | passes 1.20R |
| EURUSD BUY | admitted | 1.36965R | admit | passes 1.20R |
| GER40 SELL | admitted | 1.17028R | reject | `INITIAL_CLEAN_ROOM_TOO_SMALL_AFTER_COSTS` |

Shadow outcome, assuming identical fills/exits for the two retained trades: `-$491.22`. V2.202-only trades: `-$247.13 - $234.78 + $37.97 = -$443.94`. This proves the 1.15R change directly admitted two of today's four losses, but it did not cause GER40 BUY or EURUSD BUY.

The old XAU carryover is `N/A` for this replay because V2.202 did not admit it.

## Stop-loss audit

| Trade | Stop construction | Post-stop evidence | Verdict |
|---|---|---|---|
| US100 SELL | M5 29343.40 + 7.4185 buffer; 1.3383 M5 ATR | extended to ~29367.65; slow reclaim | structurally correct; not too tight/noise |
| XAUUSD SELL | M5 4432.63 + 1.9404; 1.8405 M5 ATR | extended to ~4441.51; no 30m reclaim | structurally correct; not too tight |
| GER40 BUY | M5 26519.15 − 3.1356; 1.3263 M5 ATR | breached to ~26513.75, entry reclaimed in 2m31s | structural invalidation plus rapid sweep/reclaim; entry-room flicker is the proven defect |
| EURUSD BUY | M5 1.15952 − 0.0000816; 1.1811 M5 ATR | reached ~1.15936, entry reclaimed in ~8m55s | structurally valid but sweep-vulnerable; insufficient evidence to declare stop defect |
| GER40 SELL | initial M5 26336.25 + 5.8136; 1.8546 M5 ATR | initial stop never threatened | initial stop valid; exit was profit protection |

No losing stop was inside the selected M5 invalidation. The stop model was not the common cause of four losses.

## Winner and runner audit

### GER40 SELL

- Peak `+0.52817R / +$129.27`; MAE `-$28.39`; no `0.75R` runner activation.
- At 17:20:50 it entered confirmed-profit phase and moved the stop from 26342.06 to 26301.20 (`+0.05282R`). Further successful monotonic updates: 26298.25 (`+0.12882R`), 26297.28 (`+0.15381R`), 26297.23 (`+0.15510R`).
- Four successful updates, exit `+$37.97`, capture `29.3726%` of peak dollars.
- After the protected exit, price first pulled back to about 26306.25 and then fell to about 26246.25 within 30 minutes. The protection worked exactly as coded but was empirically too tight for that continuation.

### Old XAU runner

- Peak `+1.19683R / +$288.67`; runner activated; final stop 4444.98 protected `+0.45270R / +$106.01`.
- Five modification attempts from 00:00:11–00:00:50 SAST returned `10018 / MARKET_CLOSED`. The first accepted modification was at 00:01:20.
- One successful trail update; net exit `+$111.97` = approximately `+0.4642R`; peak-profit capture `38.7882%`.
- Runner/protection calculations and monotonicity were correct. The delayed first modification was broker market closure, not ownership.

Therefore the evidence shows both weak entry admission and weak realized peak capture. Only the former is proven as today's strategy-entry defect; the runner executed its current design.

## Runtime and ownership separation

Ownership claim-write failures occurred at 02:08:33, 06:31:37, 10:15:55, and 17:04:32 SAST. Each logged `fail_closed=true`.

- US100 entry: current VPS permit granted at 02:13:40.
- GER40 BUY entry: current VPS permit granted at 08:02:20.
- EURUSD entry: current VPS permit granted at 10:17:10.
- GER40 SELL entry: current VPS permit granted at 17:06:30.
- GER40 profit modification: current VPS permit granted at 17:20:50; all four modifications succeeded.
- The XAU entry at 04:54:30 is present as a successful broker order with confirmed SL; no ownership-block event or failed send is present.
- No `OWNERSHIP_BLOCKED_PROTECTION`, `OWNERSHIP_BLOCKED_THESIS_EXIT`, `THESIS_EXIT_FAILED`, missed close, or ownership-caused retry exists in the evidence/lifecycle logs.
- A broker disconnect at 14:34:39 SAST lasted five seconds with zero open positions; reconciliation passed with no duplicates and therefore affected no trade.

Ownership gaps were fail-closed availability events. They did not alter any observed trade outcome.

## Root-cause mechanics in source

- Opposing room switches immediately to the nearest level still ahead of the current tick; a just-crossed level is discarded without persistence: `SolTradeFastMultiMarketV2.mq5` lines 1373–1398.
- Persistence is updated from `directional_core_qualified` before net room/RR, spread and final admission are required to remain stable: lines 1478–1490.
- The final room/RR gate and final eligible assignment happen later: lines 1499–1525.
- Adverse confirmation movement is clamped to zero consumption, and only positive drift can fail the chase gate: lines 1492–1496 and 1521–1522.
- Stop distance is structurally anchored, buffered, and floored by `max(1.15*M5 ATR, 0.55*M15 ATR)`: lines 1360–1371.

## Supporting evidence

- Full scanner/structure/spread/risk/runner archive: `ops/forexvps/remote-output/v202-audit-20260831.zip`
- V2.202 entry/management/deal ledger: `ops/forexvps/remote-output/result-fp-evidence.csv`
- Ownership, disconnect and recovery lifecycle: `ops/forexvps/remote-output/result-fp-lifecycle.csv`
- Expert ownership log: `ops/forexvps/remote-output/result-fp-expert.log`
- Runtime account snapshot: `ops/forexvps/remote-output/result-fp-runtime.csv`
- Current ownership lease at capture: `ops/forexvps/remote-output/result-fp-lease.json`
- Watchdog state at capture: `ops/forexvps/remote-output/result-watchdog.json`
- Original duplicate-sender XAU entry record: `reports/incidents/fp-7404213-xauusd-duplicate-sender-20260828.md`
- V2.202 source inspected: `ops/forexvps/payload/fp-demo/SolTradeFastMultiMarketV2.mq5`
- V2.201 shadow source inspected without running or trading: `ops/forexvps/payload/fxify-10k/SolTradeFastMultiMarketV201F10.mq5`

## Evidence limits

The scanner/structure series is sampled every ten seconds, not broker tick-by-tick. Post-stop sweep/reclaim statements therefore use observed snapshots and exact broker exit prices; they do not claim an unseen intrasecond path. The old XAU entry predates the current VPS V2.202 ledger, so unavailable original admission fields are reported as unavailable rather than reconstructed from later state.
