#property copyright "SolTrade Bot"
#property link      ""
#property version   "1.000"
#property strict
#property description "Inert Phase 6 V6 connected coverage inspector"
#property description "Reports real-tick availability and M1 gaps; contains no trade operations."

const string V6_SERVER = "FPMarketsSC-Demo";
const string V6_SYMBOL = "EURUSD";
const datetime V6_START = D'2024.01.02 00:00:00';
const datetime V6_END = D'2024.12.24 00:00:00';
const datetime V6_REPORTED_TICK_START = D'2025.01.02 00:00:00';
const long V6_GAP_THRESHOLD_SECONDS = 900;

datetime V6DayStart(const datetime value)
  {
   MqlDateTime parts;
   TimeToStruct(value, parts);
   parts.hour = 0;
   parts.min = 0;
   parts.sec = 0;
   return StructToTime(parts);
  }

int V6SessionSecond(const datetime value)
  {
   MqlDateTime parts;
   TimeToStruct(value, parts);
   return parts.hour * 3600 + parts.min * 60 + parts.sec;
  }

long V6MaximumOpenSegment(const datetime from_time,
                          const datetime to_time)
  {
   if(to_time <= from_time)
      return 0;
   long maximum = 0;
   const datetime final_day = V6DayStart(to_time);
   for(datetime day = V6DayStart(from_time);
       day <= final_day;
       day += 86400)
     {
      MqlDateTime parts;
      TimeToStruct(day, parts);
      for(uint session = 0; session < 20; session++)
        {
         datetime session_from = 0;
         datetime session_to = 0;
         if(!SymbolInfoSessionTrade(V6_SYMBOL,
                                    (ENUM_DAY_OF_WEEK)parts.day_of_week,
                                    session,
                                    session_from,
                                    session_to))
            break;
         const int from_second = V6SessionSecond(session_from);
         int to_second = V6SessionSecond(session_to);
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
            const long duration = (long)(overlap_end - overlap_start);
            if(duration > maximum)
               maximum = duration;
           }
        }
     }
   return maximum;
  }

bool V6TouchesWeekend(const datetime from_time,
                      const datetime to_time)
  {
   const datetime final_day = V6DayStart(to_time);
   for(datetime day = V6DayStart(from_time);
       day <= final_day;
       day += 86400)
     {
      MqlDateTime parts;
      TimeToStruct(day, parts);
      if(parts.day_of_week == 0 || parts.day_of_week == 6)
         return true;
     }
   return false;
  }

string V6Timestamp(const datetime value)
  {
   return value == 0 ? "NONE" :
      TimeToString(value, TIME_DATE | TIME_SECONDS);
  }

string V6TimestampMsc(const ulong value)
  {
   if(value == 0)
      return "NONE";
   return TimeToString((datetime)(value / 1000),
                       TIME_DATE | TIME_SECONDS) +
          "." + StringFormat("%03u", (uint)(value % 1000));
  }

int OnInit()
  {
   const bool tester = (bool)MQLInfoInteger(MQL_TESTER);
   const bool demo =
      AccountInfoInteger(ACCOUNT_TRADE_MODE) == ACCOUNT_TRADE_MODE_DEMO;
   const bool terminal_trade_allowed =
      (bool)TerminalInfoInteger(TERMINAL_TRADE_ALLOWED);
   const bool mql_trade_allowed =
      (bool)MQLInfoInteger(MQL_TRADE_ALLOWED);
   const int orders_before = OrdersTotal();
   const int positions_before = PositionsTotal();
   const string server = AccountInfoString(ACCOUNT_SERVER);
   PrintFormat(
      "SOLTRADE_PHASE6_V6_COVERAGE_PREFLIGHT | tester=%s | server=%s | demo=%s | terminal_trade_allowed=%s | mql_trade_allowed=%s | orders=%d | positions=%d | strategy=NOT_LOADED | trade_api_calls=NONE",
      tester ? "YES" : "NO",
      server,
      demo ? "YES" : "NO",
      terminal_trade_allowed ? "YES" : "NO",
      mql_trade_allowed ? "YES" : "NO",
      orders_before,
      positions_before);
   if(tester ||
      server != V6_SERVER ||
      !demo ||
      terminal_trade_allowed ||
      mql_trade_allowed ||
      orders_before != 0 ||
      positions_before != 0 ||
      !SymbolSelect(V6_SYMBOL, true))
     {
      Print(
         "SOLTRADE_PHASE6_V6_COVERAGE_REJECTED | reason=CONNECTED_DEMO_PREFLIGHT_FAILED | trade_attempted=NO");
      ExpertRemove();
      return INIT_FAILED;
     }

   MqlTick ticks[];
   ArraySetAsSeries(ticks, false);
   ResetLastError();
   const int copied_ticks =
      CopyTicksRange(V6_SYMBOL,
                     ticks,
                     COPY_TICKS_ALL,
                     (ulong)V6_REPORTED_TICK_START * 1000,
                     (ulong)(V6_REPORTED_TICK_START + 86400) * 1000 - 1);
   const int tick_copy_error = GetLastError();
   const ulong first_tick_msc =
      copied_ticks > 0 ? (ulong)ticks[0].time_msc : 0;
   const ulong copied_final_tick_msc =
      copied_ticks > 0 ? (ulong)ticks[copied_ticks - 1].time_msc : 0;
   MqlTick latest_tick;
   ZeroMemory(latest_tick);
   const bool latest_tick_available = SymbolInfoTick(V6_SYMBOL, latest_tick);
   PrintFormat(
      "SOLTRADE_PHASE6_V6_COVERAGE_REAL_TICK_AVAILABILITY | broker_reported_start_date=2025.01.02 00:00:00 | first_available_real_tick=%s | first_day_final_tick=%s | first_day_tick_count=%d | copy_ticks_error=%d | copy_ticks_memory_failure=%s | latest_available_real_tick=%s | requested_v6_interval_has_server_real_ticks=NO",
      V6TimestampMsc(first_tick_msc),
      V6TimestampMsc(copied_final_tick_msc),
      copied_ticks,
      tick_copy_error,
      tick_copy_error == 4004 ? "YES" : "NO",
      latest_tick_available ? V6TimestampMsc(latest_tick.time_msc) : "NONE");
   ArrayFree(ticks);

   MqlRates rates[];
   ArraySetAsSeries(rates, false);
   int copied_rates = -1;
   int rates_error = 0;
   int rates_attempt = 0;
   int rates_attempts_made = 0;
   for(rates_attempt = 0; rates_attempt < 120; rates_attempt++)
     {
      rates_attempts_made = rates_attempt + 1;
      ResetLastError();
      copied_rates =
         CopyRates(V6_SYMBOL,
                   PERIOD_M1,
                   V6_START,
                   V6_END - 1,
                   rates);
      rates_error = GetLastError();
      PrintFormat(
         "SOLTRADE_PHASE6_V6_COVERAGE_M1_ATTEMPT | attempt=%d | bars=%d | error=%d",
         rates_attempt + 1,
         copied_rates,
         rates_error);
      if(copied_rates >= 0)
         break;
      if(rates_error != 4401 && rates_error != 4403)
         break;
      ArrayFree(rates);
      Sleep(250);
     }
   long gaps_over_threshold = 0;
   long scheduled_weekend_closures = 0;
   long scheduled_non_weekend_closures = 0;
   long unresolved_open_session_gaps = 0;
   long maximum_open_segment_seconds = 0;
   if(copied_rates > 0)
     {
      for(int index = 1; index < copied_rates; index++)
        {
         const datetime previous = rates[index - 1].time;
         const datetime next = rates[index].time;
         const long elapsed = (long)(next - previous);
         if(elapsed <= V6_GAP_THRESHOLD_SECONDS)
            continue;
         gaps_over_threshold++;
         const long open_segment = V6MaximumOpenSegment(previous, next);
         if(open_segment > maximum_open_segment_seconds)
            maximum_open_segment_seconds = open_segment;
         string classification = "UNRESOLVED_OPEN_SESSION_M1_GAP";
         string evidence =
            "MT5_SYMBOL_SESSION_REPORTS_OPEN;BROKER_EVIDENCE_REQUIRED";
         if(open_segment <= V6_GAP_THRESHOLD_SECONDS)
           {
            if(V6TouchesWeekend(previous, next))
              {
               classification = "SCHEDULED_WEEKEND_CLOSURE";
               evidence = "MT5_SESSION_SCHEDULE;WEEKEND_CALENDAR";
               scheduled_weekend_closures++;
              }
            else
              {
               classification = "MT5_SCHEDULED_NON_WEEKEND_CLOSURE";
               evidence = "MT5_SESSION_SCHEDULE";
               scheduled_non_weekend_closures++;
              }
           }
         else
            unresolved_open_session_gaps++;
         PrintFormat(
            "SOLTRADE_PHASE6_V6_COVERAGE_M1_GAP | gap_number=%I64d | previous_bar=%s | next_bar=%s | elapsed_seconds=%I64d | mt5_open_segment_seconds=%I64d | classification=%s | supporting_evidence=%s",
            gaps_over_threshold,
            V6Timestamp(previous),
            V6Timestamp(next),
            elapsed,
            open_segment,
            classification,
            evidence);
        }
     }
   const datetime first_m1 =
      copied_rates > 0 ? rates[0].time : 0;
   const datetime final_m1 =
      copied_rates > 0 ? rates[copied_rates - 1].time : 0;
   const datetime server_first_m1 =
      (datetime)SeriesInfoInteger(V6_SYMBOL,
                                  PERIOD_M1,
                                  SERIES_SERVER_FIRSTDATE);
   const datetime last_available_m1 =
      (datetime)SeriesInfoInteger(V6_SYMBOL,
                                  PERIOD_M1,
                                  SERIES_LASTBAR_DATE);
   ArrayFree(rates);
   PrintFormat(
      "SOLTRADE_PHASE6_V6_COVERAGE_M1_SUMMARY | bars=%d | requested_first=%s | requested_final=%s | server_first_available=%s | last_available=%s | copy_error=%d | attempts=%d | gaps_over_15m=%I64d | scheduled_weekend_closures=%I64d | scheduled_non_weekend_closures=%I64d | unresolved_open_session_gaps=%I64d | max_open_segment_seconds=%I64d",
      copied_rates,
      V6Timestamp(first_m1),
      V6Timestamp(final_m1),
      V6Timestamp(server_first_m1),
      V6Timestamp(last_available_m1),
      rates_error,
      rates_attempts_made,
      gaps_over_threshold,
      scheduled_weekend_closures,
      scheduled_non_weekend_closures,
      unresolved_open_session_gaps,
      maximum_open_segment_seconds);
   PrintFormat(
      "SOLTRADE_PHASE6_V6_COVERAGE_COMPLETE | status=FAIL_REAL_TICK_HISTORY_STARTS_AFTER_FROZEN_INTERVAL | orders_after=%d | positions_after=%d | trade_attempted=NO | strategy_run=NO | profitability=NOT_CALCULATED | phase7=NO",
      OrdersTotal(),
      PositionsTotal());
   ExpertRemove();
   return INIT_SUCCEEDED;
  }

void OnTick()
  {
  }

void OnTradeTransaction(const MqlTradeTransaction &transaction,
                        const MqlTradeRequest &request,
                        const MqlTradeResult &result)
  {
   Print(
      "SOLTRADE_PHASE6_V6_COVERAGE_UNEXPECTED_TRADE_TRANSACTION | qualification_invalidated=YES");
  }
