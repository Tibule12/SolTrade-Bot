# V3 full-lifetime causal tracker — four-hour termination removed

**Status: `CORRECTED_TRACKER_DEPLOYED__NO_POSITION_TIME_LIMIT`.** Tracker version **1.1.0** is compiled and running in the isolated research terminal. A hypothetical `ENTRY_TRIGGERED` position no longer ends at the four-hour opportunity boundary. It remains open until the frozen baseline structural management path reaches a genuine terminal state. The four-hour value remains only as the same-symbol opportunity-generation independence interval.

The correction was deployed before any fresh-market V3 trigger. The pre-deployment and final heartbeats both contain **0 triggered positions, 0 lifetime observations and 0 outcomes**. Saturday quotes were stale, so the tracker correctly created no market evidence.

## Corrected lifetime semantics

The baseline path now terminates only as follows:

1. Before Bank1R, the executable bid/ask reaches the original structural stop.
2. At +1R, 50% is banked exactly once.
3. The remaining 50% runner stays active until its monotonic structural stop is reached. That stop is derived from completed M5/M15 structure with the frozen volatility/spread breathing distance and can only tighten into profit.

The production manager audit found no normal four-hour, session-end or overnight forced exit to reproduce. The frozen research baseline remains the structural-stop path declared in the original full-lifetime task; no time exit was added.

A candidate causal invalidation records its hypothetical exit but does not stop observation. The baseline path, MFE/MAE and all aftermath flags continue until the baseline genuinely terminates. This includes recovery to breakeven, Bank1R, +2R, +3R, +5R and eventual structural loss after the candidate exit.

State now persists the original entry, initial stop/risk, Bank1R state, current runner stop, runner-stop timestamp and update count, MFE/MAE, baseline terminal state, and every invalidation/aftermath flag. On restart or market reopen, invalidation scoring waits for a new continuous 30-second tick window. A quote gap greater than 10 seconds resets that readiness check. Stale or closed-market quotes freeze evaluation and cannot manufacture stops, invalidations, time cutoffs or exits.

The optional research safety horizon is present but **disabled** (`ResearchSafetyHorizonDays=0`). If explicitly enabled later, it emits `RIGHT_CENSORED`; it leaves final baseline R blank, marks `baseline_final_r_known=false` and `aftermath_complete=false`, and is excluded from calculations that require a known final outcome.

[Exact V2 schema and semantics](schema.json) · [deployed manifest](repair-manifest.csv).

## Frozen specifications preserved

The deployed model remains **`ENTRY_ENGINE_V3_TRACKING_DIAGNOSTIC_20260918`** with the same 72 base features, eight interactions, fitted coefficients, thresholds and four invalidation candidates. The model include SHA-256 is unchanged at `d3a91f5b10b6d9c99b88939a90f5710e314b082e31ea22f77bbef76e57bf29a2`.

| Candidate | Frozen condition |
|---|---|
| `FROZEN_V3_DIAGNOSTIC` | `current_R <= -0.40` and `transition_score <= -0.25` |
| `STRICT_PRESSURE_RESUMPTION` | `current_R <= -0.50`, `transition_score <= -0.35`, no resumption |
| `STRUCTURAL_REVERSAL_CONFIRMATION` | `current_R <= -0.40`, `transition_score <= -0.25`, aligned M1+M5 trend ≤ −1 |
| `EXPANDING_PULLBACK_FAILURE` | `current_R <= -0.35`, `transition_score <= -0.30`, expanding pullback, no resumption |

Bank1R remains one 50% bank. `WHOLE_TRADE_PROFIT_RATCHET_V1` remains undeployed. The seven-day / 700-episode V3 continuation gate and the original collector are unchanged. [Frozen candidates](frozen-invalidation-candidates.csv) · [frozen model](frozen-tracking-model.json).

## Verification

The combined regression suite passes **17/17**. It explicitly proves:

- an unbanked triggered position remains active beyond four hours;
- a Bank1R runner remains active beyond four hours;
- overnight/restart serialization restores the complete open state;
- stale quotes cannot create a stop, invalidation, cutoff or exit;
- invalidation aftermath continues beyond four hours through breakeven and +1R/+2R/+3R/+5R;
- a forced research cutoff produces `RIGHT_CENSORED` with no fabricated baseline result;
- the source contains no `CTrade`, `OrderSend`, trade request/action, position close/modify or order-delete path.

The VPS compiler completed with **0 errors and 0 warnings**. The tracker-only forced restart advanced restart count **4 → 5** while the persisted state hash remained exactly `06309e685ab6d9a09affcfedcfa4182864151228beba7ac22ffe8336a8f75cd7`.

[Test receipt](test-results.json) · [compiler log](repair-compile.log) · [full deployment receipt](repair-deployment-verification.json).

## Fresh runtime proof

The post-restart heartbeat reports:

| Field | Value |
|---|---|
| Status | `COLLECTING_FULL_LIFETIMES` |
| Tracker version | `1.1.0` |
| Position time limit | `none` |
| Research safety horizon | `0` days / disabled |
| Account / server | `7404213` / `FPMarketsSC-Demo` |
| Connected | `true` |
| Terminal trading / MQL trading | `false` / `false` |
| Order capability | `false` |
| Copy errors | `0` |
| Symbols | `19` |
| Triggered positions | `0` |
| Right-censored outcomes | `0` |

[Fresh heartbeat](repair-heartbeat.csv) · [start status](start-status.json).

## Production isolation

The deployment receipt records `orders_sent=false`, `positions_modified=false`, `production_files_modified=false` and `fxify_files_modified=false`. FP had **0 positions / 0 orders** before and after the tracker-only work.

FP remained PID **2892**, autonomous and ownership-granted. Its source stayed `4d1980812f3312728d8c8258c6b8b59d4c29013f3f3832128866fbcfcab3c63e`; its binary stayed `fa2107a6088cf211d73eee646676cb3d61a6975b5b98eb47a548544c04199fea`.

FXIFY 7196820 and 7198096 remain blocked by `Enabled=0` and `AllowLiveTrading=0`. Their startup hashes were identical before and after deployment. The original collector remained `COLLECTING`, on 19 symbols, with zero copy errors and all order permissions false; the deployment script only read its heartbeat and did not target its terminal, source, binary, storage or watchdog.

[Machine-readable operational proof](operational-verification.json).

## Commits and hashes

The corrected implementation is the commit chain ending at **`b5e8947352da65b02ec8d41da7301ebdbf0e2f3d`**:

- `4898bab33a3587465fa6a5e2887227587dd2ef6a` — remove the four-hour position termination and add full structural lifetime/restart/censoring behavior;
- `c0822a856db3bf4bfd4b5469949d31f7e51f1823` — require the corrected heartbeat during deployment verification;
- `b5e8947352da65b02ec8d41da7301ebdbf0e2f3d` — align compiled tracker version metadata.

| Artifact | SHA-256 |
|---|---|
| Deployed tracker source | `9daaeccc44fef63d67c8b9fc1c11270beda3a9a8ad8e21a976e7692273a9e56e` |
| Frozen model include | `d3a91f5b10b6d9c99b88939a90f5710e314b082e31ea22f77bbef76e57bf29a2` |
| Deployed tracker binary | `60918ce78fdb8624bf23e8837468ceeef429d92b1f0382bc811129b10b6c9513` |
| Tracker preset | `064aa33f9f8c7c83fca7dbb55a99f5b2f45bff13b39a9eeb5b9ffd28002db291` |
| Reference lifetime semantics | `7bafbfe909b6300503fdba11d3ea535edd21923ce73af9c4e985662bd3d6cb67` |
| Deployment script | `14b5e3b55bd2cd5dc5900aeb7ac912fda5153f65a6dfbf3aad78bcab747f3aaf` |
| Lifetime regression test | `e9cef57a24dad7ba5c635358f9157c07daecb22d9f102c5c36f826cb25406c25` |

The VPS source hash matches the committed local source hash exactly. The rollback snapshot is `C:\SolTrade\backups\full-lifetime-tracker-update-20260919-091837`.
