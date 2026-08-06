#property copyright "SolTrade Bot"
#property link      ""
#property version   "1.000"
#property strict
#property description "Inert Phase 6 V2 Strategy Tester data-qualification probe"
#property description "Observes tester history only; contains no strategy or trade operations."

input bool EnableEntryPermission              = false;
input bool EnableExecutionPermission          = false;
input bool EnablePositionManagementPermission = false;
input bool PermitStrategyOrders               = false;

const datetime SOLTRADE_PROBE_START_INCLUSIVE =
   D'2024.01.02 00:00:00';
const datetime SOLTRADE_WARMUP_END_EXCLUSIVE =
   D'2024.01.16 00:00:00';
const datetime SOLTRADE_RESEARCH_START_INCLUSIVE =
   D'2024.01.16 00:00:00';
const datetime SOLTRADE_PROBE_END_EXCLUSIVE =
   D'2024.12.24 00:00:00';
const long SOLTRADE_PROBE_GAP_THRESHOLD_SECONDS = 15 * 60;

ulong    g_tick_count = 0;
ulong    g_first_tick_msc = 0;
ulong    g_final_tick_msc = 0;
ulong    g_first_research_tick_msc = 0;
long     g_tick_gap_count = 0;
long     g_unexplained_tick_gap_count = 0;
long     g_max_open_tick_gap_seconds = 0;
long     g_boundary_violation_count = 0;
long     g_trade_transaction_count = 0;
int      g_orders_before = 0;
int      g_positions_before = 0;
int      g_deals_before = 0;
int      g_m1_count = 0;
datetime g_m1_first = 0;
datetime g_m1_final = 0;
long     g_m1_gap_count = 0;
long     g_unexplained_m1_gap_count = 0;
long     g_max_open_m1_gap_seconds = 0;
long     g_m1_series_first = 0;
long     g_m1_terminal_first = 0;
long     g_m1_server_first = 0;
bool     g_m1_synchronized = false;
bool     g_m1_coverage_usable = false;
int      g_m1_error = 0;
int      g_warmup_h1_count = 0;
datetime g_warmup_h1_first = 0;
datetime g_warmup_h1_final = 0;
bool     g_indicator_warmup_available = false;
bool     g_indicator_warmup_checked = false;
bool     g_real_tick_api_available = false;
int      g_real_tick_api_error = 0;
int      g_ema_handle = INVALID_HANDLE;
int      g_atr_handle = INVALID_HANDLE;

string ProbeTimestampMsc(const ulong value)
  {
   if(value == 0)
      return "NONE";
   return TimeToString((datetime)(value / 1000),
                       TIME_DATE | TIME_SECONDS) +
          "." + StringFormat("%03u", (uint)(value % 1000));
  }

datetime ProbeDayStart(const datetime value)
  {
   MqlDateTime parts;
   TimeToStruct(value, parts);
   parts.hour = 0;
   parts.min = 0;
   parts.sec = 0;
   return StructToTime(parts);
  }

int ProbeSessionSecond(const datetime value)
  {
   MqlDateTime parts;
   TimeToStruct(value, parts);
   return parts.hour * 3600 + parts.min * 60 + parts.sec;
  }

long ProbeMaximumOpenSegmentSeconds(const datetime from_time,
                                    const datetime to_time)
  {
   if(to_time <= from_time)
      return 0;

   long maximum = 0;
   const datetime final_day = ProbeDayStart(to_time);
   for(datetime day = ProbeDayStart(from_time);
       day <= final_day;
       day += 86400)
     {
      MqlDateTime day_parts;
      TimeToStruct(day, day_parts);
      for(uint session = 0; session < 20; session++)
        {
         datetime session_from = 0;
         datetime session_to = 0;
         if(!SymbolInfoSessionTrade(
               _Symbol,
               (ENUM_DAY_OF_WEEK)day_parts.day_of_week,
               session,
               session_from,
               session_to))
            break;

         const int from_second = ProbeSessionSecond(session_from);
         int to_second = ProbeSessionSecond(session_to);
         if(to_second <= from_second)
            to_second = 86400;

         const datetime session_start = day + from_second;
         const datetime session_end = day + to_second;
         const datetime overlap_start =
            from_time > session_start ? from_time : session_start;
         const datetime overlap_end =
            to_time < session_end ? to_time : session_end;
         if(overlap_end > overlap_start)
           {
            const long duration =
               (long)(overlap_end - overlap_start);
            if(duration > maximum)
               maximum = duration;
           }
        }
     }
   return maximum;
  }

void ProbeScanM1Coverage()
  {
   MqlRates rates[];
   ArraySetAsSeries(rates, false);
   ResetLastError();
   g_m1_count =
      CopyRates(_Symbol,
                PERIOD_M1,
                SOLTRADE_PROBE_START_INCLUSIVE,
                SOLTRADE_PROBE_END_EXCLUSIVE - 1,
                rates);
   g_m1_error = GetLastError();
   if(g_m1_count > 0)
     {
      g_m1_first = rates[0].time;
      g_m1_final = rates[g_m1_count - 1].time;
      for(int index = 1; index < g_m1_count; index++)
        {
         const long elapsed =
            (long)(rates[index].time - rates[index - 1].time);
         if(elapsed <= SOLTRADE_PROBE_GAP_THRESHOLD_SECONDS)
            continue;
         g_m1_gap_count++;
         const long open_segment =
            ProbeMaximumOpenSegmentSeconds(rates[index - 1].time,
                                           rates[index].time);
         if(open_segment > g_max_open_m1_gap_seconds)
            g_max_open_m1_gap_seconds = open_segment;
         if(open_segment > SOLTRADE_PROBE_GAP_THRESHOLD_SECONDS)
            g_unexplained_m1_gap_count++;
        }
     }

   g_m1_synchronized =
      (bool)SeriesInfoInteger(_Symbol,
                              PERIOD_M1,
                              SERIES_SYNCHRONIZED);
   g_m1_series_first =
      SeriesInfoInteger(_Symbol, PERIOD_M1, SERIES_FIRSTDATE);
   g_m1_terminal_first =
      SeriesInfoInteger(_Symbol,
                        PERIOD_M1,
                        SERIES_TERMINAL_FIRSTDATE);
   g_m1_server_first =
      SeriesInfoInteger(_Symbol,
                        PERIOD_M1,
                        SERIES_SERVER_FIRSTDATE);
   g_m1_coverage_usable =
      g_m1_count > 0 &&
      g_m1_error == 0 &&
      g_m1_first == SOLTRADE_PROBE_START_INCLUSIVE &&
      g_m1_final >= SOLTRADE_PROBE_END_EXCLUSIVE - 60 &&
      g_unexplained_m1_gap_count == 0;
  }

void ProbeScanWarmupBars()
  {
   MqlRates rates[];
   ArraySetAsSeries(rates, false);
   ResetLastError();
   g_warmup_h1_count =
      CopyRates(_Symbol,
                PERIOD_H1,
                SOLTRADE_PROBE_START_INCLUSIVE,
                SOLTRADE_WARMUP_END_EXCLUSIVE - 1,
                rates);
   if(g_warmup_h1_count > 0)
     {
      g_warmup_h1_first = rates[0].time;
      g_warmup_h1_final = rates[g_warmup_h1_count - 1].time;
     }
  }

void ProbeCheckIndicatorWarmup()
  {
   if(g_indicator_warmup_checked)
      return;
   g_indicator_warmup_checked = true;

   double ema[];
   double atr[];
   double highs[];
   double lows[];
   ArraySetAsSeries(ema, true);
   ArraySetAsSeries(atr, true);
   ArraySetAsSeries(highs, true);
   ArraySetAsSeries(lows, true);
   ResetLastError();
   const int ema_copied =
      CopyBuffer(g_ema_handle, 0, 1, 1, ema);
   const int atr_copied =
      CopyBuffer(g_atr_handle, 0, 1, 1, atr);
   const int highs_copied =
      CopyHigh(_Symbol, PERIOD_H1, 1, 20, highs);
   const int lows_copied =
      CopyLow(_Symbol, PERIOD_H1, 1, 20, lows);
   const int error = GetLastError();
   g_indicator_warmup_available =
      g_warmup_h1_count >= 222 &&
      ema_copied == 1 &&
      atr_copied == 1 &&
      highs_copied == 20 &&
      lows_copied == 20 &&
      MathIsValidNumber(ema[0]) &&
      MathIsValidNumber(atr[0]) &&
      atr[0] > 0.0;
   PrintFormat(
      "SOLTRADE_PHASE6_V2_PROBE_INDICATORS | checked_at=%s | warmup_h1_bars=%d | ema200=%s | atr14=%s | donchian20_highs=%d | donchian20_lows=%d | error=%d | available=%s",
      TimeToString(TimeCurrent(), TIME_DATE | TIME_SECONDS),
      g_warmup_h1_count,
      ema_copied == 1 ? "AVAILABLE" : "UNAVAILABLE",
      atr_copied == 1 ? "AVAILABLE" : "UNAVAILABLE",
      highs_copied,
      lows_copied,
      error,
      g_indicator_warmup_available ? "YES" : "NO");
  }

int OnInit()
  {
   const bool permissions_disabled =
      !EnableEntryPermission &&
      !EnableExecutionPermission &&
      !EnablePositionManagementPermission &&
      !PermitStrategyOrders;
   HistorySelect(0, TimeCurrent());
   g_orders_before = OrdersTotal();
   g_positions_before = PositionsTotal();
   g_deals_before = HistoryDealsTotal();

   PrintFormat(
      "SOLTRADE_PHASE6_V2_PROBE_PREFLIGHT | MQL_TESTER=%s | symbol=%s | timeframe=%s | entry_permission=%s | execution_permission=%s | position_management_permission=%s | strategy_orders_permitted=%s | orders=%d | positions=%d | deals=%d",
      (bool)MQLInfoInteger(MQL_TESTER) ? "true" : "false",
      _Symbol,
      EnumToString(_Period),
      EnableEntryPermission ? "true" : "false",
      EnableExecutionPermission ? "true" : "false",
      EnablePositionManagementPermission ? "true" : "false",
      PermitStrategyOrders ? "true" : "false",
      g_orders_before,
      g_positions_before,
      g_deals_before);
   Print(
      "SOLTRADE_PHASE6_V2_PROBE_BOUNDARIES | warmup=[2024.01.02 00:00:00,2024.01.16 00:00:00) | research=[2024.01.16 00:00:00,2024.12.24 00:00:00) | tester=[2024.01.02 00:00:00,2024.12.24 00:00:00) | semantics=START_INCLUSIVE_END_EXCLUSIVE");
   Print(
      "SOLTRADE_PHASE6_V2_PROBE_SCOPE | probe_only=YES | strategy=NOT_LOADED | authoritative_run=NO | replica=NO | optimization=NO | research_decision=NONE | performance_statistics=NOT_GENERATED | trade_api_calls=NONE");

   if(!(bool)MQLInfoInteger(MQL_TESTER) ||
      _Symbol != "EURUSD" ||
      _Period != PERIOD_H1 ||
      !permissions_disabled ||
      g_orders_before != 0 ||
      g_positions_before != 0 ||
      g_deals_before != 0)
     {
      Print("SOLTRADE_PHASE6_V2_PROBE_REJECTED | invalid inert tester preflight");
      return INIT_FAILED;
     }

   g_ema_handle =
      iMA(_Symbol, PERIOD_H1, 200, 0, MODE_EMA, PRICE_CLOSE);
   g_atr_handle = iATR(_Symbol, PERIOD_H1, 14);
   if(g_ema_handle == INVALID_HANDLE ||
      g_atr_handle == INVALID_HANDLE)
     {
      PrintFormat(
         "SOLTRADE_PHASE6_V2_PROBE_REJECTED | indicator handle unavailable | error=%d",
         GetLastError());
      return INIT_FAILED;
     }
   return INIT_SUCCEEDED;
  }

void OnTick()
  {
   MqlTick tick;
   if(!SymbolInfoTick(_Symbol, tick))
      return;

   if(g_tick_count == 0)
     {
      g_first_tick_msc = tick.time_msc;
      MqlTick copied_ticks[];
      ResetLastError();
      const int copied =
         CopyTicks(_Symbol,
                   copied_ticks,
                   COPY_TICKS_ALL,
                   0,
                   10);
      g_real_tick_api_error = GetLastError();
      g_real_tick_api_available = copied >= 0;
      PrintFormat(
         "SOLTRADE_PHASE6_V2_PROBE_TICK_MODEL | CopyTicks=%d | error=%d | real_tick_api_available=%s",
         copied,
         g_real_tick_api_error,
         g_real_tick_api_available ? "YES" : "NO");
     }
   else
     {
      const datetime previous =
         (datetime)(g_final_tick_msc / 1000);
      const datetime current =
         (datetime)(tick.time_msc / 1000);
      if(current - previous >
         SOLTRADE_PROBE_GAP_THRESHOLD_SECONDS)
        {
         g_tick_gap_count++;
         const long open_segment =
            ProbeMaximumOpenSegmentSeconds(previous, current);
         if(open_segment > g_max_open_tick_gap_seconds)
            g_max_open_tick_gap_seconds = open_segment;
         if(open_segment >
            SOLTRADE_PROBE_GAP_THRESHOLD_SECONDS)
            g_unexplained_tick_gap_count++;
        }
     }

   g_final_tick_msc = tick.time_msc;
   g_tick_count++;
   if(tick.time < SOLTRADE_PROBE_START_INCLUSIVE ||
      tick.time >= SOLTRADE_PROBE_END_EXCLUSIVE)
      g_boundary_violation_count++;
   if(g_first_research_tick_msc == 0 &&
      tick.time >= SOLTRADE_RESEARCH_START_INCLUSIVE)
     {
      g_first_research_tick_msc = tick.time_msc;
      ProbeScanWarmupBars();
      ProbeCheckIndicatorWarmup();
     }
  }

void OnTradeTransaction(const MqlTradeTransaction &transaction,
                        const MqlTradeRequest &request,
                        const MqlTradeResult &result)
  {
   g_trade_transaction_count++;
  }

void OnDeinit(const int reason)
  {
   ProbeScanM1Coverage();
   if(g_ema_handle != INVALID_HANDLE)
      IndicatorRelease(g_ema_handle);
   if(g_atr_handle != INVALID_HANDLE)
      IndicatorRelease(g_atr_handle);

   HistorySelect(0, SOLTRADE_PROBE_END_EXCLUSIVE);
   const int orders_after = OrdersTotal();
   const int positions_after = PositionsTotal();
   const int deals_after = HistoryDealsTotal();
   const int history_orders_after = HistoryOrdersTotal();
   const bool tick_coverage_usable =
      g_tick_count > 0 &&
      g_first_tick_msc >=
         (ulong)SOLTRADE_PROBE_START_INCLUSIVE * 1000 &&
      g_final_tick_msc <
         (ulong)SOLTRADE_PROBE_END_EXCLUSIVE * 1000 &&
      g_boundary_violation_count == 0 &&
      g_unexplained_tick_gap_count == 0 &&
      g_real_tick_api_available;
   const bool warmup_usable =
      g_warmup_h1_count >= 222 &&
      g_warmup_h1_first == SOLTRADE_PROBE_START_INCLUSIVE &&
      g_warmup_h1_final <
         SOLTRADE_WARMUP_END_EXCLUSIVE &&
      g_first_research_tick_msc >=
         (ulong)SOLTRADE_RESEARCH_START_INCLUSIVE * 1000 &&
      g_indicator_warmup_available;
   const bool zero_trading =
      g_orders_before == 0 &&
      g_positions_before == 0 &&
      g_deals_before == 0 &&
      orders_after == 0 &&
      positions_after == 0 &&
      deals_after == 0 &&
      history_orders_after == 0 &&
      g_trade_transaction_count == 0;
   const bool passed =
      (bool)MQLInfoInteger(MQL_TESTER) &&
      g_m1_coverage_usable &&
      tick_coverage_usable &&
      warmup_usable &&
      zero_trading;

   PrintFormat(
      "SOLTRADE_PHASE6_V2_PROBE_M1_HCC | bars=%d | first=%s | final=%s | copy_error=%d | series_synchronized=%s | series_first=%s | terminal_first=%s | server_first=%s | gaps_over_15m=%I64d | unexplained_open_session_gaps=%I64d | max_open_gap_seconds=%I64d | usable=%s",
      g_m1_count,
      TimeToString(g_m1_first, TIME_DATE | TIME_SECONDS),
      TimeToString(g_m1_final, TIME_DATE | TIME_SECONDS),
      g_m1_error,
      g_m1_synchronized ? "YES" : "NO",
      TimeToString((datetime)g_m1_series_first,
                   TIME_DATE | TIME_SECONDS),
      TimeToString((datetime)g_m1_terminal_first,
                   TIME_DATE | TIME_SECONDS),
      TimeToString((datetime)g_m1_server_first,
                   TIME_DATE | TIME_SECONDS),
      g_m1_gap_count,
      g_unexplained_m1_gap_count,
      g_max_open_m1_gap_seconds,
      g_m1_coverage_usable ? "YES" : "NO");
   PrintFormat(
      "SOLTRADE_PHASE6_V2_PROBE_WARMUP | h1_bars=%d | first=%s | final=%s | first_research_tick=%s | indicator_warmup_available=%s | usable=%s",
      g_warmup_h1_count,
      TimeToString(g_warmup_h1_first,
                   TIME_DATE | TIME_SECONDS),
      TimeToString(g_warmup_h1_final,
                   TIME_DATE | TIME_SECONDS),
      ProbeTimestampMsc(g_first_research_tick_msc),
      g_indicator_warmup_available ? "YES" : "NO",
      warmup_usable ? "YES" : "NO");
   PrintFormat(
      "SOLTRADE_PHASE6_V2_PROBE_TICKS | count=%I64u | first=%s | final=%s | boundary_violations=%I64d | gaps_over_15m=%I64d | unexplained_open_session_gaps=%I64d | max_open_gap_seconds=%I64d | real_tick_api_available=%s | usable=%s",
      g_tick_count,
      ProbeTimestampMsc(g_first_tick_msc),
      ProbeTimestampMsc(g_final_tick_msc),
      g_boundary_violation_count,
      g_tick_gap_count,
      g_unexplained_tick_gap_count,
      g_max_open_tick_gap_seconds,
      g_real_tick_api_available ? "YES" : "NO",
      tick_coverage_usable ? "YES" : "NO");
   PrintFormat(
      "SOLTRADE_PHASE6_V2_PROBE_POSTRUN | orders=%d | historical_orders=%d | deals=%d | positions=%d | trade_transactions=%I64d | zero_trading=%s | deinit_reason=%d",
      orders_after,
      history_orders_after,
      deals_after,
      positions_after,
      g_trade_transaction_count,
      zero_trading ? "YES" : "NO",
      reason);
   PrintFormat(
      "SOLTRADE_PHASE6_V2_PROBE_RESULT | status=%s | MQL_TESTER=%s | exact_boundaries=%s | m1_hcc=%s | warmup=%s | tick_coverage=%s | zero_orders_deals_positions=%s | authoritative_run=NO | replica=NO | strategy=NOT_LOADED | research_decision=NONE | performance_statistics=NOT_GENERATED",
      passed ? "PASS" : "FAIL",
      (bool)MQLInfoInteger(MQL_TESTER) ? "true" : "false",
      g_boundary_violation_count == 0 ? "YES" : "NO",
      g_m1_coverage_usable ? "YES" : "NO",
      warmup_usable ? "YES" : "NO",
      tick_coverage_usable ? "YES" : "NO",
      zero_trading ? "YES" : "NO");
  }
