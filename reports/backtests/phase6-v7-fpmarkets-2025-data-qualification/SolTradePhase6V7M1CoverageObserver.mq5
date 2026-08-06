#property copyright "SolTrade Bot"
#property link      ""
#property version   "1.000"
#property strict
#property description "Inert timer-deferred Phase 6 V7 M1 coverage observer"
#property description "Reads connected FP Markets M1 bars only; contains no trade operations."

const string V7M1_SERVER = "FPMarketsSC-Demo";
const string V7M1_SYMBOL = "EURUSD";
const datetime V7M1_START = D'2025.01.02 00:00:00';
const datetime V7M1_END = D'2025.12.24 00:00:00';
const long V7M1_GAP_SECONDS = 900;
const int V7M1_MAX_ATTEMPTS = 120;

int g_v7m1_attempts = 0;
long g_v7m1_trade_transactions = 0;

datetime V7M1DayStart(const datetime value)
  {
   MqlDateTime parts;
   TimeToStruct(value, parts);
   parts.hour = 0;
   parts.min = 0;
   parts.sec = 0;
   return StructToTime(parts);
  }

int V7M1SessionSecond(const datetime value)
  {
   MqlDateTime parts;
   TimeToStruct(value, parts);
   return parts.hour * 3600 + parts.min * 60 + parts.sec;
  }

long V7M1MaximumOpenSegment(const datetime from_time,
                            const datetime to_time)
  {
   long maximum = 0;
   const datetime final_day = V7M1DayStart(to_time);
   for(datetime day = V7M1DayStart(from_time);
       day <= final_day;
       day += 86400)
     {
      MqlDateTime parts;
      TimeToStruct(day, parts);
      for(uint index = 0; index < 20; index++)
        {
         datetime from = 0;
         datetime to = 0;
         if(!SymbolInfoSessionTrade(V7M1_SYMBOL,
                                    (ENUM_DAY_OF_WEEK)parts.day_of_week,
                                    index,
                                    from,
                                    to))
            break;
         const int from_seconds = V7M1SessionSecond(from);
         int to_seconds = V7M1SessionSecond(to);
         if(to_seconds <= from_seconds)
            to_seconds = 86400;
         const datetime session_start = day + from_seconds;
         const datetime session_end = day + to_seconds;
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

bool V7M1TouchesWeekend(const datetime from_time,
                        const datetime to_time)
  {
   const datetime final_day = V7M1DayStart(to_time);
   for(datetime day = V7M1DayStart(from_time);
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

void V7M1Stop(const string status,
              const string reason)
  {
   PrintFormat(
      "SOLTRADE_PHASE6_V7_M1_COMPLETE | status=%s | reason=%s | attempts=%d | orders_after=%d | positions_after=%d | trade_transactions=%I64d | trade_attempted=NO | strategy_run=NO | profitability=NOT_CALCULATED",
      status,
      reason,
      g_v7m1_attempts,
      OrdersTotal(),
      PositionsTotal(),
      g_v7m1_trade_transactions);
   EventKillTimer();
   ExpertRemove();
  }

int OnInit()
  {
   const bool valid =
      !(bool)MQLInfoInteger(MQL_TESTER) &&
      AccountInfoInteger(ACCOUNT_TRADE_MODE) == ACCOUNT_TRADE_MODE_DEMO &&
      AccountInfoString(ACCOUNT_SERVER) == V7M1_SERVER &&
      _Symbol == V7M1_SYMBOL &&
      _Period == PERIOD_M1 &&
      !(bool)TerminalInfoInteger(TERMINAL_TRADE_ALLOWED) &&
      !(bool)MQLInfoInteger(MQL_TRADE_ALLOWED) &&
      OrdersTotal() == 0 &&
      PositionsTotal() == 0;
   PrintFormat(
      "SOLTRADE_PHASE6_V7_M1_PREFLIGHT | valid=%s | tester=%s | server=%s | demo=%s | symbol=%s | period=%s | terminal_trade_allowed=%s | mql_trade_allowed=%s | orders=%d | positions=%d | strategy=NOT_LOADED | trade_api_calls=NONE",
      valid ? "YES" : "NO",
      (bool)MQLInfoInteger(MQL_TESTER) ? "YES" : "NO",
      AccountInfoString(ACCOUNT_SERVER),
      AccountInfoInteger(ACCOUNT_TRADE_MODE) == ACCOUNT_TRADE_MODE_DEMO ?
         "YES" : "NO",
      _Symbol,
      EnumToString(_Period),
      (bool)TerminalInfoInteger(TERMINAL_TRADE_ALLOWED) ? "YES" : "NO",
      (bool)MQLInfoInteger(MQL_TRADE_ALLOWED) ? "YES" : "NO",
      OrdersTotal(),
      PositionsTotal());
   if(!valid)
      return INIT_FAILED;
   EventSetTimer(1);
   return INIT_SUCCEEDED;
  }

void OnTimer()
  {
   g_v7m1_attempts++;
   MqlRates rates[];
   ArraySetAsSeries(rates, false);
   ResetLastError();
   const int copied = CopyRates(V7M1_SYMBOL,
                                PERIOD_M1,
                                V7M1_START,
                                V7M1_END - 1,
                                rates);
   const int error = GetLastError();
   if(copied < 0)
     {
      if(g_v7m1_attempts == 1 ||
         g_v7m1_attempts == V7M1_MAX_ATTEMPTS)
         PrintFormat(
            "SOLTRADE_PHASE6_V7_M1_DEFERRED_ATTEMPT | attempt=%d | bars=%d | error=%d | synchronized=%s",
            g_v7m1_attempts,
            copied,
            error,
            (bool)SeriesInfoInteger(V7M1_SYMBOL,
                                    PERIOD_M1,
                                    SERIES_SYNCHRONIZED) ? "YES" : "NO");
      ArrayFree(rates);
      if(g_v7m1_attempts >= V7M1_MAX_ATTEMPTS)
         V7M1Stop("FAIL_M1_HISTORY_UNAVAILABLE",
                  "COPYRATES_ERROR_" + IntegerToString(error));
      return;
     }

   long gap_count = 0;
   long unresolved = 0;
   long weekends = 0;
   long scheduled_non_weekend = 0;
   long maximum_open = 0;
   for(int index = 1; index < copied; index++)
     {
      const datetime previous = rates[index - 1].time;
      const datetime next = rates[index].time;
      const long duration = (long)(next - previous);
      if(duration <= V7M1_GAP_SECONDS)
         continue;
      gap_count++;
      const long open_seconds = V7M1MaximumOpenSegment(previous, next);
      const bool weekend = V7M1TouchesWeekend(previous, next);
      string classification = "";
      string evidence = "";
      if(open_seconds > V7M1_GAP_SECONDS)
        {
         classification = "UNRESOLVED_OPEN_SESSION_GAP";
         evidence = "MT5_SYMBOL_SESSION_REPORTS_OPEN;INTERVAL_SPECIFIC_BROKER_EVIDENCE_ABSENT";
         unresolved++;
        }
      else if(weekend)
        {
         classification = "SCHEDULED_WEEKEND_CLOSURE";
         evidence = "MT5_SYMBOL_SESSION_SCHEDULE;WEEKEND_CALENDAR";
         weekends++;
        }
      else
        {
         classification = "SCHEDULED_NON_WEEKEND_CLOSURE";
         evidence = "MT5_SYMBOL_SESSION_SCHEDULE";
         scheduled_non_weekend++;
        }
      if(open_seconds > maximum_open)
         maximum_open = open_seconds;
      PrintFormat(
         "SOLTRADE_PHASE6_V7_M1_GAP | gap_number=%I64d | previous=%s | next=%s | duration_seconds=%I64d | open_segment_seconds=%I64d | classification=%s | supporting_evidence=%s",
         gap_count,
         TimeToString(previous, TIME_DATE | TIME_SECONDS),
         TimeToString(next, TIME_DATE | TIME_SECONDS),
         duration,
         open_seconds,
         classification,
         evidence);
     }

   const datetime first = copied > 0 ? rates[0].time : 0;
   const datetime last = copied > 0 ? rates[copied - 1].time : 0;
   const bool synchronized =
      (bool)SeriesInfoInteger(V7M1_SYMBOL,
                              PERIOD_M1,
                              SERIES_SYNCHRONIZED);
   const bool complete = copied > 0 &&
                         error == 0 &&
                         synchronized &&
                         first == V7M1_START &&
                         last >= V7M1_END - 60;
   PrintFormat(
      "SOLTRADE_PHASE6_V7_M1_DEFERRED_SUMMARY | bars=%d | first=%s | final=%s | copy_error=%d | attempts=%d | synchronized=%s | gaps_over_15m=%I64d | unresolved_open_session_gaps=%I64d | scheduled_weekend_gaps=%I64d | scheduled_non_weekend_gaps=%I64d | max_open_segment_seconds=%I64d | complete=%s",
      copied,
      first == 0 ? "NONE" : TimeToString(first, TIME_DATE | TIME_SECONDS),
      last == 0 ? "NONE" : TimeToString(last, TIME_DATE | TIME_SECONDS),
      error,
      g_v7m1_attempts,
      synchronized ? "YES" : "NO",
      gap_count,
      unresolved,
      weekends,
      scheduled_non_weekend,
      maximum_open,
      complete ? "YES" : "NO");
   ArrayFree(rates);
   V7M1Stop(complete ? "M1_COVERAGE_CAPTURED" :
                      "FAIL_M1_HISTORY_UNAVAILABLE",
             complete ? "CONNECTED_COPYRATES_COMPLETE" :
                        "M1_BOUNDARY_OR_SYNCHRONIZATION_FAILED");
  }

void OnTick()
  {
  }

void OnTradeTransaction(const MqlTradeTransaction &transaction,
                        const MqlTradeRequest &request,
                        const MqlTradeResult &result)
  {
   g_v7m1_trade_transactions++;
   Print("SOLTRADE_PHASE6_V7_M1_UNEXPECTED_TRADE_TRANSACTION | qualification_invalidated=YES");
  }
