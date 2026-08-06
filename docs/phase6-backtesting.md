# Phase 6 — Frozen Backtest and Reconciliation Protocol

## Current gate

Phase 6 code provides tester-only gates, per-run state isolation, artifact
generation, chronological cash-flow reporting, replica reconciliation, and
deterministic safety tests. It does not authorize a Strategy Tester run.

The proposed manifest is
`reports/backtests/phase6-proposed-manifest/proposed-frozen-manifest.json`.
Its status must remain
`HISTORY_UNAVAILABLE_FOR_PROPOSED_MATRIX`. None of the nine authoritative
runs or nine replicas may start. A replacement interval is a separate
`PHASE6-PROPOSED-V2` review item and is not an execution authorization.

Phase 6 does not add or change strategy signals, risk calculations, order
construction, position ownership, exit rules, retry behavior, demo automation,
or live trading. It performs no optimization.

## Authoritative matrix

The proposed full interval is
`[2024-01-01 00:00:00, 2026-07-01 00:00:00)`. Start is inclusive and end is
exclusive. It is split by elapsed duration into:

| Dataset | Inclusive start | Exclusive end | Duration |
|---|---:|---:|---:|
| Development | 2024-01-01 00:00:00 | 2025-04-01 00:00:00 | 456 days |
| Validation | 2025-04-01 00:00:00 | 2025-11-15 00:00:00 | 228 days |
| Out of sample | 2025-11-15 00:00:00 | 2026-07-01 00:00:00 | 228 days |

Each dataset has Normal, High, and Stress profiles, producing nine
authoritative runs. Every authoritative run has one replica. The model is
`Every tick based on real ticks` with a fixed execution delay. MT5 Random Delay
must not be combined with the real-tick matrix.

Any future random-delay experiment must use a compatible generated-tick model,
must be labelled supplementary and non-comparable, and must disclose its seed,
repeat count, and platform limitations.

## Latency and costs

The frozen base delay `D` is the nearest 50 ms to the median of at least 30
successful server round trips, with exact halves rounded upward. The proposed
evidence has 30 TCP-connect round trips, a median of 193.5 ms, and `D = 200 ms`.
Raw timestamps and measurements are preserved in
`latency-observations.csv`. It was collected in one session; multiple sessions
remain preferable, but the mandatory 30-observation gate is satisfied.

| Profile | Fixed delay | Supplementary multiplier |
|---|---:|---:|
| Normal | `D = 200 ms` | `0.00` |
| High | `2D = 400 ms` | `0.50` |
| Stress | `4D = 800 ms` | `1.00` |

Native MT5 fills already contain native spread, commission, swap, fees, and
slippage. The supplementary layer uses:

```text
supplementary_charge = native_friction × supplementary_multiplier
adjusted_trade_net = native_trade_net - supplementary_charge
```

It never subtracts native friction twice. Adjusted net profit, gross profit,
gross loss, expectancy, profit factor, drawdown, annualized return,
concentration, and equity curve are rebuilt from the chronological adjusted
trade sequence. Native MT5 statistics are never scaled.

Outputs always retain two layers:

- `NATIVE_MT5`: native Tester statistics and the separately exported native MT5
  report;
- `SUPPLEMENTARY_NOT_BROKER_NATIVE`: cost-adjusted reporting that is never
  described as a broker fill.

Supplementary costs never feed signals, sizing, entry, position management, or
risk locks.

## Canonical trading identity and isolation

The canonical SHA-256 material contains every strategy, risk, market,
environment, dataset, date, cost, fixed-delay, tester, source-build, and
execution input that can affect trading or statistics. The authoritative run
and its replica must have identical canonical material and
`TradingInputHash`.

`ExecutionInstanceId` is deliberately excluded. It is used only below:

```text
<state root>/<TradingInputHash>/<ExecutionInstanceId>/
<artifact root>/<TradingInputHash>/<ExecutionInstanceId>/
```

The ID and the derived roots do not reach StrategyBreakout, RiskEngine,
ExecutionEngine, PositionManager planning, or metric calculations. The MQL
safety fixture compares authoritative and replica signal direction, volume,
entry, stop, and magic number. The static test prohibits any instance-ID
reference in those four trading modules. A non-empty state or artifact
namespace rejects initialization, preventing reused state from contaminating a
run.

Authoritative and replica `.set` files are not claimed to be byte-identical:
their `ExecutionInstanceId` values must differ. Every trading input and the
resulting canonical trading-input hash must match within the pair.

## Date, warm-up, and boundary evidence

Indicator warm-up is separate from the registered dataset. The manifest records
the first warm-up bar, actual first tick, and actual final tick. Entry and close
plans reject a completed signal candle outside `[start,end)`, so no warm-up
order can enter the test or its statistics.

Each reconstructed position records both `crosses_start_boundary` and
`crosses_end_boundary`. An unexplained start-boundary position indicates state
contamination. Boundary positions, deal cash flows, native Tester net, and the
reconstructed total must reconcile within one cent or the run is invalid.

## Pre-registered acceptance rules

A valid result must have positive adjusted net profit and positive adjusted
expectancy. The remaining profile rules are:

| Profile | Adjusted profit factor | Maximum adjusted equity drawdown |
|---|---:|---:|
| Normal | `> 1.15` | `< 8.00%` |
| High | `>= 1.05` | `<= 10.00%` |
| Stress | `>= 1.00` | `<= 12.00%` |

For every profile:

- the best individual trade may contribute at most 20% of positive net profit;
- the best calendar year or registered subperiod may contribute at most 40%;
- a run shorter than four years uses five equal chronological subperiods;
- an out-of-sample result requires at least 50 naturally closed trades;
- fewer than 50 is `INCONCLUSIVE_INSUFFICIENT_SAMPLE`, never a pass;
- the strategy must never be changed merely to increase trade count.

Across Development, Validation, and Out of Sample under the same cost profile:

- each normalized expectancy must be at least 50% of the largest;
- each annualized return must be at least 50% of the largest;
- the maximum minus minimum profit factor may not exceed `0.40`.

## Reporting-only uncertainty

`tools/phase6_analyze.py` performs 100,000 deterministic-seed bootstrap paths
and 100,000 trade-order reshuffles. It reports 90% and 95% expectancy confidence
intervals, median/90th/95th percentile simulated drawdown, and probability of
ending with negative net profit.

The individual-trade bootstrap assumes independently resampled historical
trade returns. It does not reproduce serial dependence, market regimes, or the
strategy's time-based lock state. All uncertainty output is reporting-only and
cannot modify Phase 1–5 behavior or an acceptance statistic.

## Required artifacts and invalidation

Every run must retain:

- the native MT5 Strategy Tester report;
- `run_manifest.csv` and `canonical_trading_inputs.txt`;
- the exact `.set` file;
- the journal;
- `trade_cashflows.csv`;
- `native_mt5_summary.csv`;
- `supplementary_adjusted_summary.csv`;
- `reconciliation.csv`;
- supplementary analysis JSON;
- tester logs and history-quality messages.

`tools/phase6_reconcile_pair.py` requires the pair's canonical material,
trading hash, first/final ticks, native summary, adjusted summary,
reconciliation, chronological trade cash flows, normalized journal, and
fixed-delay economic results to match. Native reports and `.set` files are not
claimed byte-identical because they include presentation metadata and different
instance IDs.

Any journal mismatch, missing report, missing metadata, history change, reused
state/artifact namespace, reconciliation failure, trading-input hash mismatch,
or failure to reproduce the fixed-delay result invalidates the affected run.
`tools/phase6_verify_history.py` must validate every frozen file's size and
SHA-256 immediately before and after every run.

## History freeze blocker

The non-trading connected collector acquired all 30 in-range easyMarkets TKC
months (`202401` through `202606`); `202607.tkc` is explicitly out of range.
It recorded 58,542,679 ticks, zero copy failures, and zero weekday dates with
no ticks. The exact first tick is `2024-01-01 22:10:00.021` and the exact final
tick is `2026-06-30 23:59:55.707`.

The proposed interval is still unavailable because the collector found 12
gaps longer than 15 minutes inside the broker's weekly sessions. It also
recorded incomplete connected `CopyRates(M1)` access: 841 failed dates and
available bars only from `2026-04-21 07:31:00` through
`2026-06-30 23:59:00`. Raw 2024–2026 HCC files, the H1 cache, symbol
specification, sessions, terminal build, every TKC, and the acquisition
messages are independently hashed in
`reports/backtests/phase6-prerun-evidence/aggregate-history-identity.sha256`.

The longest full-day cache segment before a candidate gap is
`[2024-01-02, 2024-12-24)`. Reserving a deterministic 14-calendar-day
indicator warm-up produces the review-only `PHASE6-PROPOSED-V2` research
interval `[2024-01-16, 2024-12-24)`. No strategy result was viewed when
selecting it. Its dates and splits require review before new canonical
trading-input hashes are registered.

The one authorized connected safety run also remains an invalidating gate: it
reported 65 passed and 1 failed because the 50-trade sample fixture put 100% of
profit in one reporting subperiod. The fixture timing was corrected without
changing the 40% concentration rule and compiles with zero warnings, but a
second connected run was not authorized or performed.
