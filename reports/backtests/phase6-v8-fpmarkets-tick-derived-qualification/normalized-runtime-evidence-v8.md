# Phase 6 V8 normalized runtime evidence

Only V8 data qualification and an inert tester capability probe were run. The source logs remain in the isolated FP Markets Wine prefix. Account credentials and login identifiers are omitted.

## Connected tick-derived bar construction

```text
SOLTRADE_PHASE6_V8_BAR_PREFLIGHT | valid=YES | tester=NO | server=FPMarketsSC-Demo | demo=YES | symbol=EURUSD | terminal_trade_allowed=NO | mql_trade_allowed=NO | orders=0 | positions=0 | strategy=NOT_LOADED | trade_api_calls=NONE | generated_ticks=PROHIBITED
SOLTRADE_PHASE6_V8_ALIGNMENT | bucket_clock=BROKER_SERVER_TIMESTAMP | m1_floor_milliseconds=60000 | h1_floor_milliseconds=3600000 | broker_server_time=2026.08.03 13:24:51 | observed_utc_time=2026.08.03 10:24:51 | observed_offset_seconds=10800 | observed_offset_hours=3.0000 | dst_status=UNDETERMINED | historical_session_timezone=AMBIGUOUS_DISCLOSED | utc_rebucketing=NO
SOLTRADE_PHASE6_V8_BAR_SUMMARY | ticks=20682267 | first_tick=2025.01.02 00:00:00.594 | final_tick=2025.12.23 23:59:59.877 | chunks=356 | memory_errors=0 | timeout_errors=0 | retrieval_failures=0 | invalid_tick_prices=0 | m1_bars=365245 | first_m1=2025.01.02 00:00:00.000 | final_m1=2025.12.23 23:59:00.000 | h1_bars=6097 | first_h1=2025.01.02 00:00:00.000 | final_h1=2025.12.23 23:00:00.000 | tick_gaps=53 | unresolved_gaps=3 | weekend_gaps=50 | scheduled_other_gaps=0 | expected_unresolved_matches=3 | unexpected_unresolved=0 | source_chain_sha256=2c53e0e69a7f37e12122f8a14d1f576467eea23d320590345a41560ffcb5fda
SOLTRADE_PHASE6_V8_BAR_COMPLETE | outcome=BAR_CONSTRUCTION_COMPLETE | reason=REAL_TICK_M1_H1_FILES_WRITTEN | orders_after=0 | positions_after=0 | trade_transactions=0 | trade_attempted=NO | strategy_run=NO | profitability=NOT_CALCULATED | generated_ticks=NO | interpolation=NO
```

## Inert real-tick tester probe

The first launch failed closed before processing ticks because the tester's one initial-deposit `DEAL_TYPE_BALANCE` record was conservatively treated as a deal. The final probe distinguishes that administrative record from trading deals and still requires zero orders, positions, non-balance deals, and trade transactions.

```text
EURUSD,H1 (FPMarketsSC-Demo): generating based on real ticks
SOLTRADE_PHASE6_V8_TESTER_PROBE_PREFLIGHT | valid=YES | MQL_TESTER=true | symbol=EURUSD | period=PERIOD_H1 | entry_permission=false | execution_permission=false | position_management_permission=false | strategy_orders_permitted=false | orders=0 | positions=0 | history_deals=1 | nonbalance_deals=0 | tester_balance_records=1 | strategy=NOT_LOADED | trade_api_calls=NONE | profitability=NOT_CALCULATED
EURUSD : real ticks begin from 2025.01.02 00:00:00
SOLTRADE_PHASE6_V8_TESTER_PROBE_TICKS | count=20682265 | first=2025.01.02 00:00:00.594 | final=2025.12.23 23:59:58.664 | expected_count=20682267 | expected_first=2025.01.02 00:00:00.594 | expected_final=2025.12.23 23:59:59.877 | boundary_violations=0 | out_of_order=0 | exact_connected_stream_match=NO
SOLTRADE_PHASE6_V8_TESTER_PROBE_POSTRUN | orders=0 | historical_orders=0 | history_deals=1 | nonbalance_deals=0 | tester_balance_records=1 | positions=0 | trade_transactions=0 | zero_trading=YES | deinit_reason=1
SOLTRADE_PHASE6_V8_TESTER_PROBE_RESULT | status=FAIL | exact_connected_stream_match=NO | zero_orders_deals_positions=YES | strategy=NOT_LOADED | performance_statistics=NOT_GENERATED | profitability=NOT_CALCULATED | trade_api_calls=NONE
EURUSD,H1: 20682265 ticks, 6097 bars generated.
```

No generated-tick fallback message occurred in the V8 run window.

## Connected tail diagnosis

```text
SOLTRADE_PHASE6_V8_TAIL_PREFLIGHT | valid=YES | server=FPMarketsSC-Demo | demo=YES | symbol=EURUSD | terminal_trade_allowed=NO | mql_trade_allowed=NO | orders=0 | positions=0 | strategy=NOT_LOADED | trade_api_calls=NONE
SOLTRADE_PHASE6_V8_TAIL_SUMMARY | copied=7 | error=0 | from=2025.12.23 23:59:55.000 | to=2025.12.23 23:59:59.999
SOLTRADE_PHASE6_V8_TAIL_TICK | index=4 | timestamp=2025.12.23 23:59:58.664 | bid=1.1794200000 | ask=1.1796100000 | flags=1158
SOLTRADE_PHASE6_V8_TAIL_TICK | index=5 | timestamp=2025.12.23 23:59:59.369 | bid=1.1793900000 | ask=1.1795800000 | flags=1158
SOLTRADE_PHASE6_V8_TAIL_TICK | index=6 | timestamp=2025.12.23 23:59:59.877 | bid=1.1793800000 | ask=1.1795700000 | flags=1158
SOLTRADE_PHASE6_V8_TAIL_COMPLETE | strategy_run=NO | profitability=NOT_CALCULATED | orders_created=0 | positions_created=0 | trade_api_calls=NONE
```

The final two connected bid/ask price ticks were not delivered to the tester EA's `OnTick()` before deinitialization. The mismatch remains unresolved and fails the frozen exact-stream probe gate.
