#property copyright "SolTrade Bot"
#property link      ""
#property version   "1.000"
#property strict
#property script_show_inputs
#property description "Non-trading easyMarkets EURUSD real-tick history acquisition"
#property description "Never places, checks, modifies, or closes an order."

#define SOLTRADE_HISTORY_SCHEMA "SOLTRADE_PHASE6_HISTORY_ACQUISITION_V1"

input bool ConfirmNonTradingHistoryAcquisition = false;

const string SOLTRADE_HISTORY_SYMBOL = "EURUSD";
const string SOLTRADE_HISTORY_SERVER = "easyMarkets-Live";
const datetime SOLTRADE_HISTORY_START = D'2024.01.01 00:00:00';
const datetime SOLTRADE_HISTORY_END_EXCLUSIVE = D'2026.07.01 00:00:00';
const ulong SOLTRADE_GAP_THRESHOLD_MSC = 15 * 60 * 1000;
const string SOLTRADE_HISTORY_DIRECTORY =
   "SolTradeBot\\phase6-history-acquisition-v1";

bool SolTradeHistoryProductionEaDetached()
  {
   long chart_id = ChartFirst();
   while(chart_id >= 0)
     {
      const string expert_name =
         ChartGetString(chart_id, CHART_EXPERT_NAME);
      if(StringFind(expert_name, "SolTradeBot") >= 0)
         return false;
      chart_id = ChartNext(chart_id);
     }
   return true;
  }

datetime SolTradeHistoryNextMonth(const datetime month_start)
  {
   MqlDateTime parts;
   TimeToStruct(month_start, parts);
   parts.day = 1;
   parts.hour = 0;
   parts.min = 0;
   parts.sec = 0;
   parts.mon++;
   if(parts.mon > 12)
     {
      parts.mon = 1;
      parts.year++;
     }
   return StructToTime(parts);
  }

string SolTradeHistoryTimestampMsc(const ulong time_msc)
  {
   if(time_msc == 0)
      return "";
   return TimeToString((datetime)(time_msc / 1000),
                       TIME_DATE | TIME_SECONDS) +
          "." + StringFormat("%03u", (uint)(time_msc % 1000));
  }

bool SolTradeHistoryWeekday(const datetime value)
  {
   MqlDateTime parts;
   TimeToStruct(value, parts);
   return (parts.day_of_week >= 1 && parts.day_of_week <= 5);
  }

string SolTradeHistoryGapClass(const datetime from_time,
                               const datetime to_time)
  {
   for(datetime cursor = from_time;
       cursor <= to_time;
       cursor += 86400)
     {
      MqlDateTime parts;
      TimeToStruct(cursor, parts);
      if(parts.day_of_week == 0 || parts.day_of_week == 6)
         return "INCLUDES_WEEKEND";
     }
   return "IN_SESSION_CANDIDATE_GAP";
  }

int SolTradeCopyTicksDay(const datetime day_start,
                         const datetime day_end_exclusive,
                         MqlTick &ticks[],
                         int &last_error)
  {
   last_error = 0;
   for(int attempt = 1; attempt <= 5; attempt++)
     {
      if(IsStopped())
        {
         last_error = 4999;
         return -1;
        }
      ResetLastError();
      const int copied =
         CopyTicksRange(SOLTRADE_HISTORY_SYMBOL,
                        ticks,
                        COPY_TICKS_ALL,
                        (ulong)day_start * 1000,
                        (ulong)day_end_exclusive * 1000 - 1);
      last_error = GetLastError();
      PrintFormat(
         "SOLTRADE_HISTORY_DOWNLOAD | date=%s | attempt=%d | copied=%d | error=%d",
         TimeToString(day_start, TIME_DATE),
         attempt,
         copied,
         last_error);
      if(copied >= 0)
         return copied;
      Sleep(1000);
     }
   return -1;
  }

bool SolTradeSynchronizeM1(int &last_error)
  {
   const datetime probe_start = D'2024.01.02 00:00:00';
   const datetime probe_end_exclusive = probe_start + 86400;
   last_error = 0;
   for(int attempt = 1; attempt <= 120; attempt++)
     {
      if(IsStopped())
        {
         last_error = 4999;
         return false;
        }
      MqlRates probe[];
      ResetLastError();
      const int copied =
         CopyRates(SOLTRADE_HISTORY_SYMBOL,
                   PERIOD_M1,
                   probe_start,
                   probe_end_exclusive - 1,
                   probe);
      last_error = GetLastError();
      PrintFormat(
         "SOLTRADE_M1_SYNCHRONIZATION | attempt=%d | probe_start=%s | copied=%d | error=%d | synchronized=%s",
         attempt,
         TimeToString(probe_start, TIME_DATE | TIME_SECONDS),
         copied,
         last_error,
         (bool)SeriesInfoInteger(SOLTRADE_HISTORY_SYMBOL,
                                 PERIOD_M1,
                                 SERIES_SYNCHRONIZED)
            ? "YES" : "NO");
      if(copied >= 0)
         return true;
      Sleep(1000);
     }
   return false;
  }

int SolTradeCopyM1Day(const datetime day_start,
                      const datetime day_end_exclusive,
                      MqlRates &rates[],
                      int &last_error)
  {
   last_error = 0;
   if(IsStopped())
     {
      last_error = 4999;
      return -1;
     }
   ResetLastError();
   const int copied =
      CopyRates(SOLTRADE_HISTORY_SYMBOL,
                PERIOD_M1,
                day_start,
                day_end_exclusive - 1,
                rates);
   last_error = GetLastError();
   PrintFormat(
      "SOLTRADE_M1_DOWNLOAD | date=%s | attempt=1 | copied=%d | error=%d",
      TimeToString(day_start, TIME_DATE),
      copied,
      last_error);
   return copied;
  }

bool SolTradeWriteSymbolSpecification()
  {
   const string filename =
      SOLTRADE_HISTORY_DIRECTORY + "\\symbol_specification.csv";
   const int handle =
      FileOpen(filename,
               FILE_WRITE | FILE_CSV | FILE_ANSI,
               ',');
   if(handle == INVALID_HANDLE)
      return false;

   FileWrite(handle, "schema", "field", "value");
   FileWrite(handle, SOLTRADE_HISTORY_SCHEMA, "symbol",
             SOLTRADE_HISTORY_SYMBOL);
   FileWrite(handle, SOLTRADE_HISTORY_SCHEMA, "server",
             AccountInfoString(ACCOUNT_SERVER));
   FileWrite(handle, SOLTRADE_HISTORY_SCHEMA, "company",
             AccountInfoString(ACCOUNT_COMPANY));
   FileWrite(handle, SOLTRADE_HISTORY_SCHEMA, "terminal_build",
             IntegerToString((int)TerminalInfoInteger(TERMINAL_BUILD)));
   FileWrite(handle, SOLTRADE_HISTORY_SCHEMA, "description",
             SymbolInfoString(SOLTRADE_HISTORY_SYMBOL,
                              SYMBOL_DESCRIPTION));
   FileWrite(handle, SOLTRADE_HISTORY_SCHEMA, "path",
             SymbolInfoString(SOLTRADE_HISTORY_SYMBOL,
                              SYMBOL_PATH));
   FileWrite(handle, SOLTRADE_HISTORY_SCHEMA, "currency_base",
             SymbolInfoString(SOLTRADE_HISTORY_SYMBOL,
                              SYMBOL_CURRENCY_BASE));
   FileWrite(handle, SOLTRADE_HISTORY_SCHEMA, "currency_profit",
             SymbolInfoString(SOLTRADE_HISTORY_SYMBOL,
                              SYMBOL_CURRENCY_PROFIT));
   FileWrite(handle, SOLTRADE_HISTORY_SCHEMA, "currency_margin",
             SymbolInfoString(SOLTRADE_HISTORY_SYMBOL,
                              SYMBOL_CURRENCY_MARGIN));
   FileWrite(handle, SOLTRADE_HISTORY_SCHEMA, "digits",
             IntegerToString((int)SymbolInfoInteger(
                SOLTRADE_HISTORY_SYMBOL, SYMBOL_DIGITS)));
   FileWrite(handle, SOLTRADE_HISTORY_SCHEMA, "point",
             DoubleToString(SymbolInfoDouble(
                SOLTRADE_HISTORY_SYMBOL, SYMBOL_POINT), 10));
   FileWrite(handle, SOLTRADE_HISTORY_SCHEMA, "tick_size",
             DoubleToString(SymbolInfoDouble(
                SOLTRADE_HISTORY_SYMBOL, SYMBOL_TRADE_TICK_SIZE), 10));
   FileWrite(handle, SOLTRADE_HISTORY_SCHEMA, "tick_value",
             DoubleToString(SymbolInfoDouble(
                SOLTRADE_HISTORY_SYMBOL, SYMBOL_TRADE_TICK_VALUE), 10));
   FileWrite(handle, SOLTRADE_HISTORY_SCHEMA, "contract_size",
             DoubleToString(SymbolInfoDouble(
                SOLTRADE_HISTORY_SYMBOL, SYMBOL_TRADE_CONTRACT_SIZE), 8));
   FileWrite(handle, SOLTRADE_HISTORY_SCHEMA, "volume_min",
             DoubleToString(SymbolInfoDouble(
                SOLTRADE_HISTORY_SYMBOL, SYMBOL_VOLUME_MIN), 8));
   FileWrite(handle, SOLTRADE_HISTORY_SCHEMA, "volume_max",
             DoubleToString(SymbolInfoDouble(
                SOLTRADE_HISTORY_SYMBOL, SYMBOL_VOLUME_MAX), 8));
   FileWrite(handle, SOLTRADE_HISTORY_SCHEMA, "volume_step",
             DoubleToString(SymbolInfoDouble(
                SOLTRADE_HISTORY_SYMBOL, SYMBOL_VOLUME_STEP), 8));
   FileWrite(handle, SOLTRADE_HISTORY_SCHEMA, "stops_level_points",
             IntegerToString((int)SymbolInfoInteger(
                SOLTRADE_HISTORY_SYMBOL, SYMBOL_TRADE_STOPS_LEVEL)));
   FileWrite(handle, SOLTRADE_HISTORY_SCHEMA, "freeze_level_points",
             IntegerToString((int)SymbolInfoInteger(
                SOLTRADE_HISTORY_SYMBOL, SYMBOL_TRADE_FREEZE_LEVEL)));
   FileWrite(handle, SOLTRADE_HISTORY_SCHEMA, "trade_mode",
             IntegerToString((int)SymbolInfoInteger(
                SOLTRADE_HISTORY_SYMBOL, SYMBOL_TRADE_MODE)));
   FileWrite(handle, SOLTRADE_HISTORY_SCHEMA, "execution_mode",
             IntegerToString((int)SymbolInfoInteger(
                SOLTRADE_HISTORY_SYMBOL, SYMBOL_TRADE_EXEMODE)));
   FileWrite(handle, SOLTRADE_HISTORY_SCHEMA, "filling_mode",
             IntegerToString((int)SymbolInfoInteger(
                SOLTRADE_HISTORY_SYMBOL, SYMBOL_FILLING_MODE)));
   FileWrite(handle, SOLTRADE_HISTORY_SCHEMA, "order_mode",
             IntegerToString((int)SymbolInfoInteger(
                SOLTRADE_HISTORY_SYMBOL, SYMBOL_ORDER_MODE)));
   FileFlush(handle);
   FileClose(handle);
   return true;
  }

bool SolTradeWriteTradingSessions()
  {
   const string filename =
      SOLTRADE_HISTORY_DIRECTORY + "\\trading_sessions.csv";
   const int handle =
      FileOpen(filename,
               FILE_WRITE | FILE_CSV | FILE_ANSI,
               ',');
   if(handle == INVALID_HANDLE)
      return false;

   FileWrite(handle,
             "schema",
             "day_of_week",
             "session_index",
             "from",
             "to");
   for(int day = 0; day <= 6; day++)
     {
      for(uint session = 0; session < 20; session++)
        {
         datetime from_time = 0;
         datetime to_time = 0;
         if(!SymbolInfoSessionTrade(
               SOLTRADE_HISTORY_SYMBOL,
               (ENUM_DAY_OF_WEEK)day,
               session,
               from_time,
               to_time))
            break;
         FileWrite(handle,
                   SOLTRADE_HISTORY_SCHEMA,
                   IntegerToString(day),
                   IntegerToString((int)session),
                   TimeToString(from_time, TIME_MINUTES),
                   TimeToString(to_time, TIME_MINUTES));
        }
     }
   FileFlush(handle);
   FileClose(handle);
   return true;
  }

void OnStart()
  {
   Print("SOLTRADE_HISTORY_PREFLIGHT | action=NON_TRADING_HISTORY_ACQUISITION");
   if(!ConfirmNonTradingHistoryAcquisition)
     {
      Print("SOLTRADE_HISTORY_NOT_CONFIRMED | no history request made");
      return;
     }
   if((bool)MQLInfoInteger(MQL_TESTER) ||
      AccountInfoInteger(ACCOUNT_TRADE_MODE) !=
         ACCOUNT_TRADE_MODE_DEMO ||
      AccountInfoString(ACCOUNT_SERVER) != SOLTRADE_HISTORY_SERVER ||
      (bool)TerminalInfoInteger(TERMINAL_TRADE_ALLOWED) ||
      OrdersTotal() != 0 ||
      PositionsTotal() != 0 ||
      !SolTradeHistoryProductionEaDetached())
     {
      PrintFormat(
         "SOLTRADE_HISTORY_PREFLIGHT_REJECTED | tester=%s | demo=%s | server_match=%s | algo_trading=%s | orders=%d | positions=%d | production_ea_detached=%s",
         (bool)MQLInfoInteger(MQL_TESTER) ? "YES" : "NO",
         AccountInfoInteger(ACCOUNT_TRADE_MODE) ==
            ACCOUNT_TRADE_MODE_DEMO ? "YES" : "NO",
         AccountInfoString(ACCOUNT_SERVER) ==
            SOLTRADE_HISTORY_SERVER ? "YES" : "NO",
         (bool)TerminalInfoInteger(TERMINAL_TRADE_ALLOWED)
            ? "ON" : "OFF",
         OrdersTotal(),
         PositionsTotal(),
         SolTradeHistoryProductionEaDetached() ? "YES" : "NO");
      return;
     }
   if(!SymbolSelect(SOLTRADE_HISTORY_SYMBOL, true))
     {
      Print("SOLTRADE_HISTORY_FAILED | cannot select EURUSD");
      return;
     }

   int m1_synchronization_error = 0;
   const bool m1_synchronized =
      SolTradeSynchronizeM1(m1_synchronization_error);
   PrintFormat(
      "SOLTRADE_M1_SYNCHRONIZATION_COMPLETE | synchronized=%s | error=%d",
      m1_synchronized ? "YES" : "NO",
      m1_synchronization_error);
   if(IsStopped())
     {
      Print("SOLTRADE_HISTORY_STOPPED | no completed inventory emitted");
      return;
     }

   const int monthly_handle =
      FileOpen(SOLTRADE_HISTORY_DIRECTORY + "\\monthly_ticks.csv",
               FILE_WRITE | FILE_CSV | FILE_ANSI,
               ',');
   const int daily_handle =
      FileOpen(SOLTRADE_HISTORY_DIRECTORY + "\\daily_ticks.csv",
               FILE_WRITE | FILE_CSV | FILE_ANSI,
               ',');
   const int gaps_handle =
      FileOpen(SOLTRADE_HISTORY_DIRECTORY + "\\tick_gaps.csv",
               FILE_WRITE | FILE_CSV | FILE_ANSI,
               ',');
   const int m1_handle =
      FileOpen(SOLTRADE_HISTORY_DIRECTORY + "\\m1_bars.csv",
               FILE_WRITE | FILE_CSV | FILE_ANSI,
               ',');
   if(monthly_handle == INVALID_HANDLE ||
      daily_handle == INVALID_HANDLE ||
      gaps_handle == INVALID_HANDLE ||
      m1_handle == INVALID_HANDLE ||
      !SolTradeWriteSymbolSpecification() ||
      !SolTradeWriteTradingSessions())
     {
      PrintFormat("SOLTRADE_HISTORY_FAILED | cannot create artifacts | error=%d",
                  GetLastError());
      if(monthly_handle != INVALID_HANDLE) FileClose(monthly_handle);
      if(daily_handle != INVALID_HANDLE) FileClose(daily_handle);
      if(gaps_handle != INVALID_HANDLE) FileClose(gaps_handle);
      if(m1_handle != INVALID_HANDLE) FileClose(m1_handle);
      return;
     }

   FileWrite(monthly_handle,
             "schema",
             "month_start",
             "month_end_exclusive",
             "tick_count",
             "earliest_tick",
             "final_tick",
             "weekday_zero_tick_days",
             "copy_failures",
             "m1_bar_count",
             "m1_copy_failures");
   FileWrite(daily_handle,
             "schema",
             "date",
             "tick_count",
             "earliest_tick",
             "final_tick",
             "copy_error");
   FileWrite(gaps_handle,
             "schema",
             "gap_start",
             "gap_end",
             "gap_seconds",
             "classification");
   FileWrite(m1_handle,
             "schema",
             "date",
             "bar_count",
             "earliest_bar",
             "final_bar",
             "copy_error");

   long total_ticks = 0;
   long total_m1_bars = 0;
   int total_copy_failures = 0;
   int total_m1_failures = 0;
   int total_weekday_zero_days = 0;
   int candidate_gaps = 0;
   ulong global_first_msc = 0;
   ulong global_final_msc = 0;
   ulong previous_tick_msc = 0;
   bool stopped = false;

   for(datetime month_start = SOLTRADE_HISTORY_START;
       month_start < SOLTRADE_HISTORY_END_EXCLUSIVE;
       month_start = SolTradeHistoryNextMonth(month_start))
     {
      if(IsStopped())
        {
         stopped = true;
         break;
        }
      const datetime next_month =
         MathMin(SolTradeHistoryNextMonth(month_start),
                 SOLTRADE_HISTORY_END_EXCLUSIVE);
      long month_ticks = 0;
      long month_m1_bars = 0;
      int month_failures = 0;
      int month_m1_failures = 0;
      int month_weekday_zero_days = 0;
      ulong month_first_msc = 0;
      ulong month_final_msc = 0;

      for(datetime day_start = month_start;
          day_start < next_month;
          day_start += 86400)
        {
         if(IsStopped())
           {
            stopped = true;
            break;
           }
         const datetime day_end =
            MathMin(day_start + 86400, next_month);
         MqlTick ticks[];
         int tick_error = 0;
         const int day_ticks =
            SolTradeCopyTicksDay(day_start,
                                 day_end,
                                 ticks,
                                 tick_error);
         if(day_ticks < 0)
           {
            month_failures++;
            total_copy_failures++;
           }
         else
           {
            month_ticks += day_ticks;
            total_ticks += day_ticks;
            if(day_ticks == 0 && SolTradeHistoryWeekday(day_start))
              {
               month_weekday_zero_days++;
               total_weekday_zero_days++;
               FileWrite(gaps_handle,
                         SOLTRADE_HISTORY_SCHEMA,
                         TimeToString(day_start,
                                      TIME_DATE | TIME_SECONDS),
                         TimeToString(day_end,
                                      TIME_DATE | TIME_SECONDS),
                         IntegerToString((int)(day_end - day_start)),
                         "ZERO_TICK_WEEKDAY");
               candidate_gaps++;
              }
            for(int index = 0; index < day_ticks; index++)
              {
               const ulong tick_msc = ticks[index].time_msc;
               if(tick_msc == 0)
                  continue;
               if(global_first_msc == 0)
                  global_first_msc = tick_msc;
               global_final_msc = tick_msc;
               if(month_first_msc == 0)
                  month_first_msc = tick_msc;
               month_final_msc = tick_msc;
               if(previous_tick_msc > 0 &&
                  tick_msc > previous_tick_msc +
                     SOLTRADE_GAP_THRESHOLD_MSC)
                 {
                  const datetime gap_start =
                     (datetime)(previous_tick_msc / 1000);
                  const datetime gap_end =
                     (datetime)(tick_msc / 1000);
                  const string gap_class =
                     SolTradeHistoryGapClass(gap_start, gap_end);
                  FileWrite(
                     gaps_handle,
                     SOLTRADE_HISTORY_SCHEMA,
                     SolTradeHistoryTimestampMsc(previous_tick_msc),
                     SolTradeHistoryTimestampMsc(tick_msc),
                     DoubleToString(
                        (double)(tick_msc - previous_tick_msc) / 1000.0,
                        3),
                     gap_class);
                  if(gap_class == "IN_SESSION_CANDIDATE_GAP")
                     candidate_gaps++;
                 }
               previous_tick_msc = tick_msc;
              }
           }
         FileWrite(daily_handle,
                   SOLTRADE_HISTORY_SCHEMA,
                   TimeToString(day_start, TIME_DATE),
                   IntegerToString(MathMax(day_ticks, 0)),
                   day_ticks > 0
                      ? SolTradeHistoryTimestampMsc(ticks[0].time_msc)
                      : "",
                   day_ticks > 0
                      ? SolTradeHistoryTimestampMsc(
                           ticks[day_ticks - 1].time_msc)
                      : "",
                   IntegerToString(tick_error));

         MqlRates rates[];
         int m1_error = 0;
         const int day_bars =
            SolTradeCopyM1Day(day_start,
                              day_end,
                              rates,
                              m1_error);
         if(day_bars < 0)
           {
            month_m1_failures++;
            total_m1_failures++;
           }
         else
           {
            month_m1_bars += day_bars;
            total_m1_bars += day_bars;
           }
         FileWrite(m1_handle,
                   SOLTRADE_HISTORY_SCHEMA,
                   TimeToString(day_start, TIME_DATE),
                   IntegerToString(MathMax(day_bars, 0)),
                   day_bars > 0
                      ? TimeToString(rates[0].time,
                                     TIME_DATE | TIME_SECONDS)
                      : "",
                   day_bars > 0
                      ? TimeToString(rates[day_bars - 1].time,
                                     TIME_DATE | TIME_SECONDS)
                      : "",
                   IntegerToString(m1_error));
         FileFlush(daily_handle);
         FileFlush(gaps_handle);
         FileFlush(m1_handle);
        }

      if(stopped)
         break;

      FileWrite(monthly_handle,
                SOLTRADE_HISTORY_SCHEMA,
                TimeToString(month_start,
                             TIME_DATE | TIME_SECONDS),
                TimeToString(next_month,
                             TIME_DATE | TIME_SECONDS),
                StringFormat("%I64d", month_ticks),
                SolTradeHistoryTimestampMsc(month_first_msc),
                SolTradeHistoryTimestampMsc(month_final_msc),
                IntegerToString(month_weekday_zero_days),
                IntegerToString(month_failures),
                StringFormat("%I64d", month_m1_bars),
                IntegerToString(month_m1_failures));
      FileFlush(monthly_handle);
      PrintFormat(
         "SOLTRADE_HISTORY_MONTH_COMPLETE | start=%s | end_exclusive=%s | ticks=%I64d | first=%s | final=%s | weekday_zero_days=%d | failures=%d | m1_bars=%I64d | m1_failures=%d",
         TimeToString(month_start, TIME_DATE),
         TimeToString(next_month, TIME_DATE),
         month_ticks,
         SolTradeHistoryTimestampMsc(month_first_msc),
         SolTradeHistoryTimestampMsc(month_final_msc),
         month_weekday_zero_days,
         month_failures,
         month_m1_bars,
         month_m1_failures);
     }

   FileClose(monthly_handle);
   FileClose(daily_handle);
   FileClose(gaps_handle);
   FileClose(m1_handle);
   if(stopped)
     {
      Print("SOLTRADE_HISTORY_STOPPED | no completed inventory emitted");
      return;
     }
   PrintFormat(
      "SOLTRADE_HISTORY_ACQUISITION_COMPLETE | interval=[%s,%s) | total_ticks=%I64d | earliest=%s | final=%s | tick_copy_failures=%d | weekday_zero_tick_days=%d | candidate_gaps=%d | m1_bars=%I64d | m1_synchronized=%s | m1_copy_failures=%d | orders=%d | positions=%d | broker_calls=NONE",
      TimeToString(SOLTRADE_HISTORY_START,
                   TIME_DATE | TIME_SECONDS),
      TimeToString(SOLTRADE_HISTORY_END_EXCLUSIVE,
                   TIME_DATE | TIME_SECONDS),
      total_ticks,
      SolTradeHistoryTimestampMsc(global_first_msc),
      SolTradeHistoryTimestampMsc(global_final_msc),
      total_copy_failures,
      total_weekday_zero_days,
      candidate_gaps,
      total_m1_bars,
      m1_synchronized ? "YES" : "NO",
      total_m1_failures,
      OrdersTotal(),
      PositionsTotal());
  }
