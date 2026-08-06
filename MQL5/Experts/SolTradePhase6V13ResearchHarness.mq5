#property copyright "SolTrade Bot"
#property link      ""
#property version   "1.000"
#property strict
#property description "Phase 6 V13 tester-only segment-local signal harness"
#property description "No orders, P/L calculations, optimization, demo, or live trading."

#include <SolTrade/StrategyBreakout.mqh>
#include <SolTradeResearch/V13ResearchHarness.mqh>

input datetime ResetAt = D'2025.01.02 00:00:00';
input datetime EligibleFrom = D'2025.01.16 00:00:00';
input datetime EligibleTo = D'2025.02.05 00:00:00';
input datetime ResearchCutoff = D'2025.12.24 00:00:00';
input string SegmentId = "S1";
input datetime ExpectedFirstEvaluation = D'2025.01.16 00:00:00';
input int ExpectedEvaluationCount = 335;
input string SignalOutputFile =
   "SolTrade\\Phase6\\V13\\signals-s1.csv";
input string CutoffOutputFile =
   "SolTrade\\Phase6\\V13\\cutoff-s1.csv";
input string MetadataOutputFile =
   "SolTrade\\Phase6\\V13\\metadata-s1.csv";
input bool PermitOrders = false;
input bool CalculateProfitability = false;

MqlRates g_local_bars[];
datetime g_last_current_bar = 0;
int g_signal_handle = INVALID_HANDLE;
int g_evaluation_count = 0;
int g_entry_decision_count = 0;
int g_exit_decision_count = 0;
int g_state_event_count = 0;
long g_trade_transaction_count = 0;
datetime g_first_evaluation = 0;
datetime g_final_evaluation = 0;
bool g_preflight_passed = false;
bool g_cutoff_frozen = false;
bool g_post_cutoff_action = false;
bool g_pre_reset_contamination = false;
ENUM_SOLTRADE_V13_SIGNAL_STATE g_strategy_state =
   SOLTRADE_V13_STATE_FLAT;
SolTradeV13CutoffSnapshot g_latest_pre_cutoff_snapshot;
SolTradeV13CutoffSnapshot g_frozen_cutoff_snapshot;

string V13Timestamp(const datetime value)
  {
   if(value <= 0)
      return "NONE";
   return TimeToString(value, TIME_DATE | TIME_SECONDS);
  }

bool V13WriteMetadata()
  {
   const int handle =
      FileOpen(MetadataOutputFile,
               FILE_WRITE | FILE_CSV | FILE_ANSI | FILE_COMMON,
               ',');
   if(handle == INVALID_HANDLE)
      return false;

   FileWrite(handle, "field", "value");
   FileWrite(handle, "schema", SOLTRADE_V13_HARNESS_SCHEMA);
   FileWrite(handle, "segment_id", SegmentId);
   FileWrite(handle, "broker_server", AccountInfoString(ACCOUNT_SERVER));
   FileWrite(handle, "symbol", _Symbol);
   FileWrite(handle, "timeframe", EnumToString((ENUM_TIMEFRAMES)_Period));
   FileWrite(handle, "terminal_build",
             IntegerToString((int)TerminalInfoInteger(TERMINAL_BUILD)));
   FileWrite(handle, "reset_at", V13Timestamp(ResetAt));
   FileWrite(handle, "eligible_from", V13Timestamp(EligibleFrom));
   FileWrite(handle, "eligible_to", V13Timestamp(EligibleTo));
   FileWrite(handle, "research_cutoff", V13Timestamp(ResearchCutoff));
   FileWrite(handle, "permit_orders", PermitOrders ? "YES" : "NO");
   FileWrite(handle, "profitability", CalculateProfitability ? "YES" : "NO");
   FileWrite(handle, "swap_mode",
             IntegerToString((int)SymbolInfoInteger(_Symbol,
                                                    SYMBOL_SWAP_MODE)));
   FileWrite(handle, "swap_long",
             DoubleToString(SymbolInfoDouble(_Symbol, SYMBOL_SWAP_LONG), 10));
   FileWrite(handle, "swap_short",
             DoubleToString(SymbolInfoDouble(_Symbol, SYMBOL_SWAP_SHORT), 10));
   FileWrite(handle, "swap_rollover_3days",
             IntegerToString((int)SymbolInfoInteger(
                _Symbol, SYMBOL_SWAP_ROLLOVER3DAYS)));
   FileWrite(handle, "trade_transactions", "0");
   FileClose(handle);
   return true;
  }

bool V13OpenSignalOutput()
  {
   g_signal_handle =
      FileOpen(SignalOutputFile,
               FILE_WRITE | FILE_CSV | FILE_ANSI | FILE_COMMON,
               ',');
   if(g_signal_handle == INVALID_HANDLE)
      return false;

   FileWrite(g_signal_handle,
             "schema",
             "segment_id",
             "local_bar_count",
             "signal_bar_time",
             "evaluation_time",
             "entry_signal",
             "exit_signal",
             "state_before",
             "state_after",
             "state_event",
             "open",
             "high",
             "low",
             "close",
             "ema_200",
             "atr_14",
             "entry_high",
             "entry_low",
             "exit_high",
             "exit_low",
             "initial_stop_distance",
             "entry_reason_code",
             "exit_reason_code");
   return true;
  }

void V13ObservePreCutoffSnapshot(const datetime observation_time)
  {
   if(observation_time >= EligibleTo)
      return;

   ResetSolTradeV13CutoffSnapshot(g_latest_pre_cutoff_snapshot);
   g_latest_pre_cutoff_snapshot.observation_time = observation_time;
   g_latest_pre_cutoff_snapshot.strategy_state = g_strategy_state;
   if(PositionSelect(_Symbol) &&
      PositionGetInteger(POSITION_MAGIC) == (long)SOLTRADE_V13_MAGIC_NUMBER)
     {
      g_latest_pre_cutoff_snapshot.position_open = true;
      g_latest_pre_cutoff_snapshot.position_ticket =
         (ulong)PositionGetInteger(POSITION_TICKET);
      g_latest_pre_cutoff_snapshot.position_type =
         PositionGetInteger(POSITION_TYPE);
      g_latest_pre_cutoff_snapshot.volume =
         PositionGetDouble(POSITION_VOLUME);
      g_latest_pre_cutoff_snapshot.entry_price =
         PositionGetDouble(POSITION_PRICE_OPEN);
      g_latest_pre_cutoff_snapshot.stop_loss =
         PositionGetDouble(POSITION_SL);
      g_latest_pre_cutoff_snapshot.unrealized_result =
         PositionGetDouble(POSITION_PROFIT) +
         PositionGetDouble(POSITION_SWAP);
     }
  }

bool V13FreezeCutoff(const datetime captured_at)
  {
   if(g_cutoff_frozen)
      return true;

   g_frozen_cutoff_snapshot = g_latest_pre_cutoff_snapshot;
   g_frozen_cutoff_snapshot.captured = true;
   g_frozen_cutoff_snapshot.cutoff_time = EligibleTo;

   const int handle =
      FileOpen(CutoffOutputFile,
               FILE_WRITE | FILE_CSV | FILE_ANSI | FILE_COMMON,
               ',');
   if(handle == INVALID_HANDLE)
      return false;

   FileWrite(handle, "field", "value");
   FileWrite(handle, "schema", SOLTRADE_V13_HARNESS_SCHEMA);
   FileWrite(handle, "segment_id", SegmentId);
   FileWrite(handle, "eligible_to", V13Timestamp(EligibleTo));
   FileWrite(handle, "captured_at", V13Timestamp(captured_at));
   FileWrite(handle, "last_pre_cutoff_observation",
             V13Timestamp(g_frozen_cutoff_snapshot.observation_time));
   FileWrite(handle, "classification",
             SolTradeV13CutoffClassification(
                g_frozen_cutoff_snapshot.position_open));
   FileWrite(handle, "position_open",
             g_frozen_cutoff_snapshot.position_open ? "YES" : "NO");
   FileWrite(handle, "position_ticket",
             StringFormat("%I64u",
                          g_frozen_cutoff_snapshot.position_ticket));
   FileWrite(handle, "position_type",
             IntegerToString((int)g_frozen_cutoff_snapshot.position_type));
   FileWrite(handle, "volume",
             DoubleToString(g_frozen_cutoff_snapshot.volume, 8));
   FileWrite(handle, "entry_price",
             DoubleToString(g_frozen_cutoff_snapshot.entry_price, 10));
   FileWrite(handle, "stop_loss",
             DoubleToString(g_frozen_cutoff_snapshot.stop_loss, 10));
   FileWrite(handle, "unrealized_result_reporting_only",
             DoubleToString(
                g_frozen_cutoff_snapshot.unrealized_result, 8));
   FileWrite(handle, "strategy_state",
             SolTradeV13SignalStateName(
                g_frozen_cutoff_snapshot.strategy_state));
   FileWrite(handle, "later_deal_classification",
             "POST_CUTOFF_EXCLUDED");
   FileClose(handle);
   g_cutoff_frozen = true;
   Print("SOLTRADE_V13_CUTOFF_FROZEN | segment=", SegmentId,
         " | eligible_to=", V13Timestamp(EligibleTo),
         " | captured_at=", V13Timestamp(captured_at),
         " | classification=",
         SolTradeV13CutoffClassification(
            g_frozen_cutoff_snapshot.position_open));
   return true;
  }

void V13AppendLocalBar(const MqlRates &bar)
  {
   const int size = ArraySize(g_local_bars);
   ArrayResize(g_local_bars, size + 1, 512);
   g_local_bars[size] = bar;
   if(bar.time < ResetAt)
      g_pre_reset_contamination = true;
  }

void V13EvaluateLocalHistory(const datetime evaluation_time)
  {
   const int total = ArraySize(g_local_bars);
   if(total < SOLTRADE_STRATEGY_HISTORY_BARS)
      return;

   const MqlRates current = g_local_bars[total - 1];
   if(!SolTradeV13BarIsEligible(current.time,
                                EligibleFrom,
                                EligibleTo,
                                ResearchCutoff))
      return;

   SolTradeStrategySignal signal;
   if(!SolTradeEvaluateCompletedBars(g_local_bars, signal) ||
      !signal.valid ||
      signal.signal_bar_time != current.time)
     {
      Print("SOLTRADE_V13_SIGNAL_INVALID | segment=", SegmentId,
            " | bar=", V13Timestamp(current.time),
            " | reason=", signal.calculation_error);
      g_post_cutoff_action = true;
      return;
     }

   if(g_first_evaluation == 0)
      g_first_evaluation = current.time;
   g_final_evaluation = current.time;
   g_evaluation_count++;
   if(signal.entry_signal != SOLTRADE_SIGNAL_NONE)
      g_entry_decision_count++;
   if(signal.exit_signal != SOLTRADE_EXIT_NONE)
      g_exit_decision_count++;

   const ENUM_SOLTRADE_V13_SIGNAL_STATE state_before = g_strategy_state;
   string state_event = "NONE";
   if(g_strategy_state == SOLTRADE_V13_STATE_FLAT &&
      signal.entry_signal == SOLTRADE_SIGNAL_BUY)
     {
      g_strategy_state = SOLTRADE_V13_STATE_LONG;
      state_event = "BUY";
     }
   else if(g_strategy_state == SOLTRADE_V13_STATE_FLAT &&
           signal.entry_signal == SOLTRADE_SIGNAL_SELL)
     {
      g_strategy_state = SOLTRADE_V13_STATE_SHORT;
      state_event = "SELL";
     }
   else if(g_strategy_state == SOLTRADE_V13_STATE_LONG &&
           signal.exit_signal == SOLTRADE_EXIT_LONG)
     {
      g_strategy_state = SOLTRADE_V13_STATE_FLAT;
      state_event = "EXIT_LONG";
     }
   else if(g_strategy_state == SOLTRADE_V13_STATE_SHORT &&
           signal.exit_signal == SOLTRADE_EXIT_SHORT)
     {
      g_strategy_state = SOLTRADE_V13_STATE_FLAT;
      state_event = "EXIT_SHORT";
     }
   if(state_event != "NONE")
      g_state_event_count++;

   FileWrite(g_signal_handle,
             SOLTRADE_V13_HARNESS_SCHEMA,
             SegmentId,
             IntegerToString(total),
             V13Timestamp(signal.signal_bar_time),
             V13Timestamp(evaluation_time),
             SolTradeEntrySignalName(signal.entry_signal),
             SolTradeExitSignalName(signal.exit_signal),
             SolTradeV13SignalStateName(state_before),
             SolTradeV13SignalStateName(g_strategy_state),
             state_event,
             DoubleToString(signal.signal_open, 10),
             DoubleToString(signal.signal_high, 10),
             DoubleToString(signal.signal_low, 10),
             DoubleToString(signal.signal_close, 10),
             DoubleToString(signal.ema_200, 15),
             DoubleToString(signal.atr_14, 15),
             DoubleToString(signal.entry_channel_high, 10),
             DoubleToString(signal.entry_channel_low, 10),
             DoubleToString(signal.exit_channel_high, 10),
             DoubleToString(signal.exit_channel_low, 10),
             DoubleToString(signal.initial_stop_distance, 15),
             signal.entry_reason_code,
             signal.exit_reason_code);
  }

void V13ProcessNewCompletedBar(const datetime now)
  {
   const datetime current_bar = iTime(_Symbol, PERIOD_H1, 0);
   if(current_bar <= 0 || current_bar == g_last_current_bar)
      return;
   g_last_current_bar = current_bar;

   MqlRates completed[1];
   const int copied = CopyRates(_Symbol, PERIOD_H1, 1, 1, completed);
   if(copied != 1)
      return;
   if(!SolTradeV13BarIsLocal(completed[0].time,
                             ResetAt,
                             EligibleTo))
      return;

   V13AppendLocalBar(completed[0]);
   V13EvaluateLocalHistory(now);
  }

int OnInit()
  {
   ResetSolTradeV13CutoffSnapshot(g_latest_pre_cutoff_snapshot);
   ResetSolTradeV13CutoffSnapshot(g_frozen_cutoff_snapshot);
   ArrayResize(g_local_bars, 0);

   if(!MQLInfoInteger(MQL_TESTER) ||
      MQLInfoInteger(MQL_OPTIMIZATION) ||
      _Symbol != "EURUSD" ||
      _Period != PERIOD_H1 ||
      AccountInfoString(ACCOUNT_SERVER) != "FPMarketsSC-Demo" ||
      !SolTradeV13ValidBoundaries(ResetAt,
                                  EligibleFrom,
                                  EligibleTo,
                                  ResearchCutoff) ||
      StringLen(SegmentId) == 0 ||
      ExpectedFirstEvaluation < EligibleFrom ||
      ExpectedFirstEvaluation >= EligibleTo ||
      ExpectedEvaluationCount <= 0 ||
      PermitOrders ||
      CalculateProfitability)
     {
      Print("SOLTRADE_V13_PREFLIGHT_FAILED");
      return INIT_PARAMETERS_INCORRECT;
     }

   if(!V13OpenSignalOutput() || !V13WriteMetadata())
     {
      Print("SOLTRADE_V13_OUTPUT_FAILED | error=", GetLastError());
      return INIT_FAILED;
     }

   g_last_current_bar = iTime(_Symbol, PERIOD_H1, 0);
   g_preflight_passed = true;
   Print("SOLTRADE_V13_PREFLIGHT_PASSED | segment=", SegmentId,
         " | reset_at=", V13Timestamp(ResetAt),
         " | eligible_from=", V13Timestamp(EligibleFrom),
         " | eligible_to=", V13Timestamp(EligibleTo),
         " | orders=PROHIBITED | profitability=PROHIBITED");
   return INIT_SUCCEEDED;
  }

void OnTick()
  {
   const datetime now = TimeCurrent();
   if(now >= EligibleTo)
     {
      V13FreezeCutoff(now);
      return;
     }

   V13ProcessNewCompletedBar(now);
   V13ObservePreCutoffSnapshot(now);
  }

void OnTradeTransaction(const MqlTradeTransaction &transaction,
                        const MqlTradeRequest &request,
                        const MqlTradeResult &result)
  {
   g_trade_transaction_count++;
   Print("SOLTRADE_V13_UNEXPECTED_TRADE_TRANSACTION | type=",
         EnumToString(transaction.type));
  }

double OnTester()
  {
   if(!g_cutoff_frozen)
      V13FreezeCutoff(EligibleTo);
   if(g_signal_handle != INVALID_HANDLE)
      FileFlush(g_signal_handle);

   const bool passed =
      g_preflight_passed &&
      g_cutoff_frozen &&
      !g_pre_reset_contamination &&
      !g_post_cutoff_action &&
      g_trade_transaction_count == 0 &&
      OrdersTotal() == 0 &&
      PositionsTotal() == 0 &&
      g_first_evaluation == ExpectedFirstEvaluation &&
      g_evaluation_count == ExpectedEvaluationCount;

   Print("SOLTRADE_V13_SIGNAL_ONLY_RESULT | status=",
         passed ? "PASS" : "FAIL",
         " | segment=", SegmentId,
         " | local_bars=", ArraySize(g_local_bars),
         " | evaluations=", g_evaluation_count,
         " | entries=", g_entry_decision_count,
         " | exits=", g_exit_decision_count,
         " | state_events=", g_state_event_count,
         " | first_evaluation=", V13Timestamp(g_first_evaluation),
         " | final_evaluation=", V13Timestamp(g_final_evaluation),
         " | pre_reset_contamination=",
         g_pre_reset_contamination ? "YES" : "NO",
         " | post_cutoff_action=", g_post_cutoff_action ? "YES" : "NO",
         " | trade_transactions=", g_trade_transaction_count,
         " | orders=", OrdersTotal(),
         " | positions=", PositionsTotal(),
         " | pnl=NOT_CALCULATED");
   return passed ? 1.0 : 0.0;
  }

void OnDeinit(const int reason)
  {
   if(g_signal_handle != INVALID_HANDLE)
     {
      FileClose(g_signal_handle);
      g_signal_handle = INVALID_HANDLE;
     }
  }
