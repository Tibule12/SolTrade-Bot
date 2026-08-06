#property copyright "SolTrade Bot"
#property link      ""
#property version   "1.200"
#property strict
#property description "Inert Phase 6 V4 Strategy Tester data-qualification probe"
#property description "Observes tester history only; contains no strategy or trade operations."

input bool EnableEntryPermission              = false;
input bool EnableExecutionPermission          = false;
input bool EnablePositionManagementPermission = false;
input bool PermitStrategyOrders               = false;
input double ExpectedInitialTesterDeposit     = 10000.0;

const ulong SOLTRADE_PROBE_MAGIC_NUMBER = 2607202601;

const datetime SOLTRADE_PROBE_START_INCLUSIVE =
   D'2024.01.02 00:00:00';
const datetime SOLTRADE_WARMUP_END_EXCLUSIVE =
   D'2024.01.16 00:00:00';
const datetime SOLTRADE_RESEARCH_START_INCLUSIVE =
   D'2024.01.16 00:00:00';
const datetime SOLTRADE_PROBE_END_EXCLUSIVE =
   D'2024.12.24 00:00:00';
const long SOLTRADE_PROBE_GAP_THRESHOLD_SECONDS = 15 * 60;
const ulong SOLTRADE_PROBE_DAY_MILLISECONDS = 86400000;
const ulong SOLTRADE_PROBE_MINIMUM_CHUNK_MILLISECONDS = 900000;
const int SOLTRADE_PROBE_MAX_CHUNK_RETRIES = 8;
const int SOLTRADE_PROBE_HASH_BLOCK_TICKS = 4096;
const int SOLTRADE_ERROR_NOT_ENOUGH_MEMORY = 4004;
const int SOLTRADE_ERROR_HISTORY_TIMEOUT = 4403;

ulong    g_tick_count = 0;
ulong    g_first_tick_msc = 0;
ulong    g_final_tick_msc = 0;
ulong    g_first_research_tick_msc = 0;
long     g_boundary_violation_count = 0;
long     g_trade_transaction_count = 0;
int      g_orders_before = 0;
int      g_positions_before = 0;
int      g_history_orders_before = 0;
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
long     g_entry_engine_activity_count = 0;
long     g_position_manager_activity_count = 0;
ulong    g_stream_tick_count = 0;
ulong    g_stream_first_tick_msc = 0;
ulong    g_stream_final_tick_msc = 0;
long     g_stream_gap_count = 0;
long     g_stream_open_gap_count = 0;
long     g_stream_max_open_gap_seconds = 0;
long     g_stream_boundary_violation_count = 0;
long     g_stream_duplicate_tick_count = 0;
long     g_stream_out_of_order_tick_count = 0;
long     g_stream_chunk_count = 0;
long     g_stream_retry_count = 0;
long     g_stream_memory_error_count = 0;
long     g_stream_timeout_error_count = 0;
bool     g_stream_complete = false;
string   g_stream_hash = "";

struct ProbeGapRecord
  {
   long    number;
   MqlTick previous;
   MqlTick next;
   long    duration_milliseconds;
   long    duration_seconds;
   long    open_segment_seconds;
   string  previous_weekday_time;
   string  next_weekday_time;
   string  previous_sessions;
   string  next_sessions;
   string  monthly_tkc_files;
   int     m1_bars_inside;
   datetime m1_first_inside;
   datetime m1_final_inside;
   int     m1_copy_error;
   string  classification;
   string  supporting_evidence;
  };

ProbeGapRecord g_gap_records[];

struct ProbeDealRecord
  {
   ulong          ticket;
   ulong          order_ticket;
   ulong          position_id;
   ulong          magic;
   ulong          time_msc;
   ENUM_DEAL_TYPE type;
   ENUM_DEAL_REASON reason;
   long           entry;
   double         volume;
   double         amount;
   double         commission;
   double         swap;
   double         fee;
   string         symbol;
   string         comment;
   string         external_id;
  };

struct ProbeDealSummary
  {
   int             total_records;
   int             permitted_administrative_records;
   int             trading_deals;
   int             soltrade_owned_deals;
   int             unexplained_administrative_records;
   ProbeDealRecord permitted_balance;
  };

ProbeDealRecord g_initial_balance_snapshot;

string ProbeTimestampMsc(const ulong value)
  {
   if(value == 0)
      return "NONE";
   return TimeToString((datetime)(value / 1000),
                       TIME_DATE | TIME_SECONDS) +
          "." + StringFormat("%03u", (uint)(value % 1000));
  }

string ProbeSha256(const string value)
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
      PrintFormat(
         "SOLTRADE_PHASE6_V4_PROBE_HASH_ERROR | error=%d | source_bytes=%d",
         GetLastError(),
         ArraySize(source));
      return "";
     }

   string result = "";
   for(int index = 0; index < ArraySize(digest); index++)
      result += StringFormat("%02x", digest[index]);
   return result;
  }

string ProbeTickCanonical(const MqlTick &tick)
  {
   return StringFormat(
      "%I64u|%.10f|%.10f|%.10f|%I64u|%u|%.10f\n",
      tick.time_msc,
      tick.bid,
      tick.ask,
      tick.last,
      tick.volume,
      tick.flags,
      tick.volume_real);
  }

bool ProbeTicksIdentical(const MqlTick &left,
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

string ProbeHashTickBlock(MqlTick &ticks[],
                          const int start_index,
                          const int count)
  {
   string canonical = "";
   for(int offset = 0; offset < count; offset++)
      canonical += ProbeTickCanonical(ticks[start_index + offset]);
   const string result = ProbeSha256(canonical);
   canonical = "";
   return result;
  }

bool ProbeIsTradingDealType(const ENUM_DEAL_TYPE type)
  {
   return type == DEAL_TYPE_BUY ||
          type == DEAL_TYPE_SELL ||
          type == DEAL_TYPE_BUY_CANCELED ||
          type == DEAL_TYPE_SELL_CANCELED;
  }

void ProbeReadDealRecord(const ulong ticket,
                         ProbeDealRecord &record)
  {
   record.ticket = ticket;
   record.order_ticket =
      (ulong)HistoryDealGetInteger(ticket, DEAL_ORDER);
   record.position_id =
      (ulong)HistoryDealGetInteger(ticket, DEAL_POSITION_ID);
   record.magic =
      (ulong)HistoryDealGetInteger(ticket, DEAL_MAGIC);
   record.time_msc =
      (ulong)HistoryDealGetInteger(ticket, DEAL_TIME_MSC);
   record.type =
      (ENUM_DEAL_TYPE)HistoryDealGetInteger(ticket, DEAL_TYPE);
   record.reason =
      (ENUM_DEAL_REASON)HistoryDealGetInteger(ticket, DEAL_REASON);
   record.entry = HistoryDealGetInteger(ticket, DEAL_ENTRY);
   record.volume = HistoryDealGetDouble(ticket, DEAL_VOLUME);
   record.amount = HistoryDealGetDouble(ticket, DEAL_PROFIT);
   record.commission =
      HistoryDealGetDouble(ticket, DEAL_COMMISSION);
   record.swap = HistoryDealGetDouble(ticket, DEAL_SWAP);
   record.fee = HistoryDealGetDouble(ticket, DEAL_FEE);
   record.symbol = HistoryDealGetString(ticket, DEAL_SYMBOL);
   record.comment = HistoryDealGetString(ticket, DEAL_COMMENT);
   record.external_id =
      HistoryDealGetString(ticket, DEAL_EXTERNAL_ID);
  }

void ProbeLogDealRecord(const string phase,
                        const ProbeDealRecord &record)
  {
   PrintFormat(
      "SOLTRADE_PHASE6_V4_PROBE_DEAL_RECORD | phase=%s | ticket=%I64u | timestamp=%s | type=%s | reason=%s | entry=%I64d | amount=%.8f | volume=%.8f | symbol=%s | order_ticket=%I64u | position_id=%I64u | magic=%I64u | commission=%.8f | swap=%.8f | fee=%.8f | comment=%s | external_id=%s",
      phase,
      record.ticket,
      ProbeTimestampMsc(record.time_msc),
      EnumToString(record.type),
      EnumToString(record.reason),
      record.entry,
      record.amount,
      record.volume,
      record.symbol == "" ? "EMPTY" : record.symbol,
      record.order_ticket,
      record.position_id,
      record.magic,
      record.commission,
      record.swap,
      record.fee,
      record.comment == "" ? "EMPTY" : record.comment,
      record.external_id == "" ? "EMPTY" : record.external_id);
  }

bool ProbeIsPermittedInitialBalance(const ProbeDealRecord &record)
  {
   const double tolerance = 0.0000001;
   return record.type == DEAL_TYPE_BALANCE &&
          record.order_ticket == 0 &&
          record.position_id == 0 &&
          record.magic == 0 &&
          record.magic != SOLTRADE_PROBE_MAGIC_NUMBER &&
          MathAbs(record.volume) <= tolerance &&
          record.symbol == "" &&
          MathAbs(record.amount - ExpectedInitialTesterDeposit) <=
             tolerance &&
          MathAbs(record.commission) <= tolerance &&
          MathAbs(record.swap) <= tolerance &&
          MathAbs(record.fee) <= tolerance;
  }

void ProbeScanDealRecords(const string phase,
                          ProbeDealSummary &summary)
  {
   summary.total_records = HistoryDealsTotal();
   summary.permitted_administrative_records = 0;
   summary.trading_deals = 0;
   summary.soltrade_owned_deals = 0;
   summary.unexplained_administrative_records = 0;

   for(int index = 0; index < summary.total_records; index++)
     {
      const ulong ticket = HistoryDealGetTicket(index);
      ProbeDealRecord record;
      ProbeReadDealRecord(ticket, record);
      ProbeLogDealRecord(phase, record);

      if(record.magic == SOLTRADE_PROBE_MAGIC_NUMBER)
         summary.soltrade_owned_deals++;
      if(ProbeIsTradingDealType(record.type))
        {
         summary.trading_deals++;
         continue;
        }
      if(ProbeIsPermittedInitialBalance(record) &&
         summary.permitted_administrative_records == 0)
        {
         summary.permitted_balance = record;
         summary.permitted_administrative_records++;
         continue;
        }
      summary.unexplained_administrative_records++;
     }

   PrintFormat(
      "SOLTRADE_PHASE6_V4_PROBE_DEAL_SUMMARY | phase=%s | total_historical_records=%d | permitted_administrative_records=%d | trading_deals=%d | soltrade_owned_deals=%d | unexplained_administrative_records=%d",
      phase,
      summary.total_records,
      summary.permitted_administrative_records,
      summary.trading_deals,
      summary.soltrade_owned_deals,
      summary.unexplained_administrative_records);
  }

bool ProbeDealRecordUnchanged(const ProbeDealRecord &before,
                              const ProbeDealRecord &after)
  {
   return before.ticket == after.ticket &&
          before.order_ticket == after.order_ticket &&
          before.position_id == after.position_id &&
          before.magic == after.magic &&
          before.time_msc == after.time_msc &&
          before.type == after.type &&
          before.reason == after.reason &&
          before.entry == after.entry &&
          before.volume == after.volume &&
          before.amount == after.amount &&
          before.commission == after.commission &&
          before.swap == after.swap &&
          before.fee == after.fee &&
          before.symbol == after.symbol &&
          before.comment == after.comment &&
          before.external_id == after.external_id;
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

string ProbeClockFromSecond(const int value)
  {
   if(value >= 86400)
      return "24:00:00";
   const int normalized = value < 0 ? 0 : value;
   return StringFormat("%02d:%02d:%02d",
                       normalized / 3600,
                       (normalized % 3600) / 60,
                       normalized % 60);
  }

string ProbeBrokerWeekdayTime(const ulong time_msc)
  {
   MqlDateTime parts;
   TimeToStruct((datetime)(time_msc / 1000), parts);
   return EnumToString((ENUM_DAY_OF_WEEK)parts.day_of_week) + " " +
          ProbeTimestampMsc(time_msc);
  }

string ProbeSessionDescription(const datetime value)
  {
   MqlDateTime parts;
   TimeToStruct(value, parts);
   string result = EnumToString((ENUM_DAY_OF_WEEK)parts.day_of_week) + ":";
   int count = 0;
   for(uint session = 0; session < 20; session++)
     {
      datetime session_from = 0;
      datetime session_to = 0;
      if(!SymbolInfoSessionTrade(_Symbol,
                                 (ENUM_DAY_OF_WEEK)parts.day_of_week,
                                 session,
                                 session_from,
                                 session_to))
         break;
      const int from_second = ProbeSessionSecond(session_from);
      int to_second = ProbeSessionSecond(session_to);
      if(to_second <= from_second)
         to_second = 86400;
      if(count > 0)
         result += ",";
      result += ProbeClockFromSecond(from_second) + "-" +
                ProbeClockFromSecond(to_second);
      count++;
     }
   if(count == 0)
      result += "CLOSED";
   return result;
  }

string ProbeMonthlyTkcName(const ulong time_msc)
  {
   MqlDateTime parts;
   TimeToStruct((datetime)(time_msc / 1000), parts);
   return StringFormat("%04d%02d.tkc", parts.year, parts.mon);
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

bool ProbeGapTouchesWeekend(const datetime from_time,
                            const datetime to_time)
  {
   const datetime final_day = ProbeDayStart(to_time);
   for(datetime day = ProbeDayStart(from_time);
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

void ProbeRecordGap(const MqlTick &previous,
                    const MqlTick &next)
  {
   const int index = ArraySize(g_gap_records);
   ArrayResize(g_gap_records, index + 1);
   ProbeGapRecord record;
   record.number = index + 1;
   record.previous = previous;
   record.next = next;
   record.duration_milliseconds =
      next.time_msc - previous.time_msc;
   record.duration_seconds = record.duration_milliseconds / 1000;
   record.open_segment_seconds =
      ProbeMaximumOpenSegmentSeconds(
         (datetime)(previous.time_msc / 1000),
         (datetime)(next.time_msc / 1000));
   record.previous_weekday_time =
      ProbeBrokerWeekdayTime(previous.time_msc);
   record.next_weekday_time = ProbeBrokerWeekdayTime(next.time_msc);
   record.previous_sessions =
      ProbeSessionDescription((datetime)(previous.time_msc / 1000));
   record.next_sessions =
      ProbeSessionDescription((datetime)(next.time_msc / 1000));
   const string previous_file = ProbeMonthlyTkcName(previous.time_msc);
   const string next_file = ProbeMonthlyTkcName(next.time_msc);
   record.monthly_tkc_files = previous_file == next_file ?
      previous_file : previous_file + "," + next_file;
   record.m1_bars_inside = 0;
   record.m1_first_inside = 0;
   record.m1_final_inside = 0;
   record.m1_copy_error = 0;

   const bool terminal_open =
      record.open_segment_seconds > SOLTRADE_PROBE_GAP_THRESHOLD_SECONDS;
   if(terminal_open)
     {
      record.classification = "UNRESOLVED";
      record.supporting_evidence =
         "MT5_SYMBOL_SESSION_REPORTS_OPEN;BROKER_CONFIRMATION_REQUIRED";
      g_stream_open_gap_count++;
      if(record.open_segment_seconds > g_stream_max_open_gap_seconds)
         g_stream_max_open_gap_seconds = record.open_segment_seconds;
     }
   else if(ProbeGapTouchesWeekend(
              (datetime)(previous.time_msc / 1000),
              (datetime)(next.time_msc / 1000)))
     {
      record.classification = "SCHEDULED_WEEKEND";
      record.supporting_evidence =
         "MT5_SYMBOL_SESSION_REPORTS_NO_OPEN_SEGMENT;WEEKEND_CALENDAR";
     }
   else
     {
      record.classification = "BROKER_DECLARED_CLOSURE";
      record.supporting_evidence =
         "MT5_SYMBOL_SESSION_REPORTS_NO_OPEN_SEGMENT";
     }
   g_gap_records[index] = record;
   g_stream_gap_count++;
  }

void ProbeAnnotateAndLogGaps()
  {
   for(int index = 0; index < ArraySize(g_gap_records); index++)
     {
      ProbeGapRecord record = g_gap_records[index];
      MqlRates rates[];
      ArraySetAsSeries(rates, false);
      ResetLastError();
      const int copied =
         CopyRates(_Symbol,
                   PERIOD_M1,
                   (datetime)(record.previous.time_msc / 1000),
                   (datetime)(record.next.time_msc / 1000),
                   rates);
      record.m1_copy_error = GetLastError();
      if(copied > 0)
        {
         for(int rate_index = 0; rate_index < copied; rate_index++)
           {
            const ulong bar_msc = (ulong)rates[rate_index].time * 1000;
            if(bar_msc <= (ulong)record.previous.time_msc ||
               bar_msc >= (ulong)record.next.time_msc)
               continue;
            if(record.m1_bars_inside == 0)
               record.m1_first_inside = rates[rate_index].time;
            record.m1_final_inside = rates[rate_index].time;
            record.m1_bars_inside++;
           }
        }
      ArrayFree(rates);
      g_gap_records[index] = record;
      PrintFormat(
         "SOLTRADE_PHASE6_V4_PROBE_GAP | gap_number=%I64d | previous_tick=%s | next_tick=%s | duration_milliseconds=%I64d | duration_seconds=%I64d | previous_broker_weekday_time=%s | next_broker_weekday_time=%s | previous_symbol_sessions=%s | next_symbol_sessions=%s | terminal_regarded_session_open=%s | open_segment_seconds=%I64d | bid_before=%.10f | ask_before=%.10f | bid_after=%.10f | ask_after=%.10f | monthly_tkc_files=%s | m1_bars_present=%s | m1_bars_inside=%d | m1_first_inside=%s | m1_final_inside=%s | m1_copy_error=%d | classification=%s | supporting_evidence=%s",
         record.number,
         ProbeTimestampMsc(record.previous.time_msc),
         ProbeTimestampMsc(record.next.time_msc),
         record.duration_milliseconds,
         record.duration_seconds,
         record.previous_weekday_time,
         record.next_weekday_time,
         record.previous_sessions,
         record.next_sessions,
         record.open_segment_seconds >
            SOLTRADE_PROBE_GAP_THRESHOLD_SECONDS ? "YES" : "NO",
         record.open_segment_seconds,
         record.previous.bid,
         record.previous.ask,
         record.next.bid,
         record.next.ask,
         record.monthly_tkc_files,
         record.m1_bars_inside > 0 ? "YES" : "NO",
         record.m1_bars_inside,
         record.m1_first_inside == 0 ? "NONE" :
            TimeToString(record.m1_first_inside,
                         TIME_DATE | TIME_SECONDS),
         record.m1_final_inside == 0 ? "NONE" :
            TimeToString(record.m1_final_inside,
                         TIME_DATE | TIME_SECONDS),
         record.m1_copy_error,
         record.classification,
         record.supporting_evidence);
     }
  }

bool ProbeStreamTicksInChunks()
  {
   const ulong requested_start =
      (ulong)SOLTRADE_PROBE_START_INCLUSIVE * 1000;
   const ulong requested_end =
      (ulong)SOLTRADE_PROBE_END_EXCLUSIVE * 1000;
   ulong cursor = requested_start;
   MqlTick previous_tick;
   ZeroMemory(previous_tick);
   bool have_previous_tick = false;
   string aggregate_hash = ProbeSha256(
      "SOLTRADE_PHASE6_V4_TICK_STREAM_SHA256_CHAIN_V1");
   if(aggregate_hash == "")
      return false;

   while(cursor < requested_end)
     {
      const ulong next_day =
         ((cursor / SOLTRADE_PROBE_DAY_MILLISECONDS) + 1) *
         SOLTRADE_PROBE_DAY_MILLISECONDS;
      const ulong day_end = next_day < requested_end ?
         next_day : requested_end;
      ulong span = day_end - cursor;
      int retry_count = 0;
      int copied = -1;
      int error = 0;
      ulong requested_to = cursor;
      MqlTick ticks[];
      bool chunk_available = false;

      while(retry_count <= SOLTRADE_PROBE_MAX_CHUNK_RETRIES)
        {
         requested_to = cursor + span - 1;
         ResetLastError();
         copied = CopyTicksRange(_Symbol,
                                 ticks,
                                 COPY_TICKS_ALL,
                                 cursor,
                                 requested_to);
         error = GetLastError();
         const ulong returned_first = copied > 0 ?
            ticks[0].time_msc : 0;
         const ulong returned_final = copied > 0 ?
            ticks[copied - 1].time_msc : 0;
         PrintFormat(
            "SOLTRADE_PHASE6_V4_PROBE_CHUNK_ATTEMPT | requested_from=%s | requested_to_inclusive=%s | returned_first=%s | returned_final=%s | tick_count=%d | error=%d | retry_count=%d | requested_span_milliseconds=%I64u",
            ProbeTimestampMsc(cursor),
            ProbeTimestampMsc(requested_to),
            ProbeTimestampMsc(returned_first),
            ProbeTimestampMsc(returned_final),
            copied,
            error,
            retry_count,
            span);
         if(copied >= 0)
           {
            chunk_available = true;
            break;
           }

         if(error == SOLTRADE_ERROR_NOT_ENOUGH_MEMORY)
            g_stream_memory_error_count++;
         if(error == SOLTRADE_ERROR_HISTORY_TIMEOUT)
            g_stream_timeout_error_count++;
         ArrayFree(ticks);
         const bool reducible_error =
            error == SOLTRADE_ERROR_NOT_ENOUGH_MEMORY ||
            error == SOLTRADE_ERROR_HISTORY_TIMEOUT;
         if(!reducible_error ||
            retry_count >= SOLTRADE_PROBE_MAX_CHUNK_RETRIES ||
            span <= SOLTRADE_PROBE_MINIMUM_CHUNK_MILLISECONDS)
            break;
         span /= 2;
         if(span < SOLTRADE_PROBE_MINIMUM_CHUNK_MILLISECONDS)
            span = SOLTRADE_PROBE_MINIMUM_CHUNK_MILLISECONDS;
         retry_count++;
         g_stream_retry_count++;
        }

      if(!chunk_available)
        {
         PrintFormat(
            "SOLTRADE_PHASE6_V4_PROBE_CHUNK_FAILED | requested_from=%s | requested_to_inclusive=%s | tick_count=%d | error=%d | retry_count=%d | fail_closed=YES",
            ProbeTimestampMsc(cursor),
            ProbeTimestampMsc(requested_to),
            copied,
            error,
            retry_count);
         ArrayFree(ticks);
         g_real_tick_api_error = error;
         g_stream_complete = false;
         return false;
        }

      string chunk_hash = ProbeSha256("EMPTY_CHUNK");
      for(int block_start = 0;
          block_start < copied;
          block_start += SOLTRADE_PROBE_HASH_BLOCK_TICKS)
        {
         const int remaining = copied - block_start;
         const int block_count =
            remaining < SOLTRADE_PROBE_HASH_BLOCK_TICKS ?
               remaining : SOLTRADE_PROBE_HASH_BLOCK_TICKS;
         const string block_hash =
            ProbeHashTickBlock(ticks, block_start, block_count);
         if(block_hash == "")
           {
            ArrayFree(ticks);
            g_stream_complete = false;
            return false;
           }
         chunk_hash = ProbeSha256(
            chunk_hash + "|" + IntegerToString(block_start) + "|" +
            IntegerToString(block_count) + "|" + block_hash);
         if(chunk_hash == "")
           {
            ArrayFree(ticks);
            g_stream_complete = false;
            return false;
           }
        }

      for(int index = 0; index < copied; index++)
        {
         const MqlTick current_tick = ticks[index];
         const ulong current_tick_msc = (ulong)current_tick.time_msc;
         if(current_tick_msc < requested_start ||
            current_tick_msc >= requested_end ||
            current_tick_msc < cursor ||
            current_tick_msc > requested_to)
            g_stream_boundary_violation_count++;
         if(g_stream_tick_count == 0)
            g_stream_first_tick_msc = current_tick_msc;

         if(have_previous_tick)
           {
            if(current_tick.time_msc < previous_tick.time_msc)
               g_stream_out_of_order_tick_count++;
            if(ProbeTicksIdentical(previous_tick, current_tick))
               g_stream_duplicate_tick_count++;
            if(current_tick.time_msc > previous_tick.time_msc &&
               current_tick.time_msc - previous_tick.time_msc >
                  SOLTRADE_PROBE_GAP_THRESHOLD_SECONDS * 1000)
               ProbeRecordGap(previous_tick, current_tick);
           }
         previous_tick = current_tick;
         have_previous_tick = true;
         g_stream_final_tick_msc = current_tick_msc;
         g_stream_tick_count++;
        }

      aggregate_hash = ProbeSha256(
         aggregate_hash + "|" + IntegerToString((long)cursor) + "|" +
         IntegerToString((long)requested_to) + "|" +
         IntegerToString(copied) + "|" + chunk_hash);
      if(aggregate_hash == "")
        {
         ArrayFree(ticks);
         g_stream_complete = false;
         return false;
        }
      g_stream_chunk_count++;
      PrintFormat(
         "SOLTRADE_PHASE6_V4_PROBE_CHUNK | chunk_number=%I64d | requested_from=%s | requested_to_inclusive=%s | returned_first=%s | returned_final=%s | tick_count=%d | error=%d | retry_count=%d | chunk_sha256_chain=%s | aggregate_sha256_chain=%s",
         g_stream_chunk_count,
         ProbeTimestampMsc(cursor),
         ProbeTimestampMsc(requested_to),
         copied > 0 ? ProbeTimestampMsc(ticks[0].time_msc) : "NONE",
         copied > 0 ? ProbeTimestampMsc(ticks[copied - 1].time_msc) :
            "NONE",
         copied,
         error,
         retry_count,
         chunk_hash,
         aggregate_hash);
      ArrayFree(ticks);
      cursor = requested_to + 1;
     }

   g_stream_hash = aggregate_hash;
   g_real_tick_api_error = 0;
   g_real_tick_api_available = true;
   g_stream_complete =
      cursor == requested_end &&
      g_stream_tick_count > 0 &&
      g_stream_out_of_order_tick_count == 0 &&
      g_stream_duplicate_tick_count == 0 &&
      g_stream_boundary_violation_count == 0;
   PrintFormat(
      "SOLTRADE_PHASE6_V4_PROBE_CHUNK_SUMMARY | requested_start_inclusive=%s | requested_end_exclusive=%s | chunks=%I64d | retries=%I64d | memory_errors=%I64d | timeout_errors=%I64d | ticks=%I64u | first=%s | final=%s | duplicates=%I64d | out_of_order=%I64d | boundary_violations=%I64d | aggregate_sha256_chain=%s | complete=%s",
      ProbeTimestampMsc(requested_start),
      ProbeTimestampMsc(requested_end),
      g_stream_chunk_count,
      g_stream_retry_count,
      g_stream_memory_error_count,
      g_stream_timeout_error_count,
      g_stream_tick_count,
      ProbeTimestampMsc(g_stream_first_tick_msc),
      ProbeTimestampMsc(g_stream_final_tick_msc),
      g_stream_duplicate_tick_count,
      g_stream_out_of_order_tick_count,
      g_stream_boundary_violation_count,
      g_stream_hash,
      g_stream_complete ? "YES" : "NO");
   return g_stream_complete;
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
      g_m1_synchronized &&
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
      "SOLTRADE_PHASE6_V4_PROBE_INDICATORS | checked_at=%s | warmup_h1_bars=%d | ema200=%s | atr14=%s | donchian20_highs=%d | donchian20_lows=%d | error=%d | available=%s",
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
   if(!HistorySelect(0, TimeCurrent()))
     {
      PrintFormat(
         "SOLTRADE_PHASE6_V4_PROBE_REJECTED | history selection failed | error=%d",
         GetLastError());
      return INIT_FAILED;
     }
   g_orders_before = OrdersTotal();
   g_positions_before = PositionsTotal();
   g_history_orders_before = HistoryOrdersTotal();
   ProbeDealSummary preflight_deals;
   ProbeScanDealRecords("PREFLIGHT", preflight_deals);
   const bool initial_balance_valid =
      preflight_deals.total_records == 1 &&
      preflight_deals.permitted_administrative_records == 1 &&
      preflight_deals.trading_deals == 0 &&
      preflight_deals.soltrade_owned_deals == 0 &&
      preflight_deals.unexplained_administrative_records == 0 &&
      MathAbs(AccountInfoDouble(ACCOUNT_BALANCE) -
              ExpectedInitialTesterDeposit) <= 0.0000001;
   if(initial_balance_valid)
      g_initial_balance_snapshot =
         preflight_deals.permitted_balance;

   PrintFormat(
      "SOLTRADE_PHASE6_V4_PROBE_PREFLIGHT | MQL_TESTER=%s | symbol=%s | timeframe=%s | entry_permission=%s | execution_permission=%s | position_management_permission=%s | strategy_orders_permitted=%s | pending_orders=%d | historical_orders=%d | positions=%d | total_historical_records=%d | permitted_administrative_records=%d | trading_deals=%d | soltrade_owned_deals=%d | entry_engine_activity=%I64d | position_manager_activity=%I64d | expected_initial_deposit=%.2f | account_balance=%.2f | initial_balance_valid=%s",
      (bool)MQLInfoInteger(MQL_TESTER) ? "true" : "false",
      _Symbol,
      EnumToString(_Period),
      EnableEntryPermission ? "true" : "false",
      EnableExecutionPermission ? "true" : "false",
      EnablePositionManagementPermission ? "true" : "false",
      PermitStrategyOrders ? "true" : "false",
      g_orders_before,
      g_history_orders_before,
      g_positions_before,
      preflight_deals.total_records,
      preflight_deals.permitted_administrative_records,
      preflight_deals.trading_deals,
      preflight_deals.soltrade_owned_deals,
      g_entry_engine_activity_count,
      g_position_manager_activity_count,
      ExpectedInitialTesterDeposit,
      AccountInfoDouble(ACCOUNT_BALANCE),
      initial_balance_valid ? "YES" : "NO");
   if(initial_balance_valid)
      PrintFormat(
         "SOLTRADE_PHASE6_V4_PROBE_INITIAL_BALANCE_SNAPSHOT | ticket=%I64u | timestamp=%s | amount=%.8f | type=%s | symbol=%s | volume=%.8f | order_ticket=%I64u | position_id=%I64u | magic=%I64u | reason=%s | comment=%s",
         g_initial_balance_snapshot.ticket,
         ProbeTimestampMsc(g_initial_balance_snapshot.time_msc),
         g_initial_balance_snapshot.amount,
         EnumToString(g_initial_balance_snapshot.type),
         g_initial_balance_snapshot.symbol == "" ?
            "EMPTY" : g_initial_balance_snapshot.symbol,
         g_initial_balance_snapshot.volume,
         g_initial_balance_snapshot.order_ticket,
         g_initial_balance_snapshot.position_id,
         g_initial_balance_snapshot.magic,
         EnumToString(g_initial_balance_snapshot.reason),
         g_initial_balance_snapshot.comment == "" ?
            "EMPTY" : g_initial_balance_snapshot.comment);
   Print(
      "SOLTRADE_PHASE6_V4_PROBE_BOUNDARIES | warmup=[2024.01.02 00:00:00,2024.01.16 00:00:00) | research=[2024.01.16 00:00:00,2024.12.24 00:00:00) | tester=[2024.01.02 00:00:00,2024.12.24 00:00:00) | semantics=START_INCLUSIVE_END_EXCLUSIVE");
   Print(
      "SOLTRADE_PHASE6_V4_PROBE_SCOPE | probe_only=YES | strategy=NOT_LOADED | entry_engine=NOT_LOADED | position_manager=NOT_LOADED | authoritative_run=NO | replica=NO | parameter_search=NO | research_decision=NONE | performance_statistics=NOT_GENERATED | strategy_profitability=NOT_CALCULATED | trade_api_calls=NONE");
   PrintFormat(
      "SOLTRADE_PHASE6_V4_PROBE_CHUNK_POLICY | api=CopyTicksRange | default_chunk_milliseconds=%I64u | default_chunk=ONE_BROKER_DAY | minimum_chunk_milliseconds=%I64u | maximum_retries=%d | array_release=AFTER_EVERY_CHUNK | cross_chunk_gap_state=RETAIN_FINAL_TICK | full_interval_array=PROHIBITED | hash_mode=INCREMENTAL_SHA256_CHAIN | hash_block_ticks=%d",
      SOLTRADE_PROBE_DAY_MILLISECONDS,
      SOLTRADE_PROBE_MINIMUM_CHUNK_MILLISECONDS,
      SOLTRADE_PROBE_MAX_CHUNK_RETRIES,
      SOLTRADE_PROBE_HASH_BLOCK_TICKS);

   if(!(bool)MQLInfoInteger(MQL_TESTER) ||
      _Symbol != "EURUSD" ||
      _Period != PERIOD_H1 ||
      !permissions_disabled ||
      g_orders_before != 0 ||
      g_positions_before != 0 ||
      g_history_orders_before != 0 ||
      !initial_balance_valid)
     {
      Print("SOLTRADE_PHASE6_V4_PROBE_REJECTED | invalid inert tester preflight");
      return INIT_FAILED;
     }

   g_ema_handle =
      iMA(_Symbol, PERIOD_H1, 200, 0, MODE_EMA, PRICE_CLOSE);
   g_atr_handle = iATR(_Symbol, PERIOD_H1, 14);
   if(g_ema_handle == INVALID_HANDLE ||
      g_atr_handle == INVALID_HANDLE)
     {
      PrintFormat(
         "SOLTRADE_PHASE6_V4_PROBE_REJECTED | indicator handle unavailable | error=%d",
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
      g_first_tick_msc = tick.time_msc;

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
   const bool chunk_stream_complete = ProbeStreamTicksInChunks();
   ProbeScanM1Coverage();
   ProbeAnnotateAndLogGaps();
   if(g_ema_handle != INVALID_HANDLE)
      IndicatorRelease(g_ema_handle);
   if(g_atr_handle != INVALID_HANDLE)
      IndicatorRelease(g_atr_handle);

   const bool history_selected =
      HistorySelect(0, SOLTRADE_PROBE_END_EXCLUSIVE);
   const int orders_after = OrdersTotal();
   const int positions_after = PositionsTotal();
   const int history_orders_after = HistoryOrdersTotal();
   ProbeDealSummary postrun_deals;
   ProbeScanDealRecords("POSTRUN", postrun_deals);
   const bool balance_record_unchanged =
      postrun_deals.permitted_administrative_records == 1 &&
      ProbeDealRecordUnchanged(
         g_initial_balance_snapshot,
         postrun_deals.permitted_balance);
   const bool no_new_historical_deal_ticket =
      postrun_deals.total_records == 1 &&
      postrun_deals.permitted_administrative_records == 1 &&
      postrun_deals.permitted_balance.ticket ==
         g_initial_balance_snapshot.ticket;
   const datetime first_tick_time =
      (datetime)(g_stream_first_tick_msc / 1000);
   const datetime final_tick_time =
      (datetime)(g_stream_final_tick_msc / 1000);
   const long start_boundary_open_gap_seconds =
      g_stream_first_tick_msc == 0 ? -1 :
         ProbeMaximumOpenSegmentSeconds(
            SOLTRADE_PROBE_START_INCLUSIVE,
            first_tick_time);
   const long end_boundary_open_gap_seconds =
      g_stream_final_tick_msc == 0 ? -1 :
         ProbeMaximumOpenSegmentSeconds(
            final_tick_time,
            SOLTRADE_PROBE_END_EXCLUSIVE);
   const bool model_stream_match =
      g_tick_count == g_stream_tick_count &&
      g_first_tick_msc == g_stream_first_tick_msc &&
      g_final_tick_msc == g_stream_final_tick_msc;
   const bool actual_tick_boundaries_qualified =
      g_stream_tick_count > 0 &&
      g_stream_first_tick_msc >=
         (ulong)SOLTRADE_PROBE_START_INCLUSIVE * 1000 &&
      g_stream_final_tick_msc <
         (ulong)SOLTRADE_PROBE_END_EXCLUSIVE * 1000 &&
      start_boundary_open_gap_seconds >= 0 &&
      start_boundary_open_gap_seconds <=
         SOLTRADE_PROBE_GAP_THRESHOLD_SECONDS &&
      end_boundary_open_gap_seconds >= 0 &&
      end_boundary_open_gap_seconds <=
         SOLTRADE_PROBE_GAP_THRESHOLD_SECONDS &&
      g_stream_boundary_violation_count == 0;
   const bool gap_rule_qualified = g_stream_open_gap_count == 0;
   const bool tick_coverage_usable =
      chunk_stream_complete &&
      g_real_tick_api_available &&
      g_stream_memory_error_count == 0 &&
      g_stream_timeout_error_count == 0 &&
      actual_tick_boundaries_qualified &&
      model_stream_match &&
      gap_rule_qualified;
   const bool warmup_usable =
      g_warmup_h1_count >= 222 &&
      g_warmup_h1_first == SOLTRADE_PROBE_START_INCLUSIVE &&
      g_warmup_h1_final <
         SOLTRADE_WARMUP_END_EXCLUSIVE &&
      g_first_research_tick_msc >=
         (ulong)SOLTRADE_RESEARCH_START_INCLUSIVE * 1000 &&
      g_indicator_warmup_available;
   const bool inert_history_unchanged =
      history_selected &&
      g_orders_before == 0 &&
      g_positions_before == 0 &&
      g_history_orders_before == 0 &&
      orders_after == 0 &&
      positions_after == 0 &&
      history_orders_after == 0 &&
      postrun_deals.total_records == 1 &&
      postrun_deals.permitted_administrative_records == 1 &&
      postrun_deals.trading_deals == 0 &&
      postrun_deals.soltrade_owned_deals == 0 &&
      postrun_deals.unexplained_administrative_records == 0 &&
      no_new_historical_deal_ticket &&
      balance_record_unchanged &&
      g_trade_transaction_count == 0 &&
      g_entry_engine_activity_count == 0 &&
      g_position_manager_activity_count == 0;
   const bool passed =
      (bool)MQLInfoInteger(MQL_TESTER) &&
      g_m1_coverage_usable &&
      tick_coverage_usable &&
      warmup_usable &&
      inert_history_unchanged;

   PrintFormat(
      "SOLTRADE_PHASE6_V4_PROBE_M1_HCC | bars=%d | first=%s | final=%s | copy_error=%d | series_synchronized=%s | series_first=%s | terminal_first=%s | server_first=%s | gaps_over_15m=%I64d | unexplained_open_session_gaps=%I64d | max_open_gap_seconds=%I64d | usable=%s",
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
      "SOLTRADE_PHASE6_V4_PROBE_WARMUP | h1_bars=%d | first=%s | final=%s | first_research_tick=%s | indicator_warmup_available=%s | usable=%s",
      g_warmup_h1_count,
      TimeToString(g_warmup_h1_first,
                   TIME_DATE | TIME_SECONDS),
      TimeToString(g_warmup_h1_final,
                   TIME_DATE | TIME_SECONDS),
      ProbeTimestampMsc(g_first_research_tick_msc),
      g_indicator_warmup_available ? "YES" : "NO",
      warmup_usable ? "YES" : "NO");
   PrintFormat(
      "SOLTRADE_PHASE6_V4_PROBE_TICKS | requested_start_inclusive=2024.01.02 00:00:00 | requested_end_exclusive=2024.12.24 00:00:00 | streamed_count=%I64u | modeled_count=%I64u | actual_first=%s | actual_final=%s | modeled_first=%s | modeled_final=%s | start_boundary_open_gap_seconds=%I64d | end_boundary_open_gap_seconds=%I64d | boundary_violations=%I64d | gaps_over_15m=%I64d | unexplained_open_session_gaps=%I64d | max_open_gap_seconds=%I64d | duplicates=%I64d | out_of_order=%I64d | chunks=%I64d | retries=%I64d | memory_errors=%I64d | timeout_errors=%I64d | aggregate_sha256_chain=%s | real_tick_api_error=%d | complete_chunk_coverage=%s | model_stream_match=%s | gap_rule_qualified=%s | usable=%s",
      g_stream_tick_count,
      g_tick_count,
      ProbeTimestampMsc(g_stream_first_tick_msc),
      ProbeTimestampMsc(g_stream_final_tick_msc),
      ProbeTimestampMsc(g_first_tick_msc),
      ProbeTimestampMsc(g_final_tick_msc),
      start_boundary_open_gap_seconds,
      end_boundary_open_gap_seconds,
      g_stream_boundary_violation_count,
      g_stream_gap_count,
      g_stream_open_gap_count,
      g_stream_max_open_gap_seconds,
      g_stream_duplicate_tick_count,
      g_stream_out_of_order_tick_count,
      g_stream_chunk_count,
      g_stream_retry_count,
      g_stream_memory_error_count,
      g_stream_timeout_error_count,
      g_stream_hash,
      g_real_tick_api_error,
      chunk_stream_complete ? "YES" : "NO",
      model_stream_match ? "YES" : "NO",
      gap_rule_qualified ? "YES" : "NO",
      tick_coverage_usable ? "YES" : "NO");
   PrintFormat(
      "SOLTRADE_PHASE6_V4_PROBE_POSTRUN | total_historical_records=%d | permitted_administrative_records=%d | trading_deals=%d | soltrade_owned_deals=%d | unexplained_administrative_records=%d | pending_orders=%d | historical_orders=%d | positions=%d | trade_transactions=%I64d | entry_engine_activity=%I64d | position_manager_activity=%I64d | initial_balance_ticket_before=%I64u | initial_balance_ticket_after=%I64u | no_new_historical_deal_ticket=%s | initial_balance_unchanged=%s | inert_history_unchanged=%s | deinit_reason=%d",
      postrun_deals.total_records,
      postrun_deals.permitted_administrative_records,
      postrun_deals.trading_deals,
      postrun_deals.soltrade_owned_deals,
      postrun_deals.unexplained_administrative_records,
      orders_after,
      history_orders_after,
      positions_after,
      g_trade_transaction_count,
      g_entry_engine_activity_count,
      g_position_manager_activity_count,
      g_initial_balance_snapshot.ticket,
      postrun_deals.permitted_balance.ticket,
      no_new_historical_deal_ticket ? "YES" : "NO",
      balance_record_unchanged ? "YES" : "NO",
      inert_history_unchanged ? "YES" : "NO",
      reason);
   PrintFormat(
      "SOLTRADE_PHASE6_V4_PROBE_RESULT | status=%s | MQL_TESTER=%s | requested_boundaries_exact=%s | complete_chunk_coverage=%s | no_memory_error=%s | actual_tick_boundaries_qualified=%s | m1_hcc=%s | warmup=%s | tick_gap_rule=%s | tick_coverage=%s | exactly_one_permitted_initial_balance=%s | zero_trading_deals=%s | zero_orders=%s | zero_positions=%s | no_new_historical_deal_ticket=%s | initial_balance_unchanged=%s | entry_engine_activity_zero=%s | position_manager_activity_zero=%s | authoritative_run=NO | replica=NO | strategy=NOT_LOADED | research_decision=NONE | performance_statistics=NOT_GENERATED | strategy_profitability=NOT_CALCULATED",
      passed ? "PASS" : "FAIL",
      (bool)MQLInfoInteger(MQL_TESTER) ? "true" : "false",
      g_stream_boundary_violation_count == 0 ? "YES" : "NO",
      chunk_stream_complete ? "YES" : "NO",
      g_stream_memory_error_count == 0 ?
         "YES" : "NO",
      actual_tick_boundaries_qualified ? "YES" : "NO",
      g_m1_coverage_usable ? "YES" : "NO",
      warmup_usable ? "YES" : "NO",
      gap_rule_qualified ? "YES" : "NO",
      tick_coverage_usable ? "YES" : "NO",
      postrun_deals.total_records == 1 &&
         postrun_deals.permitted_administrative_records == 1 ?
            "YES" : "NO",
      postrun_deals.trading_deals == 0 ? "YES" : "NO",
      orders_after == 0 && history_orders_after == 0 ?
         "YES" : "NO",
      positions_after == 0 ? "YES" : "NO",
      no_new_historical_deal_ticket ? "YES" : "NO",
      balance_record_unchanged ? "YES" : "NO",
      g_entry_engine_activity_count == 0 ? "YES" : "NO",
      g_position_manager_activity_count == 0 ? "YES" : "NO");
  }
