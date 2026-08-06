# Trend Breakout V1 closure report

## Decision

Trend Breakout V1 is retired from further profitability testing. It must not be sent to demo forward testing or live trading.

This decision uses only the immutable Phase 6 V14 evidence at commit `433d976d8041c5e107fead3c41d411059894bbf5`. No V1 rerun or parameter change was performed.

## What worked

The research and trading infrastructure operated correctly:

- all 36 frozen physical Strategy Tester runs passed their evidence checks;
- real ticks, fixed inputs, isolated state, cutoff handling and right-censoring operated as specified;
- commission was reconciled without double counting;
- the 200 ms replica layer was executed independently;
- the Phase 1–5 risk controls kept every formal-cell drawdown below its frozen limit;
- maximum formal-cell relative drawdown was 3.046112%, below the 8%, 10% and 12% Normal, High and Stress limits.

## What failed

V1 did not demonstrate a positive trading edge. Every one of the 18 formal cells had negative adjusted net profit, profit factor below 1.0 and negative expectancy.

Normal/native results were:

| Dataset | Closed trades | Adjusted net profit | Profit factor | Expectancy R | Relative drawdown |
|---|---:|---:|---:|---:|---:|
| Development | 49 | -190.700457 | 0.751767 | -0.154227 | 2.472771% |
| Validation | 28 | -230.152854 | 0.430753 | -0.331387 | 2.741217% |
| Out-of-sample | 17 | -112.354882 | 0.563557 | -0.264554 | 1.308502% |

The frozen OOS sample gate was not met: 17 naturally closed trades were observed versus 50 required. That correctly produced `INCONCLUSIVE_INSUFFICIENT_SAMPLE` at V14. It does not erase the consistent negative evidence in Development, Validation and OOS, and it does not justify advancement to Phase 7.

## Costs and delay were not the primary cause

V1 was already negative under the Normal profile and native execution in every dataset. Increasing supplementary costs made results worse, as expected, but did not create the underlying loss. The 200 ms layer changed Development net profit by approximately -7.55 to -7.73 USD, changed Validation by approximately +0.30 USD, and did not change OOS net profit. The native and delayed layers therefore show the same structural outcome.

## Closure

- V1 infrastructure: operational and evidence-valid.
- V1 risk containment: effective within the frozen drawdown limits.
- Positive edge: not demonstrated.
- Further V1 backtests, parameter changes, optimization and sweeps: prohibited by this closure.
- Demo-forward or live use: prohibited.
- Phase 7: unauthorized.
