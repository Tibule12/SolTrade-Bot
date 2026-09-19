# V3 full-lifetime causal trade tracking — deployed orderless observer

**Status: `FULL_LIFETIME_TRACKER_DEPLOYED_ORDERLESS__WAITING_FOR_FIRST_FRESH_MARKET_TRIGGER`.** The full hypothetical position-lifetime tracker is implemented, compiled, deployed and running in its own portable MT5 terminal. It preserves the frozen V3 detector, 72 features, eight interactions and entry thresholds; once that specification emits `ENTRY_TRIGGERED`, the tracker follows the hypothetical trade tick by tick through its structural stop or four-hour expiry and writes a five-second causal feature snapshot throughout the position. It cannot send, modify or close orders.

The commissioning occurred on Saturday while the 19 configured markets were closed. The final heartbeat is healthy with `COLLECTING_FULL_LIFETIMES`, both MT5 trading permissions false, `order_capability=false`, zero copy errors, and **zero admitted opportunities, triggered positions, lifetime observations or outcomes**. This means the service is started, but no honest forward post-entry record exists yet. The first valid records will begin after the first fresh market quote and a frozen V3 trigger. [Start status](start-status.json) · [live heartbeat](heartbeat.csv).

## Frozen entry and invalidation specifications

The tracker uses research identity **`ENTRY_ENGINE_V3_TRACKING_DIAGNOSTIC_20260918`**, fitted once from the already available September 16–18 snapshot solely to reproduce the frozen V3 diagnostic forward. It uses the pre-existing `TRANSITION_INTERACTIONS` formulation: L2 10, expected net R at least 0.10, predicted full-loss probability at most 0.45, Bank1R probability at least 0.45, and directional expected-R margin at least 0.05. It has 72 base fields and the same eight declared interactions. This tracker identity does not promote V3, reopen its development search, or alter the 7-day / 700-episode continuation gate. [Frozen tracking model](frozen-tracking-model.json).

Four causal invalidation paths were fixed before forward results:

| Candidate | Adverse R condition | Evidence-failure condition |
|---|---:|---|
| `FROZEN_V3_DIAGNOSTIC` | `current_R <= -0.40` | `transition_score <= -0.25` |
| `STRICT_PRESSURE_RESUMPTION` | `current_R <= -0.50` | `transition_score <= -0.35` and no resumption |
| `STRUCTURAL_REVERSAL_CONFIRMATION` | `current_R <= -0.40` | `transition_score <= -0.25` and aligned M1+M5 trend ≤ −1 |
| `EXPANDING_PULLBACK_FAILURE` | `current_R <= -0.35` | `transition_score <= -0.30`, pullback expanding and no resumption |

Every rule requires both meaningful adverse movement and causal evidence failure. Negative R by itself cannot exit. Candidate definitions are written by the running tracker in [the frozen candidate receipt](frozen-invalidation-candidates.csv).

## Full-lifetime behavior

Every accepted broker tick updates executable current R, MFE, MAE, bid/ask movement, Bank1R, structural-stop state and the post-invalidation path. The five-second snapshots add 1/5/30-second tick and pressure windows, pressure reversal, acceleration, burst rate, spread, pullback/resumption state, completed M1/M5/M15/H1 bars, correlated markets, volatility and cost. `CopyRates` uses shift 1, so forming bars do not enter the features.

For each invalidation, tracking continues rather than ending at the hypothetical causal exit. The completed outcome records whether price later continued to −1R, recovered to breakeven, or reached +1R, +2R, +3R or +5R. That supports the requested loss-avoidance, interrupted-winner, expectancy, drawdown, profit-factor, payoff, symbol/session concentration, best-winner and best-day comparisons once completed forward trades exist.

The baseline path uses the original structural stop. At +1R it banks 50% exactly once and retains a 50% runner. There is no repeated bank and no deployed profit ratchet.

## Storage and restart persistence

The isolated terminal is `C:\SolTrade\Research\SolTrade-Full-Lifetime-Tracker-V1`; data is under `...\MQL5\Files\SolTradeFullLifetimeTrackerV1`:

- `lifetime_observations\YYYYMMDD\YYYYMMDD-HH-lifetime.csv` — 69-field causal position snapshots;
- `events\YYYYMMDD\YYYYMMDD-HH-events.csv` — detection, entry, Bank1R, invalidation, stop and completion events;
- `outcomes\YYYYMMDD\YYYYMMDD-outcomes.csv` — baseline plus one row per invalidation path, including all post-exit aftermath flags;
- `status\state.csv` — atomic restart state for every opportunity, open position and candidate aftermath;
- `status\heartbeat.csv`, `manifest.csv`, and `frozen-invalidation-candidates.csv` — runtime proofs and frozen configuration.

[The exact field order and semantics](schema.json) are machine-readable. A forced tracker-only restart advanced restart count from 1 to 2 while the state hash remained `743aae8f1ae20fd06a057877f1c63346376186595df399356f175b2cf232cb4a`; the watchdog is installed and running. [Operational verification](operational-verification.json).

## Commissioning defect caught and repaired

The initial Saturday launch exposed that MT5 can return the last Friday quote when no current market tick exists. That could have created false weekend opportunities. Version 1.0.1 now requires each symbol's newest broker quote to be no more than ten seconds old before detection or WAIT evaluation. The invalid tracker-only startup store was excluded from evidence, copied to `C:\SolTrade\backups\full-lifetime-invalid-stale-state-20260919-083453`, and reset. The final run has zero stale active opportunities and positions. No production or collector data was touched.

## Isolation proof

FP 7404213 remained PID 2892, autonomous and `ENABLED_OWNERSHIP_GRANTED`, with source SHA-256 `4d1980812f3312728d8c8258c6b8b59d4c29013f3f3832128866fbcfcab3c63e` and binary SHA-256 `fa2107a6088cf211d73eee646676cb3d61a6975b5b98eb47a548544c04199fea` before and after deployment. It was flat at the final capture. No FP file or setting changed.

FXIFY 7196820 and 7198096 still have `Enabled=0`, `AllowLiveTrading=0`, and preserved `DISABLED_DRY_RUN` / autonomous-false runtimes. Their startup hashes did not change. Those disabled runtime rows remain dated September 16 because disabled EAs do not refresh them.

The existing brain collector remained `COLLECTING`, orderless, on 19 symbols with zero copy errors. Deployment sent **zero orders**, modified **zero positions**, changed **zero production files**, changed **zero FXIFY files**, and did not touch the collector. [Full VPS deployment receipt](deployment-verification.json).

## Verification, commits and hashes

The combined V3 and lifetime suite passes **12/12**. The lifetime tests prove the two-condition invalidation rule, continued post-exit aftermath, one-time Bank1R accounting, frozen model/candidate identity, absence of trade APIs and stale-quote rejection. MQL compilation completed with **0 errors and 0 warnings**. [Test receipt](test-results.json) · [compiler log](compile.log).

Implementation commit: `552269a9e663df1beb6e58d123dee54ae9978171`.

| Artifact | SHA-256 |
|---|---|
| Tracker source | `133b623e455edab50367fd42fbead105e6150edae1798c5a33c586673a76a68e` |
| Frozen model include | `d3a91f5b10b6d9c99b88939a90f5710e314b082e31ea22f77bbef76e57bf29a2` |
| Deployed tracker binary | `e9475e785230b59c85ece62cbb02d3ccc72dc628bd8b830c2e60f03523e1f0aa` |
| Deployment script | `4e1d3ac30d10e70007a5f64aced6767da2f0d22d2da10267c0bc754d55563386` |
| Model exporter | `4caa7ce8f0e577981d1fb61bb141d7e91c2ce2a470fa769d59df64b91a9ec5e7` |
| Reference lifetime semantics | `6b44cf9d73b2615fd8d90216f31d7738baf96367f35724e4283686af71e5be0b` |
| Lifetime regression test | `3099da7685136e6f7693c3c87e1af353c14cbd8af1f7ab209365007d3123d16e` |
