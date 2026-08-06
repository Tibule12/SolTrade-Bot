#property copyright "SolTrade Bot"
#property link      ""
#property version   "1.000"
#property strict
#property description "Inert Phase 6 V8 Strategy Tester real-tick capability probe"
#property description "No strategy, performance calculation, or trade operations."

input bool EnableEntryPermission              = false;
input bool EnableExecutionPermission          = false;
input bool EnablePositionManagementPermission = false;
input bool PermitStrategyOrders               = false;

const datetime V8_PROBE_START = D'2025.01.02 00:00:00';
const datetime V8_PROBE_END = D'2025.12.24 00:00:00';
const ulong V8_EXPECTED_TICKS = 20682267;
const ulong V8_EXPECTED_FIRST =
   (ulong)D'2025.01.02 00:00:00' * 1000 + 594;
const ulong V8_EXPECTED_FINAL =
   (ulong)D'2025.12.23 23:59:59' * 1000 + 877;

ulong g_tick_count = 0;
ulong g_first_tick_msc = 0;
ulong g_final_tick_msc = 0;
long g_boundary_violations = 0;
long g_out_of_order = 0;
long g_trade_transactions = 0;
int g_orders_before = 0;
int g_positions_before = 0;
int g_deals_before = 0;
int g_nonbalance_deals_before = 0;

string V8ProbeTimestamp(const ulong value)
  {
   if(value == 0)
      return "NONE";
   return TimeToString((datetime)(value / 1000),
                       TIME_DATE | TIME_SECONDS) +
          "." + StringFormat("%03u", (uint)(value % 1000));
  }

int V8ProbeCountNonbalanceDeals()
  {
   int count = 0;
   const int total = HistoryDealsTotal();
   for(int index = 0; index < total; index++)
     {
      const ulong ticket = HistoryDealGetTicket(index);
      if(ticket == 0)
        {
         count++;
         continue;
        }
      const ENUM_DEAL_TYPE type =
         (ENUM_DEAL_TYPE)HistoryDealGetInteger(ticket, DEAL_TYPE);
      if(type != DEAL_TYPE_BALANCE)
         count++;
     }
   return count;
  }

int OnInit()
  {
   const bool permissions_disabled =
      !EnableEntryPermission &&
      !EnableExecutionPermission &&
      !EnablePositionManagementPermission &&
      !PermitStrategyOrders;
   HistorySelect(V8_PROBE_START, V8_PROBE_END);
   g_orders_before = OrdersTotal();
   g_positions_before = PositionsTotal();
   g_deals_before = HistoryDealsTotal();
   g_nonbalance_deals_before = V8ProbeCountNonbalanceDeals();

   const bool preflight =
      (bool)MQLInfoInteger(MQL_TESTER) &&
      _Symbol == "EURUSD" &&
      _Period == PERIOD_H1 &&
      permissions_disabled &&
      g_orders_before == 0 &&
      g_positions_before == 0 &&
      g_nonbalance_deals_before == 0;

   PrintFormat(
      "SOLTRADE_PHASE6_V8_TESTER_PROBE_PREFLIGHT | valid=%s | MQL_TESTER=%s | symbol=%s | period=%s | entry_permission=%s | execution_permission=%s | position_management_permission=%s | strategy_orders_permitted=%s | orders=%d | positions=%d | history_deals=%d | nonbalance_deals=%d | tester_balance_records=%d | strategy=NOT_LOADED | trade_api_calls=NONE | profitability=NOT_CALCULATED",
      preflight ? "YES" : "NO",
      (bool)MQLInfoInteger(MQL_TESTER) ? "true" : "false",
      _Symbol,
      EnumToString(_Period),
      EnableEntryPermission ? "true" : "false",
      EnableExecutionPermission ? "true" : "false",
      EnablePositionManagementPermission ? "true" : "false",
      PermitStrategyOrders ? "true" : "false",
      g_orders_before,
      g_positions_before,
      g_deals_before,
      g_nonbalance_deals_before,
      g_deals_before - g_nonbalance_deals_before);
   Print(
      "SOLTRADE_PHASE6_V8_TESTER_PROBE_SCOPE | interval=[2025.01.02 00:00:00,2025.12.24 00:00:00) | requested_model=EVERY_TICK_BASED_ON_REAL_TICKS | expected_ticks=20682267 | expected_first=2025.01.02 00:00:00.594 | expected_final=2025.12.23 23:59:59.877 | authoritative_strategy_run=NO | replica=NO | optimization=NO");

   if(!preflight)
     {
      Print("SOLTRADE_PHASE6_V8_TESTER_PROBE_REJECTED | reason=INERT_PREFLIGHT_FAILED");
      return INIT_FAILED;
     }
   return INIT_SUCCEEDED;
  }

void OnTick()
  {
   MqlTick tick;
   if(!SymbolInfoTick(_Symbol, tick))
      return;
   const ulong tick_msc = (ulong)tick.time_msc;

   if(g_tick_count == 0)
      g_first_tick_msc = tick_msc;
   else if(tick_msc < g_final_tick_msc)
      g_out_of_order++;

   if(tick_msc < (ulong)V8_PROBE_START * 1000 ||
      tick_msc >= (ulong)V8_PROBE_END * 1000)
      g_boundary_violations++;

   g_final_tick_msc = tick_msc;
   g_tick_count++;
  }

void OnTradeTransaction(const MqlTradeTransaction &transaction,
                        const MqlTradeRequest &request,
                        const MqlTradeResult &result)
  {
   g_trade_transactions++;
  }

void OnDeinit(const int reason)
  {
   HistorySelect(V8_PROBE_START, V8_PROBE_END);
   const int orders_after = OrdersTotal();
   const int positions_after = PositionsTotal();
   const int deals_after = HistoryDealsTotal();
   const int history_orders_after = HistoryOrdersTotal();
   const int nonbalance_deals_after = V8ProbeCountNonbalanceDeals();
   const bool exact_stream =
      g_tick_count == V8_EXPECTED_TICKS &&
      g_first_tick_msc == V8_EXPECTED_FIRST &&
      g_final_tick_msc == V8_EXPECTED_FINAL &&
      g_boundary_violations == 0 &&
      g_out_of_order == 0;
   const bool zero_trading =
      g_orders_before == 0 &&
      g_positions_before == 0 &&
      g_nonbalance_deals_before == 0 &&
      orders_after == 0 &&
      positions_after == 0 &&
      nonbalance_deals_after == 0 &&
      history_orders_after == 0 &&
      g_trade_transactions == 0;
   const bool passed =
      (bool)MQLInfoInteger(MQL_TESTER) &&
      exact_stream &&
      zero_trading;

   PrintFormat(
      "SOLTRADE_PHASE6_V8_TESTER_PROBE_TICKS | count=%I64u | first=%s | final=%s | expected_count=%I64u | expected_first=%s | expected_final=%s | boundary_violations=%I64d | out_of_order=%I64d | exact_connected_stream_match=%s",
      g_tick_count,
      V8ProbeTimestamp(g_first_tick_msc),
      V8ProbeTimestamp(g_final_tick_msc),
      V8_EXPECTED_TICKS,
      V8ProbeTimestamp(V8_EXPECTED_FIRST),
      V8ProbeTimestamp(V8_EXPECTED_FINAL),
      g_boundary_violations,
      g_out_of_order,
      exact_stream ? "YES" : "NO");
   PrintFormat(
      "SOLTRADE_PHASE6_V8_TESTER_PROBE_POSTRUN | orders=%d | historical_orders=%d | history_deals=%d | nonbalance_deals=%d | tester_balance_records=%d | positions=%d | trade_transactions=%I64d | zero_trading=%s | deinit_reason=%d",
      orders_after,
      history_orders_after,
      deals_after,
      nonbalance_deals_after,
      deals_after - nonbalance_deals_after,
      positions_after,
      g_trade_transactions,
      zero_trading ? "YES" : "NO",
      reason);
   PrintFormat(
      "SOLTRADE_PHASE6_V8_TESTER_PROBE_RESULT | status=%s | exact_connected_stream_match=%s | zero_orders_deals_positions=%s | controller_fallback_scan=REQUIRED_EXTERNAL_EVIDENCE | strategy=NOT_LOADED | performance_statistics=NOT_GENERATED | profitability=NOT_CALCULATED | trade_api_calls=NONE",
      passed ? "PASS" : "FAIL",
      exact_stream ? "YES" : "NO",
      zero_trading ? "YES" : "NO");
  }
