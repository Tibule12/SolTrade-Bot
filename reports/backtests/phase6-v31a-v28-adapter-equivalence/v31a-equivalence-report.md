# Phase 6 V31A — V28 external-feed compatibility adapter equivalence proof

## Terminal outcome

`V28_ADAPTER_EQUIVALENCE_PASSED`

The separate research adapter resolves each frozen V28 canonical symbol through one centralized `ResearchSymbol(canonical_symbol)` function. The frozen V28 source and EX5 were not modified. The only behavioral allowance is symbol-name resolution to the isolated `.V31` custom symbols; reporting retains canonical and resolved names.

This is a strategy-equivalence result, not a binary-identical replication. The frozen future label is `STRATEGY_EQUIVALENT_EXTERNAL_FEED_REPLICATION`.

## Exact parity result

- Four canonical original/adapter pairs and eight canonical Strategy Tester runs passed. Ten physical executions occurred in total because the two 2025 adapter runs were repeated after correcting the pre-start custom-symbol history boundary; the adapter binary and strategy rules were unchanged.
- 119 frozen signal identities and 238 physical signal evaluations per side were preserved.
- 734 event rows, 730 transaction rows and 420 complete deal rows were compared.
- 29818 semantic field comparisons were performed.
- Numeric tolerance: 1e-10.
- Maximum observed numeric absolute difference: 0.0.
- Divergences: 0.

The comparison covers signal and decision timing, direction, canonical symbol selection, entry and exit attempts, prices, volume, stop levels, spread/execution/risk blocks, trade identifiers, complete deal economics, adjusted trade results, profit factor, expectancy and drawdown.

## Original and adapter metrics

Both sides produced the same value in every row.

| Physical run | Closed trades | Adjusted net USD | Profit factor | Expectancy R | Drawdown |
|---|---:|---:|---:|---:|---:|
| 01-v28-2025-development-native | 70 | 492.11891769 | 1.444959773965 | 0.139418157517 | 4.432586657911% |
| 02-v28-2026-preseal-development-native | 35 | 257.61379801 | 1.350552981933 | 0.148563863102 | 6.174049195719% |
| 03-v28-2025-development-delay200 | 70 | 491.50973033 | 1.443965994864 | 0.139254109115 | 4.434802954890% |
| 04-v28-2026-preseal-development-delay200 | 35 | 258.79011960 | 1.352735014384 | 0.149217896893 | 6.160953776315% |

## Data clone

The isolated custom symbols contain 202,101,002 FP Markets ticks. Imported and reloaded counts are identical, with 0 tick mismatches. The already-consumed pre-start export contains 421,907 FP Markets M1 rates; all were reapplied and reloaded with 0 mismatches. No external feed was downloaded or inspected.

## Restrictions preserved

No optimization or tuning occurred. No Dukascopy data was downloaded. No 2018–2024 profitability replication was run. No connected, demo-forward or live order was placed; trading activity existed only inside isolated Strategy Tester simulations. Phase 1–5 production code and frozen V28 remain unchanged. External-feed replication is not started or authorized in V31A.
