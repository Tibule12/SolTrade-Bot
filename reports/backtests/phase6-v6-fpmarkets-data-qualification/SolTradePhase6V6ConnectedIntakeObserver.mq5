#property copyright "SolTrade Bot"
#property link      ""
#property version   "1.000"
#property strict
#property description "Inert connected-terminal Phase 6 V6 intake observer"
#property description "Captures FP Markets demo metadata only; contains no trade operations."

const string SOLTRADE_V6_EXPECTED_SERVER = "FPMarketsSC-Demo";
const string SOLTRADE_V6_EXPECTED_SYMBOL = "EURUSD";

string V6Clock(const datetime value)
  {
   return TimeToString(value, TIME_DATE | TIME_SECONDS);
  }

int V6SessionSecond(const datetime value)
  {
   MqlDateTime parts;
   TimeToStruct(value, parts);
   return parts.hour * 3600 + parts.min * 60 + parts.sec;
  }

string V6SessionClock(const int value)
  {
   if(value >= 86400)
      return "24:00:00";
   const int normalized = value < 0 ? 0 : value;
   return StringFormat("%02d:%02d:%02d",
                       normalized / 3600,
                       (normalized % 3600) / 60,
                       normalized % 60);
  }

string V6SessionDescription(const string symbol,
                            const ENUM_DAY_OF_WEEK weekday)
  {
   string result = "";
   int count = 0;
   for(uint session = 0; session < 20; session++)
     {
      datetime session_from = 0;
      datetime session_to = 0;
      if(!SymbolInfoSessionTrade(symbol,
                                 weekday,
                                 session,
                                 session_from,
                                 session_to))
         break;
      const int from_second = V6SessionSecond(session_from);
      int to_second = V6SessionSecond(session_to);
      if(to_second <= from_second)
         to_second = 86400;
      if(count > 0)
         result += ",";
      result += V6SessionClock(from_second) + "-" +
                V6SessionClock(to_second);
      count++;
     }
   return count == 0 ? "CLOSED" : result;
  }

void V6LogSessions(const string symbol)
  {
   for(int day = 0; day <= 6; day++)
     {
      const ENUM_DAY_OF_WEEK weekday = (ENUM_DAY_OF_WEEK)day;
      PrintFormat(
         "SOLTRADE_PHASE6_V6_INTAKE_SESSION | weekday=%s | schedule=%s | source=SymbolInfoSessionTrade | broker_server_timezone=UNRESOLVED",
         EnumToString(weekday),
         V6SessionDescription(symbol, weekday));
     }
  }

int OnInit()
  {
   const string server = AccountInfoString(ACCOUNT_SERVER);
   const string company = AccountInfoString(ACCOUNT_COMPANY);
   const string currency = AccountInfoString(ACCOUNT_CURRENCY);
   const long trade_mode = AccountInfoInteger(ACCOUNT_TRADE_MODE);
   const long leverage = AccountInfoInteger(ACCOUNT_LEVERAGE);
   const bool demo = trade_mode == ACCOUNT_TRADE_MODE_DEMO;
   const bool tester = (bool)MQLInfoInteger(MQL_TESTER);
   const bool terminal_trade_allowed =
      (bool)TerminalInfoInteger(TERMINAL_TRADE_ALLOWED);
   const bool mql_trade_allowed =
      (bool)MQLInfoInteger(MQL_TRADE_ALLOWED);
   const int orders = OrdersTotal();
   const int positions = PositionsTotal();
   const bool symbol_selected = SymbolSelect(SOLTRADE_V6_EXPECTED_SYMBOL,
                                             true);

   Print(
      "SOLTRADE_PHASE6_V6_INTAKE_SCOPE | intake_only=YES | strategy=NOT_LOADED | risk_engine=NOT_LOADED | execution_engine=NOT_LOADED | position_manager=NOT_LOADED | trade_api_calls=NONE | profitability=NOT_CALCULATED | optimization=NO | replica=NO | phase7=NO");
   PrintFormat(
      "SOLTRADE_PHASE6_V6_INTAKE_PREFLIGHT | tester=%s | server=%s | company=%s | demo=%s | account_currency=%s | account_leverage=%I64d | terminal_build=%d | terminal_trade_allowed=%s | mql_trade_allowed=%s | orders=%d | positions=%d | symbol_select=%s",
      tester ? "YES" : "NO",
      server,
      company,
      demo ? "YES" : "NO",
      currency,
      leverage,
      (int)TerminalInfoInteger(TERMINAL_BUILD),
      terminal_trade_allowed ? "YES" : "NO",
      mql_trade_allowed ? "YES" : "NO",
      orders,
      positions,
      symbol_selected ? "YES" : "NO");

   if(tester ||
      server != SOLTRADE_V6_EXPECTED_SERVER ||
      !demo ||
      !symbol_selected ||
      terminal_trade_allowed ||
      mql_trade_allowed ||
      orders != 0 ||
      positions != 0)
     {
      Print(
         "SOLTRADE_PHASE6_V6_INTAKE_REJECTED | reason=CONNECTED_DEMO_PREFLIGHT_FAILED | trade_attempted=NO");
      ExpertRemove();
      return INIT_FAILED;
     }

   const int digits =
      (int)SymbolInfoInteger(SOLTRADE_V6_EXPECTED_SYMBOL,
                             SYMBOL_DIGITS);
   const double point =
      SymbolInfoDouble(SOLTRADE_V6_EXPECTED_SYMBOL, SYMBOL_POINT);
   const double tick_size =
      SymbolInfoDouble(SOLTRADE_V6_EXPECTED_SYMBOL,
                       SYMBOL_TRADE_TICK_SIZE);
   const double tick_value =
      SymbolInfoDouble(SOLTRADE_V6_EXPECTED_SYMBOL,
                       SYMBOL_TRADE_TICK_VALUE);
   const double tick_value_profit =
      SymbolInfoDouble(SOLTRADE_V6_EXPECTED_SYMBOL,
                       SYMBOL_TRADE_TICK_VALUE_PROFIT);
   const double tick_value_loss =
      SymbolInfoDouble(SOLTRADE_V6_EXPECTED_SYMBOL,
                       SYMBOL_TRADE_TICK_VALUE_LOSS);
   const double contract_size =
      SymbolInfoDouble(SOLTRADE_V6_EXPECTED_SYMBOL,
                       SYMBOL_TRADE_CONTRACT_SIZE);
   PrintFormat(
      "SOLTRADE_PHASE6_V6_INTAKE_SYMBOL | symbol=%s | digits=%d | point=%.10f | tick_size=%.10f | tick_value=%.10f | tick_value_profit=%.10f | tick_value_loss=%.10f | contract_size=%.4f",
      SOLTRADE_V6_EXPECTED_SYMBOL,
      digits,
      point,
      tick_size,
      tick_value,
      tick_value_profit,
      tick_value_loss,
      contract_size);

   const datetime server_time = TimeTradeServer();
   const datetime gmt_time = TimeGMT();
   const datetime local_time = TimeLocal();
   const long observed_utc_offset_seconds =
      (long)(server_time - gmt_time);
   PrintFormat(
      "SOLTRADE_PHASE6_V6_INTAKE_TIME | broker_server_time=%s | observed_utc_time=%s | local_time=%s | observed_utc_offset_seconds=%I64d | observed_utc_offset_hours=%.4f | daylight_saving_status=UNDETERMINED",
      V6Clock(server_time),
      V6Clock(gmt_time),
      V6Clock(local_time),
      observed_utc_offset_seconds,
      (double)observed_utc_offset_seconds / 3600.0);

   V6LogSessions(SOLTRADE_V6_EXPECTED_SYMBOL);

   const datetime m1_server_first =
      (datetime)SeriesInfoInteger(SOLTRADE_V6_EXPECTED_SYMBOL,
                                  PERIOD_M1,
                                  SERIES_SERVER_FIRSTDATE);
   const datetime m1_terminal_first =
      (datetime)SeriesInfoInteger(SOLTRADE_V6_EXPECTED_SYMBOL,
                                  PERIOD_M1,
                                  SERIES_TERMINAL_FIRSTDATE);
   const datetime m1_last =
      (datetime)SeriesInfoInteger(SOLTRADE_V6_EXPECTED_SYMBOL,
                                  PERIOD_M1,
                                  SERIES_LASTBAR_DATE);
   MqlTick latest_tick;
   ZeroMemory(latest_tick);
   const bool latest_tick_available =
      SymbolInfoTick(SOLTRADE_V6_EXPECTED_SYMBOL, latest_tick);
   PrintFormat(
      "SOLTRADE_PHASE6_V6_INTAKE_AVAILABILITY | first_available_real_tick=DEFERRED_TO_REAL_TICK_QUALIFICATION | latest_connected_tick=%s | latest_tick_available=%s | first_available_m1_server=%s | first_available_m1_terminal=%s | last_available_m1=%s",
      latest_tick_available ? V6Clock(latest_tick.time) : "NONE",
      latest_tick_available ? "YES" : "NO",
      m1_server_first == 0 ? "UNKNOWN" : V6Clock(m1_server_first),
      m1_terminal_first == 0 ? "UNKNOWN" : V6Clock(m1_terminal_first),
      m1_last == 0 ? "UNKNOWN" : V6Clock(m1_last));
   Print(
      "SOLTRADE_PHASE6_V6_INTAKE_COMPLETE | status=METADATA_CAPTURED | trade_attempted=NO | orders_created=0 | positions_created=0 | next=REAL_TICK_DATA_QUALIFICATION_ONLY");
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
      "SOLTRADE_PHASE6_V6_INTAKE_UNEXPECTED_TRADE_TRANSACTION | qualification_invalidated=YES");
  }
