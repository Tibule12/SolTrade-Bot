#property copyright "SolTrade Bot"
#property link      ""
#property version   "1.000"
#property strict
#property description "Inert Phase 6 V9 connected COPY_TICKS_ALL stream hash probe"
#property description "No strategy, performance calculation, or trade operations."

#include "SolTradePhase6V9Hashing.mqh"

long g_trade_transactions = 0;

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
      OrdersTotal() == 0 && PositionsTotal() == 0;
   PrintFormat(
      "SOLTRADE_PHASE6_V9_CONNECTED_PREFLIGHT | valid=%s | server=%s | demo=%s | symbol=%s | terminal_trade_allowed=%s | mql_trade_allowed=%s | orders=%d | positions=%d | copy_mode=COPY_TICKS_ALL | strategy=NOT_LOADED | trade_api_calls=NONE",
      valid ? "YES" : "NO", AccountInfoString(ACCOUNT_SERVER),
      (ENUM_ACCOUNT_TRADE_MODE)AccountInfoInteger(ACCOUNT_TRADE_MODE) ==
         ACCOUNT_TRADE_MODE_DEMO ? "YES" : "NO",
      _Symbol,
      (bool)TerminalInfoInteger(TERMINAL_TRADE_ALLOWED) ? "YES" : "NO",
      (bool)MQLInfoInteger(MQL_TRADE_ALLOWED) ? "YES" : "NO",
      OrdersTotal(), PositionsTotal());
   if(!valid)
      return INIT_FAILED;

   V9StreamSet probe_a;
   V9StreamSet probe_b;
   V9StreamSet probe_c;
   V9StreamInit(probe_a, "A", "CONNECTED_COPYTICKS",
                D'2025.01.02 00:00:00', D'2025.12.24 00:00:00');
   V9StreamInit(probe_b, "B", "CONNECTED_COPYTICKS",
                D'2025.01.02 00:00:00', D'2025.12.25 00:00:00');
   V9StreamInit(probe_c, "C", "CONNECTED_COPYTICKS",
                D'2025.12.23 00:00:00', D'2025.12.25 00:00:00');

   const ulong start_msc =
      (ulong)D'2025.01.02 00:00:00' * 1000;
   const ulong end_msc =
      (ulong)D'2025.12.25 00:00:00' * 1000;
   ulong cursor = start_msc;
   ulong total = 0;
   long chunks = 0;
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
         "EURUSD", ticks, COPY_TICKS_ALL, cursor, request_end);
      const int error = GetLastError();
      if(copied < 0)
        {
         retrieval_failures++;
         PrintFormat(
            "SOLTRADE_PHASE6_V9_CONNECTED_CHUNK_FAIL | from=%s | to=%s | error=%d",
            V9Timestamp(cursor), V9Timestamp(request_end), error);
         break;
        }
      for(int index = 0; index < copied; index++)
        {
         const string record = V9TickRecord(ticks[index]);
         if(!V9StreamAdd(probe_a, ticks[index], record) ||
            !V9StreamAdd(probe_b, ticks[index], record) ||
            !V9StreamAdd(probe_c, ticks[index], record))
           {
            hashing_ok = false;
            break;
           }
         total++;
        }
      ArrayFree(ticks);
      chunks++;
      cursor = day_end < end_msc ? day_end : end_msc;
     }

   V9StreamPrint(probe_a);
   V9StreamPrint(probe_b);
   V9StreamPrint(probe_c);
   const bool passed =
      cursor == end_msc && hashing_ok && retrieval_failures == 0 &&
      probe_a.complete.count == 20682267 &&
      probe_a.complete.first_msc ==
         (ulong)D'2025.01.02 00:00:00' * 1000 + 594 &&
      probe_a.complete.last_msc ==
         (ulong)D'2025.12.23 23:59:59' * 1000 + 877;
   PrintFormat(
      "SOLTRADE_PHASE6_V9_CONNECTED_COMPLETE | status=%s | scanned_ticks=%I64u | daily_chunks=%I64d | retrieval_failures=%I64d | hashing_ok=%s | orders=%d | positions=%d | trade_transactions=%I64d | strategy_run=NO | profitability=NOT_CALCULATED | generated_ticks=NO",
      passed ? "PASS" : "FAIL", total, chunks,
      retrieval_failures, hashing_ok ? "YES" : "NO",
      OrdersTotal(), PositionsTotal(), g_trade_transactions);
   ExpertRemove();
   return passed ? INIT_SUCCEEDED : INIT_FAILED;
  }

void OnTick()
  {
  }

void OnTradeTransaction(const MqlTradeTransaction &transaction,
                        const MqlTradeRequest &request,
                        const MqlTradeResult &result)
  {
   g_trade_transactions++;
  }
