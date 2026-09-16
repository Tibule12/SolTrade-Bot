# SolTrade brain rebuild — live orderless collector baseline

**Status: `COLLECTOR_DEPLOYED_AND_COLLECTING`.** `SOLTRADE_BRAIN_COLLECTOR_V1` is running in its own portable MT5 terminal on FP demo 7404213 and is collecting live broker ticks and causal features for all 19 configured symbols. Both terminal trading permissions are false, the program contains no order API, and its runtime heartbeat reports `order_capability=false`. No model was trained.

FP's production EA remains the only trading authority. Its process stayed at PID **2892** through commissioning, and its source and binary hashes did not change. Both FXIFY accounts remain disabled under their September 16 pause configuration; neither FXIFY runtime, preset, binary nor ownership setting was touched.

## Frozen failed baseline

The active FP strategy is preserved and labelled **`SOLTRADE_FAILED_DIRECTIONAL_BASELINE`**.

| Artifact | SHA256 |
|---|---|
| FP source | `4d1980812f3312728d8c8258c6b8b59d4c29013f3f3832128866fbcfcab3c63e` |
| FP binary | `fa2107a6088cf211d73eee646676cb3d61a6975b5b98eb47a548544c04199fea` |

These values match before and after collector commissioning. The preserved release remains at `ops/forexvps/releases/fp-adaptive-payoff-v1-bank1r-giveback-20260912`; its source commit is `9e8a1aa6b10016729c4cfc47b9cb997aa10f04ef`. [Frozen identity](failed-baseline.json).

## Collector architecture

The collector runs in `C:\SolTrade\Research\SolTrade-Brain-Collector-V1`, separate from `C:\SolTrade\MT5-FP-DEMO`. A 200 ms timer reads `CopyTicks(COPY_TICKS_ALL)`, appends raw ticks to per-symbol hourly files, and writes a 5-second causal feature snapshot. Durable state records each symbol's last broker timestamp and sequence. On startup, the final build reconciles that checkpoint against the current and previous hourly append-only shards before requesting later ticks.

Data is stored at:

- raw ticks: `C:\SolTrade\Research\SolTrade-Brain-Collector-V1\MQL5\Files\SolTradeBrainCollectorV1\raw_ticks\YYYYMMDD\YYYYMMDD-HH-SYMBOL.csv`;
- causal features: `...\features\YYYYMMDD\YYYYMMDD-HH-features.csv`;
- durable state: `...\status\state.csv`;
- heartbeat: `...\status\heartbeat.csv`;
- runtime manifest: `...\manifest.csv`;
- startup configuration: `C:\SolTrade\state\brain-collector-v1.ini`.

Raw and feature files rotate hourly. The maintenance policy retains 30 days subject to a 20 GB cap. [Architecture receipt](architecture.json) · [exact schema](schema.json).

## Implemented information

The raw stream records server and derived UTC millisecond timestamps, bid, ask, last, spread, mid, bid/ask/quote direction, broker buy/sell flags, tick volume, real tick volume when supplied, interarrival time and durable per-symbol sequence.

Each causal snapshot contains:

- 1, 5 and 30-second tick rates, quote pressure, broker trade pressure, mid changes, spread means and arrival time;
- quote acceleration and observed day/session opens;
- completed M1/M5/M15/H1 OHLC, tick volume, ATR, volatility ratio, three-bar return, trend and structure;
- completed M1 correlated-market return, alignment, member count and synchronization lag within FX, metal and index groups;
- live spread, tick size, tick value, estimated spread cash per lot and broker swap properties;
- MT5 scheduled-event availability, next event, currency, importance and API error.

Unavailable information is explicit. Commission is blank with `commission_available=false`; calendar fields remain unavailable when the broker calendar API does not provide them. The collector does not infer or manufacture either value.

## Causality and runtime proof

| Check | Result |
|---|---|
| Compile | **0 errors, 0 warnings** |
| Static engineering suite | **5/5 passed** |
| Broker timestamp conversion | **1,361 rows checked; 0 errors** |
| Completed-bar cutoff | `CopyRates(..., shift=1, ...)`; forming bars excluded |
| Captured feature audit | **855 rows / 19 symbols; 0 sampled causality errors** |
| Live clean commissioning | **57 ticks and 19 features before receipt; 0 copy errors** |
| Trading permissions | terminal false; MQL false; `order_capability=false` |
| Trade API | no `CTrade`, `OrderSend`, trade request/action, close, modify or delete path |
| Restart persistence | forced restart harness increased restart count and durable sequences; checkpoint-lag defect found and repaired with shard-tail reconciliation |
| Model training | none |

The restart harness deliberately exposed a checkpoint edge: a forced process stop could occur after a CSV append but before the next state write, causing sequence rollback on restart. The final source now reads both possible active-hour tails and advances its timestamp and sequence to the newest persisted tick before backfill. The repaired source passed the regression suite, compiled cleanly and was commissioned from a clean store. [Test results](test-results.json) · [commissioning receipt](commission.json) · [compiler log](compile.log).

## Actual captured records

The evidence package contains bounded records copied from the live VPS collection:

- XAUUSD tick sequence 459 recorded broker time `1789542000229`, derived UTC `1789531200229`, bid `4327.14`, ask `4327.26`, 12 spread points and 403 ms since the prior tick;
- the next XAUUSD record arrived 402 ms later and recorded an upward bid/ask/quote change;
- the EURUSD feature snapshot recorded completed M1/M5/M15/H1 states, correlated context from 11 other FX symbols, live cost properties and a broker calendar CPI event, with `completed_bars_only=true` and `order_capability=false`.

[Live tick sample](sample-ticks.csv) · [live feature sample](sample-features.csv) · [heartbeat](live-heartbeat.csv) · [state sample](restart-state-sample.csv).

## Isolation result

Collector commissioning sent **zero orders**, modified **zero positions**, and trained **zero models**. FP source, binary, process and entry settings were unchanged; a production position that appeared during the work was opened and managed solely by the pre-existing FP EA. The collector cannot place, modify or close it.

FXIFY 7196820 and 7198096 remain governed by `Enabled=0`, `AllowLiveTrading=0` and `DryRunOnly=true`, with `DISABLED_DRY_RUN`, autonomous false and zero exposure in the preserved independent pause verification. [FXIFY pause proof](fxify-pause-verification.json).

Collector source SHA256: `a2a2faa3c7a2f6b307258b52630aeb728699c24b6065d61b60d3433a8d56a261`. Collector binary SHA256: `a967591a77577d3166d4c74946a2d9ea17943d10df3d47151d3572cc834b90e8`. Engineering commit: `33b9b43`. [File manifest](files.json).
