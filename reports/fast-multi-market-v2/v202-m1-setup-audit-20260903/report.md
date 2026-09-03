# V2.202 setup-specific M1 timing audit — 3 September 2026

## Decision

**DO NOT PROMOTE; KEEP THE M1 RULE IN SHADOW.**

The setup-family timing rule separated all four held-out cases: it rejected
the GBPJPY loss and retained the EURJPY, US500-reference, and USDJPY winners.
That is promising, but it is not yet reliable enough to change live trading:
the held-out set contains only three independent FP executions, and the same
rule retained only 5.72% of development-period winning P/L. Deploying it now
would be fitting one recent day and would have removed two large earlier
winners.

No strategy source, version, risk, runner, reward/risk, spread, session,
ownership, or watchdog setting was changed. Nothing was deployed. FXIFY was
not touched.

## Evidence integrity

- Source: FP Markets account 7404213 broker tick caches for August and
  September 2026.
- Coverage: all 15 FP executions from 31 August through 3 September, plus one
  US500 reference signal that executed on FXIFY but was replayed on FP bars.
- Export: 264,383 broker ticks aggregated into 3,328 M1 bars; all 16 cases
  passed.
- Window per case: three hours before entry through 30 minutes after entry.
- Feature cutoff: completed M1 bars only. The forming entry-minute bar and all
  post-entry bars are excluded.
- Cross-check: reconstructed USDJPY absolute M1 trend `2.14125458`, efficiency
  `0.36299766`, pullback depth `0.76923077 ATR`, and reclaim `false` match the
  independently recorded live shadow values to rounding.
- Exporter safety: isolated terminal, `AllowLiveTrading=0`, no `CTrade`,
  `OrderSend`, position-close, modify, or pending-order operation in the probe.
  Post-run FP state remained 0 positions and 0 orders.

## Rules tested

| Rule | Timing requirement |
|---|---|
| Universal M1 trend | Side-aligned M1 trend above 0.20 and path efficiency at least 0.24 |
| Universal reclaim/retention | Pullback reclaim or two completed M1 closes retaining a breakout |
| Setup-family timing V1: continuation | Last completed M1 body or three-bar close change resumes the trade direction |
| Setup-family timing V1: pullback/reversal | Completed M1 reclaim through the detected pullback level |
| Setup-family timing V1: breakout | Two completed M1 closes retain the M5 breakout anchor |

## Walk-forward result

| Rule | Development accepted net | Development winner retention | Held-out accepted net | Held-out winner retention | Held-out loser rejection |
|---|---:|---:|---:|---:|---:|
| No M1 gate | -$352.66 | 100.00% | $512.78 | 100.00% | 0.00% |
| Universal M1 trend | $37.97 | 5.72% | $0.00 | 0.00% | 100.00% |
| Universal reclaim/retention | $37.97 | 5.72% | $30.03 | 3.95% | 100.00% |
| Setup-family timing V1 | -$210.73 | 5.72% | **$760.46** | **100.00%** | **100.00%** |

Development is 31 August–1 September (12 trades). Held-out is 2–3 September
(three independent FP executions plus the US500 cross-broker reference). The
US500 reference is excluded from the independent-FP sample count.

## Required winner/loss comparison

| Case | Result | Side-aligned M1 trend | Last M1 resumes side | 3-bar resumes side | Reclaim | Setup-family decision |
|---|---:|---:|---:|---:|---:|---|
| GBPJPY SELL | -$247.68 / -1.006R | -1.607 | no | no | no | **Reject** |
| EURJPY SELL | +$30.03 / +0.122R | -2.450 | yes | yes | yes | **Accept** |
| US500 BUY reference | +$148.18 / +0.602R | -0.928 | yes | no | no | **Accept** |
| USDJPY SELL | +$582.25 / +2.369R | -2.141 | yes | no | no | **Accept** |

All four were `STRUCTURE_INSIDE` setups. This proves why a blanket M1 trend
alignment gate is wrong: all three winners were counter-trend on the M1 trend
measure at entry. What separated the held-out GBPJPY loss was the absence of
an actual completed-M1 resumption, not its trend label.

The trade-off is material and must remain visible. Setup-family timing V1
would also have rejected the +1.064R GER40 SELL and +1.516R XAUUSD SELL in the
development period. It accepted the old EURUSD BUY loss and one small XAUUSD
scratch. Therefore the held-out success is not yet stable across dates.

## Acceptance result and next move

Promotion threshold: at least eight independent held-out FP executions, at
least 80% winner retention, at least 50% loser rejection, and zero accepted
losers. Current independent held-out count is **3/8**. Result: **FAIL on sample
size and development stability**.

Next move: leave live V2.202 unchanged, keep the existing M1 shadow stream
running, and retain FP broker ticks until at least five more independent FP
executions complete. Re-run this locked rule from those bars without changing
its definition. Only then can it qualify for promotion.

## Verification

- M1 backfill: 16/16 cases PASS.
- Focused no-look-ahead/family-rule tests: 2/2 PASS.
- Full deterministic Python suite: 136/136 PASS.
- MQL5 probe compile: MetaEditor 0 errors / 0 warnings.
- FP runtime after audit: connected, scanner active, autonomous entry enabled,
  VPS ownership granted, one FP terminal, 0 positions, 0 pending orders.
- Live strategy deployment: none.
