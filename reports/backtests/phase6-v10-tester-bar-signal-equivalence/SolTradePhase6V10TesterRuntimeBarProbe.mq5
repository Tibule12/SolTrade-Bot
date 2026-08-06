#property copyright "SolTrade Bot"
#property link      ""
#property version   "1.000"
#property strict
#property description "Inert Phase 6 V10 tester-runtime completed-H1 bar exporter"
#property description "No strategy, profitability calculation, or trade operations."

input datetime ProbeStart = D'2025.01.02 00:00:00';
input datetime ProbeEnd = D'2025.12.25 00:00:00';
input datetime ResearchCutoff = D'2025.12.24 00:00:00';
input bool EnableEntryPermission = false;
input bool EnableExecutionPermission = false;
input bool EnablePositionManagementPermission = false;
input bool PermitStrategyOrders = false;

struct V10RuntimeHour
  {
   datetime time;
   ulong count;
   long first_msc;
   long last_msc;
  };

V10RuntimeHour g_hours[];
int g_hour_count = 0;
ulong g_unique_minutes = 0;
long g_last_minute = -1;
long g_trade_transactions = 0;
int g_nonbalance_before = 0;
bool g_preflight = false;

int V10NonbalanceDeals()
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

string V10TimestampMsc(const long value)
  {
   if(value <= 0)
      return "NONE";
   return TimeToString((datetime)(value / 1000),
                       TIME_DATE | TIME_SECONDS) +
          "." + StringFormat("%03d", (int)(value % 1000));
  }

void V10AddRuntimeTick(const MqlTick &tick)
  {
   const datetime hour = (datetime)((tick.time / 3600) * 3600);
   if(g_hour_count == 0 || g_hours[g_hour_count - 1].time != hour)
     {
      ArrayResize(g_hours, g_hour_count + 1, 1024);
      g_hours[g_hour_count].time = hour;
      g_hours[g_hour_count].count = 0;
      g_hours[g_hour_count].first_msc = tick.time_msc;
      g_hours[g_hour_count].last_msc = tick.time_msc;
      g_hour_count++;
     }
   g_hours[g_hour_count - 1].count++;
   g_hours[g_hour_count - 1].last_msc = tick.time_msc;

   const long minute = tick.time_msc / 60000;
   if(g_unique_minutes == 0 || minute != g_last_minute)
     {
      g_unique_minutes++;
      g_last_minute = minute;
     }
  }

int V10FindRuntimeHour(const datetime time)
  {
   int low = 0;
   int high = g_hour_count - 1;
   while(low <= high)
     {
      const int middle = low + (high - low) / 2;
      if(g_hours[middle].time == time)
         return middle;
      if(g_hours[middle].time < time)
         low = middle + 1;
      else
         high = middle - 1;
     }
   return -1;
  }

bool V10WriteResearchBars(const MqlRates &rates[],
                          int &written,
                          int &missing_runtime,
                          datetime &first_bar,
                          datetime &last_bar,
                          double &final_close)
  {
   FolderCreate("SolTrade", FILE_COMMON);
   FolderCreate("SolTrade\\Phase6", FILE_COMMON);
   FolderCreate("SolTrade\\Phase6\\V10", FILE_COMMON);
   ResetLastError();
   const int handle = FileOpen(
      "SolTrade\\Phase6\\V10\\tester-runtime-h1-bars-v10.csv",
      FILE_WRITE | FILE_CSV | FILE_ANSI | FILE_COMMON, ',');
   if(handle == INVALID_HANDLE)
     {
      PrintFormat("SOLTRADE_PHASE6_V10_FILE_FAIL | error=%d", GetLastError());
      return false;
     }

   FileWrite(handle, "timestamp", "open", "high", "low", "close",
             "tick_volume", "spread", "runtime_tick_count",
             "first_runtime_tick", "last_runtime_tick",
             "research_eligible_time_domain");
   written = 0;
   missing_runtime = 0;
   first_bar = 0;
   last_bar = 0;
   final_close = 0.0;
   for(int index = 0; index < ArraySize(rates); index++)
     {
      if(rates[index].time < ProbeStart ||
         rates[index].time >= ResearchCutoff)
         continue;
      const int runtime_index = V10FindRuntimeHour(rates[index].time);
      const ulong runtime_count = runtime_index >= 0 ?
         g_hours[runtime_index].count : 0;
      const string first_tick = runtime_index >= 0 ?
         V10TimestampMsc(g_hours[runtime_index].first_msc) : "NONE";
      const string last_tick = runtime_index >= 0 ?
         V10TimestampMsc(g_hours[runtime_index].last_msc) : "NONE";
      if(runtime_index < 0)
         missing_runtime++;
      FileWrite(handle,
                TimeToString(rates[index].time,
                             TIME_DATE | TIME_SECONDS),
                DoubleToString(rates[index].open, 10),
                DoubleToString(rates[index].high, 10),
                DoubleToString(rates[index].low, 10),
                DoubleToString(rates[index].close, 10),
                (string)rates[index].tick_volume,
                IntegerToString(rates[index].spread),
                (string)runtime_count,
                first_tick, last_tick, "PRE_CUTOFF_ONLY");
      if(written == 0)
         first_bar = rates[index].time;
      last_bar = rates[index].time;
      final_close = rates[index].close;
      written++;
     }
   FileFlush(handle);
   FileClose(handle);
   return true;
  }

int OnInit()
  {
   HistorySelect(ProbeStart, ProbeEnd);
   g_nonbalance_before = V10NonbalanceDeals();
   g_preflight =
      (bool)MQLInfoInteger(MQL_TESTER) && _Symbol == "EURUSD" &&
      _Period == PERIOD_H1 &&
      ProbeStart == D'2025.01.02 00:00:00' &&
      ProbeEnd == D'2025.12.25 00:00:00' &&
      ResearchCutoff == D'2025.12.24 00:00:00' &&
      !EnableEntryPermission && !EnableExecutionPermission &&
      !EnablePositionManagementPermission && !PermitStrategyOrders &&
      OrdersTotal() == 0 && PositionsTotal() == 0 &&
      g_nonbalance_before == 0;
   PrintFormat(
      "SOLTRADE_PHASE6_V10_PREFLIGHT | valid=%s | interval=[%s,%s) | research_cutoff=%s | MQL_TESTER=%s | symbol=%s | period=%s | entry=NO | execution=NO | management=NO | strategy_orders=NO | orders=%d | positions=%d | nonbalance_deals=%d | requested_model=EVERY_TICK_BASED_ON_REAL_TICKS | strategy=NOT_LOADED | trade_api_calls=NONE | profitability=NOT_CALCULATED",
      g_preflight ? "YES" : "NO",
      TimeToString(ProbeStart, TIME_DATE | TIME_SECONDS),
      TimeToString(ProbeEnd, TIME_DATE | TIME_SECONDS),
      TimeToString(ResearchCutoff, TIME_DATE | TIME_SECONDS),
      (bool)MQLInfoInteger(MQL_TESTER) ? "YES" : "NO",
      _Symbol, EnumToString(_Period), OrdersTotal(), PositionsTotal(),
      g_nonbalance_before);
   return g_preflight ? INIT_SUCCEEDED : INIT_FAILED;
  }

void OnTick()
  {
   MqlTick tick;
   if(SymbolInfoTick(_Symbol, tick))
      V10AddRuntimeTick(tick);
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
   MqlRates rates[];
   ArraySetAsSeries(rates, false);
   ResetLastError();
   const int copied = CopyRates(_Symbol, PERIOD_H1,
                                ProbeStart, ProbeEnd - 1, rates);
   const int copy_error = GetLastError();
   int written = 0;
   int missing_runtime = 0;
   datetime first_bar = 0;
   datetime last_bar = 0;
   double final_close = 0.0;
   const bool file_ok = copied > 0 &&
      V10WriteResearchBars(rates, written, missing_runtime,
                           first_bar, last_bar, final_close);

   MqlRates m1[];
   ArraySetAsSeries(m1, false);
   ResetLastError();
   const int m1_count = CopyRates(_Symbol, PERIOD_M1,
                                  ProbeStart, ProbeEnd - 1, m1);
   const int m1_error = GetLastError();
   HistorySelect(ProbeStart, ProbeEnd);
   const int nonbalance_after = V10NonbalanceDeals();
   const bool zero_trading = OrdersTotal() == 0 &&
      PositionsTotal() == 0 && HistoryOrdersTotal() == 0 &&
      nonbalance_after == 0 && g_trade_transactions == 0;
   const bool no_silent_minutes = m1_count >= 0 &&
      (ulong)m1_count == g_unique_minutes;
   const bool final_ok = last_bar == D'2025.12.23 23:00:00' &&
      MathAbs(final_close - 1.17938) < 0.0000001;
   const bool passed = file_ok && copy_error == 0 &&
      written == 6097 && missing_runtime == 0 && no_silent_minutes &&
      zero_trading && final_ok;
   PrintFormat(
      "SOLTRADE_PHASE6_V10_COMPLETE | status=%s | copied_h1=%d | exported_pre_cutoff_h1=%d | first_bar=%s | final_bar=%s | final_close=%.10f | runtime_hours=%d | missing_runtime_hours=%d | runtime_unique_minutes=%I64u | tester_m1_bars=%d | m1_error=%d | no_silent_generated_minute=%s | file_ok=%s | orders=%d | historical_orders=%d | positions=%d | nonbalance_deals=%d | trade_transactions=%I64d | guard_tail_in_research=NO | strategy_run=NO | profitability=NOT_CALCULATED | deinit_reason=%d",
      passed ? "PASS" : "FAIL", copied, written,
      TimeToString(first_bar, TIME_DATE | TIME_SECONDS),
      TimeToString(last_bar, TIME_DATE | TIME_SECONDS), final_close,
      g_hour_count, missing_runtime, g_unique_minutes, m1_count,
      m1_error, no_silent_minutes ? "YES" : "NO",
      file_ok ? "YES" : "NO", OrdersTotal(), HistoryOrdersTotal(),
      PositionsTotal(), nonbalance_after, g_trade_transactions, reason);
   ArrayFree(rates);
   ArrayFree(m1);
  }
