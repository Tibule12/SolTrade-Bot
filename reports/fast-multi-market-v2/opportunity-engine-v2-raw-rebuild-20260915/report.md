# OPPORTUNITY_ENGINE_V2 — raw-market development result

**Decision: `NO_DEMONSTRATED_MARKET_EDGE_IN_CURRENT_INFORMATION_SET`.** The replacement generator produced **12,094 independent raw-market opportunities** from preserved April–August broker scans. Of 12,060 resolved opportunities, 3,018 had only a LONG +1R-before-−1R edge, 3,017 had only a SHORT edge, 5,819 had no edge and 206 were ambiguous. Nevertheless, **none of 42 predeclared joint opportunity/direction models passed development**. The September 8–15 holdout remains sealed with zero evaluations.

This is a deeper negative result than the previous 279-production-admission audit. The universe does not begin with production trades, scores or direction. It detects completed raw structural events, evaluates LONG and SHORT independently, and permits WAIT/REJECT. The failure is now localized: tradable moves exist in the four-hour horizon, but the retained causal price state does not select their direction with stable positive costed expectancy.

All work was local and orderless. FP 7404213, FXIFY 7196820 and FXIFY 7198096 were not contacted or changed. No VPS command, MT5 replay, order, position, stop, source, binary, preset, ownership lease, watchdog or deployment was touched.

## Raw opportunity universe

| Partition | Opportunities | LONG_EDGE | SHORT_EDGE | NO_EDGE | Ambiguous | Censored | Boundary UTC |
|---|---:|---:|---:|---:|---:|---:|---|
| April–May | 4,694 | 1,233 | 1,173 | 2,193 | 79 | 16 | Apr 1 13:00–May 29 20:59 |
| June–August | 7,400 | 1,785 | 1,844 | 3,626 | 127 | 18 | Jun 1 13:00–Aug 31 18:47 |
| Combined | **12,094** | **3,018** | **3,017** | **5,819** | **206** | **34** | strictly before Sep 8 |

Each symbol is evaluated every five minutes using only completed M1/M5/M15/H1 bars. Once an event is emitted, that symbol cannot emit another until its four-hour label window expires. The persisted test verifies every same-symbol timestamp is at least 14,400 seconds after its predecessor. These are event episodes rather than repeated scan rows.

| Event family | Events | Event-hypothesis W / L | Event-hypothesis net R |
|---|---:|---:|---:|
| Fresh directional expansion | 1,832 | 451 / 1,053 | −602 |
| Structural reversal | 1,811 | 506 / 1,023 | −517 |
| Breakout retest | 1,698 | 414 / 827 | −413 |
| Failed breakout | 1,603 | 435 / 1,071 | −636 |
| Trend resumption | 1,473 | 415 / 797 | −382 |
| Completed breakout | 1,200 | 255 / 480 | −225 |
| Range to direction | 1,114 | 256 / 498 | −242 |
| Pullback continuation | 1,043 | 310 / 572 | −262 |
| Compression expansion | 187 | 37 / 96 | −59 |
| Exhaustion rejection | 133 | 20 / 26 | −6 |

The event direction itself is therefore not a usable trading rule. It entered 9,542 causally resolved hypotheses, won 3,099, lost 6,443, produced **−3,344R / −0.3505R per entry**, and had **3,351R** maximum standardized drawdown. All ten families and all five months were negative. Simply reversing each event was also negative: 3,348 wins, 7,151 losses, **−3,803R / −0.3622R per entry**, and 3,803R drawdown.

[Combined universe](opportunities.csv) · [dataset manifest and source hashes](dataset-manifest.json) · [April–May receipt](manifest-april-may.json) · [June–August receipt](manifest-june-august.json).

## Causal fields and labels

The raw record includes opportunity ID, symbol, event family, first-observed and causal-entry time, structure context, event-direction hypothesis, four-hour expiry, and separate LONG/SHORT structural invalidations. Features use the last completed M1 bar and only completed M5/M15/H1 buckets. Future bid/ask observations are used only for labels.

The **43 model inputs** are direction-mirrored values derived from raw state: M1/M5/M15/H1 trend; latest completed impulse direction, origin, age and displacement; momentum and acceleration; path efficiency; volatility expansion/compression; pullback depth, progress and resumption; completed breakout/retest; failed breakout; structural and opposing pressure; body/wick rejection; close sequences; recent/session/previous-day location; structural levels and remaining room; stop distance against M1/M5 ATR; spread and expected cost. Symbol identity, production `buy_score`, `sell_score`, `admission_score`, production direction, MFE/MAE and every outcome field are excluded.

[Exact model feature manifest](feature-manifest.json).

Each direction uses its executable entry side, post-entry executable exit side, recorded expected cost and the production-comparable M5/M15 structural stop with volatility buffer and the 1.15×M5/0.55×M15 ATR floors. Broker stop/freeze metadata was absent from the raw archive, so its small server floor is not reconstructed; this is disclosed rather than fabricated.

| Directional label evidence | LONG | SHORT | Combined |
|---|---:|---:|---:|
| +1R before structural −1R | 3,232 | 3,224 | 6,456 |
| Structural −1R before +1R | 6,557 | 7,074 | 13,631 |
| Neither boundary within four hours | 2,305 | 1,796 | 4,101 |
| +2R available before stop | 1,510 | 1,609 | 3,119 |
| +3R available before stop | 794 | 902 | 1,696 |
| +5R available before stop | 279 | 346 | 625 |

The +2R/+3R/+5R counts show that large moves existed; the model failed to identify them reliably in advance. The four-hour horizon is not empty. Of resolved opportunity-level labels, **50.04%** had exactly one directional edge, 48.25% had no edge and 1.71% had both directions reach +1R before their stops.

## Joint direction model

Every model emits `LONG_QUALITY`, `SHORT_QUALITY` and a joint `NO_TRADE_QUALITY`, followed by LONG, SHORT, WAIT or REJECT. ENTER requires the stronger direction to clear its quality threshold and exceed both the opposite direction and NO_TRADE by the fixed margin.

The fixed search contains four L2-regularized pairwise logistic models and three shallow stump ensembles, crossed with three quality thresholds and two separation margins: **42 total formulations**. Walk-forward folds were fixed chronologically:

| Validation month | Training opportunities | Validation opportunities |
|---|---:|---:|
| May | 2,383 April | 2,295 resolved May |
| June | 4,678 April–May | 2,435 June |
| July | 7,113 April–June | 2,591 July |
| August | 9,704 April–July | 2,356 resolved August |

Promotion required positive costed expectancy, at least 55% directional accuracy, at least 25% edge retention, lower loss rate than the event benchmark, at least 80 resolved entries, controlled drawdown, less than 40% from one symbol, usable nonnegative results in every validation month, positive results without the best symbol and month, and survival after removing one winner.

The highest-net diagnostic was an eight-stump model at quality 0.55 and margin 0.05. It produced **30 wins / 25 losses / +5R / +0.0909R expectancy / 7R drawdown**, but all 55 entries occurred in May. It generated no entries in June, July or August, retained only **0.50%** of available directional edges, fell to **−2R without XAUUSD**, and missed the 80-entry floor. This is a sparse month-specific artifact, not a frozen candidate.

The broadest candidate entered 2,876 cases across all validation months and exposed the opposite result: **1,069 wins / 1,807 losses / −738R / −0.2566R expectancy / 744R drawdown**. Its directional accuracy was 51.87%, edge retention 20.27%, and every month was negative.

[All 42 candidate results, folds, actions, monthly and symbol contribution](development-results.json) · [model freeze disposition](model-freeze.json).

## Exact failure-layer diagnosis

| Layer | Result | Evidence |
|---|---|---|
| Event construction | Failed as a directional rule | −3,344R; all 10 event families and all 5 months negative |
| Direction prediction | Failed stable separation | 0/42 passed; useful coverage was −738R; +5R diagnostic traded only May |
| Structural-stop geometry | Not the primary failure | 12/24,188 stops inside 1×M1 ATR; 0 inside 1×M5 ATR; median 6.38×M1 and 2.30×M5 ATR |
| Horizon/R target | Opportunity exists but is unselected | 6,035 single-direction opportunity edges; 3,119 +2R, 1,696 +3R and 625 +5R pre-stop paths |
| Cost burden | Material | median expected total cost 0.274R LONG and 0.319R SHORT; 95th percentile 0.570R and 0.627R |
| Regime stability | Failed | event rule negative every month; best positive diagnostic disappeared after May |
| Data sufficiency | Adequate to reject this information set | 12,060 resolved opportunities, 19 symbols, five months; not proof that no other market information can work |

The cost figures are the recorded expected spread plus non-spread cost divided by net initial structural risk. No zero-cost relabel was used because removing costs would answer a different, non-executable question. Full machine-readable detail is in [the layer diagnosis](layer-diagnosis.json).

## Holdout and implementation disposition

The September 8–15 holdout has **zero evaluations**. There are no retrospective LONG/SHORT/WAIT/REJECT decisions for its ten known trades. Opening it after development failure would turn those outcomes into model-selection data. [Holdout seal](holdout-seal.json).

No model was frozen, so the conditional production stages were not reached: no `OPPORTUNITY_ENGINE_V2` MQL5 source or binary was created, no compiler or VPS orderless integration ran, and no deployment occurred. [Implementation status](implementation-status.json).

Eight regression checks pass, including completed-bar cutoffs, mirrored directional features, direction/NO_TRADE separation, stop floors, four-hour episode independence, persisted pre-holdout boundaries, required raw context, and trainer isolation from the holdout. [Test receipt](test-results.json).

The engineering conclusion is specific: neither filtering the existing generator nor replacing it with these broader completed-price event families produces a demonstrated stable edge. Building the bot the user needs now requires a different information set or trading premise, rather than another threshold, score patch or retrospective selection from the September losses.
