#property copyright "SolTrade Bot"
#property link      ""
#property version   "1.000"
#property strict
#property description "Deterministic Phase 3 Trend Breakout V1 tests"
#property description "Completed historical candles only; no trading APIs."

#include <SolTrade/StrategyBreakout.mqh>

int g_tests_passed = 0;
int g_tests_failed = 0;

void CheckTrue(const bool condition, const string test_name)
  {
   if(condition)
     {
      g_tests_passed++;
      Print("PASS: ", test_name);
     }
   else
     {
      g_tests_failed++;
      Print("FAIL: ", test_name);
     }
  }

void CheckNear(const double actual,
               const double expected,
               const double tolerance,
               const string test_name)
  {
   const bool passed =
      MathIsValidNumber(actual) &&
      MathAbs(actual - expected) <= tolerance;
   if(passed)
     {
      g_tests_passed++;
      PrintFormat("PASS: %s | actual=%.10f expected=%.10f",
                  test_name,
                  actual,
                  expected);
     }
   else
     {
      g_tests_failed++;
      PrintFormat("FAIL: %s | actual=%.10f expected=%.10f",
                  test_name,
                  actual,
                  expected);
     }
  }

void CheckText(const string actual,
               const string expected,
               const string test_name)
  {
   if(actual == expected)
     {
      g_tests_passed++;
      PrintFormat("PASS: %s | value=%s", test_name, actual);
     }
   else
     {
      g_tests_failed++;
      PrintFormat("FAIL: %s | actual=%s expected=%s",
                  test_name,
                  actual,
                  expected);
     }
  }

void SetHistoricalBar(MqlRates &bar,
                      const datetime bar_time,
                      const double open,
                      const double high,
                      const double low,
                      const double close)
  {
   bar.time        = bar_time;
   bar.open        = open;
   bar.high        = high;
   bar.low         = low;
   bar.close       = close;
   bar.tick_volume = 100;
   bar.spread      = 10;
   bar.real_volume = 100;
  }

void BuildFlatHistory(MqlRates &rates[],
                      const double close_price)
  {
   ArrayResize(rates, SOLTRADE_STRATEGY_HISTORY_BARS);
   ArraySetAsSeries(rates, false);

   const datetime first_time = D'2025.01.01 00:00:00';
   for(int index = 0;
       index < SOLTRADE_STRATEGY_HISTORY_BARS;
       index++)
     {
      SetHistoricalBar(rates[index],
                       first_time + (datetime)(index * 3600),
                       close_price,
                       close_price + 0.0005,
                       close_price - 0.0005,
                       close_price);
     }
  }

void RunFlatIndicatorFixture()
  {
   MqlRates rates[];
   BuildFlatHistory(rates, 1.1000);

   SolTradeStrategySignal signal;
   CheckTrue(SolTradeEvaluateCompletedBars(rates, signal),
             "FLAT-001 history evaluates");
   CheckTrue(signal.valid,
             "FLAT-001 result is valid");
   CheckText(SolTradeEntrySignalName(signal.entry_signal),
             "NONE",
             "FLAT-001 entry signal");
   CheckText(SolTradeExitSignalName(signal.exit_signal),
             "NONE",
             "FLAT-001 exit signal");
   CheckText(signal.entry_reason_code,
             "NO_ENTRY_BREAKOUT",
             "FLAT-001 entry reason code");
   CheckNear(signal.ema_200,
             1.1000,
             1e-10,
             "FLAT-001 EMA 200");
   CheckNear(signal.entry_channel_high,
             1.1005,
             1e-10,
             "FLAT-001 Donchian 20 high");
   CheckNear(signal.entry_channel_low,
             1.0995,
             1e-10,
             "FLAT-001 Donchian 20 low");
   CheckNear(signal.exit_channel_high,
             1.1005,
             1e-10,
             "FLAT-001 Donchian 10 high");
   CheckNear(signal.exit_channel_low,
             1.0995,
             1e-10,
             "FLAT-001 Donchian 10 low");
   CheckNear(signal.atr_14,
             0.0010,
             1e-10,
             "FLAT-001 ATR 14");
   CheckNear(signal.initial_stop_distance,
             0.0020,
             1e-10,
             "FLAT-001 two-ATR initial stop distance");
  }

void RunBuyFixture()
  {
   MqlRates rates[];
   BuildFlatHistory(rates, 1.1000);
   const int signal_index = ArraySize(rates) - 1;
   SetHistoricalBar(rates[signal_index],
                    rates[signal_index].time,
                    1.1002,
                    1.1012,
                    1.1001,
                    1.1010);

   SolTradeStrategySignal signal;
   CheckTrue(SolTradeEvaluateCompletedBars(rates, signal),
             "BUY-001 history evaluates");
   CheckText(SolTradeEntrySignalName(signal.entry_signal),
             "BUY",
             "BUY-001 entry signal");
   CheckText(signal.entry_reason_code,
             "BUY_BREAKOUT_ABOVE_EMA200",
             "BUY-001 structured reason");
   CheckTrue(signal.signal_close > signal.entry_channel_high,
             "BUY-001 close strictly exceeds preceding 20-bar high");
   CheckTrue(signal.signal_close > signal.ema_200,
             "BUY-001 close is above EMA 200");
   CheckNear(signal.ema_200,
             1.100009950249,
             1e-10,
             "BUY-001 EMA 200");
   CheckNear(signal.atr_14,
             0.001014285714,
             1e-10,
             "BUY-001 ATR 14");
   CheckNear(signal.entry_channel_high,
             1.1005,
             1e-10,
             "BUY-001 signal candle high excluded from entry channel");
   CheckText(SolTradeExitSignalName(signal.exit_signal),
             "EXIT_SHORT",
             "BUY-001 inverse 10-bar exit signal");

   const string details = SolTradeStrategyLogDetails(signal, 5);
   CheckTrue(
      StringFind(details,
                 "entry_reason_code=BUY_BREAKOUT_ABOVE_EMA200") >= 0,
      "BUY-001 structured log includes entry reason code");
  }

void RunSellFixture()
  {
   MqlRates rates[];
   BuildFlatHistory(rates, 1.1000);
   const int signal_index = ArraySize(rates) - 1;
   SetHistoricalBar(rates[signal_index],
                    rates[signal_index].time,
                    1.0998,
                    1.0999,
                    1.0988,
                    1.0990);

   SolTradeStrategySignal signal;
   CheckTrue(SolTradeEvaluateCompletedBars(rates, signal),
             "SELL-001 history evaluates");
   CheckText(SolTradeEntrySignalName(signal.entry_signal),
             "SELL",
             "SELL-001 entry signal");
   CheckText(signal.entry_reason_code,
             "SELL_BREAKOUT_BELOW_EMA200",
             "SELL-001 structured reason");
   CheckTrue(signal.signal_close < signal.entry_channel_low,
             "SELL-001 close strictly breaks preceding 20-bar low");
   CheckTrue(signal.signal_close < signal.ema_200,
             "SELL-001 close is below EMA 200");
   CheckNear(signal.ema_200,
             1.099990049751,
             1e-10,
             "SELL-001 EMA 200");
   CheckNear(signal.atr_14,
             0.001014285714,
             1e-10,
             "SELL-001 ATR 14");
   CheckNear(signal.entry_channel_low,
             1.0995,
             1e-10,
             "SELL-001 signal candle low excluded from entry channel");
   CheckText(SolTradeExitSignalName(signal.exit_signal),
             "EXIT_LONG",
             "SELL-001 inverse 10-bar exit signal");
  }

void RunStrictBoundaryFixtures()
  {
   MqlRates rates[];
   BuildFlatHistory(rates, 1.1000);
   int signal_index = ArraySize(rates) - 1;
   SetHistoricalBar(rates[signal_index],
                    rates[signal_index].time,
                    1.1001,
                    1.1007,
                    1.0999,
                    1.1005);

   SolTradeStrategySignal signal;
   CheckTrue(SolTradeEvaluateCompletedBars(rates, signal),
             "BOUNDARY-HIGH history evaluates");
   CheckText(SolTradeEntrySignalName(signal.entry_signal),
             "NONE",
             "BOUNDARY-HIGH entry channel equality is not a breakout");
   CheckText(SolTradeExitSignalName(signal.exit_signal),
             "NONE",
             "BOUNDARY-HIGH exit channel equality is not a breakout");

   BuildFlatHistory(rates, 1.1000);
   signal_index = ArraySize(rates) - 1;
   SetHistoricalBar(rates[signal_index],
                    rates[signal_index].time,
                    1.0999,
                    1.1001,
                    1.0993,
                    1.0995);
   CheckTrue(SolTradeEvaluateCompletedBars(rates, signal),
             "BOUNDARY-LOW history evaluates");
   CheckText(SolTradeEntrySignalName(signal.entry_signal),
             "NONE",
             "BOUNDARY-LOW entry channel equality is not a breakout");
   CheckText(SolTradeExitSignalName(signal.exit_signal),
             "NONE",
             "BOUNDARY-LOW exit channel equality is not a breakout");
  }

void RunTrendFilterFixtures()
  {
   MqlRates rates[];
   BuildFlatHistory(rates, 1.2000);
   for(int index = 200; index < 220; index++)
     {
      SetHistoricalBar(rates[index],
                       rates[index].time,
                       1.1000,
                       1.1005,
                       1.0995,
                       1.1000);
     }
   SetHistoricalBar(rates[220],
                    rates[220].time,
                    1.1002,
                    1.1012,
                    1.1001,
                    1.1010);

   SolTradeStrategySignal signal;
   CheckTrue(SolTradeEvaluateCompletedBars(rates, signal),
             "FILTER-BUY history evaluates");
   CheckText(SolTradeEntrySignalName(signal.entry_signal),
             "NONE",
             "FILTER-BUY returns no entry");
   CheckText(signal.entry_reason_code,
             "BUY_TREND_FILTER_FAILED",
             "FILTER-BUY reason identifies EMA filter");
   CheckTrue(signal.signal_close < signal.ema_200,
             "FILTER-BUY breakout remains below EMA 200");
   CheckNear(signal.ema_200,
             1.181068232992,
             1e-10,
             "FILTER-BUY EMA 200");

   BuildFlatHistory(rates, 1.0000);
   for(int index = 200; index < 220; index++)
     {
      SetHistoricalBar(rates[index],
                       rates[index].time,
                       1.1000,
                       1.1005,
                       1.0995,
                       1.1000);
     }
   SetHistoricalBar(rates[220],
                    rates[220].time,
                    1.0998,
                    1.0999,
                    1.0988,
                    1.0990);

   CheckTrue(SolTradeEvaluateCompletedBars(rates, signal),
             "FILTER-SELL history evaluates");
   CheckText(SolTradeEntrySignalName(signal.entry_signal),
             "NONE",
             "FILTER-SELL returns no entry");
   CheckText(signal.entry_reason_code,
             "SELL_TREND_FILTER_FAILED",
             "FILTER-SELL reason identifies EMA filter");
   CheckTrue(signal.signal_close > signal.ema_200,
             "FILTER-SELL breakout remains above EMA 200");
   CheckNear(signal.ema_200,
             1.018931767008,
             1e-10,
             "FILTER-SELL EMA 200");
  }

void RunExitOnlyFixtures()
  {
   MqlRates rates[];
   BuildFlatHistory(rates, 1.1000);
   SetHistoricalBar(rates[200],
                    rates[200].time,
                    1.1000,
                    1.1005,
                    1.0980,
                    1.1000);
   SetHistoricalBar(rates[220],
                    rates[220].time,
                    1.0998,
                    1.0999,
                    1.0988,
                    1.0990);

   SolTradeStrategySignal signal;
   CheckTrue(SolTradeEvaluateCompletedBars(rates, signal),
             "EXIT-LONG-001 history evaluates");
   CheckText(SolTradeEntrySignalName(signal.entry_signal),
             "NONE",
             "EXIT-LONG-001 has no 20-bar entry breakout");
   CheckText(SolTradeExitSignalName(signal.exit_signal),
             "EXIT_LONG",
             "EXIT-LONG-001 triggers 10-bar long exit");
   CheckText(signal.exit_reason_code,
             "LONG_EXIT_BREAKOUT",
             "EXIT-LONG-001 structured exit reason");

   BuildFlatHistory(rates, 1.1000);
   SetHistoricalBar(rates[200],
                    rates[200].time,
                    1.1000,
                    1.1020,
                    1.0995,
                    1.1000);
   SetHistoricalBar(rates[220],
                    rates[220].time,
                    1.1002,
                    1.1012,
                    1.1001,
                    1.1010);

   CheckTrue(SolTradeEvaluateCompletedBars(rates, signal),
             "EXIT-SHORT-001 history evaluates");
   CheckText(SolTradeEntrySignalName(signal.entry_signal),
             "NONE",
             "EXIT-SHORT-001 has no 20-bar entry breakout");
   CheckText(SolTradeExitSignalName(signal.exit_signal),
             "EXIT_SHORT",
             "EXIT-SHORT-001 triggers 10-bar short exit");
   CheckText(signal.exit_reason_code,
             "SHORT_EXIT_BREAKOUT",
             "EXIT-SHORT-001 structured exit reason");
  }

void RunInvalidHistoryFixtures()
  {
   MqlRates rates[];
   BuildFlatHistory(rates, 1.1000);
   ArrayResize(rates, SOLTRADE_STRATEGY_HISTORY_BARS - 1);

   SolTradeStrategySignal signal;
   CheckTrue(!SolTradeEvaluateCompletedBars(rates, signal),
             "INVALID-SHORT rejects insufficient completed history");
   CheckText(signal.entry_reason_code,
             "INVALID_HISTORY",
             "INVALID-SHORT structured reason");

   BuildFlatHistory(rates, 1.1000);
   rates[220].time = rates[219].time;
   CheckTrue(!SolTradeEvaluateCompletedBars(rates, signal),
             "INVALID-ORDER rejects non-chronological history");
   CheckText(signal.entry_reason_code,
             "INVALID_BAR_ORDER",
             "INVALID-ORDER structured reason");

   BuildFlatHistory(rates, 1.1000);
   rates[220].high = rates[220].low - 0.0001;
   CheckTrue(!SolTradeEvaluateCompletedBars(rates, signal),
             "INVALID-OHLC rejects malformed completed candle");
   CheckText(signal.entry_reason_code,
             "INVALID_CANDLE",
             "INVALID-OHLC structured reason");
  }

void OnStart()
  {
   Print("SolTrade Phase 3 deterministic historical signal tests started");

   RunFlatIndicatorFixture();
   RunBuyFixture();
   RunSellFixture();
   RunStrictBoundaryFixtures();
   RunTrendFilterFixtures();
   RunExitOnlyFixtures();
   RunInvalidHistoryFixtures();

   PrintFormat("SolTrade Strategy tests complete: %d passed, %d failed",
               g_tests_passed,
               g_tests_failed);

   if(g_tests_failed == 0)
      Print("ALL SOLTRADE PHASE 3 STRATEGY TESTS PASSED");
   else
      Print("SOLTRADE PHASE 3 STRATEGY TESTS FAILED");
  }
