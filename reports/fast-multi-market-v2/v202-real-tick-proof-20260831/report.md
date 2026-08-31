# FP V2.202 pre-deployment real-tick proof — 31 August 2026

Status: **PASS; research build only; NOT DEPLOYED; zero orders sent**.

Scope stayed limited to the FP V2.202 experimental build. FXIFY V2.201,
`MinRewardRisk`, risk sizing, runner thresholds/behaviour, and account
ownership/watchdog logic were not changed.

## Evidence method

MT5 Strategy Tester was attempted first with `Model=4` (`Every tick based on
real ticks`). It entered `generating based on real ticks`, but MT5 treats the
end date as exclusive and the current 31 August session could not be included
without a future 1 September boundary. The completed 30–31 August attempt
therefore produced `0 ticks, 0 bars`; no result was invented from it.

The fallback used the FP production terminal's own August tick-cache files for
account 7404213. The four source and copied SHA-256 values match in
`ops/forexvps/remote-output/v202-vps-ticks/manifest.json`. The production
terminal was not stopped and strategy code was not changed. The cache was then
read by an isolated MT5 clone with networking removed and
`AllowLiveTrading=0`. The probe contains no `CTrade`, `OrderSend`, modify, or
close operation. It emitted only CSV evidence and then closed the isolated
terminal.

FP cache time is broker UTC+3. Times below are converted to SAST (UTC+2); the
raw CSV retains broker timestamps and millisecond epoch values.

## Persistence regression — exact five trades

| Trade | Original V2.202 result | New admission decision | Persistent complete state | Result versus original |
|---|---:|---|---:|---|
| US100 SELL | -$247.13 / -1.00000R | **REJECT** | 1 scan / 0 sec | order prevented; full original loss avoided |
| XAUUSD SELL | -$234.78 / -1.00000R | **REJECT at original entry** | 1 / 0 | order prevented; full original loss avoided |
| GER40 BUY | -$246.04 / -0.99990R | **REJECT** | 1 / 0 | order prevented; full original loss avoided |
| EURUSD BUY | -$245.18 / -1.00000R | **ADMIT** | 4 / 30 sec | real-tick scratch model below |
| GER40 SELL | +$37.97 / +0.15512R | **REJECT** | 1 / 0 | genuine winner removed; opportunity cost $37.97 |

The required GER40 BUY sequence is explicitly reset:

| SAST | Structural room | Complete admission | Persistence | Order |
|---|---:|---|---:|---|
| 08:02:10 | 0.1671R | invalid | reset | blocked |
| 08:02:20 | 1.5303R | valid | 1 / 0 | blocked |
| 08:02:30 | 0.1671R | invalid | reset | blocked |

US100 SELL and GER40 SELL are likewise one-scan flashes and cannot order.
XAUUSD's original entry is rejected, but a distinct complete state persists
later and qualifies at 04:55:30 SAST; that later admission is included in the
real-tick proof.

## Real-tick scratch results

The virtual fill is the actual FP cached executable tick matching the replay's
admission time and fill price. Zero slippage is used because real orders were
prohibited; the modeled commission is the recorded $6.00 per lot round-turn
cost. `response` means the EA's rule evaluates and requests the scratch on the
same incoming adverse tick. Broker acknowledgement/network execution latency
cannot be measured without placing an order and is not claimed here.

| Admitted case | Virtual fill (SAST) | Fill quote / reference | First genuine adverse tick (SAST) | Fill → cross | Response | Modeled P/L | Realized R | Avoided vs original |
|---|---|---|---|---:|---:|---:|---:|---:|
| XAUUSD delayed SELL, 0.19 lot | 04:55:30.594, bid 4417.32 | bid/ask 4417.32/4417.41; reference ask 4417.41 | 04:55:30.998, ask 4417.47 | 404 ms | **0 ms** | **-$3.99** | **-0.01646040R** | $230.79 contextually vs original XAU loss; later setup is distinct |
| EURUSD BUY, 5.31 lot | 10:17:10.469, ask 1.15984 | bid/ask 1.15982/1.15984; reference bid 1.15982 | 10:17:10.771, bid 1.15981 | 302 ms | **0 ms** | **-$47.79** | **-0.19497369R** | **$197.39** |

For both cases, the first post-fill tick was the adverse crossing. Therefore
the tick-event CSV contains every relevant bid/ask tick from fill through
trigger: the fill tick and the immediately following trigger tick.

No admitted trade reached a large negative R before the scratch. The EURUSD
loss is materially larger than XAUUSD despite only one adverse point because
its 5.31-lot round-turn commission is $31.86; this is execution cost, not a
delay to -0.1R or beyond.

## Price semantics and spread test

The production implementation and the no-order probe use these exact values:

| Side | EA fill | EA stored reference | Probe reference under the zero-slippage replay | Adverse crossing | Executable exit |
|---|---|---|---|---|---|
| BUY | actual `POSITION_PRICE_OPEN` ask fill | actual fill minus the captured submission-tick spread | matched fill tick bid | current bid strictly below reference | current bid |
| SELL | actual `POSITION_PRICE_OPEN` bid fill | actual fill plus the captured submission-tick spread | matched fill tick ask | current ask strictly above reference | current ask |

The captured submission tick and matched fill tick are the same quote in this
zero-slippage replay, so the implementation reference and exact cached
close-side quote coincide. The report does not claim behaviour under unmeasured
broker slippage; the broker-side structural SL remains the emergency failsafe.

At each fill tick, executable close equals the reference, so
`spread_false_trigger=false`. Floating P/L and commission are not inputs to the
trigger. The rule fires only after the relevant executable bid/ask moves
strictly through its fill-time boundary.

The original structural broker SL remains on the opening order as catastrophe
protection. The scratch path verifies the current account ownership permit
immediately before requesting a close.

## Recovery trade-off

Both real-tick cases would later recover after being scratched:

| Case | Raw fill reclaimed | Net profitable after modeled commission | Trade-off |
|---|---|---|---|
| XAUUSD delayed SELL | 04:56:14.492 SAST | 04:56:14.492 SAST | recovered 43.898 seconds after fill |
| EURUSD BUY | 10:17:22.754 SAST | 10:17:31.711 SAST | recovered net 21.242 seconds after fill |

This is not optimized away: zero directional tolerance prevents the original
large losses, but it also exits entries that briefly cross the boundary and
then recover. The persistence fix separately removes the profitable GER40 SELL
before entry.

## Acceptance and build verification

- Persistence fix: **PASS** — all complete admission components must remain
  valid; any invalid component resets state.
- GER40 `0.167R -> 1.530R -> 0.167R`: **PASS / rejected**.
- One-scan US100 and GER40 SELL: **PASS / rejected**.
- Immediate adverse crossing: **PASS** on actual FP tick-cache resolution.
- First adverse crossing response: **0 ms modeled decision delay**, on the
  triggering tick; crossings occurred 404 ms and 302 ms after fill.
- False scratch from spread: **NO**.
- Any admitted case reaching large negative R before scratch: **NO**.
- Structural broker SL retained: **PASS**.
- Runner behaviour and risk sizing unchanged: **PASS**.
- Ownership/watchdog behaviour unchanged and ownership static checks: **PASS**.
- FXIFY touched: **NO**.
- Deterministic Python regression: **69/69 PASS**.
- FP static strategy safety checks: **PASS**.
- Account-ownership static safety checks: **PASS**.
- Strategy MetaEditor compile: **0 errors / 0 warnings**.
- No-order probe MetaEditor compile: **0 errors / 0 warnings**.
- FP source SHA-256: `58649a396dff714ebc3901eb03c90715eba305e6986bc58a2f7446c6a3dbe525`.
- Canonical and FP payload sources: **byte-identical**.
- Research EX5 SHA-256: `0b37e5c4cc4383a310003625c40ce7931aabdf2c4031b19222af58585a19b70e`.
- Repository base commit: `d157ec37705b0967e709f3856f6e5113c7c219a2`.

## Final decision

| Decision | Result |
|---|---|
| PERSISTENCE FIX | **PASS** |
| SCRATCH RULE | **PASS** |
| FIRST ADVERSE CROSSING RESPONSE | **0 ms modeled on trigger tick** |
| MODELED LOSSES | **XAU -$3.99 / -0.01646040R; EURUSD -$47.79 / -0.19497369R** |
| ANY LARGE NEGATIVE R BEFORE SCRATCH | **NO** |
| FALSE SCRATCH FROM SPREAD | **NO** |
| SAFE TO DEPLOY TO FP DEMO | **YES, based on the completed replay and regression evidence** |

Deployment status remains **NOT DEPLOYED**, exactly as requested pending review
of this evidence.
