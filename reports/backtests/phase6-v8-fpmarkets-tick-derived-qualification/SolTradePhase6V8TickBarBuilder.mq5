#property copyright "SolTrade Bot"
#property link      ""
#property version   "1.000"
#property strict
#property description "Inert Phase 6 V8 connected real-tick M1/H1 bar builder"
#property description "No strategy, interpolation, generated prices, or trade operations."

const string V8_SERVER = "FPMarketsSC-Demo";
const string V8_SYMBOL = "EURUSD";
const datetime V8_START = D'2025.01.02 00:00:00';
const datetime V8_END = D'2025.12.24 00:00:00';
const ulong V8_DAY_MILLISECONDS = 86400000;
const ulong V8_M1_MILLISECONDS = 60000;
const ulong V8_H1_MILLISECONDS = 3600000;
const long V8_GAP_SECONDS = 900;
const int V8_MAX_RETRIES = 8;
const int V8_ERROR_MEMORY = 4004;
const int V8_ERROR_HISTORY_NOT_FOUND = 4401;
const int V8_ERROR_HISTORY_TIMEOUT = 4403;
const string V8_M1_FILE = "SolTradePhase6V8DerivedM1.csv";
const string V8_H1_FILE = "SolTradePhase6V8DerivedH1.csv";

struct V8Bar
  {
   bool initialized;
   ulong bucket_msc;
   double bid_open;
   double bid_high;
   double bid_low;
   double bid_close;
   double ask_open;
   double ask_high;
   double ask_low;
   double ask_close;
   double spread_open;
   double spread_high;
   double spread_low;
   double spread_close;
   ulong tick_count;
   ulong first_tick_msc;
   ulong last_tick_msc;
   ulong observed_bid_count;
   ulong observed_ask_count;
  };

long g_trade_transactions = 0;
long g_invalid_tick_prices = 0;
long g_tick_gaps = 0;
long g_unresolved_tick_gaps = 0;
long g_weekend_tick_gaps = 0;
long g_scheduled_other_tick_gaps = 0;
long g_expected_unresolved_matches = 0;
long g_unexpected_unresolved_gaps = 0;
long g_m1_bars = 0;
long g_h1_bars = 0;
ulong g_m1_first_bucket = 0;
ulong g_m1_last_bucket = 0;
ulong g_h1_first_bucket = 0;
ulong g_h1_last_bucket = 0;

string V8TimestampMsc(const ulong value)
  {
   if(value == 0)
      return "NONE";
   return TimeToString((datetime)(value / 1000), TIME_DATE | TIME_SECONDS) +
          "." + StringFormat("%03u", (uint)(value % 1000));
  }

datetime V8DayStart(const datetime value)
  {
   MqlDateTime parts;
   TimeToStruct(value, parts);
   parts.hour = 0;
   parts.min = 0;
   parts.sec = 0;
   return StructToTime(parts);
  }

int V8SessionSecond(const datetime value)
  {
   MqlDateTime parts;
   TimeToStruct(value, parts);
   return parts.hour * 3600 + parts.min * 60 + parts.sec;
  }

long V8MaximumOpenSegment(const datetime from_time,
                          const datetime to_time)
  {
   long maximum = 0;
   const datetime final_day = V8DayStart(to_time);
   for(datetime day = V8DayStart(from_time);
       day <= final_day;
       day += 86400)
     {
      MqlDateTime parts;
      TimeToStruct(day, parts);
      for(uint index = 0; index < 20; index++)
        {
         datetime from = 0;
         datetime to = 0;
         if(!SymbolInfoSessionTrade(V8_SYMBOL,
                                    (ENUM_DAY_OF_WEEK)parts.day_of_week,
                                    index,
                                    from,
                                    to))
            break;
         const int from_seconds = V8SessionSecond(from);
         int to_seconds = V8SessionSecond(to);
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

bool V8TouchesWeekend(const datetime from_time,
                      const datetime to_time)
  {
   const datetime final_day = V8DayStart(to_time);
   for(datetime day = V8DayStart(from_time);
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

bool V8ExpectedUnresolvedGap(const ulong previous_msc,
                             const ulong next_msc)
  {
   const ulong gap1_previous =
      (ulong)D'2025.02.05 00:15:05' * 1000 + 295;
   const ulong gap1_next =
      (ulong)D'2025.02.05 00:37:12' * 1000 + 833;
   const ulong gap2_previous =
      (ulong)D'2025.03.07 23:57:59' * 1000 + 5;
   const ulong gap2_next =
      (ulong)D'2025.03.10 00:59:59' * 1000 + 698;
   const ulong gap3_previous =
      (ulong)D'2025.08.06 16:13:41' * 1000 + 24;
   const ulong gap3_next =
      (ulong)D'2025.08.06 17:14:06' * 1000 + 171;
   return (previous_msc == gap1_previous && next_msc == gap1_next) ||
          (previous_msc == gap2_previous && next_msc == gap2_next) ||
          (previous_msc == gap3_previous && next_msc == gap3_next);
  }

string V8Sha256(const string value)
  {
   uchar source[];
   uchar key[];
   uchar digest[];
   int source_size = StringToCharArray(value, source, 0, -1, CP_UTF8);
   if(source_size > 0)
      ArrayResize(source, source_size - 1);
   ResetLastError();
   if(CryptEncode(CRYPT_HASH_SHA256, source, key, digest) <= 0)
      return "";
   string result = "";
   for(int index = 0; index < ArraySize(digest); index++)
      result += StringFormat("%02x", digest[index]);
   return result;
  }

void V8ResetBar(V8Bar &bar)
  {
   ZeroMemory(bar);
   bar.initialized = false;
  }

void V8StartBar(V8Bar &bar,
                const ulong bucket_msc,
                const MqlTick &tick,
                const double point)
  {
   bar.initialized = true;
   bar.bucket_msc = bucket_msc;
   bar.bid_open = tick.bid;
   bar.bid_high = tick.bid;
   bar.bid_low = tick.bid;
   bar.bid_close = tick.bid;
   bar.ask_open = tick.ask;
   bar.ask_high = tick.ask;
   bar.ask_low = tick.ask;
   bar.ask_close = tick.ask;
   const double spread = (tick.ask - tick.bid) / point;
   bar.spread_open = spread;
   bar.spread_high = spread;
   bar.spread_low = spread;
   bar.spread_close = spread;
   bar.tick_count = 1;
   bar.first_tick_msc = tick.time_msc;
   bar.last_tick_msc = tick.time_msc;
   bar.observed_bid_count = tick.bid > 0.0 ? 1 : 0;
   bar.observed_ask_count = tick.ask > 0.0 ? 1 : 0;
  }

void V8UpdateBar(V8Bar &bar,
                 const MqlTick &tick,
                 const double point)
  {
   if(tick.bid > bar.bid_high)
      bar.bid_high = tick.bid;
   if(tick.bid < bar.bid_low)
      bar.bid_low = tick.bid;
   if(tick.ask > bar.ask_high)
      bar.ask_high = tick.ask;
   if(tick.ask < bar.ask_low)
      bar.ask_low = tick.ask;
   bar.bid_close = tick.bid;
   bar.ask_close = tick.ask;
   const double spread = (tick.ask - tick.bid) / point;
   if(spread > bar.spread_high)
      bar.spread_high = spread;
   if(spread < bar.spread_low)
      bar.spread_low = spread;
   bar.spread_close = spread;
   bar.tick_count++;
   bar.last_tick_msc = tick.time_msc;
   if(tick.bid > 0.0)
      bar.observed_bid_count++;
   if(tick.ask > 0.0)
      bar.observed_ask_count++;
  }

bool V8WriteBar(const int handle,
                const string layer,
                const V8Bar &bar)
  {
   if(handle == INVALID_HANDLE || !bar.initialized)
      return false;
   const string line = StringFormat(
      "%s,%.10f,%.10f,%.10f,%.10f,%.10f,%.10f,%.10f,%.10f,%.4f,%.4f,%.4f,%.4f,%I64u,%s,%s,%I64u,%I64u\n",
      TimeToString((datetime)(bar.bucket_msc / 1000),
                   TIME_DATE | TIME_SECONDS),
      bar.bid_open,
      bar.bid_high,
      bar.bid_low,
      bar.bid_close,
      bar.ask_open,
      bar.ask_high,
      bar.ask_low,
      bar.ask_close,
      bar.spread_open,
      bar.spread_high,
      bar.spread_low,
      bar.spread_close,
      bar.tick_count,
      V8TimestampMsc(bar.first_tick_msc),
      V8TimestampMsc(bar.last_tick_msc),
      bar.observed_bid_count,
      bar.observed_ask_count);
   if(FileWriteString(handle, line) <= 0)
      return false;
   if(layer == "M1")
     {
      if(g_m1_bars == 0)
         g_m1_first_bucket = bar.bucket_msc;
      g_m1_last_bucket = bar.bucket_msc;
      g_m1_bars++;
     }
   else
     {
      if(g_h1_bars == 0)
         g_h1_first_bucket = bar.bucket_msc;
      g_h1_last_bucket = bar.bucket_msc;
      g_h1_bars++;
     }
   return true;
  }

bool V8ProcessTick(const MqlTick &tick,
                   const double point,
                   const int m1_handle,
                   const int h1_handle,
                   V8Bar &m1,
                   V8Bar &h1)
  {
   if(tick.bid <= 0.0 || tick.ask <= 0.0 || tick.ask < tick.bid)
      g_invalid_tick_prices++;
   const ulong m1_bucket =
      (tick.time_msc / V8_M1_MILLISECONDS) * V8_M1_MILLISECONDS;
   const ulong h1_bucket =
      (tick.time_msc / V8_H1_MILLISECONDS) * V8_H1_MILLISECONDS;
   if(!m1.initialized)
      V8StartBar(m1, m1_bucket, tick, point);
   else if(m1.bucket_msc != m1_bucket)
     {
      if(!V8WriteBar(m1_handle, "M1", m1))
         return false;
      V8StartBar(m1, m1_bucket, tick, point);
     }
   else
      V8UpdateBar(m1, tick, point);

   if(!h1.initialized)
      V8StartBar(h1, h1_bucket, tick, point);
   else if(h1.bucket_msc != h1_bucket)
     {
      if(!V8WriteBar(h1_handle, "H1", h1))
         return false;
      V8StartBar(h1, h1_bucket, tick, point);
     }
   else
      V8UpdateBar(h1, tick, point);
   return true;
  }

int OnInit()
  {
   const bool preflight =
      !(bool)MQLInfoInteger(MQL_TESTER) &&
      AccountInfoInteger(ACCOUNT_TRADE_MODE) == ACCOUNT_TRADE_MODE_DEMO &&
      AccountInfoString(ACCOUNT_SERVER) == V8_SERVER &&
      _Symbol == V8_SYMBOL &&
      !(bool)TerminalInfoInteger(TERMINAL_TRADE_ALLOWED) &&
      !(bool)MQLInfoInteger(MQL_TRADE_ALLOWED) &&
      OrdersTotal() == 0 &&
      PositionsTotal() == 0 &&
      !FileIsExist(V8_M1_FILE) &&
      !FileIsExist(V8_H1_FILE);
   PrintFormat(
      "SOLTRADE_PHASE6_V8_BAR_PREFLIGHT | valid=%s | tester=%s | server=%s | demo=%s | symbol=%s | terminal_trade_allowed=%s | mql_trade_allowed=%s | orders=%d | positions=%d | m1_output_exists=%s | h1_output_exists=%s | strategy=NOT_LOADED | trade_api_calls=NONE | generated_ticks=PROHIBITED",
      preflight ? "YES" : "NO",
      (bool)MQLInfoInteger(MQL_TESTER) ? "YES" : "NO",
      AccountInfoString(ACCOUNT_SERVER),
      AccountInfoInteger(ACCOUNT_TRADE_MODE) == ACCOUNT_TRADE_MODE_DEMO ?
         "YES" : "NO",
      _Symbol,
      (bool)TerminalInfoInteger(TERMINAL_TRADE_ALLOWED) ? "YES" : "NO",
      (bool)MQLInfoInteger(MQL_TRADE_ALLOWED) ? "YES" : "NO",
      OrdersTotal(),
      PositionsTotal(),
      FileIsExist(V8_M1_FILE) ? "YES" : "NO",
      FileIsExist(V8_H1_FILE) ? "YES" : "NO");
   if(!preflight)
      return INIT_FAILED;

   const datetime server_time = TimeTradeServer();
   const datetime utc_time = TimeGMT();
   const long offset = (long)(server_time - utc_time);
   PrintFormat(
      "SOLTRADE_PHASE6_V8_ALIGNMENT | bucket_clock=BROKER_SERVER_TIMESTAMP | m1_floor_milliseconds=60000 | h1_floor_milliseconds=3600000 | broker_server_time=%s | observed_utc_time=%s | observed_offset_seconds=%I64d | observed_offset_hours=%.4f | dst_status=UNDETERMINED | historical_session_timezone=AMBIGUOUS_DISCLOSED | utc_rebucketing=NO",
      TimeToString(server_time, TIME_DATE | TIME_SECONDS),
      TimeToString(utc_time, TIME_DATE | TIME_SECONDS),
      offset,
      (double)offset / 3600.0);

   const int m1_handle =
      FileOpen(V8_M1_FILE, FILE_WRITE | FILE_TXT | FILE_ANSI);
   const int h1_handle =
      FileOpen(V8_H1_FILE, FILE_WRITE | FILE_TXT | FILE_ANSI);
   if(m1_handle == INVALID_HANDLE || h1_handle == INVALID_HANDLE)
     {
      PrintFormat(
         "SOLTRADE_PHASE6_V8_BAR_COMPLETE | outcome=FAIL_TICK_DERIVED_BAR_CONSTRUCTION | reason=OUTPUT_FILE_OPEN_FAILED | error=%d | trade_attempted=NO",
         GetLastError());
      if(m1_handle != INVALID_HANDLE)
         FileClose(m1_handle);
      if(h1_handle != INVALID_HANDLE)
         FileClose(h1_handle);
      return INIT_FAILED;
     }
   const string header =
      "timestamp,bid_open,bid_high,bid_low,bid_close,ask_open,ask_high,ask_low,ask_close,spread_points_open,spread_points_high,spread_points_low,spread_points_close,tick_count,first_tick_timestamp,last_tick_timestamp,observed_bid_count,observed_ask_count\n";
   FileWriteString(m1_handle, header);
   FileWriteString(h1_handle, header);

   const double point = SymbolInfoDouble(V8_SYMBOL, SYMBOL_POINT);
   const ulong requested_start = (ulong)V8_START * 1000;
   const ulong requested_end = (ulong)V8_END * 1000;
   ulong cursor = requested_start;
   ulong tick_count = 0;
   ulong first_tick_msc = 0;
   ulong final_tick_msc = 0;
   long chunks = 0;
   long memory_errors = 0;
   long timeout_errors = 0;
   long retrieval_failures = 0;
   string chain = V8Sha256("SOLTRADE_PHASE6_V8_TICK_DERIVED_BAR_SOURCE_CHAIN_V1");
   MqlTick previous;
   ZeroMemory(previous);
   bool have_previous = false;
   V8Bar m1;
   V8Bar h1;
   V8ResetBar(m1);
   V8ResetBar(h1);
   bool construction_ok = point > 0.0 && chain != "";

   while(cursor < requested_end && construction_ok)
     {
      const ulong next_day =
         ((cursor / V8_DAY_MILLISECONDS) + 1) * V8_DAY_MILLISECONDS;
      const ulong chunk_end = next_day < requested_end ?
         next_day : requested_end;
      const ulong requested_to = chunk_end - 1;
      MqlTick ticks[];
      int copied = -1;
      int error = 0;
      int attempts = 0;
      for(int attempt = 1; attempt <= V8_MAX_RETRIES + 1; attempt++)
        {
         attempts = attempt;
         ResetLastError();
         copied = CopyTicksRange(V8_SYMBOL,
                                 ticks,
                                 COPY_TICKS_ALL,
                                 cursor,
                                 requested_to);
         error = GetLastError();
         if(copied >= 0)
            break;
         if(error == V8_ERROR_MEMORY)
            memory_errors++;
         if(error == V8_ERROR_HISTORY_TIMEOUT)
            timeout_errors++;
         if(error != V8_ERROR_MEMORY &&
            error != V8_ERROR_HISTORY_TIMEOUT &&
            error != V8_ERROR_HISTORY_NOT_FOUND)
            break;
         Sleep(250);
        }
      if(copied < 0)
        {
         retrieval_failures++;
         construction_ok = false;
         PrintFormat(
            "SOLTRADE_PHASE6_V8_TICK_CHUNK_FAILED | from=%s | to=%s | error=%d | attempts=%d",
            V8TimestampMsc(cursor),
            V8TimestampMsc(requested_to),
            error,
            attempts);
         ArrayFree(ticks);
         break;
        }

      for(int index = 0; index < copied && construction_ok; index++)
        {
         const MqlTick current = ticks[index];
         if(tick_count == 0)
            first_tick_msc = current.time_msc;
         if(have_previous &&
            current.time_msc > previous.time_msc &&
            current.time_msc - previous.time_msc >
               V8_GAP_SECONDS * 1000)
           {
            g_tick_gaps++;
            const long open_seconds = V8MaximumOpenSegment(
               (datetime)(previous.time_msc / 1000),
               (datetime)(current.time_msc / 1000));
            if(open_seconds > V8_GAP_SECONDS)
              {
               g_unresolved_tick_gaps++;
               if(V8ExpectedUnresolvedGap(previous.time_msc,
                                          current.time_msc))
                  g_expected_unresolved_matches++;
               else
                  g_unexpected_unresolved_gaps++;
              }
            else if(V8TouchesWeekend(
                       (datetime)(previous.time_msc / 1000),
                       (datetime)(current.time_msc / 1000)))
               g_weekend_tick_gaps++;
            else
               g_scheduled_other_tick_gaps++;
           }
         construction_ok = V8ProcessTick(current,
                                         point,
                                         m1_handle,
                                         h1_handle,
                                         m1,
                                         h1);
         previous = current;
         have_previous = true;
         final_tick_msc = current.time_msc;
         tick_count++;
        }
      const string first = copied > 0 ?
         V8TimestampMsc(ticks[0].time_msc) : "NONE";
      const string final_text = copied > 0 ?
         V8TimestampMsc(ticks[copied - 1].time_msc) : "NONE";
      chain = V8Sha256(chain + "|" +
                      IntegerToString((long)cursor) + "|" +
                      IntegerToString((long)requested_to) + "|" +
                      IntegerToString(copied) + "|" + first + "|" +
                      final_text);
      chunks++;
      ArrayFree(ticks);
      cursor = chunk_end;
     }

   if(construction_ok && m1.initialized)
      construction_ok = V8WriteBar(m1_handle, "M1", m1);
   if(construction_ok && h1.initialized)
      construction_ok = V8WriteBar(h1_handle, "H1", h1);
   FileFlush(m1_handle);
   FileFlush(h1_handle);
   FileClose(m1_handle);
   FileClose(h1_handle);

   const bool expected_ticks =
      tick_count == 20682267 &&
      first_tick_msc == (ulong)D'2025.01.02 00:00:00' * 1000 + 594 &&
      final_tick_msc == (ulong)D'2025.12.23 23:59:59' * 1000 + 877;
   const bool gaps_verified =
      g_tick_gaps == 53 &&
      g_unresolved_tick_gaps == 3 &&
      g_weekend_tick_gaps == 50 &&
      g_expected_unresolved_matches == 3 &&
      g_unexpected_unresolved_gaps == 0;
   const bool final_ok =
      construction_ok &&
      cursor == requested_end &&
      expected_ticks &&
      gaps_verified &&
      g_invalid_tick_prices == 0 &&
      memory_errors == 0 &&
      timeout_errors == 0 &&
      retrieval_failures == 0 &&
      g_m1_bars > 0 &&
      g_h1_bars > 0;
   PrintFormat(
      "SOLTRADE_PHASE6_V8_BAR_SUMMARY | ticks=%I64u | first_tick=%s | final_tick=%s | chunks=%I64d | memory_errors=%I64d | timeout_errors=%I64d | retrieval_failures=%I64d | invalid_tick_prices=%I64d | m1_bars=%I64d | first_m1=%s | final_m1=%s | h1_bars=%I64d | first_h1=%s | final_h1=%s | tick_gaps=%I64d | unresolved_gaps=%I64d | weekend_gaps=%I64d | scheduled_other_gaps=%I64d | expected_unresolved_matches=%I64d | unexpected_unresolved=%I64d | source_chain_sha256=%s",
      tick_count,
      V8TimestampMsc(first_tick_msc),
      V8TimestampMsc(final_tick_msc),
      chunks,
      memory_errors,
      timeout_errors,
      retrieval_failures,
      g_invalid_tick_prices,
      g_m1_bars,
      V8TimestampMsc(g_m1_first_bucket),
      V8TimestampMsc(g_m1_last_bucket),
      g_h1_bars,
      V8TimestampMsc(g_h1_first_bucket),
      V8TimestampMsc(g_h1_last_bucket),
      g_tick_gaps,
      g_unresolved_tick_gaps,
      g_weekend_tick_gaps,
      g_scheduled_other_tick_gaps,
      g_expected_unresolved_matches,
      g_unexpected_unresolved_gaps,
      chain);
   PrintFormat(
      "SOLTRADE_PHASE6_V8_BAR_COMPLETE | outcome=%s | reason=%s | orders_after=%d | positions_after=%d | trade_transactions=%I64d | trade_attempted=NO | strategy_run=NO | profitability=NOT_CALCULATED | generated_ticks=NO | interpolation=NO",
      final_ok ? "BAR_CONSTRUCTION_COMPLETE" :
                 "FAIL_TICK_DERIVED_BAR_CONSTRUCTION",
      final_ok ? "REAL_TICK_M1_H1_FILES_WRITTEN" :
                 "CONSTRUCTION_OR_SOURCE_INVARIANT_FAILED",
      OrdersTotal(),
      PositionsTotal(),
      g_trade_transactions);
   ExpertRemove();
   return final_ok ? INIT_SUCCEEDED : INIT_FAILED;
  }

void OnTick()
  {
  }

void OnTradeTransaction(const MqlTradeTransaction &transaction,
                        const MqlTradeRequest &request,
                        const MqlTradeResult &result)
  {
   g_trade_transactions++;
   Print("SOLTRADE_PHASE6_V8_UNEXPECTED_TRADE_TRANSACTION | qualification_invalidated=YES");
  }
