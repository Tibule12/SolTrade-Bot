# ENTRY_ENGINE_V2 clean rebuild — development stop condition B

**Decision: `DIRECTIONAL_GENERATOR_HAS_NO_DEMONSTRATED_EXPLOITABLE_SIGNAL`.** The clean rebuild is complete through the development gate. The preserved pre-September-8 evidence contains **279 usable causal opportunities, 267 resolved labels, 131 +1R-first wins, 136 −1R-first losses and 12 censored paths**. The generator produced **−5R / −0.0187R per resolved opportunity**. None of **46** compact multivariable selectors passed the predeclared walk-forward gates.

This is stop condition **B** from the task. No `ENTRY_ENGINE_V2` production candidate is being represented as ready. The September 8–15 holdout remains sealed with **zero evaluations**, because no model passed development and therefore no model was eligible to freeze before that one-time test.

All work was local and orderless. FP 7404213, FXIFY 7196820 and FXIFY 7198096 were not contacted or changed. No trade, permission, risk, stop, Bank1R state, giveback state, source, binary, preset, terminal, ownership lease or watchdog was touched. No MT5 replay, VPS command, browser session or deployment ran.

## Dataset and boundaries

| Partition | Source admissions | Usable | Resolved W / L | Censored | Entry-time boundary |
|---|---:|---:|---:|---:|---|
| April–May | 113 | 111 | 50 / 56 | 5 | 2026-04-01 01:04:20 through 2026-05-29 14:20:40 UTC |
| June–August | 168 | 168 | 81 / 80 | 7 | 2026-06-01 14:05:40 through 2026-08-31 17:52:00 UTC |
| Combined development | 281 | **279** | **131 / 136** | **12** | strictly before the 2026-09-08 holdout |

April–May positions 2 and 124 were omitted because the archive did not contain enough completed bars before entry to construct the declared features. They were not assigned an outcome or filled with later information.

The `symbol-brain-20260908` episode file was not used as development input: its episode timestamps are on September 8, at the locked boundary. The larger preserved April–August native archives provide the 279 independent pre-boundary candidates used here.

The primary label is **+1.00 executable R before −1.00 executable R within four hours**, using the recorded entry-side ask/bid, executable post-entry bid/ask, original structural price risk, and recorded expected non-spread cost. Future quotes create labels only. The dataset also retains full and pre-stop MFE/MAE, time to ±0.5R and ±1R, time to +2R/+3R/+5R, continuation after +1R, target availability before the stop, terminal R and censoring.

[Master dataset manifest](dataset-manifest.json) · [development dataset](development-dataset.csv) · [April–May manifest](dataset-manifest-april-may.json) · [June–August manifest](dataset-manifest-june-august.json)

## Causal features

The model received **52 numeric features**. Every bar-derived value uses completed bars strictly before the candidate timestamp; the forming entry-minute bar is excluded. Entry evidence fields are limited to information already recorded when the candidate was proposed.

| Requested family | Implemented evidence |
|---|---|
| Parent move age | detectable pivot age in minutes/M5 bars; time since completed structural break |
| Location and consumption | ATR displacement from origin; recent-range location; favorable-extreme distance; confirmation consumption |
| Remaining room | M5/M15 swing, session, previous-session/day room; net room in R |
| Impulse quality | M1/M5 displacement and acceleration; volatility expansion; body/wick; directional close streak |
| Pullback state | depth; expansion; completed reclaim/resumption; distance from pullback extreme |
| Multi-timeframe state | separate M1/M5/M15/H1 directional states; alignment/opposition fractions; range/transition |
| Opposing pressure | opposing score and five-minute rate; score dominance; opposing breakout |
| Volatility and stop | structural stop in M1/M5 ATR; inside-noise indicator |
| Confirmation | normalized confirmation move; consumption; persistence scans/seconds; entry drift |
| Cost and execution | cost R, spread/ATR, cost multiple, cost-to-room fraction, spread-median ratio |

No symbol identity is a model feature. No MFE, MAE, target time, terminal return or label is a feature. [Exact feature manifest](feature-manifest.json).

## Development generator evidence

| Month | Resolved | Wins / losses | Net R | Mean R |
|---|---:|---:|---:|---:|
| April | 53 | 25 / 28 | −3 | −0.0566 |
| May | 53 | 25 / 28 | −3 | −0.0566 |
| June | 58 | 33 / 25 | +8 | +0.1379 |
| July | 58 | 26 / 32 | −6 | −0.1034 |
| August | 45 | 22 / 23 | −1 | −0.0222 |

The overall win rate is **49.06%**. Its Wilson 95% interval is **43.12%–55.03%**; the deterministic bootstrap 95% interval for mean standardized payoff is **−0.1386R to +0.1011R**. Four of five months are negative. A separate previously rejected shadow cohort points the same way: 49 resolved episodes produced 21 wins, 28 losses and **−7R**; 76 further paths were censored rather than assigned convenient outcomes.

This does not claim mathematical impossibility of a future edge. It establishes that the archived directional opportunities and the requested causal state do not contain a stable exploitable signal strong enough to promote.

## Two development formulations

The first formulation tested regularized logistic models with five L2 penalties and six ENTER thresholds. Its strongest diagnostic retained 113 of 214 out-of-fold cases, produced **54 wins / 59 losses / −5R**, rejected **44 winners and 37 losses**, had AUC **0.459**, and had **14R** maximum standardized drawdown. It failed expectancy, differential loss rejection, winner retention, monthly stability and concentration robustness.

The second formulation used deterministic three-, five-, eight- and twelve-stump shallow ensembles with four ENTER thresholds and an explicit WAIT band. Its strongest diagnostic was:

| Decision | Cases | Wins / losses | Standardized R |
|---|---:|---:|---:|
| ENTER | 190 | 95 / 95 | 0R |
| WAIT | 17 | 6 / 11 | −5R |
| REJECT | 7 | 5 / 2 | +3R hidden in rejected trades |

That selector retained **89.62% of winners**, but rejected **4.72% of winners and only 1.85% of losses**, and had AUC **0.457**. It produced no expectancy improvement across 190 accepted outcomes and failed expectancy, loss-separation, monthly-usefulness and concentration-robustness gates.

Across the 52 fields, no nonconstant feature kept a predictive direction across all five months. Constant fields appear mechanically stable at AUC 0.5 and carry no separation. The strongest next compact causal formulation therefore failed for the same reason as the logistic model: loss and winner states overlap, and filtering removes at least as much useful opportunity as damage.

[All 46 experiments, folds, gates and feature stability](development-results.json) · [nonpassing model receipt](model-freeze.json).

## Locked holdout and implementation disposition

The requested ten September 8–15 cases remain named in [the holdout seal](holdout-seal.json), but there are no ENTER/WAIT/REJECT decisions and no mechanical attributions for them. Producing those decisions after a failed development search would open the one-time holdout without an eligible frozen candidate and would make its known winners and losses part of model selection.

Because development failed, the task's conditional implementation stages were not reached:

- no production model was frozen;
- no MQL5 candidate source was created;
- no compiler was run, so no source/binary hashes are claimed;
- no orderless VPS integration was started;
- no deployment was performed.

[Implementation status](implementation-status.json) records these conditional skips explicitly. Five regression tests pass, covering causal feature presence, forming-bar exclusion, pre-stop target accounting and holdout isolation. [Test receipt](test-results.json).

The concrete engineering conclusion is that another filter on the current directional candidates is unsupported. The component that constructs proposed directional opportunities must be replaced before a new location/timing selector can be credibly trained. Freezing the best failed filter would discard 5 out-of-fold winners while rejecting only 2 losses and would leave the accepted cohort at 0R and would repeat the same failure under a new name.
