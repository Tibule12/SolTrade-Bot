# All-three live damage audit — September 15, 2026

**Decision: `DEPLOYMENT_IS_CURRENTLY_LOSING`.** From the flat September 13 deployment baseline through the latest read-only snapshots, FP lost **$3,917.09 / 3.9996R** on four consecutive trades. FXIFY 10K lost **$190.69 / 2.0243R** on its two closed trades, and FXIFY 100K lost **$1,992.14 / 2.0105R** on its two closed trades. No closed trade reached +1R, no profit was banked, and no runner was created.

> **Operating instruction after this audit:** keep all three accounts active and leave every trade, stop and setting unchanged. This supersedes the pause recommendation originally made from the snapshot.

The snapshots were captured directly from the existing VPS runtime and evidence files at 15:53–15:54 UTC (17:53–17:54 SAST). No replay, portal session, order, position, setting, source, binary or deployment was changed.

## Account damage since the September 13 baseline

| Account | Baseline equity | Snapshot equity | Equity change | Closed W/L | Closed result | Open position | Risk from snapshot equity to broker stop |
|---|---:|---:|---:|---:|---:|---|---:|
| FP 7404213 | $99,579.64 | $95,662.55 | **-$3,917.09 (-3.934%)** | 0 / 4 | -$3,917.09 / -3.9996R | None | $0.00 |
| FXIFY 10K 7196820 | $10,039.41 | $9,849.14 | **-$190.27 (-1.895%)** | 0 / 2 | -$190.69 / -2.0243R | US500 sell | $94.08 |
| FXIFY 100K 7198096 | $100,321.36 | $98,406.60 | **-$1,914.76 (-1.909%)** | 0 / 2 | -$1,992.14 / -2.0105R | US500 sell | $1,054.12 |

The two open US500 positions account for the difference between closed cash and the FXIFY equity changes at the snapshot: approximately **+$0.42** on 10K and **+$77.38** on 100K, including any live account effects represented in equity. If both positions reach their existing broker stops from the captured equity, the deployment-era equity changes would be approximately **-$284.35 (-2.832%)** and **-$2,968.88 (-2.959%)**, respectively.

Across the three accounts, the eight closed position instances lost **$6,099.92**. They represent four distinct market signals because XAUUSD and GER40/DE30 were copied across accounts. All four distinct signals lost.

## Every closed trade

| Account | Symbol | Direction | Entry UTC | Result | Peak | Banked | Final state / exit |
|---|---|---|---|---:|---:|---|---|
| FP | XAUUSD.r | Sell | 09-14 13:38:51 | -$990.00 / -1.0000R | +0.3506R | No | `HEALTHY_POSITION` / structural stop |
| FP | USDJPY.r | Sell | 09-14 19:20:30 | -$985.77 / -1.0000R | +0.0141R | No | `ENTRY_PROBATION` / structural stop |
| FP | US100 | Sell | 09-15 05:40:40 | -$975.83 / -1.0000R | +0.0000R | No | `ENTRY_PROBATION` / structural stop |
| FP | GER40 | Sell | 09-15 08:21:02 | -$965.49 / -0.9997R | +0.6808R | No | `PRE_BANK_GIVEBACK` / structural stop |
| FXIFY 10K | XAUUSD.r | Sell | 09-14 13:38:51 | -$93.06 / -1.0197R | +0.2783R | No | `HEALTHY_POSITION` / structural stop |
| FXIFY 10K | DE30.r | Sell | 09-15 08:21:01 | -$97.63 / -1.0046R | +0.7179R | No | `PRE_BANK_GIVEBACK` / structural stop |
| FXIFY 100K | XAUUSD.r | Sell | 09-14 13:38:51 | -$999.60 / -1.0059R | +0.3021R | No | `HEALTHY_POSITION` / structural stop |
| FXIFY 100K | DE30.r | Sell | 09-15 08:21:01 | -$992.54 / -1.0046R | +0.7179R | No | `PRE_BANK_GIVEBACK` / structural stop |

The only active trades at the snapshot were matching FXIFY US500 sells opened at 15:18 UTC. Both were still in `HEALTHY_POSITION`, had reached a sampled peak of +0.3152R, and had not banked.

## What failed

This result is primarily an **entry-selection failure**. The manager received no +1R winner to bank. USDJPY and US100 failed almost immediately, while still in entry probation. XAUUSD reached only +0.28R to +0.35R before reversing into its structural stop. Changing the profit-banking manager cannot repair trades that never approach the banking objective.

The German-index trade also exposes a remaining payoff weakness. The repaired state machine did move from `PRE_BANK_PROFIT` to `PRE_BANK_GIVEBACK`; it was not trapped in the old state. The trade then moved from approximately +0.68R/+0.72R to a full structural loss. No `PRE_BANK_GIVEBACK_FAILED` exit fired because the configured causal-failure detector did not become true. The manager intentionally suppresses its generic soft exit in this state, so without that specific causal signal the full stop remains authoritative. This produced a sampled peak-to-final giveback of about **1.68R to 1.72R** on the same market signal across all three accounts.

The deployed payoff claim is therefore not being delivered in this cohort:

- closed win rate: **0%** on eight account-level positions and four distinct signals;
- +1R reaches: **0**;
- partial banks: **0**;
- runners: **0**;
- full structural losses: **8 of 8 closed positions**;
- `PRE_BANK_GIVEBACK_FAILED` exits: **0**.

This is not enough data to estimate long-run expectancy, but it is enough to reject the claim that the currently deployed configuration is demonstrating controlled losses and materially larger winners. Continuing autonomous entries would expose all three accounts to an unproven entry policy after a synchronized losing cohort.

## Operational finding

All three runtimes were connected, autonomous and ownership-granted. The losses are real strategy outcomes recorded by the deployed builds, rather than evidence that a terminal stopped or the ownership guard failed. FP was flat at the snapshot. Both FXIFY accounts still had one open US500 position and no pending orders.

The audit initially recommended pausing new autonomous entries. The user subsequently directed that all three accounts continue running unchanged. No pause, close, stop movement or configuration change was performed.

[Machine-readable snapshot](snapshot.json) · [trade-level results](trades.csv) · [raw FP runtime](raw-fp-runtime.csv) · [raw FP events](raw-fp-events.csv) · [raw FXIFY 10K runtime](raw-fxify-10k-runtime.csv) · [raw FXIFY 10K events](raw-fxify-10k-events.csv) · [raw FXIFY 100K runtime](raw-fxify-100k-runtime.csv) · [raw FXIFY 100K events](raw-fxify-100k-events.csv)
