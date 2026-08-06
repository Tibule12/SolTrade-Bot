#property copyright "SolTrade Bot"
#property link      ""
#property version   "1.000"
#property strict
#property description "Inert V8 connected tail-tick diagnostic observer"
#property description "Read-only CopyTicksRange evidence; no strategy or trade operations."

int OnInit()
  {
   const bool valid =
      !(bool)MQLInfoInteger(MQL_TESTER) &&
      AccountInfoString(ACCOUNT_SERVER) == "FPMarketsSC-Demo" &&
      (ENUM_ACCOUNT_TRADE_MODE)AccountInfoInteger(ACCOUNT_TRADE_MODE) ==
         ACCOUNT_TRADE_MODE_DEMO &&
      _Symbol == "EURUSD" &&
      !(bool)TerminalInfoInteger(TERMINAL_TRADE_ALLOWED) &&
      !(bool)MQLInfoInteger(MQL_TRADE_ALLOWED) &&
      OrdersTotal() == 0 &&
      PositionsTotal() == 0;
   PrintFormat(
      "SOLTRADE_PHASE6_V8_TAIL_PREFLIGHT | valid=%s | server=%s | demo=%s | symbol=%s | terminal_trade_allowed=%s | mql_trade_allowed=%s | orders=%d | positions=%d | strategy=NOT_LOADED | trade_api_calls=NONE",
      valid ? "YES" : "NO",
      AccountInfoString(ACCOUNT_SERVER),
      (ENUM_ACCOUNT_TRADE_MODE)AccountInfoInteger(ACCOUNT_TRADE_MODE) ==
         ACCOUNT_TRADE_MODE_DEMO ? "YES" : "NO",
      _Symbol,
      (bool)TerminalInfoInteger(TERMINAL_TRADE_ALLOWED) ? "YES" : "NO",
      (bool)MQLInfoInteger(MQL_TRADE_ALLOWED) ? "YES" : "NO",
      OrdersTotal(),
      PositionsTotal());
   if(!valid)
      return INIT_FAILED;

   MqlTick ticks[];
   const ulong from_msc =
      (ulong)D'2025.12.23 23:59:55' * 1000;
   const ulong to_msc =
      (ulong)D'2025.12.24 00:00:00' * 1000 - 1;
   ResetLastError();
   const int copied =
      CopyTicksRange("EURUSD", ticks, COPY_TICKS_ALL, from_msc, to_msc);
   const int error = GetLastError();
   PrintFormat(
      "SOLTRADE_PHASE6_V8_TAIL_SUMMARY | copied=%d | error=%d | from=2025.12.23 23:59:55.000 | to=2025.12.23 23:59:59.999",
      copied,
      error);
   for(int index = 0; index < copied; index++)
     {
      const ulong time_msc = (ulong)ticks[index].time_msc;
      PrintFormat(
         "SOLTRADE_PHASE6_V8_TAIL_TICK | index=%d | timestamp=%s.%03u | bid=%.10f | ask=%.10f | last=%.10f | volume=%I64u | flags=%u",
         index,
         TimeToString((datetime)(time_msc / 1000),
                      TIME_DATE | TIME_SECONDS),
         (uint)(time_msc % 1000),
         ticks[index].bid,
         ticks[index].ask,
         ticks[index].last,
         ticks[index].volume,
         ticks[index].flags);
     }
   Print(
      "SOLTRADE_PHASE6_V8_TAIL_COMPLETE | strategy_run=NO | profitability=NOT_CALCULATED | orders_created=0 | positions_created=0 | trade_api_calls=NONE");
   ExpertRemove();
   return INIT_SUCCEEDED;
  }

void OnTick()
  {
  }
