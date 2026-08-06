# Phase 6 V6 FP Markets normalized runtime evidence

This file preserves selected evidence markers without raw account login, password, or unredacted terminal logs.

## Connected intake

```text
SOLTRADE_PHASE6_V6_INTAKE_PREFLIGHT | tester=NO | server=FPMarketsSC-Demo | company=First Prudential Markets Limited | demo=YES | account_currency=USD | account_leverage=30 | terminal_build=6090 | terminal_trade_allowed=NO | mql_trade_allowed=NO | orders=0 | positions=0 | symbol_select=YES
SOLTRADE_PHASE6_V6_INTAKE_SYMBOL | symbol=EURUSD | digits=5 | point=0.0000100000 | tick_size=0.0000100000 | tick_value=1.0000000000 | tick_value_profit=1.0000000000 | tick_value_loss=1.0000000000 | contract_size=100000.0000
SOLTRADE_PHASE6_V6_INTAKE_TIME | broker_server_time=2026.08.03 12:34:35 | observed_utc_time=2026.08.03 09:34:35 | observed_utc_offset_seconds=10800 | observed_utc_offset_hours=3.0000 | daylight_saving_status=UNDETERMINED
SOLTRADE_PHASE6_V6_INTAKE_SESSION | weekday=SUNDAY | schedule=CLOSED | source=SymbolInfoSessionTrade | broker_server_timezone=UNRESOLVED
SOLTRADE_PHASE6_V6_INTAKE_SESSION | weekday=MONDAY | schedule=00:01:00-23:59:00 | source=SymbolInfoSessionTrade | broker_server_timezone=UNRESOLVED
SOLTRADE_PHASE6_V6_INTAKE_SESSION | weekday=TUESDAY | schedule=00:01:00-23:59:00 | source=SymbolInfoSessionTrade | broker_server_timezone=UNRESOLVED
SOLTRADE_PHASE6_V6_INTAKE_SESSION | weekday=WEDNESDAY | schedule=00:01:00-23:59:00 | source=SymbolInfoSessionTrade | broker_server_timezone=UNRESOLVED
SOLTRADE_PHASE6_V6_INTAKE_SESSION | weekday=THURSDAY | schedule=00:01:00-23:59:00 | source=SymbolInfoSessionTrade | broker_server_timezone=UNRESOLVED
SOLTRADE_PHASE6_V6_INTAKE_SESSION | weekday=FRIDAY | schedule=00:01:00-23:59:00 | source=SymbolInfoSessionTrade | broker_server_timezone=UNRESOLVED
SOLTRADE_PHASE6_V6_INTAKE_SESSION | weekday=SATURDAY | schedule=CLOSED | source=SymbolInfoSessionTrade | broker_server_timezone=UNRESOLVED
SOLTRADE_PHASE6_V6_INTAKE_AVAILABILITY | first_available_m1_terminal=2023.01.02 00:00:00 | last_available_m1=2026.08.03 12:34:00
SOLTRADE_PHASE6_V6_INTAKE_COMPLETE | status=METADATA_CAPTURED | trade_attempted=NO | orders_created=0 | positions_created=0 | next=REAL_TICK_DATA_QUALIFICATION_ONLY
```

## Connected coverage inspector

```text
SOLTRADE_PHASE6_V6_COVERAGE_PREFLIGHT | tester=NO | server=FPMarketsSC-Demo | demo=YES | terminal_trade_allowed=NO | mql_trade_allowed=NO | orders=0 | positions=0 | strategy=NOT_LOADED | trade_api_calls=NONE
SOLTRADE_PHASE6_V6_COVERAGE_REAL_TICK_AVAILABILITY | broker_reported_start_date=2025.01.02 00:00:00 | first_available_real_tick=2025.01.02 00:00:00.594 | first_day_final_tick=2025.01.02 23:59:58.481 | first_day_tick_count=131588 | copy_ticks_error=0 | copy_ticks_memory_failure=NO | latest_available_real_tick=2026.08.03 12:44:18.538 | requested_v6_interval_has_server_real_ticks=NO
SOLTRADE_PHASE6_V6_COVERAGE_M1_SUMMARY | bars=-1 | requested_first=NONE | requested_final=NONE | server_first_available=1971.01.04 00:00:00 | last_available=2026.08.03 12:44:00 | copy_error=4401 | attempts=120
SOLTRADE_PHASE6_V6_COVERAGE_COMPLETE | status=FAIL_REAL_TICK_HISTORY_STARTS_AFTER_FROZEN_INTERVAL | orders_after=0 | positions_after=0 | trade_attempted=NO | strategy_run=NO | profitability=NOT_CALCULATED | phase7=NO
```

## Strategy Tester controller

```text
EURUSD: ticks data begins from 2025.01.02 00:00
EURUSD: history data begins from 2021.07.01 00:00
EURUSD,H1 (FPMarketsSC-Demo): generating based on real ticks
EURUSD : 2024.01.02 00:00 - 2024.12.24 00:00  no real ticks, every tick generation used
EURUSD,M1: history begins from 2023.01.02 00:04
EURUSD,H1: 18590155 ticks, 6120 bars generated. Test passed in 0:00:26.055
```

“Test passed” above is MT5’s technical completion message, not a SolTrade data-qualification pass.

## Inert qualification probe

```text
SOLTRADE_PHASE6_V4_PROBE_CHUNK_SUMMARY | chunks=357 | retries=0 | memory_errors=0 | timeout_errors=0 | ticks=131072 | first=2024.12.20 13:27:49.565 | final=2024.12.23 23:59:59.000 | aggregate_sha256_chain=d3519880f9a486c0aec1f8d93480eaba108ea92bdb3d59845619e0f72fe4295d
SOLTRADE_PHASE6_V4_PROBE_M1_HCC | bars=366617 | first=2024.01.02 00:00:00 | final=2024.12.23 23:59:00 | copy_error=0 | series_synchronized=YES | series_first=2023.01.02 00:04:00 | gaps_over_15m=54 | unexplained_open_session_gaps=3 | max_open_gap_seconds=5880 | usable=NO
SOLTRADE_PHASE6_V4_PROBE_TICKS | streamed_count=131072 | modeled_count=18590155 | actual_first=2024.12.20 13:27:49.565 | actual_final=2024.12.23 23:59:59.000 | start_boundary_open_gap_seconds=86280 | model_stream_match=NO | usable=NO
SOLTRADE_PHASE6_V4_PROBE_POSTRUN | trading_deals=0 | soltrade_owned_deals=0 | pending_orders=0 | historical_orders=0 | positions=0 | trade_transactions=0 | entry_engine_activity=0 | position_manager_activity=0 | no_new_historical_deal_ticket=YES | initial_balance_unchanged=YES | inert_history_unchanged=YES
SOLTRADE_PHASE6_V4_PROBE_RESULT | status=FAIL | actual_tick_boundaries_qualified=NO | m1_hcc=NO | tick_coverage=NO | zero_trading_deals=YES | zero_orders=YES | zero_positions=YES | authoritative_run=NO | replica=NO | strategy=NOT_LOADED | performance_statistics=NOT_GENERATED | strategy_profitability=NOT_CALCULATED
```
