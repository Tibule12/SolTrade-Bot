#property copyright "SolTrade Bot"
#property link      ""
#property version   "1.000"
#property strict
#property description "Inert connected Phase 6 V7 FP Markets data-qualification observer"
#property description "Reads broker-native ticks and M1 bars only; contains no trade operations."

const string V7_EXPECTED_SERVER = "FPMarketsSC-Demo";
const string V7_EXPECTED_SYMBOL = "EURUSD";
const datetime V7_START_INCLUSIVE = D'2025.01.02 00:00:00';
const datetime V7_END_EXCLUSIVE = D'2025.12.24 00:00:00';
const long V7_GAP_THRESHOLD_SECONDS = 900;
const ulong V7_DAY_MILLISECONDS = 86400000;
const int V7_HASH_BLOCK_TICKS = 4096;
const int V7_MAX_RETRIES = 8;
const int V7_M1_ATTEMPTS = 120;
const int V7_ERROR_NOT_ENOUGH_MEMORY = 4004;
const int V7_ERROR_HISTORY_NOT_FOUND = 4401;
const int V7_ERROR_HISTORY_TIMEOUT = 4403;

MqlRates g_m1_rates[];
long g_trade_transactions = 0;
long g_tick_gaps = 0;
long g_tick_unresolved_open_gaps = 0;
long g_tick_weekend_gaps = 0;
long g_tick_scheduled_non_weekend_gaps = 0;
long g_tick_max_open_segment_seconds = 0;
long g_m1_gaps = 0;
long g_m1_unresolved_open_gaps = 0;
long g_m1_weekend_gaps = 0;
long g_m1_scheduled_non_weekend_gaps = 0;
long g_m1_max_open_segment_seconds = 0;

string V7TimestampMsc(const ulong value)
  {
   if(value == 0)
      return "NONE";
   return TimeToString((datetime)(value / 1000), TIME_DATE | TIME_SECONDS) +
          "." + StringFormat("%03u", (uint)(value % 1000));
  }

datetime V7DayStart(const datetime value)
  {
   MqlDateTime parts;
   TimeToStruct(value, parts);
   parts.hour = 0;
   parts.min = 0;
   parts.sec = 0;
   return StructToTime(parts);
  }

int V7SessionSecond(const datetime value)
  {
   MqlDateTime parts;
   TimeToStruct(value, parts);
   return parts.hour * 3600 + parts.min * 60 + parts.sec;
  }

string V7Clock(const int seconds)
  {
   if(seconds >= 86400)
      return "24:00:00";
   const int safe = seconds < 0 ? 0 : seconds;
   return StringFormat("%02d:%02d:%02d",
                       safe / 3600,
                       (safe % 3600) / 60,
                       safe % 60);
  }

string V7SessionDescription(const datetime value)
  {
   MqlDateTime parts;
   TimeToStruct(value, parts);
   string result = EnumToString((ENUM_DAY_OF_WEEK)parts.day_of_week) + ":";
   int count = 0;
   for(uint index = 0; index < 20; index++)
     {
      datetime from = 0;
      datetime to = 0;
      if(!SymbolInfoSessionTrade(V7_EXPECTED_SYMBOL,
                                 (ENUM_DAY_OF_WEEK)parts.day_of_week,
                                 index,
                                 from,
                                 to))
         break;
      const int from_seconds = V7SessionSecond(from);
      int to_seconds = V7SessionSecond(to);
      if(to_seconds <= from_seconds)
         to_seconds = 86400;
      if(count > 0)
         result += ",";
      result += V7Clock(from_seconds) + "-" + V7Clock(to_seconds);
      count++;
     }
   return result + (count == 0 ? "CLOSED" : "");
  }

void V7LogSessions()
  {
   for(int day = 0; day <= 6; day++)
     {
      datetime from = 0;
      datetime to = 0;
      string schedule = "";
      int count = 0;
      for(uint index = 0; index < 20; index++)
        {
         if(!SymbolInfoSessionTrade(V7_EXPECTED_SYMBOL,
                                    (ENUM_DAY_OF_WEEK)day,
                                    index,
                                    from,
                                    to))
            break;
         const int from_seconds = V7SessionSecond(from);
         int to_seconds = V7SessionSecond(to);
         if(to_seconds <= from_seconds)
            to_seconds = 86400;
         if(count > 0)
            schedule += ",";
         schedule += V7Clock(from_seconds) + "-" + V7Clock(to_seconds);
         count++;
        }
      PrintFormat(
         "SOLTRADE_PHASE6_V7_SESSION | weekday=%s | schedule=%s | source=SymbolInfoSessionTrade | timezone=UNRESOLVED",
         EnumToString((ENUM_DAY_OF_WEEK)day),
         count == 0 ? "CLOSED" : schedule);
     }
  }

long V7MaximumOpenSegmentSeconds(const datetime from_time,
                                 const datetime to_time)
  {
   if(to_time <= from_time)
      return 0;
   long maximum = 0;
   const datetime final_day = V7DayStart(to_time);
   for(datetime day = V7DayStart(from_time);
       day <= final_day;
       day += 86400)
     {
      MqlDateTime parts;
      TimeToStruct(day, parts);
      for(uint index = 0; index < 20; index++)
        {
         datetime from = 0;
         datetime to = 0;
         if(!SymbolInfoSessionTrade(V7_EXPECTED_SYMBOL,
                                    (ENUM_DAY_OF_WEEK)parts.day_of_week,
                                    index,
                                    from,
                                    to))
            break;
         const int from_seconds = V7SessionSecond(from);
         int to_seconds = V7SessionSecond(to);
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

bool V7TouchesWeekend(const datetime from_time,
                      const datetime to_time)
  {
   const datetime final_day = V7DayStart(to_time);
   for(datetime day = V7DayStart(from_time);
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

string V7Sha256(const string value)
  {
   uchar source[];
   uchar key[];
   uchar digest[];
   int source_size = StringToCharArray(value, source, 0, -1, CP_UTF8);
   if(source_size > 0)
      ArrayResize(source, source_size - 1);
   ResetLastError();
   if(CryptEncode(CRYPT_HASH_SHA256, source, key, digest) <= 0)
     {
      PrintFormat("SOLTRADE_PHASE6_V7_HASH_ERROR | error=%d", GetLastError());
      return "";
     }
   string result = "";
   for(int index = 0; index < ArraySize(digest); index++)
      result += StringFormat("%02x", digest[index]);
   return result;
  }

string V7TickCanonical(const MqlTick &tick)
  {
   return StringFormat("%I64u|%.10f|%.10f|%.10f|%I64u|%u|%.10f\n",
                       tick.time_msc,
                       tick.bid,
                       tick.ask,
                       tick.last,
                       tick.volume,
                       tick.flags,
                       tick.volume_real);
  }

string V7HashTickBlock(MqlTick &ticks[],
                       const int start,
                       const int count)
  {
   string canonical = "";
   for(int index = 0; index < count; index++)
      canonical += V7TickCanonical(ticks[start + index]);
   return V7Sha256(canonical);
  }

bool V7TicksIdentical(const MqlTick &left,
                      const MqlTick &right)
  {
   return left.time_msc == right.time_msc &&
          left.bid == right.bid &&
          left.ask == right.ask &&
          left.last == right.last &&
          left.volume == right.volume &&
          left.flags == right.flags &&
          left.volume_real == right.volume_real;
  }

int V7M1BarsInside(const datetime from_time,
                   const datetime to_time,
                   datetime &first,
                   datetime &last)
  {
   first = 0;
   last = 0;
   int count = 0;
   const int total = ArraySize(g_m1_rates);
   for(int index = 0; index < total; index++)
     {
      const datetime value = g_m1_rates[index].time;
      if(value <= from_time)
         continue;
      if(value >= to_time)
         break;
      if(count == 0)
         first = value;
      last = value;
      count++;
     }
   return count;
  }

void V7LogGap(const string layer,
              const long number,
              const datetime previous_time,
              const datetime next_time,
              const ulong previous_msc,
              const ulong next_msc,
              const double bid_before,
              const double ask_before,
              const double bid_after,
              const double ask_after,
              long &unresolved_count,
              long &weekend_count,
              long &scheduled_non_weekend_count,
              long &maximum_open_seconds)
  {
   const long duration_seconds = (long)(next_time - previous_time);
   const long open_seconds =
      V7MaximumOpenSegmentSeconds(previous_time, next_time);
   const bool weekend = V7TouchesWeekend(previous_time, next_time);
   string classification = "";
   string evidence = "";
   if(open_seconds > V7_GAP_THRESHOLD_SECONDS)
     {
      classification = "UNRESOLVED_OPEN_SESSION_GAP";
      evidence = "MT5_SYMBOL_SESSION_REPORTS_OPEN;INTERVAL_SPECIFIC_BROKER_EVIDENCE_ABSENT";
      unresolved_count++;
     }
   else if(weekend)
     {
      classification = "SCHEDULED_WEEKEND_CLOSURE";
      evidence = "MT5_SYMBOL_SESSION_SCHEDULE;WEEKEND_CALENDAR";
      weekend_count++;
     }
   else
     {
      classification = "SCHEDULED_NON_WEEKEND_CLOSURE";
      evidence = "MT5_SYMBOL_SESSION_SCHEDULE";
      scheduled_non_weekend_count++;
     }
   if(open_seconds > maximum_open_seconds)
      maximum_open_seconds = open_seconds;

   datetime m1_first = 0;
   datetime m1_last = 0;
   const int m1_inside = V7M1BarsInside(previous_time,
                                        next_time,
                                        m1_first,
                                        m1_last);
   PrintFormat(
      "SOLTRADE_PHASE6_V7_GAP | layer=%s | gap_number=%I64d | previous=%s | next=%s | duration_seconds=%I64d | open_segment_seconds=%I64d | previous_sessions=%s | next_sessions=%s | classification=%s | supporting_evidence=%s | m1_bars_inside=%d | m1_first_inside=%s | m1_last_inside=%s | bid_before=%.10f | ask_before=%.10f | bid_after=%.10f | ask_after=%.10f",
      layer,
      number,
      layer == "REAL_TICK" ? V7TimestampMsc(previous_msc) :
         TimeToString(previous_time, TIME_DATE | TIME_SECONDS),
      layer == "REAL_TICK" ? V7TimestampMsc(next_msc) :
         TimeToString(next_time, TIME_DATE | TIME_SECONDS),
      duration_seconds,
      open_seconds,
      V7SessionDescription(previous_time),
      V7SessionDescription(next_time),
      classification,
      evidence,
      m1_inside,
      m1_first == 0 ? "NONE" :
         TimeToString(m1_first, TIME_DATE | TIME_SECONDS),
      m1_last == 0 ? "NONE" :
         TimeToString(m1_last, TIME_DATE | TIME_SECONDS),
      bid_before,
      ask_before,
      bid_after,
      ask_after);
  }

bool V7LoadAndScanM1(int &copy_error,
                     int &attempts,
                     datetime &first,
                     datetime &last)
  {
   ArraySetAsSeries(g_m1_rates, false);
   int copied = -1;
   copy_error = 0;
   attempts = 0;
   for(int attempt = 1; attempt <= V7_M1_ATTEMPTS; attempt++)
     {
      attempts = attempt;
      ResetLastError();
      copied = CopyRates(V7_EXPECTED_SYMBOL,
                         PERIOD_M1,
                         V7_START_INCLUSIVE,
                         V7_END_EXCLUSIVE - 1,
                         g_m1_rates);
      copy_error = GetLastError();
      if(copied >= 0)
         break;
      if(copy_error != V7_ERROR_HISTORY_NOT_FOUND &&
         copy_error != V7_ERROR_HISTORY_TIMEOUT)
         break;
      if(attempt == 1 || attempt == V7_M1_ATTEMPTS)
         PrintFormat(
            "SOLTRADE_PHASE6_V7_M1_ATTEMPT | attempt=%d | bars=%d | error=%d",
            attempt,
            copied,
            copy_error);
      Sleep(250);
     }
   if(copied <= 0)
      return false;
   first = g_m1_rates[0].time;
   last = g_m1_rates[copied - 1].time;
   for(int index = 1; index < copied; index++)
     {
      const datetime previous = g_m1_rates[index - 1].time;
      const datetime next = g_m1_rates[index].time;
      if(next - previous <= V7_GAP_THRESHOLD_SECONDS)
         continue;
      g_m1_gaps++;
      V7LogGap("M1",
               g_m1_gaps,
               previous,
               next,
               (ulong)previous * 1000,
               (ulong)next * 1000,
               0.0,
               0.0,
               0.0,
               0.0,
               g_m1_unresolved_open_gaps,
               g_m1_weekend_gaps,
               g_m1_scheduled_non_weekend_gaps,
               g_m1_max_open_segment_seconds);
     }
   const bool synchronized =
      (bool)SeriesInfoInteger(V7_EXPECTED_SYMBOL,
                              PERIOD_M1,
                              SERIES_SYNCHRONIZED);
   PrintFormat(
      "SOLTRADE_PHASE6_V7_M1_SUMMARY | bars=%d | first=%s | final=%s | copy_error=%d | attempts=%d | synchronized=%s | gaps_over_15m=%I64d | unresolved_open_session_gaps=%I64d | scheduled_weekend_gaps=%I64d | scheduled_non_weekend_gaps=%I64d | max_open_segment_seconds=%I64d",
      copied,
      TimeToString(first, TIME_DATE | TIME_SECONDS),
      TimeToString(last, TIME_DATE | TIME_SECONDS),
      copy_error,
      attempts,
      synchronized ? "YES" : "NO",
      g_m1_gaps,
      g_m1_unresolved_open_gaps,
      g_m1_weekend_gaps,
      g_m1_scheduled_non_weekend_gaps,
      g_m1_max_open_segment_seconds);
   return synchronized &&
          copy_error == 0 &&
          first == V7_START_INCLUSIVE &&
          last >= V7_END_EXCLUSIVE - 60;
  }

bool V7StreamRealTicks(ulong &tick_count,
                       ulong &first_tick_msc,
                       ulong &last_tick_msc,
                       string &stream_hash,
                       long &memory_errors,
                       long &timeout_errors,
                       long &retrieval_failures,
                       long &duplicates,
                       long &out_of_order,
                       long &boundary_violations)
  {
   const ulong start_msc = (ulong)V7_START_INCLUSIVE * 1000;
   const ulong end_msc = (ulong)V7_END_EXCLUSIVE * 1000;
   ulong cursor = start_msc;
   tick_count = 0;
   first_tick_msc = 0;
   last_tick_msc = 0;
   memory_errors = 0;
   timeout_errors = 0;
   retrieval_failures = 0;
   duplicates = 0;
   out_of_order = 0;
   boundary_violations = 0;
   stream_hash = V7Sha256("SOLTRADE_PHASE6_V7_FP_MARKETS_REAL_TICK_CHAIN_V1");
   MqlTick previous;
   ZeroMemory(previous);
   bool have_previous = false;
   long chunk_number = 0;

   while(cursor < end_msc)
     {
      const ulong next_day =
         ((cursor / V7_DAY_MILLISECONDS) + 1) * V7_DAY_MILLISECONDS;
      const ulong chunk_end = next_day < end_msc ? next_day : end_msc;
      const ulong requested_to = chunk_end - 1;
      MqlTick ticks[];
      int copied = -1;
      int error = 0;
      int attempts = 0;
      for(int attempt = 1; attempt <= V7_MAX_RETRIES + 1; attempt++)
        {
         attempts = attempt;
         ResetLastError();
         copied = CopyTicksRange(V7_EXPECTED_SYMBOL,
                                 ticks,
                                 COPY_TICKS_ALL,
                                 cursor,
                                 requested_to);
         error = GetLastError();
         if(copied >= 0)
            break;
         if(error == V7_ERROR_NOT_ENOUGH_MEMORY)
            memory_errors++;
         if(error == V7_ERROR_HISTORY_TIMEOUT)
            timeout_errors++;
         if(error != V7_ERROR_NOT_ENOUGH_MEMORY &&
            error != V7_ERROR_HISTORY_TIMEOUT &&
            error != V7_ERROR_HISTORY_NOT_FOUND)
            break;
         Sleep(250);
        }
      if(copied < 0)
        {
         retrieval_failures++;
         PrintFormat(
            "SOLTRADE_PHASE6_V7_TICK_CHUNK_FAILED | requested_from=%s | requested_to=%s | error=%d | attempts=%d",
            V7TimestampMsc(cursor),
            V7TimestampMsc(requested_to),
            error,
            attempts);
         ArrayFree(ticks);
         return false;
        }

      const string chunk_hash = copied == 0 ? V7Sha256("EMPTY_CHUNK") :
         V7Sha256(IntegerToString((long)cursor) + "|" +
                  IntegerToString((long)requested_to) + "|" +
                  IntegerToString(copied) + "|" +
                  V7TickCanonical(ticks[0]) + "|" +
                  V7TickCanonical(ticks[copied - 1]));
      if(chunk_hash == "")
        {
         retrieval_failures++;
         ArrayFree(ticks);
         return false;
        }

      for(int index = 0; index < copied; index++)
        {
         const MqlTick current = ticks[index];
         const ulong value = current.time_msc;
         if(value < start_msc || value >= end_msc ||
            value < cursor || value > requested_to)
            boundary_violations++;
         if(tick_count == 0)
            first_tick_msc = value;
         if(have_previous)
           {
            if(current.time_msc < previous.time_msc)
               out_of_order++;
            if(V7TicksIdentical(previous, current))
               duplicates++;
            if(current.time_msc > previous.time_msc &&
               (ulong)(current.time_msc - previous.time_msc) >
                  (ulong)V7_GAP_THRESHOLD_SECONDS * 1000)
              {
               g_tick_gaps++;
               V7LogGap("REAL_TICK",
                        g_tick_gaps,
                        (datetime)(previous.time_msc / 1000),
                        (datetime)(current.time_msc / 1000),
                        previous.time_msc,
                        current.time_msc,
                        previous.bid,
                        previous.ask,
                        current.bid,
                        current.ask,
                        g_tick_unresolved_open_gaps,
                        g_tick_weekend_gaps,
                        g_tick_scheduled_non_weekend_gaps,
                        g_tick_max_open_segment_seconds);
              }
           }
         previous = current;
         have_previous = true;
         last_tick_msc = value;
         tick_count++;
        }
      stream_hash = V7Sha256(stream_hash + "|" +
                            IntegerToString((long)cursor) + "|" +
                            IntegerToString((long)requested_to) + "|" +
                            IntegerToString(copied) + "|" +
                            chunk_hash);
      chunk_number++;
      PrintFormat(
         "SOLTRADE_PHASE6_V7_TICK_CHUNK | number=%I64d | from=%s | to=%s | ticks=%d | first=%s | final=%s | error=%d | attempts=%d | aggregate_sha256_chain=%s",
         chunk_number,
         V7TimestampMsc(cursor),
         V7TimestampMsc(requested_to),
         copied,
         copied > 0 ? V7TimestampMsc(ticks[0].time_msc) : "NONE",
         copied > 0 ? V7TimestampMsc(ticks[copied - 1].time_msc) : "NONE",
         error,
         attempts,
         stream_hash);
      ArrayFree(ticks);
      cursor = chunk_end;
     }

   PrintFormat(
      "SOLTRADE_PHASE6_V7_TICK_SUMMARY | ticks=%I64u | first=%s | final=%s | chunks=%I64d | memory_errors=%I64d | timeout_errors=%I64d | retrieval_failures=%I64d | duplicates=%I64d | out_of_order=%I64d | boundary_violations=%I64d | gaps_over_15m=%I64d | unresolved_open_session_gaps=%I64d | scheduled_weekend_gaps=%I64d | scheduled_non_weekend_gaps=%I64d | max_open_segment_seconds=%I64d | aggregate_sha256_chain=%s",
      tick_count,
      V7TimestampMsc(first_tick_msc),
      V7TimestampMsc(last_tick_msc),
      chunk_number,
      memory_errors,
      timeout_errors,
      retrieval_failures,
      duplicates,
      out_of_order,
      boundary_violations,
      g_tick_gaps,
      g_tick_unresolved_open_gaps,
      g_tick_weekend_gaps,
      g_tick_scheduled_non_weekend_gaps,
      g_tick_max_open_segment_seconds,
      stream_hash);
   return cursor == end_msc &&
          tick_count > 0 &&
          memory_errors == 0 &&
          retrieval_failures == 0 &&
          out_of_order == 0 &&
          boundary_violations == 0 &&
          stream_hash != "";
  }

int OnInit()
  {
   const bool tester = (bool)MQLInfoInteger(MQL_TESTER);
   const bool demo = AccountInfoInteger(ACCOUNT_TRADE_MODE) ==
                     ACCOUNT_TRADE_MODE_DEMO;
   const string server = AccountInfoString(ACCOUNT_SERVER);
   const bool terminal_trade_allowed =
      (bool)TerminalInfoInteger(TERMINAL_TRADE_ALLOWED);
   const bool mql_trade_allowed = (bool)MQLInfoInteger(MQL_TRADE_ALLOWED);
   const int orders_before = OrdersTotal();
   const int positions_before = PositionsTotal();
   const bool selected = SymbolSelect(V7_EXPECTED_SYMBOL, true);
   PrintFormat(
      "SOLTRADE_PHASE6_V7_PREFLIGHT | tester=%s | server=%s | demo=%s | symbol=%s | chart_period=%s | terminal_trade_allowed=%s | mql_trade_allowed=%s | orders=%d | positions=%d | strategy=NOT_LOADED | trade_api_calls=NONE | generated_tick_path=ABSENT_CONNECTED_COPYTICKS",
      tester ? "YES" : "NO",
      server,
      demo ? "YES" : "NO",
      _Symbol,
      EnumToString(_Period),
      terminal_trade_allowed ? "YES" : "NO",
      mql_trade_allowed ? "YES" : "NO",
      orders_before,
      positions_before);
   if(tester ||
      !demo ||
      server != V7_EXPECTED_SERVER ||
      _Symbol != V7_EXPECTED_SYMBOL ||
      _Period != PERIOD_M1 ||
      terminal_trade_allowed ||
      mql_trade_allowed ||
      orders_before != 0 ||
      positions_before != 0 ||
      !selected)
     {
      Print("SOLTRADE_PHASE6_V7_COMPLETE | outcome=FAIL_TICK_RETRIEVAL | reason=PREFLIGHT_FAILED | trade_attempted=NO");
      ExpertRemove();
      return INIT_FAILED;
     }

   const datetime server_time = TimeTradeServer();
   const datetime utc_time = TimeGMT();
   const long offset = (long)(server_time - utc_time);
   PrintFormat(
      "SOLTRADE_PHASE6_V7_TIME | broker_server_time=%s | observed_utc_time=%s | observed_utc_offset_seconds=%I64d | observed_utc_offset_hours=%.4f | daylight_saving_status=UNDETERMINED | session_timezone=UNRESOLVED",
      TimeToString(server_time, TIME_DATE | TIME_SECONDS),
      TimeToString(utc_time, TIME_DATE | TIME_SECONDS),
      offset,
      (double)offset / 3600.0);
   V7LogSessions();

   int m1_error = 0;
   int m1_attempts = 0;
   datetime m1_first = 0;
   datetime m1_last = 0;
   const bool m1_ok = V7LoadAndScanM1(m1_error,
                                      m1_attempts,
                                      m1_first,
                                      m1_last);

   ulong tick_count = 0;
   ulong first_tick_msc = 0;
   ulong last_tick_msc = 0;
   string stream_hash = "";
   long memory_errors = 0;
   long timeout_errors = 0;
   long retrieval_failures = 0;
   long duplicates = 0;
   long out_of_order = 0;
   long boundary_violations = 0;
   const bool ticks_ok = V7StreamRealTicks(tick_count,
                                           first_tick_msc,
                                           last_tick_msc,
                                           stream_hash,
                                           memory_errors,
                                           timeout_errors,
                                           retrieval_failures,
                                           duplicates,
                                           out_of_order,
                                           boundary_violations);

   const long start_open_gap = first_tick_msc == 0 ? LONG_MAX :
      V7MaximumOpenSegmentSeconds(V7_START_INCLUSIVE,
                                  (datetime)(first_tick_msc / 1000));
   const long end_open_gap = last_tick_msc == 0 ? LONG_MAX :
      V7MaximumOpenSegmentSeconds((datetime)(last_tick_msc / 1000),
                                  V7_END_EXCLUSIVE);
   const bool boundaries_ok = first_tick_msc > 0 &&
                              last_tick_msc > 0 &&
                              start_open_gap <= V7_GAP_THRESHOLD_SECONDS &&
                              end_open_gap <= V7_GAP_THRESHOLD_SECONDS;
   PrintFormat(
      "SOLTRADE_PHASE6_V7_BOUNDARIES | start_inclusive=%s | end_exclusive=%s | first_real_tick=%s | final_real_tick=%s | start_open_gap_seconds=%I64d | end_open_gap_seconds=%I64d | complete=%s",
      TimeToString(V7_START_INCLUSIVE, TIME_DATE | TIME_SECONDS),
      TimeToString(V7_END_EXCLUSIVE, TIME_DATE | TIME_SECONDS),
      V7TimestampMsc(first_tick_msc),
      V7TimestampMsc(last_tick_msc),
      start_open_gap,
      end_open_gap,
      boundaries_ok ? "YES" : "NO");

   string outcome = "DATA_QUALIFICATION_PASSED";
   string reason = "ALL_DATA_GATES_SATISFIED";
   if(!ticks_ok || retrieval_failures > 0 || memory_errors > 0)
     {
      outcome = "FAIL_TICK_RETRIEVAL";
      reason = "COPYTICKS_OR_MEMORY_GATE_FAILED";
     }
   else if(!boundaries_ok)
     {
      outcome = "FAIL_INCOMPLETE_HISTORY_COVERAGE";
      reason = "REAL_TICK_BOUNDARY_COVERAGE_FAILED";
     }
   else if(!m1_ok)
     {
      outcome = "FAIL_M1_HISTORY_UNAVAILABLE";
      reason = "M1_COPY_OR_BOUNDARY_GATE_FAILED";
     }
   else if(g_tick_unresolved_open_gaps > 0 ||
           g_m1_unresolved_open_gaps > 0)
     {
      outcome = "FAIL_UNRESOLVED_OPEN_SESSION_GAPS";
      reason = "OPEN_SESSION_GAP_OVER_900_SECONDS_REMAINS_UNSUPPORTED";
     }
   else if(offset == 0)
     {
      outcome = "FAIL_TIMEZONE_OR_SESSION_AMBIGUITY";
      reason = "BROKER_SERVER_OFFSET_UNRESOLVED";
     }

   PrintFormat(
      "SOLTRADE_PHASE6_V7_COMPLETE | outcome=%s | reason=%s | generated_tick_fallback=NO | connected_copyticks_only=YES | orders_after=%d | positions_after=%d | trade_transactions=%I64d | trade_attempted=NO | strategy_run=NO | profitability=NOT_CALCULATED | optimization=NO | replica=NO | phase7=NO",
      outcome,
      reason,
      OrdersTotal(),
      PositionsTotal(),
      g_trade_transactions);
   ArrayFree(g_m1_rates);
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
   g_trade_transactions++;
   Print("SOLTRADE_PHASE6_V7_UNEXPECTED_TRADE_TRANSACTION | qualification_invalidated=YES");
  }
