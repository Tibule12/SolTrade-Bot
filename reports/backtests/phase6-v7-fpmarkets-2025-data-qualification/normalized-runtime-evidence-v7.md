# Phase 6 V7 normalized runtime evidence

Raw terminal logs are not committed because they contain account identifiers. These exact normalized markers exclude credentials and account login.

```text
SOLTRADE_PHASE6_V7_PREFLIGHT | tester=NO | server=FPMarketsSC-Demo | demo=YES | symbol=EURUSD | chart_period=PERIOD_M1 | terminal_trade_allowed=NO | mql_trade_allowed=NO | orders=0 | positions=0 | strategy=NOT_LOADED | trade_api_calls=NONE | generated_tick_path=ABSENT_CONNECTED_COPYTICKS
SOLTRADE_PHASE6_V7_TIME | broker_server_time=2026.08.03 13:03:38 | observed_utc_time=2026.08.03 10:03:38 | observed_utc_offset_seconds=10800 | observed_utc_offset_hours=3.0000 | daylight_saving_status=UNDETERMINED | session_timezone=UNRESOLVED
SOLTRADE_PHASE6_V7_TICK_SUMMARY | ticks=20682267 | first=2025.01.02 00:00:00.594 | final=2025.12.23 23:59:59.877 | chunks=356 | memory_errors=0 | timeout_errors=0 | retrieval_failures=0 | duplicates=0 | out_of_order=0 | boundary_violations=0 | gaps_over_15m=53 | unresolved_open_session_gaps=3 | scheduled_weekend_gaps=50 | scheduled_non_weekend_gaps=0 | max_open_segment_seconds=3625 | aggregate_sha256_chain=e99a26088b65bee930c50c07e6d714c459cf8e5528ac5aeebcfed65d0a9c2eb6
SOLTRADE_PHASE6_V7_BOUNDARIES | start_inclusive=2025.01.02 00:00:00 | end_exclusive=2025.12.24 00:00:00 | first_real_tick=2025.01.02 00:00:00.594 | final_real_tick=2025.12.23 23:59:59.877 | start_open_gap_seconds=0 | end_open_gap_seconds=0 | complete=YES
SOLTRADE_PHASE6_V7_COMPLETE | outcome=FAIL_M1_HISTORY_UNAVAILABLE | reason=M1_COPY_OR_BOUNDARY_GATE_FAILED | generated_tick_fallback=NO | connected_copyticks_only=YES | orders_after=0 | positions_after=0 | trade_transactions=0 | trade_attempted=NO | strategy_run=NO | profitability=NOT_CALCULATED | optimization=NO | replica=NO | phase7=NO
SOLTRADE_PHASE6_V7_M1_DEFERRED_ATTEMPT | attempt=1 | bars=-1 | error=4401 | synchronized=YES
SOLTRADE_PHASE6_V7_M1_DEFERRED_ATTEMPT | attempt=120 | bars=-1 | error=4401 | synchronized=YES
SOLTRADE_PHASE6_V7_M1_COMPLETE | status=FAIL_M1_HISTORY_UNAVAILABLE | reason=COPYRATES_ERROR_4401 | attempts=120 | orders_after=0 | positions_after=0 | trade_transactions=0 | trade_attempted=NO | strategy_run=NO | profitability=NOT_CALCULATED
```

The complete 53-record tick-gap marker set is normalized into `complete-gap-report-v7.json`.
