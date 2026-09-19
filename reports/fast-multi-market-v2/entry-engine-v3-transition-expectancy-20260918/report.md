# ENTRY_ENGINE_V3 transition-expectancy development gate

**Status: `NO_REPLACEMENT_FROZEN__COLLECTOR_CONTINUES`.** The requested orderless engineering is implemented and was run on the complete collector snapshot available through September 18. The snapshot produced **323 independent four-hour opportunities**, **39,406 causal transition observations**, **638 resolved first-observation directional labels**, and **72 model features** across 19 symbols. **None of 32 chronological candidate formulations passed the promotion gates.** FP remains on the frozen V1 baseline; FXIFY remains paused; no candidate EA, compilation, shadow process or deployment was created.

This is not stop condition B. The richer information set spans only **three calendar days**, with two out-of-fold validation days. That is enough to reject every current candidate, but not enough to claim that causal tick information itself has no usable edge. The collector therefore remains unchanged and collecting. The frozen continuation gate requires at least seven collected days, three validation days and 700 independent episodes before this exact specification can be rerun.

## Frozen failed baseline and operational isolation

The existing FP entry authority is preserved as **`SOLTRADE_ENTRY_ENGINE_V1_FAILED_BASELINE`**.

| Artifact | SHA-256 |
|---|---|
| FP source | `4d1980812f3312728d8c8258c6b8b59d4c29013f3f3832128866fbcfcab3c63e` |
| FP binary | `fa2107a6088cf211d73eee646676cb3d61a6975b5b98eb47a548544c04199fea` |

The read-only export freshly verified FP 7404213 at those hashes, PID 2892, autonomous and flat with zero positions and orders. It verified both FXIFY startup files still contain `Enabled=0` and `AllowLiveTrading=0`; their preserved disabled runtimes remain `DISABLED_DRY_RUN`, autonomous false. The collector heartbeat reported `COLLECTING`, **4,302,222 ticks**, **882,569 feature records**, 19 symbols, zero copy errors, both MT5 trade permissions false and `order_capability=false`. The exporter sent zero orders and modified zero positions. [Frozen identity](failed-entry-baseline.json) · [operational verification](operational-verification.json).

The collector snapshot contains 1,287 append-only shards and 2,258,129,582 source bytes. It compressed to 284,333,260 bytes with SHA-256 `717d57ca4a2bfcc11a4a0cdc13fea4f9018dd025f8b3e5f3cba31864170586d6`. The dataset builder read the archive directly without extracting 2.26 GB onto the local disk.

## Independent transition dataset

Every symbol can emit at most one opportunity per four hours. Each opportunity enters a 15-minute WAIT trajectory sampled every 15 seconds. The persisted audit found a minimum same-symbol gap of exactly 14,400 seconds, no duplicate opportunity/time/direction rows, and no WAIT observation beyond 900 seconds.

| Item | Result |
|---|---:|
| Independent opportunities | **323** |
| Transition observations | **39,406** |
| Resolved first-observation directional labels | **638** |
| Symbols | **19** |
| Calendar days | **3**: Sep 16–18 |
| Features | **72** |
| Outcome fields | **27** |

At each first observation, the resolved directional paths contained 371 pre-bank full losses, 250 Bank1R paths, 157 +2R continuations, 102 +3R continuations and 44 +5R continuations; 17 reached neither boundary. These are directional labels, so each opportunity may contribute LONG and SHORT evidence.

Features include explicit bid and ask movement, quote-pressure windows, trade-pressure flags when supplied, tick arrival and burst rates, quote acceleration, spread state, tick volume, completed M1/M5/M15/H1 trend and structure, completed-trend age, impulse displacement, pullback depth/expansion, resumption evidence, M5/M15 structural room, adverse structural distance, stop/noise ratios, session/open displacement, correlated movement, scheduled-event fields and live cost properties. Production scores, symbol identity, raw direction identity, forming bars and future outcomes are excluded from the model matrix. Unavailable centralized depth, aggressor volume, commission and pre-collector trend history are not fabricated.

Raw four-hour MFE/MAE remain available for market-path analysis. Tradable +2R/+3R/+5R continuation and ratchet outcomes terminate at the first executable structural stop, preventing a post-stop rally from being counted as a tradable winner. [Dataset](observations.csv) · [episodes](episodes.csv) · [dataset audit](dataset-audit.json) · [feature manifest](feature-manifest.json) · [outcome manifest](outcome-manifest.json).

## Transition state machine and models

The implemented orderless state machine is:

`NO_TRADE → OPPORTUNITY_DETECTED → WAIT_FOR_TRANSITION → ENTRY_TRIGGERED | OPPORTUNITY_ABANDONED`

An entry requires predicted net R, full-loss probability, Bank1R probability and directional margin to pass together. The model estimates `P(full loss)`, `P(Bank1R)`, `P(+2R)`, `P(+3R)`, `P(+5R+)` and expected net R. Repeated observations receive episode-balanced weights. Folds are chronological by day with a four-hour embargo; no random shuffle is used.

The fixed development search contains 16 regularized linear formulations and 16 formulations with eight predeclared transition interactions. The interactions cover pressure × burst, pressure × resumption, transition pressure × pullback expansion/correlation/current movement, burst × spread and adjacent completed-timeframe trend states. There are no symbol-specific or known-trade rules.

The strongest diagnostic was the transition-interaction model with L2 10, minimum expected R 0.10, maximum predicted full-loss probability 0.45, minimum Bank1R probability 0.45 and 0.05 directional margin:

| Measure | Result |
|---|---:|
| Validation opportunities | 227 |
| ENTER / abandon | **64 / 163** |
| WAIT then ENTER | 44 |
| Net / expectancy | **+4.7651R / +0.0745R** |
| Full losses | **33 / 64 (51.56%)** |
| Bank1R | 31 / 64 |
| +2R / +3R / +5R | 18 / 13 / 7 |
| Maximum drawdown | **11.00R** |
| Sep 17 / Sep 18 | **−0.3780R / +5.1431R** |
| Net without best winner | **−2.0027R** |
| Net without best day | **−0.3780R** |

It failed training-duration, validation-duration, full-loss separation, calibration, best-day and best-winner robustness gates. Its quality bands were nonmonotonic: the 0.65–0.70 band averaged −0.6000R while 0.60–0.65 averaged +0.1285R. Only one band had at least ten entries, so quality is not calibrated strongly enough to control trading.

[All 32 formulations and gates](development-results.json) · [out-of-fold actions](oof-actions.csv) · [calibration](calibration.csv) · [model disposition](model-freeze.json) · [state-machine source](../../../tools/entry_engine_v3/state_machine.py).

## Current V1 versus V3

Only four of the eight known FP trades map into V3's two out-of-fold days; three September 16 trades belong to the training day and the earliest XAUUSD trade predates the collector opportunity stream. The comparison therefore discloses those cases rather than pretending all eight are unseen.

| Cohort | Trades | Net R | Full losses | Bank1R | +3R | Max DD |
|---|---:|---:|---:|---:|---:|---:|
| Current V1, actual mapped FP trades | 4 | +4.0621 | 1 | 3 | 2 | 0.7662 |
| V3, all out-of-fold decisions | 64 | +4.7651 | 33 | 31 | 13 | 11.0000 |
| V1 enters, V3 abandons | 1 | −0.7662 | 1 | 0 | 0 | 0.7662 |
| V3 enters, V1 does not | 61 | +7.7651 | 30 | 31 | 13 | 14.7749 |

V3 did reject the losing UK100 entry, but that isolated result is not a promotion argument. On the three mapped episodes where both systems entered, V3 chose the same direction once and the opposite direction twice; all three V3 counterfactual directions were full losses. [Full comparison and mapping limitations](v1-vs-v3-comparison.json).

## Whole-trade profit ratchet

`WHOLE_TRADE_PROFIT_RATCHET_V1` preserves the existing one-time 50% Bank1R action. It tracks banked R, half-volume runner value, whole-trade peak and a monotonic whole-trade guarantee. The runner-stop value implied by the guarantee never moves backward; no repeated partial close is introduced.

| Formulation | Net R | Change vs structural | Max DD | Mean banked peak-to-final giveback | Positive days |
|---|---:|---:|---:|---:|---:|
| Existing structural outcome | −28.5301 | — | 61.9317 | — | — |
| Loose tiers | −28.4772 | +0.0530 | 61.0189 | 0.9175R | 1 / 3 |
| Balanced tiers | **−26.0772** | **+2.4530** | 58.7689 | **0.8984R** | 1 / 3 |
| Proportional capture | −28.0338 | +0.4964 | 58.5811 | 0.9140R | 1 / 3 |

The balanced formulation retained more R, but every total cohort remained negative and only September 18 was positive. No ratchet was frozen. [Ratchet formulations and results](ratchet-results.json).

## Causal post-entry invalidation

Four rules required both adverse movement and causal evidence failure: transition pressure reversal, expanding pullback and no resumption. The strongest diagnostic waited for −0.40R adverse movement and transition score ≤−0.25; it exited 20 of 64 entries, improved the diagnostic from +4.7651R to +11.6276R, reduced drawdown to 6.9335R and interrupted no +3R path.

It is not frozen. It has only two validation days, and this dataset observes transitions only through the 15-minute WAIT window rather than the full position lifetime. Extending orderless observations after hypothetical entry is required before this can be validated as an exit authority. [Invalidation research](post-entry-invalidation.json).

## Disposition

No replacement is ready. No V3 MQL5 source or binary was created, no compiler ran, no shadow process started and no deployment occurred. FP production, FXIFY pause settings and the collector were not modified.

The concrete next condition is already frozen: continue the unchanged collector until at least seven calendar days, three validation days and 700 independent episodes exist, then rerun this same detector, 72-feature manifest, outcome definitions, 32 formulations and gates. This prevents the favorable September 18 result or the eight known FP trades from becoming new tuning targets. [Continuation gate](continuation-gate.json) · [implementation status](implementation-status.json) · [six passing regression tests](test-results.json).

## Commits and hashes

The orderless dataset builder, transition state machine, trainer, research runner, collector exporter, credential helper and regression tests are frozen in implementation commit `2626858`. The complete artifact manifest records SHA256 hashes for the implementation and every evidence file. The separate evidence commit is reported with delivery because a commit cannot contain its own final hash. [Artifact manifest](files.json).
