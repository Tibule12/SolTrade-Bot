#property copyright "SolTrade Bot"
#property link      ""
#property version   "1.000"
#property strict
#property description "Phase 6 V14 Strategy Tester-only controlled practical backtest"
#property description "Uses unchanged Phase 1-5 modules with V13 segment-local boundaries."

#include <SolTrade/Config.mqh>
#include <SolTrade/AccountGuard.mqh>
#include <SolTrade/MarketData.mqh>
#include <SolTrade/RiskEngine.mqh>
#include <SolTrade/StrategyBreakout.mqh>
#include <SolTrade/ExecutionEngine.mqh>
#include <SolTrade/PositionManager.mqh>
#include <SolTradeResearch/V13ResearchHarness.mqh>

input datetime ResetAt = D'2025.01.02 00:00:00';
input datetime EligibleFrom = D'2025.01.16 00:00:00';
input datetime EligibleTo = D'2025.02.05 00:00:00';
input datetime ResearchCutoff = D'2025.12.24 00:00:00';
input string SegmentId = "D1";
input ENUM_SOLTRADE_BACKTEST_DATASET Dataset = SOLTRADE_DATASET_DEVELOPMENT;
input ENUM_SOLTRADE_COST_PROFILE CostProfile = SOLTRADE_COST_NORMAL;
input string ExecutionLayer = "NATIVE_NORMAL_EXECUTION";
input int ExpectedExecutionMode = 0;
input string ExecutionInstanceId = "V14-001-D1-NORMAL-NATIVE";
input string CoreTradingInputHash =
   "d6185b478920f6f6cbbb26ffc3d4758e34a6bf89129230b4db4b96ac5666c3c0";
input int ExpectedEvaluationCount = 335;
input datetime ExpectedFirstEvaluation = D'2025.01.16 00:00:00';
input string OutputRoot =
   "SolTrade\\Phase6\\V14\\V14-001-D1-NORMAL-NATIVE";

SolTradeConfig           g_config;
SolTradeAccountStatus    g_account;
SolTradeMarketSnapshot   g_market;
SolTradeRiskStatus       g_risk_status;
SolTradeExecutionStatus  g_execution_status;
SolTradePositionStatus   g_position_status;
CSolTradeRiskEngine      g_risk_engine;
CSolTradeExecutionEngine g_execution_engine;
CSolTradePositionManager g_position_manager;

MqlRates g_local_bars[];
datetime g_last_current_bar = 0;
datetime g_first_evaluation = 0;
datetime g_final_evaluation = 0;
int g_evaluations = 0;
int g_entry_signals = 0;
int g_exit_signals = 0;
int g_execution_evaluations = 0;
int g_execution_submissions = 0;
int g_execution_acceptances = 0;
int g_entry_fills = 0;
int g_close_evaluations = 0;
int g_close_submissions = 0;
int g_close_acceptances = 0;
int g_exit_fills = 0;
int g_risk_blocks = 0;
int g_spread_blocks = 0;
int g_loss_limit_pauses = 0;
int g_unexpected_post_cutoff_actions = 0;
int g_event_handle = INVALID_HANDLE;
int g_transaction_handle = INVALID_HANDLE;
bool g_preflight = false;
bool g_cutoff_frozen = false;
bool g_cutoff_position_open = false;
ulong g_cutoff_position_ticket = 0;
ulong g_cutoff_position_identifier = 0;
long g_cutoff_position_type = -1;
double g_cutoff_volume = 0.0;
double g_cutoff_entry_price = 0.0;
double g_cutoff_stop_loss = 0.0;
double g_cutoff_unrealized = 0.0;
datetime g_cutoff_observation = 0;

string V14Time(const datetime value)
  {
   if(value <= 0)
      return "NONE";
   return TimeToString(value, TIME_DATE | TIME_SECONDS);
  }

void V14Event(const string event_type,
              const string reason_code,
              const string details)
  {
   if(g_event_handle == INVALID_HANDLE)
      return;
   FileWrite(g_event_handle,
             "SOLTRADE_PHASE6_V14_EVENT_V1",
             V14Time(TimeCurrent()),
             SegmentId,
             SolTradeBacktestDatasetName(Dataset),
             SolTradeCostProfileName(CostProfile),
             ExecutionLayer,
             event_type,
             reason_code,
             details);
  }

bool V14OpenEvents()
  {
   g_event_handle =
      FileOpen(OutputRoot + "\\events.csv",
               FILE_WRITE | FILE_CSV | FILE_ANSI | FILE_COMMON,
               ',');
   if(g_event_handle == INVALID_HANDLE)
      return false;
   FileWrite(g_event_handle,
             "schema", "time", "segment_id", "dataset", "cost_profile",
             "execution_layer", "event_type", "reason_code", "details");
   return true;
  }

bool V14OpenTransactions()
  {
   g_transaction_handle =
      FileOpen(OutputRoot + "\\transactions.csv",
               FILE_WRITE | FILE_CSV | FILE_ANSI | FILE_COMMON,
               ',');
   if(g_transaction_handle == INVALID_HANDLE)
      return false;
   FileWrite(g_transaction_handle,
             "schema", "time", "segment_id", "record_type",
             "signal_bar_time", "position_identifier", "direction",
             "requested_price", "actual_price", "spread_points",
             "slippage_points", "volume", "initial_risk_amount",
             "stop_loss", "order_ticket", "deal_ticket",
             "broker_retcode", "exit_reason", "fill_confirmed");
   return true;
  }

void V14RecordEntry(const string record_type,
                    const SolTradeExecutionReport &report)
  {
   if(g_transaction_handle == INVALID_HANDLE)
      return;
   ulong position_identifier = 0;
   if(report.deal_ticket != 0)
      position_identifier =
         (ulong)HistoryDealGetInteger(report.deal_ticket, DEAL_POSITION_ID);
   FileWrite(g_transaction_handle,
             "SOLTRADE_PHASE6_V14_TRANSACTION_V1", V14Time(TimeCurrent()),
             SegmentId, record_type, V14Time(report.signal_bar_time),
             StringFormat("%I64u", position_identifier),
             report.signal_result,
             DoubleToString(report.requested_entry, 10),
             DoubleToString(report.actual_entry, 10),
             IntegerToString(report.spread_points),
             DoubleToString(report.slippage_points, 4),
             DoubleToString(report.volume, 8),
             DoubleToString(report.risk_amount, 8),
             DoubleToString(report.stop_loss, 10),
             StringFormat("%I64u", report.order_ticket),
             StringFormat("%I64u", report.deal_ticket),
             IntegerToString((int)report.broker_return_code), "NONE",
             report.fill_confirmed ? "YES" : "NO");
  }

void V14RecordExit(const string record_type,
                   const SolTradePositionReport &report)
  {
   if(g_transaction_handle == INVALID_HANDLE)
      return;
   FileWrite(g_transaction_handle,
             "SOLTRADE_PHASE6_V14_TRANSACTION_V1", V14Time(TimeCurrent()),
             SegmentId, record_type, V14Time(report.signal_bar_time),
             StringFormat("%I64u", report.position_identifier),
             report.position_direction,
             DoubleToString(report.requested_close_price, 10),
             DoubleToString(report.actual_close_price, 10), "0",
             DoubleToString(report.slippage_points, 4),
             DoubleToString(report.volume, 8), "0.00000000", "0.0000000000",
             StringFormat("%I64u", report.order_ticket),
             StringFormat("%I64u", report.deal_ticket),
             IntegerToString((int)report.broker_return_code),
             report.exit_reason_code,
             report.fill_confirmed ? "YES" : "NO");
  }

void V14LoadConfig()
  {
   g_config.strategy_version = "1.0.0";
   g_config.approved_strategy_version = "";
   g_config.risk_profile = "CONSERVATIVE_V1";
   g_config.approved_risk_profile = "";
   g_config.magic_number = SOLTRADE_V13_MAGIC_NUMBER;
   g_config.symbol = "EURUSD";
   g_config.timeframe = PERIOD_H1;
   g_config.minimum_history_bars = 222;
   g_config.max_tick_age_seconds = 120;
   g_config.max_spread_points = 30;
   g_config.max_spread_atr_percent = 10.0;
   g_config.max_slippage_points = 10;
   g_config.risk_per_trade_percent = 0.25;
   g_config.daily_loss_limit_percent = 1.0;
   g_config.weekly_loss_limit_percent = 2.5;
   g_config.emergency_drawdown_percent = 5.0;
   g_config.production_baseline_equity = 0.0;
   g_config.consecutive_loss_limit = 3;
   g_config.reset_emergency_lock = false;
   g_config.expected_environment = SOLTRADE_ENV_BACKTEST;
   g_config.enable_demo_execution = false;
   g_config.enable_position_management = false;
   g_config.approved_demo_account = 0;
   g_config.allow_live_trading = false;
   g_config.approved_live_account = 0;
   g_config.emergency_stop = false;
   g_config.enable_backtest_research = true;
   g_config.enable_backtest_execution = true;
   g_config.enable_backtest_position_management = true;
   g_config.research_manifest_id = "PHASE6-V14-CONTROLLED-PRACTICAL";
   g_config.execution_instance_id = ExecutionInstanceId;
   g_config.research_dataset = Dataset;
   g_config.research_cost_profile = CostProfile;
   g_config.research_start_inclusive = EligibleFrom;
   g_config.research_end_exclusive = EligibleTo;
   g_config.research_history_fingerprint =
      "d87ac46834047ce52f6a824fe1441278bc4276144294d87afe541cb9b47646b5";
   g_config.research_latency_fingerprint =
      "e301e77895e8f095d485b00bd1b5da9f10f07d6c8b6ae9162048a7643ddf4dfe";
   g_config.research_latency_sample_count = 30;
   g_config.research_frozen_delay_ms = 200;
   g_config.research_source_commit =
      "e0522c607eb59641662a7be9922fd8bd2ba4784c";
   g_config.research_build_fingerprint = CoreTradingInputHash;
   g_config.research_expected_terminal_build = 6090;
   g_config.research_expected_broker_server = "FPMarketsSC-Demo";
   g_config.research_expected_initial_deposit = 10000.0;
   g_config.research_expected_deposit_currency = "USD";
   g_config.research_expected_leverage = 30;
   g_config.research_expected_trading_input_hash = CoreTradingInputHash;
   g_config.research_state_root =
      "SolTradeBot\\phase6-v14-state\\" + ExecutionInstanceId;
   g_config.research_artifact_root =
      "SolTradeBot\\phase6-v14-artifacts\\" + ExecutionInstanceId;
   g_config.enable_csv_journal = true;
   g_config.journal_directory =
      "SolTradeBot\\phase6-v14-journal\\" + ExecutionInstanceId;
   g_config.risk_state_directory =
      "SolTradeBot\\phase6-v14-state\\" + ExecutionInstanceId;
   g_config.execution_state_directory =
      "SolTradeBot\\phase6-v14-state\\" + ExecutionInstanceId;
   g_config.enable_dashboard = false;
   g_config.dashboard_refresh_seconds = 1;
  }

bool V14FrozenPreflight(string &reason)
  {
   reason = "";
   if(!MQLInfoInteger(MQL_TESTER) || MQLInfoInteger(MQL_OPTIMIZATION))
     {
      reason = "Tester-only and optimization prohibited";
      return false;
     }
   if(_Symbol != "EURUSD" || _Period != PERIOD_H1 ||
      AccountInfoString(ACCOUNT_SERVER) != "FPMarketsSC-Demo" ||
      (int)TerminalInfoInteger(TERMINAL_BUILD) != 6090 ||
      AccountInfoString(ACCOUNT_CURRENCY) != "USD" ||
      (int)AccountInfoInteger(ACCOUNT_LEVERAGE) != 30 ||
      MathAbs(AccountInfoDouble(ACCOUNT_BALANCE) - 10000.0) > 0.01)
     {
      reason = "Frozen tester environment differs";
      return false;
     }
   if(CoreTradingInputHash !=
         "d6185b478920f6f6cbbb26ffc3d4758e34a6bf89129230b4db4b96ac5666c3c0" ||
      !SolTradeV13ValidBoundaries(ResetAt, EligibleFrom,
                                  EligibleTo, ResearchCutoff) ||
      StringLen(SegmentId) == 0 ||
      !SolTradeSafeIdentifier(ExecutionInstanceId) ||
      ExpectedEvaluationCount <= 0 ||
      ExpectedFirstEvaluation < EligibleFrom ||
      ExpectedFirstEvaluation >= EligibleTo)
     {
      reason = "Frozen V13 identity or boundaries differ";
      return false;
     }
   if((ExpectedExecutionMode == 0 &&
       ExecutionLayer != "NATIVE_NORMAL_EXECUTION") ||
      (ExpectedExecutionMode == 200 &&
       ExecutionLayer != "FIXED_DELAY_200_MS") ||
      (ExpectedExecutionMode != 0 && ExpectedExecutionMode != 200))
     {
      reason = "Execution layer or mode differs from V13";
      return false;
     }
   if(MathAbs(SymbolInfoDouble(_Symbol, SYMBOL_SWAP_LONG) - (-9.71)) > 1e-8 ||
      MathAbs(SymbolInfoDouble(_Symbol, SYMBOL_SWAP_SHORT) - 4.50) > 1e-8 ||
      (int)SymbolInfoInteger(_Symbol, SYMBOL_SWAP_MODE) != 1 ||
      (int)SymbolInfoInteger(_Symbol, SYMBOL_SWAP_ROLLOVER3DAYS) != 3)
     {
      reason = "Frozen current swap assumption differs";
      return false;
     }
   if(FileIsExist(OutputRoot + "\\run-summary.csv", FILE_COMMON))
     {
      reason = "Execution instance output collision";
      return false;
     }
   return ValidateSolTradeConfig(g_config, reason);
  }

void V14AppendLocalBar(const MqlRates &bar)
  {
   const int size = ArraySize(g_local_bars);
   ArrayResize(g_local_bars, size + 1, 512);
   g_local_bars[size] = bar;
  }

void V14RefreshFoundation()
  {
   EvaluateSolTradeAccountSafety(g_config, g_account);
   RefreshSolTradeMarketData(g_config, g_market);
   string reason = "";
   g_risk_engine.Refresh(TimeCurrent(),
                         AccountInfoDouble(ACCOUNT_EQUITY), reason);
   g_risk_engine.GetStatus(g_risk_status);
   g_execution_engine.RefreshExposure();
   g_execution_engine.GetStatus(g_execution_status);
   g_position_manager.Refresh(reason);
   g_position_manager.GetStatus(g_position_status);

   if(g_position_status.position_present &&
      g_risk_status.emergency_locked)
     {
      SolTradeStrategySignal empty_signal;
      ResetSolTradeStrategySignal(empty_signal);
      SolTradePositionReport emergency;
      g_position_manager.ProcessClose(empty_signal,
                                      SOLTRADE_CLOSE_EMERGENCY_DRAWDOWN,
                                      g_account, g_market, emergency);
      if(emergency.evaluated)
        {
         g_close_evaluations++;
         if(emergency.order_send_performed) g_close_submissions++;
         if(emergency.broker_accepted) g_close_acceptances++;
         V14Event(emergency.event_type, emergency.reason_code,
                  emergency.reason);
         V14RecordExit("EXIT_ATTEMPT", emergency);
        }
     }
  }

void V14EvaluateStrategy(const datetime evaluation_time)
  {
   const int total = ArraySize(g_local_bars);
   if(total < SOLTRADE_STRATEGY_HISTORY_BARS)
      return;
   const MqlRates current = g_local_bars[total - 1];
   if(!SolTradeV13BarIsEligible(current.time, EligibleFrom,
                                EligibleTo, ResearchCutoff))
      return;

   SolTradeStrategySignal signal;
   if(!SolTradeEvaluateCompletedBars(g_local_bars, signal) ||
      !signal.valid || signal.signal_bar_time != current.time)
     {
      V14Event("SIGNAL_INVALID", "CALCULATION_FAILED",
               signal.calculation_error);
      return;
     }

   if(g_first_evaluation == 0)
      g_first_evaluation = current.time;
   g_final_evaluation = current.time;
   g_evaluations++;
   if(signal.entry_signal != SOLTRADE_SIGNAL_NONE) g_entry_signals++;
   if(signal.exit_signal != SOLTRADE_EXIT_NONE) g_exit_signals++;

   V14Event("SIGNAL_EVALUATED", signal.entry_reason_code,
            SolTradeStrategyLogDetails(signal, g_market.digits));

   if(g_position_status.position_present &&
      !g_risk_status.emergency_locked)
     {
      SolTradePositionReport close_report;
      g_position_manager.ProcessClose(signal, SOLTRADE_CLOSE_STRATEGY,
                                      g_account, g_market, close_report);
      if(close_report.evaluated)
        {
         g_close_evaluations++;
         if(close_report.order_send_performed) g_close_submissions++;
         if(close_report.broker_accepted) g_close_acceptances++;
         V14Event(close_report.event_type, close_report.reason_code,
                  close_report.exit_reason_code + ";" + close_report.reason);
         V14RecordExit("EXIT_ATTEMPT", close_report);
        }
      g_position_manager.GetStatus(g_position_status);
     }

   if(signal.entry_signal == SOLTRADE_SIGNAL_BUY ||
      signal.entry_signal == SOLTRADE_SIGNAL_SELL)
     {
      SolTradeExecutionReport report;
      g_execution_engine.ProcessSignal(signal, g_account, g_market,
                                       g_risk_status, false, report);
      if(report.evaluated)
        {
         g_execution_evaluations++;
         if(report.broker_submission_attempted) g_execution_submissions++;
         if(report.broker_accepted) g_execution_acceptances++;
         // In Strategy Tester, the transaction callback may fire inside
         // OrderSend before ExecutionEngine installs its pending-match state.
         // The synchronous accepted result still contains the authoritative
         // deal ticket and therefore counts as the single confirmed entry.
         if(report.broker_accepted && report.deal_ticket != 0) g_entry_fills++;
         if(report.reason_code == "EXCESSIVE_SPREAD" ||
            report.reason_code == "SPREAD_EXCEEDS_LIMIT")
            g_spread_blocks++;
         if(report.reason_code == "RISK_LOCKED") g_risk_blocks++;
         V14Event(report.event_type, report.reason_code, report.reason);
         V14RecordEntry("ENTRY_ATTEMPT", report);
        }
      g_execution_engine.GetStatus(g_execution_status);
     }
  }

void V14ProcessNewBar(const datetime now)
  {
   const datetime current_bar = iTime(_Symbol, PERIOD_H1, 0);
   if(current_bar <= 0 || current_bar == g_last_current_bar)
      return;
   g_last_current_bar = current_bar;
   MqlRates completed[1];
   if(CopyRates(_Symbol, PERIOD_H1, 1, 1, completed) != 1)
      return;
   if(!SolTradeV13BarIsLocal(completed[0].time, ResetAt, EligibleTo))
      return;
   V14AppendLocalBar(completed[0]);
   V14EvaluateStrategy(now);
  }

void V14FreezeCutoff(const datetime observation)
  {
   if(g_cutoff_frozen)
      return;
   g_cutoff_observation = observation;
   for(int index = 0; index < PositionsTotal(); index++)
     {
      const ulong ticket = PositionGetTicket(index);
      if(ticket == 0 ||
         (ulong)PositionGetInteger(POSITION_MAGIC) !=
            SOLTRADE_V13_MAGIC_NUMBER ||
         PositionGetString(POSITION_SYMBOL) != "EURUSD")
         continue;
      g_cutoff_position_open = true;
      g_cutoff_position_ticket = ticket;
      g_cutoff_position_identifier =
         (ulong)PositionGetInteger(POSITION_IDENTIFIER);
      g_cutoff_position_type = PositionGetInteger(POSITION_TYPE);
      g_cutoff_volume = PositionGetDouble(POSITION_VOLUME);
      g_cutoff_entry_price = PositionGetDouble(POSITION_PRICE_OPEN);
      g_cutoff_stop_loss = PositionGetDouble(POSITION_SL);
      g_cutoff_unrealized = PositionGetDouble(POSITION_PROFIT) +
                            PositionGetDouble(POSITION_SWAP);
      break;
     }
   g_cutoff_frozen = true;
   V14Event("CUTOFF_FROZEN",
            g_cutoff_position_open
               ? "RIGHT_CENSORED_OPEN_POSITION"
               : "NO_OPEN_POSITION_AT_CUTOFF",
            "eligible_to=" + V14Time(EligibleTo));
  }

bool V14WriteCutoff()
  {
   const int handle =
      FileOpen(OutputRoot + "\\cutoff.csv",
               FILE_WRITE | FILE_CSV | FILE_ANSI | FILE_COMMON, ',');
   if(handle == INVALID_HANDLE) return false;
   FileWrite(handle, "field", "value");
   FileWrite(handle, "classification",
             g_cutoff_position_open
                ? "RIGHT_CENSORED_OPEN_POSITION"
                : "NO_OPEN_POSITION_AT_CUTOFF");
   FileWrite(handle, "eligible_to", V14Time(EligibleTo));
   FileWrite(handle, "observation_time", V14Time(g_cutoff_observation));
   FileWrite(handle, "position_open", g_cutoff_position_open ? "YES" : "NO");
   FileWrite(handle, "position_ticket",
             StringFormat("%I64u", g_cutoff_position_ticket));
   FileWrite(handle, "position_identifier",
             StringFormat("%I64u", g_cutoff_position_identifier));
   FileWrite(handle, "position_type", IntegerToString(g_cutoff_position_type));
   FileWrite(handle, "volume", DoubleToString(g_cutoff_volume, 8));
   FileWrite(handle, "entry_price", DoubleToString(g_cutoff_entry_price, 10));
   FileWrite(handle, "stop_loss", DoubleToString(g_cutoff_stop_loss, 10));
   FileWrite(handle, "unrealized_result_reporting_only",
             DoubleToString(g_cutoff_unrealized, 8));
   FileWrite(handle, "formal_pnl_included", "NO");
   FileWrite(handle, "naturally_closed_trade_included", "NO");
   FileWrite(handle, "later_deals", "POST_CUTOFF_EXCLUDED");
   FileClose(handle);
   return true;
  }

bool V14WriteDeals()
  {
   if(!HistorySelect(ResetAt, TimeCurrent())) return false;
   const int handle =
      FileOpen(OutputRoot + "\\deals.csv",
               FILE_WRITE | FILE_CSV | FILE_ANSI | FILE_COMMON, ',');
   if(handle == INVALID_HANDLE) return false;
   FileWrite(handle, "deal_ticket", "order_ticket", "position_identifier",
             "time", "time_msc", "entry", "type", "reason", "volume",
             "price", "profit", "commission", "swap", "fee", "magic",
             "symbol", "comment", "in_research_window");
   for(int index = 0; index < HistoryDealsTotal(); index++)
     {
      const ulong deal = HistoryDealGetTicket(index);
      if(deal == 0 ||
         (ulong)HistoryDealGetInteger(deal, DEAL_MAGIC) !=
            SOLTRADE_V13_MAGIC_NUMBER ||
         HistoryDealGetString(deal, DEAL_SYMBOL) != "EURUSD")
         continue;
      const datetime time =
         (datetime)HistoryDealGetInteger(deal, DEAL_TIME);
      FileWrite(handle,
                StringFormat("%I64u", deal),
                StringFormat("%I64u", (ulong)HistoryDealGetInteger(deal, DEAL_ORDER)),
                StringFormat("%I64u", (ulong)HistoryDealGetInteger(deal, DEAL_POSITION_ID)),
                V14Time(time),
                StringFormat("%I64d", HistoryDealGetInteger(deal, DEAL_TIME_MSC)),
                IntegerToString((int)HistoryDealGetInteger(deal, DEAL_ENTRY)),
                IntegerToString((int)HistoryDealGetInteger(deal, DEAL_TYPE)),
                IntegerToString((int)HistoryDealGetInteger(deal, DEAL_REASON)),
                DoubleToString(HistoryDealGetDouble(deal, DEAL_VOLUME), 8),
                DoubleToString(HistoryDealGetDouble(deal, DEAL_PRICE), 10),
                DoubleToString(HistoryDealGetDouble(deal, DEAL_PROFIT), 8),
                DoubleToString(HistoryDealGetDouble(deal, DEAL_COMMISSION), 8),
                DoubleToString(HistoryDealGetDouble(deal, DEAL_SWAP), 8),
                DoubleToString(HistoryDealGetDouble(deal, DEAL_FEE), 8),
                StringFormat("%I64d", HistoryDealGetInteger(deal, DEAL_MAGIC)),
                HistoryDealGetString(deal, DEAL_SYMBOL),
                HistoryDealGetString(deal, DEAL_COMMENT),
                (time >= EligibleFrom && time < EligibleTo) ? "YES" : "NO");
     }
   FileClose(handle);
   return true;
  }

bool V14WriteSummary()
  {
   const int handle =
      FileOpen(OutputRoot + "\\run-summary.csv",
               FILE_WRITE | FILE_CSV | FILE_ANSI | FILE_COMMON, ',');
   if(handle == INVALID_HANDLE) return false;
   FileWrite(handle, "field", "value");
   FileWrite(handle, "schema", "SOLTRADE_PHASE6_V14_RUN_SUMMARY_V1");
   FileWrite(handle, "core_trading_input_hash", CoreTradingInputHash);
   FileWrite(handle, "execution_instance_id", ExecutionInstanceId);
   FileWrite(handle, "segment_id", SegmentId);
   FileWrite(handle, "dataset", SolTradeBacktestDatasetName(Dataset));
   FileWrite(handle, "cost_profile", SolTradeCostProfileName(CostProfile));
   FileWrite(handle, "execution_layer", ExecutionLayer);
   FileWrite(handle, "expected_execution_mode",
             IntegerToString(ExpectedExecutionMode));
   FileWrite(handle, "reset_at", V14Time(ResetAt));
   FileWrite(handle, "eligible_from", V14Time(EligibleFrom));
   FileWrite(handle, "eligible_to", V14Time(EligibleTo));
   FileWrite(handle, "first_evaluation", V14Time(g_first_evaluation));
   FileWrite(handle, "final_evaluation", V14Time(g_final_evaluation));
   FileWrite(handle, "evaluations", IntegerToString(g_evaluations));
   FileWrite(handle, "entry_signals", IntegerToString(g_entry_signals));
   FileWrite(handle, "exit_signals", IntegerToString(g_exit_signals));
   FileWrite(handle, "execution_evaluations",
             IntegerToString(g_execution_evaluations));
   FileWrite(handle, "execution_submissions",
             IntegerToString(g_execution_submissions));
   FileWrite(handle, "execution_acceptances",
             IntegerToString(g_execution_acceptances));
   FileWrite(handle, "entry_fills", IntegerToString(g_entry_fills));
   FileWrite(handle, "close_evaluations", IntegerToString(g_close_evaluations));
   FileWrite(handle, "close_submissions", IntegerToString(g_close_submissions));
   FileWrite(handle, "close_acceptances", IntegerToString(g_close_acceptances));
   FileWrite(handle, "exit_fills", IntegerToString(g_exit_fills));
   FileWrite(handle, "risk_blocks", IntegerToString(g_risk_blocks));
   FileWrite(handle, "spread_blocks", IntegerToString(g_spread_blocks));
   FileWrite(handle, "loss_limit_pauses", IntegerToString(g_loss_limit_pauses));
   FileWrite(handle, "cutoff_frozen", g_cutoff_frozen ? "YES" : "NO");
   FileWrite(handle, "censored_position",
             g_cutoff_position_open ? "YES" : "NO");
   FileWrite(handle, "post_cutoff_actions",
             IntegerToString(g_unexpected_post_cutoff_actions));
   FileWrite(handle, "tester_profit",
             DoubleToString(TesterStatistics(STAT_PROFIT), 8));
   FileWrite(handle, "tester_trades",
             DoubleToString(TesterStatistics(STAT_TRADES), 0));
   FileWrite(handle, "tester_profit_factor",
             DoubleToString(TesterStatistics(STAT_PROFIT_FACTOR), 8));
   FileWrite(handle, "tester_expected_payoff",
             DoubleToString(TesterStatistics(STAT_EXPECTED_PAYOFF), 8));
   FileWrite(handle, "tester_equity_dd_percent",
             DoubleToString(TesterStatistics(STAT_EQUITY_DDREL_PERCENT), 8));
   FileWrite(handle, "tester_balance_dd_percent",
             DoubleToString(TesterStatistics(STAT_BALANCE_DDREL_PERCENT), 8));
   FileWrite(handle, "terminal_build",
             IntegerToString((int)TerminalInfoInteger(TERMINAL_BUILD)));
   FileWrite(handle, "broker_server", AccountInfoString(ACCOUNT_SERVER));
   FileWrite(handle, "symbol", _Symbol);
   FileWrite(handle, "swap_mode",
             IntegerToString((int)SymbolInfoInteger(_Symbol, SYMBOL_SWAP_MODE)));
   FileWrite(handle, "swap_long",
             DoubleToString(SymbolInfoDouble(_Symbol, SYMBOL_SWAP_LONG), 8));
   FileWrite(handle, "swap_short",
             DoubleToString(SymbolInfoDouble(_Symbol, SYMBOL_SWAP_SHORT), 8));
   FileWrite(handle, "swap_rollover_3days",
             IntegerToString((int)SymbolInfoInteger(_Symbol,
                                                    SYMBOL_SWAP_ROLLOVER3DAYS)));
   const bool valid = g_preflight && g_cutoff_frozen &&
      g_evaluations == ExpectedEvaluationCount &&
      g_first_evaluation == ExpectedFirstEvaluation &&
      g_unexpected_post_cutoff_actions == 0;
   FileWrite(handle, "run_evidence_status", valid ? "PASS" : "FAIL");
   FileClose(handle);
   return valid;
  }

int OnInit()
  {
   ArrayResize(g_local_bars, 0);
   ResetSolTradeMarketSnapshot(g_market);
   ResetSolTradeRiskStatus(g_risk_status);
   ResetSolTradeExecutionStatus(g_execution_status);
   ResetSolTradePositionStatus(g_position_status);
   V14LoadConfig();
   string reason = "";
   if(!V14FrozenPreflight(reason))
     {
      Print("SOLTRADE_V14_PREFLIGHT_FAILED | reason=", reason);
      return INIT_PARAMETERS_INCORRECT;
     }
   if(!V14OpenEvents() || !V14OpenTransactions()) return INIT_FAILED;
   EvaluateSolTradeAccountSafety(g_config, g_account);
   if(!InitialiseSolTradeMarketData(g_config, g_last_current_bar, reason) ||
      !g_risk_engine.Initialise(g_config, g_account.account_identifier_hash,
                                TimeCurrent(),
                                AccountInfoDouble(ACCOUNT_EQUITY), reason) ||
      !g_execution_engine.Initialise(g_config,
                                     g_account.account_identifier_hash,
                                     reason) ||
      !g_position_manager.Initialise(g_config,
                                     g_account.account_identifier_hash,
                                     reason))
     {
      Print("SOLTRADE_V14_ENGINE_INIT_FAILED | reason=", reason);
      V14Event("ENGINE_INIT_FAILED", "INITIALISATION_FAILED", reason);
      return INIT_FAILED;
     }
   g_risk_engine.GetStatus(g_risk_status);
   g_execution_engine.GetStatus(g_execution_status);
   g_position_manager.GetStatus(g_position_status);
   g_last_current_bar = iTime(_Symbol, PERIOD_H1, 0);
   g_preflight = true;
   V14Event("PREFLIGHT_PASSED", "NONE",
            "orders=TESTER_ONLY;live=PROHIBITED;optimization=PROHIBITED");
   Print("SOLTRADE_V14_PREFLIGHT_PASSED | instance=", ExecutionInstanceId,
         " | segment=", SegmentId, " | layer=", ExecutionLayer,
         " | cost=", SolTradeCostProfileName(CostProfile));
   return INIT_SUCCEEDED;
  }

void OnTick()
  {
   const datetime now = TimeCurrent();
   if(now >= EligibleTo)
     {
      V14FreezeCutoff(now);
      return;
     }
   V14RefreshFoundation();
   V14ProcessNewBar(now);
  }

void OnTradeTransaction(const MqlTradeTransaction &transaction,
                        const MqlTradeRequest &request,
                        const MqlTradeResult &result)
  {
   if(TimeCurrent() >= EligibleTo)
     {
      V14Event("POST_CUTOFF_TRANSACTION", "POST_CUTOFF_EXCLUDED",
               IntegerToString((int)transaction.type));
      return;
     }
   SolTradeExecutionReport entry;
   if(g_execution_engine.HandleTradeTransaction(transaction, entry))
     {
      V14Event(entry.event_type, entry.reason_code,
               "order=" + StringFormat("%I64u", entry.order_ticket) +
               ";deal=" + StringFormat("%I64u", entry.deal_ticket));
      V14RecordEntry("ENTRY_TRANSACTION", entry);
     }
   SolTradePositionReport exit_report;
   if(g_position_manager.HandleTradeTransaction(transaction, exit_report))
     {
      if(exit_report.fill_confirmed) g_exit_fills++;
      V14Event(exit_report.event_type, exit_report.reason_code,
               "order=" + StringFormat("%I64u", exit_report.order_ticket) +
               ";deal=" + StringFormat("%I64u", exit_report.deal_ticket) +
               ";exit_reason=" + exit_report.exit_reason_code);
      V14RecordExit("EXIT_TRANSACTION", exit_report);
      string outcome_reason = "";
      g_risk_engine.RecordClosedOutcome(
         "V14_EXIT_" + StringFormat("%I64u", exit_report.deal_ticket),
         exit_report.final_profit_loss, TimeCurrent(),
         AccountInfoDouble(ACCOUNT_EQUITY), outcome_reason);
      g_risk_engine.GetStatus(g_risk_status);
     }
  }

double OnTester()
  {
   if(!g_cutoff_frozen) V14FreezeCutoff(EligibleTo);
   const bool files_ok = V14WriteCutoff() && V14WriteDeals();
   const bool valid = files_ok && V14WriteSummary();
   if(g_event_handle != INVALID_HANDLE) FileFlush(g_event_handle);
   if(g_transaction_handle != INVALID_HANDLE) FileFlush(g_transaction_handle);
   Print("SOLTRADE_V14_RUN_RESULT | status=", valid ? "PASS" : "FAIL",
         " | instance=", ExecutionInstanceId,
         " | evaluations=", g_evaluations,
         " | entries=", g_entry_fills,
         " | exits=", g_exit_fills,
         " | censored=", g_cutoff_position_open ? "YES" : "NO",
         " | post_cutoff_actions=", g_unexpected_post_cutoff_actions);
   return valid ? 1.0 : 0.0;
  }

void OnDeinit(const int reason)
  {
   if(g_event_handle != INVALID_HANDLE)
     {
      FileClose(g_event_handle);
      g_event_handle = INVALID_HANDLE;
     }
   if(g_transaction_handle != INVALID_HANDLE)
     {
      FileClose(g_transaction_handle);
      g_transaction_handle = INVALID_HANDLE;
     }
  }
