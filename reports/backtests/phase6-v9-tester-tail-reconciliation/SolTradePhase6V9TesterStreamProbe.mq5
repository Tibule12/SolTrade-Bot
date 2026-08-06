#property copyright "SolTrade Bot"
#property link      ""
#property version   "1.000"
#property strict
#property description "Inert Phase 6 V9 tester CopyTicks/OnTick stream reconciliation probe"
#property description "No strategy, performance calculation, or trade operations."

#include "SolTradePhase6V9Hashing.mqh"

input string ProbeId = "A";
input datetime ProbeStart = D'2025.01.02 00:00:00';
input datetime ProbeEnd = D'2025.12.24 00:00:00';
input bool EnableEntryPermission = false;
input bool EnableExecutionPermission = false;
input bool EnablePositionManagementPermission = false;
input bool PermitStrategyOrders = false;

V9StreamSet g_runtime;
ulong g_last_minute = 0;
ulong g_runtime_minutes = 0;
long g_trade_transactions = 0;
int g_nonbalance_deals_before = 0;
bool g_preflight = false;

int V9CountNonbalanceDeals()
  {
   int count = 0;
   const int total = HistoryDealsTotal();
   for(int index = 0; index < total; index++)
     {
      const ulong ticket = HistoryDealGetTicket(index);
      if(ticket == 0 ||
         (ENUM_DEAL_TYPE)HistoryDealGetInteger(ticket, DEAL_TYPE) !=
            DEAL_TYPE_BALANCE)
         count++;
     }
   return count;
  }

void V9PrintBar(const ENUM_TIMEFRAMES period,
                const datetime start_time,
                const datetime end_time)
  {
   MqlRates rates[];
   ArraySetAsSeries(rates, false);
   ResetLastError();
   const int copied =
      CopyRates(_Symbol, period, start_time, end_time - 1, rates);
   const int error = GetLastError();
   if(copied != 1)
     {
      PrintFormat(
         "SOLTRADE_PHASE6_V9_TESTER_BAR | probe=%s | period=%s | copied=%d | error=%d | valid=NO",
         ProbeId, EnumToString(period), copied, error);
      return;
     }
   MqlTick ticks[];
   ResetLastError();
   const int tick_count = CopyTicksRange(
      _Symbol, ticks, COPY_TICKS_ALL,
      (ulong)start_time * 1000,
      (ulong)end_time * 1000 - 1);
   const int tick_error = GetLastError();
   const string first = tick_count > 0 ?
      V9Timestamp((ulong)ticks[0].time_msc) : "NONE";
   const string final_tick = tick_count > 0 ?
      V9Timestamp((ulong)ticks[tick_count - 1].time_msc) : "NONE";
   PrintFormat(
      "SOLTRADE_PHASE6_V9_TESTER_BAR | probe=%s | period=%s | timestamp=%s | open=%.10f | high=%.10f | low=%.10f | close=%.10f | tick_volume=%I64u | spread=%d | database_tick_count=%d | first_tick=%s | final_tick=%s | copyticks_error=%d | valid=YES",
      ProbeId, EnumToString(period),
      TimeToString(rates[0].time, TIME_DATE | TIME_SECONDS),
      rates[0].open, rates[0].high, rates[0].low, rates[0].close,
      rates[0].tick_volume, rates[0].spread,
      tick_count, first, final_tick, tick_error);
   ArrayFree(ticks);
  }

int OnInit()
  {
   HistorySelect(ProbeStart, ProbeEnd);
   g_nonbalance_deals_before = V9CountNonbalanceDeals();
   const bool valid_id = ProbeId == "A" || ProbeId == "B" || ProbeId == "C";
   const bool valid_bounds =
      (ProbeId == "A" && ProbeStart == D'2025.01.02 00:00:00' &&
       ProbeEnd == D'2025.12.24 00:00:00') ||
      (ProbeId == "B" && ProbeStart == D'2025.01.02 00:00:00' &&
       ProbeEnd == D'2025.12.25 00:00:00') ||
      (ProbeId == "C" && ProbeStart == D'2025.12.23 00:00:00' &&
       ProbeEnd == D'2025.12.25 00:00:00');
   g_preflight =
      (bool)MQLInfoInteger(MQL_TESTER) && _Symbol == "EURUSD" &&
      _Period == PERIOD_H1 && valid_id && valid_bounds &&
      !EnableEntryPermission && !EnableExecutionPermission &&
      !EnablePositionManagementPermission && !PermitStrategyOrders &&
      OrdersTotal() == 0 && PositionsTotal() == 0 &&
      g_nonbalance_deals_before == 0;
   PrintFormat(
      "SOLTRADE_PHASE6_V9_TESTER_PREFLIGHT | probe=%s | valid=%s | start=%s | end_exclusive=%s | MQL_TESTER=%s | symbol=%s | period=%s | entry=%s | execution=%s | management=%s | strategy_orders=%s | orders=%d | positions=%d | nonbalance_deals=%d | requested_model=EVERY_TICK_BASED_ON_REAL_TICKS | copy_mode=COPY_TICKS_ALL | strategy=NOT_LOADED | trade_api_calls=NONE",
      ProbeId, g_preflight ? "YES" : "NO",
      TimeToString(ProbeStart, TIME_DATE | TIME_SECONDS),
      TimeToString(ProbeEnd, TIME_DATE | TIME_SECONDS),
      (bool)MQLInfoInteger(MQL_TESTER) ? "YES" : "NO",
      _Symbol, EnumToString(_Period),
      EnableEntryPermission ? "YES" : "NO",
      EnableExecutionPermission ? "YES" : "NO",
      EnablePositionManagementPermission ? "YES" : "NO",
      PermitStrategyOrders ? "YES" : "NO",
      OrdersTotal(), PositionsTotal(), g_nonbalance_deals_before);
   if(!g_preflight)
      return INIT_FAILED;
   V9StreamInit(g_runtime, ProbeId, "TESTER_ONTICK",
                ProbeStart, ProbeEnd);
   return INIT_SUCCEEDED;
  }

void OnTick()
  {
   MqlTick tick;
   if(!SymbolInfoTick(_Symbol, tick))
      return;
   const ulong tick_msc = (ulong)tick.time_msc;
   const ulong minute = tick_msc / 60000;
   if(g_runtime_minutes == 0 || minute != g_last_minute)
     {
      g_runtime_minutes++;
      g_last_minute = minute;
     }
   const string record = V9TickRecord(tick);
   if(!V9StreamAdd(g_runtime, tick, record))
      Print("SOLTRADE_PHASE6_V9_TESTER_HASH_FAILURE | source=TESTER_ONTICK");
  }

void OnTradeTransaction(const MqlTradeTransaction &transaction,
                        const MqlTradeRequest &request,
                        const MqlTradeResult &result)
  {
   g_trade_transactions++;
  }

void OnDeinit(const int reason)
  {
   if(!g_preflight)
      return;
   V9StreamPrint(g_runtime);

   V9StreamSet database;
   V9StreamInit(database, ProbeId, "TESTER_COPYTICKS",
                ProbeStart, ProbeEnd);
   ulong cursor = (ulong)ProbeStart * 1000;
   const ulong end_msc = (ulong)ProbeEnd * 1000;
   long retrieval_failures = 0;
   bool hashing_ok = true;
   while(cursor < end_msc && hashing_ok)
     {
      const ulong day_end =
         ((cursor / 86400000) + 1) * 86400000;
      const ulong request_end =
         (day_end < end_msc ? day_end : end_msc) - 1;
      MqlTick ticks[];
      ResetLastError();
      const int copied = CopyTicksRange(
         _Symbol, ticks, COPY_TICKS_ALL, cursor, request_end);
      if(copied < 0)
        {
         retrieval_failures++;
         PrintFormat(
            "SOLTRADE_PHASE6_V9_TESTER_COPY_FAIL | probe=%s | from=%s | to=%s | error=%d",
            ProbeId, V9Timestamp(cursor), V9Timestamp(request_end),
            GetLastError());
         break;
        }
      for(int index = 0; index < copied; index++)
        {
         const string record = V9TickRecord(ticks[index]);
         if(!V9StreamAdd(database, ticks[index], record))
           {
            hashing_ok = false;
            break;
           }
        }
      ArrayFree(ticks);
      cursor = day_end < end_msc ? day_end : end_msc;
     }
   V9StreamPrint(database);

   MqlRates m1[];
   ArraySetAsSeries(m1, false);
   ResetLastError();
   const int m1_count =
      CopyRates(_Symbol, PERIOD_M1, ProbeStart, ProbeEnd - 1, m1);
   const int m1_error = GetLastError();
   V9PrintBar(PERIOD_M1,
              D'2025.12.23 23:59:00',
              D'2025.12.24 00:00:00');
   V9PrintBar(PERIOD_H1,
              D'2025.12.23 23:00:00',
              D'2025.12.24 00:00:00');

   HistorySelect(ProbeStart, ProbeEnd);
   const int nonbalance_after = V9CountNonbalanceDeals();
   const bool zero_trading =
      OrdersTotal() == 0 && PositionsTotal() == 0 &&
      HistoryOrdersTotal() == 0 && nonbalance_after == 0 &&
      g_trade_transactions == 0;
   const bool no_silent_minutes =
      m1_count >= 0 && (ulong)m1_count == g_runtime_minutes;
   const bool passed =
      cursor == end_msc && hashing_ok && retrieval_failures == 0 &&
      zero_trading && no_silent_minutes;
   PrintFormat(
      "SOLTRADE_PHASE6_V9_TESTER_COMPLETE | probe=%s | status=%s | runtime_ticks=%I64u | tester_copyticks=%I64u | runtime_unique_minutes=%I64u | tester_m1_bars=%d | m1_error=%d | no_silent_generated_minute=%s | retrieval_failures=%I64d | hashing_ok=%s | orders=%d | historical_orders=%d | positions=%d | nonbalance_deals=%d | trade_transactions=%I64d | deinit_reason=%d | strategy_run=NO | profitability=NOT_CALCULATED",
      ProbeId, passed ? "PASS" : "FAIL",
      g_runtime.complete.count, database.complete.count,
      g_runtime_minutes, m1_count, m1_error,
      no_silent_minutes ? "YES" : "NO", retrieval_failures,
      hashing_ok ? "YES" : "NO", OrdersTotal(),
      HistoryOrdersTotal(), PositionsTotal(), nonbalance_after,
      g_trade_transactions, reason);
   ArrayFree(m1);
  }
