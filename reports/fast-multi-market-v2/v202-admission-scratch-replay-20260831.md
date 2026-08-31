# FP V2.202 complete-admission and immediate-scratch replay — 31 August 2026

Status: **research build only; not deployed; no live or demo order was placed**.

Scope was limited to the FP V2.202 experimental source. FXIFY, risk sizing,
`MinRewardRisk=1.15`, runner logic, and ownership/watchdog logic were not changed.
The EA version remains `2.202`.

## Fix 1 — complete admission persistence

The persistence clock now starts only after the entire pre-order admission state
passes. Its state identity binds direction/setup to the stop anchor and opposing
structure anchor. The complete gate includes history/freshness, spread baseline
and spread safety, movement-after-costs, M5/M15 confirmation, conflict, structural
trigger, net room and reward, absolute admission score, drift/consumption,
extension/anti-chase, and re-entry eligibility. Any failure clears the count,
time, reference entry, reference room, and state identity.

The complete clock uses a new `SFM2C_P*` namespace, so previously persisted
direction-only state cannot be inherited after a future deployment.

### GER40 structural-room proof

| SAST | Room | Complete state | New persistence | Order |
|---|---:|---|---:|---|
| 08:02:10 | 0.1671R | invalid | reset | blocked |
| 08:02:20 | 1.5303R | valid | 1 scan / 0 sec | blocked |
| 08:02:30 | 0.1671R | invalid | reset | blocked |

The exact `0.167 -> 1.530 -> 0.167` flash cannot create an order.

## Fix 2 — executable-price immediate scratch

The structural SL is still included in the original broker order. It is not
removed or widened. The scratch monitor runs on every chart tick with a
one-second timer fallback and verifies account ownership immediately before its
close request.

Price semantics:

| Side | Broker fill | Fill-time reference | Adverse detector | Exit side |
|---|---|---|---|---|
| BUY | actual ask fill from `POSITION_PRICE_OPEN` | fill minus submission spread (synthetic fill-time bid) | current bid strictly below reference | market sell at bid |
| SELL | actual bid fill from `POSITION_PRICE_OPEN` | fill plus submission spread (synthetic fill-time ask) | current ask strictly above reference | market buy at ask |

At the unchanged opening quote, current bid/ask equals the corresponding
reference, so spread alone does not fire the rule. Commission/floating P/L is
not used as the trigger.

The fill reference is persisted to an account/position/symbol-bound scratch
state file. A new position whose state is not durable is flattened fail-closed
if ownership permits; otherwise its broker SL remains active. Restart
reconciliation refuses a post-fix position with missing scratch state.

## Exact five-trade admission replay

This replay uses the immutable 10-second `scan-history-v5` and
`structure-telemetry-v6` archive. Four of the five original entry flashes are
now rejected. EURUSD is the only original entry that had a complete valid state
for 30 seconds.

| Trade | Original V2.202 | New decision at original entry | Complete state | If admitted: scratch replay |
|---|---:|---|---:|---|
| US100 SELL | -$247.13 / -1.0000R | reject — complete persistence pending | 1 scan / 0 sec | N/A |
| XAUUSD SELL | -$234.78 / -1.0000R | reject — complete persistence pending | 1 / 0 | N/A at original entry; a new structural state later qualifies at 04:55:30 and scratches at 4417.71, est. -$10.88 / -0.04487R |
| GER40 BUY | -$246.04 / -0.9999R | reject — complete persistence pending | 1 / 0 | N/A |
| EURUSD BUY | -$245.18 / -1.0000R | **admit** | 4 / 30 sec | first sampled adverse bid 1.15981 at 10:17:50; est. -$111.51 / -0.45494R |
| GER40 SELL | +$37.97 / +0.15512R | reject — complete persistence pending | 1 / 0 | N/A; this is a winner removed by the stricter persistence rule |

The delayed XAU setup at 04:55:30 has modeled fill 4417.32, fill-time ask
reference 4417.41, first sampled adverse ask 4417.71 at 04:55:41, and avoids an
estimated $223.90 relative to the original loss.

## Counterfactual scratch replay on all five original fills

This table isolates the scratch rule even where the persistence fix would now
prevent the order. P/L includes the recorded spread, telemetry commission, and
the existing worst-allowed 12-point slippage model.

| Trade | First sampled trigger | Scratch price | Est. P/L | Est. R | Change vs original | Later recovery within 30m |
|---|---|---:|---:|---:|---:|---|
| US100 SELL | 02:16:00 | 29321.50 ask | -$46.23 | -0.18708R | +$200.90 | **yes**, modeled net profitable at 02:20:00 |
| XAUUSD SELL | 04:54:40 | 4416.80 ask | -$5.33 | -0.02270R | +$229.45 | no |
| GER40 BUY | 08:02:30 | 26528.25 bid | -$56.60 | -0.23002R | +$189.44 | **yes**, modeled net profitable at 08:06:00 |
| EURUSD BUY | 10:17:50 | 1.15981 bid | -$111.51 | -0.45494R | +$133.67 | raw fill reclaimed at 10:31:30, but not net profitable under the commission + maximum-slippage model |
| GER40 SELL | 17:06:40 | 26305.75 ask | -$16.52 | -0.06751R | -$54.49 vs its winner | **yes**, modeled net profitable at 17:08:00 |

### Explicit trade-off

- US100, GER40 BUY, and GER40 SELL would scratch and later recover to modeled
  profitability within 30 minutes.
- EURUSD would reclaim the fill but not all modeled costs within 30 minutes.
- The persistence fix also rejects the actual GER40 SELL winner before entry.
- These recovery cases are deliberately not optimized away.

The archive has 10-second quotes, not ticks. Live code triggers on the first
adverse tick, so the table's scratch prices and losses are conservative
first-observed bounds. They are not claims that the live tick-driven exit would
wait for the next 10-second sample. Maximum permitted slippage is also a stress
assumption, not guaranteed realized slippage.

## Acceptance evidence

- 69 deterministic Python tests pass, including one-scan reset, the GER40 room
  flash, BUY/SELL adverse crossings, and no false trigger from initial spread.
- Static FP strategy and boundary tests pass.
- Static account-ownership test passes with every one of the eight broker
  mutation sites paired with immediate ownership verification.
- MetaEditor result: **0 errors, 0 warnings**.
- Experimental EX5 SHA-256: `0b37e5c4cc4383a310003625c40ce7931aabdf2c4031b19222af58585a19b70e`.
- FP experimental source SHA-256: `58649a396dff714ebc3901eb03c90715eba305e6986bc58a2f7446c6a3dbe525`.
- Canonical and FP payload sources are byte-identical.
- `ManageFastPositions`, `MinimumProtectedR`, `CalculateLots`, and
  `VerifyOrderOwnership` are byte-for-byte unchanged from `HEAD`.
- FXIFY payloads do not appear in the change set.

Replay implementation:
`tools/replay_v202_aug31_persistence_scratch.py`.

Deployment status: **NOT DEPLOYED**, as required pending review of this replay.
