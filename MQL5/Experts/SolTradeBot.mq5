#property copyright "SolTrade Bot"
#property link      ""
#property version   "1.000"
#property strict
#property description "SolTrade Bot Phase 6 default-disabled research build"
#property description "Approved Phase 1-5 logic; tester-only reports; live trading impossible."

#include <SolTrade/Config.mqh>
#include <SolTrade/AccountGuard.mqh>
#include <SolTrade/MarketData.mqh>
#include <SolTrade/RiskEngine.mqh>
#include <SolTrade/StrategyBreakout.mqh>
#include <SolTrade/ExecutionEngine.mqh>
#include <SolTrade/PositionManager.mqh>
#include <SolTrade/TradeJournal.mqh>
#include <SolTrade/Dashboard.mqh>
#include <SolTrade/BacktestResearch.mqh>

input group "Identity"
input string StrategyVersion         = "1.0.0";
input string ApprovedStrategyVersion = "";
input string RiskProfile             = "CONSERVATIVE_V1";
input string ApprovedRiskProfile     = "";
input ulong  MagicNumber             = 2607202601;

input group "Market"
input string          TradeSymbol            = "EURUSD";
input ENUM_TIMEFRAMES SignalTimeframe         = PERIOD_H1;
input int             MinimumHistoryBars      = 222;
input int             MaxTickAgeSeconds       = 120;
input int             MaxSpreadPoints         = 30;
input double          MaxSpreadAtrPercent     = 10.0;
input int             MaxSlippagePoints       = 10;

input group "Risk Policy"
input double RiskPerTradePercent       = 0.25;
input double DailyLossLimitPercent     = 1.0;
input double WeeklyLossLimitPercent    = 2.5;
input double EmergencyDrawdownPercent  = 5.0;
input double ProductionBaselineEquity  = 0.0;
input int    ConsecutiveLossLimit       = 3;
input bool   ResetEmergencyLock         = false;

input group "Environment Safety"
input ENUM_SOLTRADE_ENVIRONMENT ExpectedEnvironment = SOLTRADE_ENV_AUTO_DETECT;
input bool EnableDemoExecution = false;
input bool EnablePositionManagement = false;
input long ApprovedDemoAccount = 0;
input bool AllowLiveTrading    = false;
input long ApprovedLiveAccount = 0;
input bool EmergencyStop        = false;

input group "Phase 6 Tester Research - Default Off"
input bool EnableBacktestResearch           = false;
input bool EnableBacktestExecution          = false;
input bool EnableBacktestPositionManagement = false;
input string ResearchManifestId             = "";
input string ExecutionInstanceId            = "";
input ENUM_SOLTRADE_BACKTEST_DATASET ResearchDataset =
   SOLTRADE_DATASET_NONE;
input ENUM_SOLTRADE_COST_PROFILE ResearchCostProfile =
   SOLTRADE_COST_NONE;
input datetime ResearchStartInclusive       = 0;
input datetime ResearchEndExclusive         = 0;
input string ResearchHistoryFingerprint     = "";
input string ResearchLatencyFingerprint     = "";
input int ResearchLatencySampleCount        = 0;
input int ResearchFrozenDelayMs             = 0;
input string ResearchSourceCommit           = "";
input string ResearchBuildFingerprint       = "";
input int ResearchExpectedTerminalBuild     = 0;
input string ResearchExpectedBrokerServer   = "";
input double ResearchExpectedInitialDeposit = 0.0;
input string ResearchExpectedDepositCurrency = "";
input int ResearchExpectedLeverage          = 0;
input string ResearchExpectedTradingInputHash = "";
input string ResearchStateRoot =
   "SolTradeBot\\phase6-state";
input string ResearchArtifactRoot =
   "SolTradeBot\\phase6-artifacts";

input group "Operations"
input bool   EnableCsvJournal       = true;
input string JournalDirectory       = "SolTradeBot\\logs";
input string RiskStateDirectory     = "SolTradeBot\\state";
input string ExecutionStateDirectory = "SolTradeBot\\state";
input bool   EnableDashboard        = true;
input int    DashboardRefreshSeconds = 1;

SolTradeConfig          g_config;
SolTradeAccountStatus   g_account;
SolTradeMarketSnapshot  g_market;
SolTradeRiskStatus      g_risk_status;
SolTradeStrategySignal  g_strategy_signal;
SolTradeExecutionStatus g_execution_status;
SolTradeExecutionReport g_last_execution;
SolTradePositionStatus  g_position_status;
SolTradePositionReport  g_last_position_action;
CSolTradeRiskEngine     g_risk_engine;
CSolTradeExecutionEngine g_execution_engine;
CSolTradePositionManager g_position_manager;
CSolTradeJournal        g_journal;
CSolTradeBacktestReporter g_backtest_reporter;
SolTradeResearchRuntimeStatus g_backtest_status;
datetime                g_last_seen_current_bar = 0;
string                  g_last_market_reason    = "";
long                    g_last_risk_revision    = 0;
string                  g_last_risk_error       = "";
string                  g_last_position_state_event = "";
string                  g_last_position_report_key  = "";

void LoadSolTradeConfig()
  {
   g_config.strategy_version             = StrategyVersion;
   g_config.approved_strategy_version    = ApprovedStrategyVersion;
   g_config.risk_profile                 = RiskProfile;
   g_config.approved_risk_profile        = ApprovedRiskProfile;
   g_config.magic_number                 = MagicNumber;

   g_config.symbol                       = TradeSymbol;
   g_config.timeframe                    = SignalTimeframe;
   g_config.minimum_history_bars         = MinimumHistoryBars;
   g_config.max_tick_age_seconds         = MaxTickAgeSeconds;
   g_config.max_spread_points            = MaxSpreadPoints;
   g_config.max_spread_atr_percent       = MaxSpreadAtrPercent;
   g_config.max_slippage_points          = MaxSlippagePoints;

   g_config.risk_per_trade_percent       = RiskPerTradePercent;
   g_config.daily_loss_limit_percent     = DailyLossLimitPercent;
   g_config.weekly_loss_limit_percent    = WeeklyLossLimitPercent;
   g_config.emergency_drawdown_percent   = EmergencyDrawdownPercent;
   g_config.production_baseline_equity   = ProductionBaselineEquity;
   g_config.consecutive_loss_limit       = ConsecutiveLossLimit;
   g_config.reset_emergency_lock         = ResetEmergencyLock;

   g_config.expected_environment         = ExpectedEnvironment;
   g_config.enable_demo_execution        = EnableDemoExecution;
   g_config.enable_position_management   = EnablePositionManagement;
   g_config.approved_demo_account        = ApprovedDemoAccount;
   g_config.allow_live_trading           = AllowLiveTrading;
   g_config.approved_live_account        = ApprovedLiveAccount;
   g_config.emergency_stop               = EmergencyStop;

   g_config.enable_backtest_research =
      EnableBacktestResearch;
   g_config.enable_backtest_execution =
      EnableBacktestExecution;
   g_config.enable_backtest_position_management =
      EnableBacktestPositionManagement;
   g_config.research_manifest_id = ResearchManifestId;
   g_config.execution_instance_id = ExecutionInstanceId;
   g_config.research_dataset = ResearchDataset;
   g_config.research_cost_profile = ResearchCostProfile;
   g_config.research_start_inclusive = ResearchStartInclusive;
   g_config.research_end_exclusive = ResearchEndExclusive;
   g_config.research_history_fingerprint =
      ResearchHistoryFingerprint;
   g_config.research_latency_fingerprint =
      ResearchLatencyFingerprint;
   g_config.research_latency_sample_count =
      ResearchLatencySampleCount;
   g_config.research_frozen_delay_ms = ResearchFrozenDelayMs;
   g_config.research_source_commit = ResearchSourceCommit;
   g_config.research_build_fingerprint =
      ResearchBuildFingerprint;
   g_config.research_expected_terminal_build =
      ResearchExpectedTerminalBuild;
   g_config.research_expected_broker_server =
      ResearchExpectedBrokerServer;
   g_config.research_expected_initial_deposit =
      ResearchExpectedInitialDeposit;
   g_config.research_expected_deposit_currency =
      ResearchExpectedDepositCurrency;
   g_config.research_expected_leverage =
      ResearchExpectedLeverage;
   g_config.research_expected_trading_input_hash =
      ResearchExpectedTradingInputHash;
   g_config.research_state_root = ResearchStateRoot;
   g_config.research_artifact_root = ResearchArtifactRoot;

   g_config.enable_csv_journal           = EnableCsvJournal;
   g_config.journal_directory            = JournalDirectory;
   g_config.risk_state_directory         = RiskStateDirectory;
   g_config.execution_state_directory    = ExecutionStateDirectory;
   g_config.enable_dashboard             = EnableDashboard;
   g_config.dashboard_refresh_seconds    = DashboardRefreshSeconds;
  }

datetime SolTradeServerTime()
  {
   datetime server_time = TimeTradeServer();
   if(server_time <= 0)
      server_time = TimeCurrent();
   return server_time;
  }

string SolTradeDeinitReason(const int reason)
  {
   switch(reason)
     {
      case REASON_PROGRAM:     return "Program requested removal";
      case REASON_REMOVE:      return "EA removed from chart";
      case REASON_RECOMPILE:   return "EA recompiled";
      case REASON_CHARTCHANGE: return "Chart symbol or timeframe changed";
      case REASON_CHARTCLOSE:  return "Chart closed";
      case REASON_PARAMETERS:  return "Inputs changed";
      case REASON_ACCOUNT:     return "Account changed";
      case REASON_TEMPLATE:    return "Chart template changed";
      case REASON_INITFAILED:  return "Initialisation failed";
      case REASON_CLOSE:       return "Terminal closed";
      default:                 return "Unknown deinitialisation reason";
     }
  }

string CurrentSolTradeStatus()
  {
   if(g_config.emergency_stop)
      return "EMERGENCY STOPPED";

   if(!g_account.expected_environment_matches)
      return "ENVIRONMENT LOCKED";

   if(g_account.detected_environment == SOLTRADE_ENV_UNKNOWN)
      return "ACCOUNT MODE INVALID";

   if(!g_account.execution_environment_eligible)
      return g_account.safety_state;

   if(!g_execution_status.state_valid)
      return "EXECUTION STATE LOCKED";

   if(!g_position_status.state_valid)
      return "POSITION STATE LOCKED";

   if(!g_risk_status.state_valid)
      return "RISK LOCKED";

   if(g_risk_status.emergency_locked)
      return "EMERGENCY STOPPED";

   if(g_risk_status.daily_locked ||
      g_risk_status.weekly_locked ||
      g_risk_status.consecutive_locked)
      return "RISK LOCKED";

   if(!g_market.valid)
      return "MARKET DATA INVALID";

   if(!g_account.terminal_autotrading_allowed ||
      !g_account.program_trading_allowed ||
      !g_account.account_trading_allowed ||
      !g_account.account_expert_allowed)
      return "TRADING PERMISSION DISABLED";

   if(g_execution_status.unprotected_soltrade_position)
      return "UNPROTECTED SOLTRADE POSITION ALERT";

   if(g_execution_status.open_soltrade_positions > 0 ||
      g_execution_status.active_soltrade_orders > 0)
     {
      if(!SolTradeBacktestManagementEnabled(
            g_config,
            g_account.detected_environment))
         return "SOLTRADE POSITION MONITORED - MANAGEMENT DISABLED";
      if(g_position_status.close_attempt_claimed)
         return "POSITION CLOSE ATTEMPT CONSUMED - NO RETRY";
      return "SOLTRADE POSITION MANAGEMENT ACTIVE";
     }

   if(g_account.detected_environment == SOLTRADE_ENV_BACKTEST)
      return g_config.enable_backtest_research
         ? "PHASE 6 TESTER RESEARCH ACTIVE"
         : "PHASE 6 TESTER RESEARCH DISABLED";

   return g_config.enable_position_management
      ? "APPROVED DEMO POSITION MANAGEMENT READY - PHASE 5"
      : "POSITION MANAGEMENT DISABLED - PHASE 5";
  }

void RecordPositionReport(const SolTradePositionReport &report)
  {
   if(!report.evaluated)
      return;

   const string report_key =
      report.event_type + "|" +
      report.reason_code + "|" +
      StringFormat("%I64u", report.position_identifier) + "|" +
      IntegerToString(report.signal_bar_time) + "|" +
      IntegerToString((long)report.broker_return_code) + "|" +
      StringFormat("%I64u", report.deal_ticket);
   if(report_key == g_last_position_report_key)
      return;

   g_last_position_action = report;
   g_journal.LogPositionManagement(report, g_market);
   g_last_position_report_key = report_key;
  }

void RefreshSolTradeFoundation()
  {
   EvaluateSolTradeAccountSafety(g_config, g_account);
   RefreshSolTradeMarketData(g_config, g_market);
   g_backtest_reporter.ObserveTick(g_market);

   string risk_reason = "";
   const bool risk_valid =
      g_risk_engine.Refresh(SolTradeServerTime(),
                            AccountInfoDouble(ACCOUNT_EQUITY),
                            risk_reason);
   g_risk_engine.GetStatus(g_risk_status);
   g_journal.UpdateRiskStatus(g_risk_status);
   g_execution_engine.RefreshExposure();
   g_execution_engine.GetStatus(g_execution_status);

   string position_reason = "";
   const bool position_valid =
      g_position_manager.Refresh(position_reason);
   g_position_manager.GetStatus(g_position_status);
   if(!position_valid)
     {
      if(g_position_status.last_event !=
         g_last_position_state_event)
        {
         g_journal.LogEvent("POSITION_STATE_INVALID",
                            "NONE",
                            position_reason,
                            g_position_status.last_event,
                            g_market);
         g_last_position_state_event =
            g_position_status.last_event;
        }
     }
   else if(g_position_status.last_event !=
           g_last_position_state_event)
     {
      g_journal.LogEvent(
         g_position_status.stop_attached ||
         !g_position_status.position_present
            ? "POSITION_STATE_CHANGED"
            : "POSITION_STOP_LOSS_MISSING",
         g_position_status.position_present
            ? SolTradePositionDirectionName(
                 g_position_status.position_type)
            : "NONE",
         g_position_status.stop_attached ||
         !g_position_status.position_present
            ? ""
            : "SolTrade position has no attached stop-loss",
         g_position_status.last_event,
         g_market);
      g_last_position_state_event =
         g_position_status.last_event;
     }

   if(!risk_valid && risk_reason != g_last_risk_error)
     {
      g_journal.LogEvent("RISK_EVALUATION_FAILED",
                         "NONE",
                         risk_reason,
                         "Risk engine failed closed",
                         g_market);
      g_last_risk_error = risk_reason;
     }
   else if(risk_valid && StringLen(g_last_risk_error) > 0)
     {
      g_journal.LogEvent("RISK_EVALUATION_RECOVERED",
                         "NONE",
                         "",
                         "Risk evaluation recovered after: " +
                            g_last_risk_error,
                         g_market);
      g_last_risk_error = "";
     }

   if(g_risk_engine.Revision() != g_last_risk_revision)
     {
      const string risk_rejection =
         (g_risk_status.daily_locked ||
          g_risk_status.weekly_locked ||
          g_risk_status.emergency_locked ||
          g_risk_status.consecutive_locked)
         ? g_risk_status.lock_reason
         : "";
      g_journal.LogEvent("RISK_STATE_CHANGED",
                         "NONE",
                         risk_rejection,
                         g_risk_status.last_event,
                         g_market);
      g_last_risk_revision = g_risk_engine.Revision();
     }

   if(g_position_status.position_present &&
      (g_risk_status.emergency_locked ||
       g_config.emergency_stop))
     {
      SolTradeStrategySignal emergency_signal;
      ResetSolTradeStrategySignal(emergency_signal);
      SolTradePositionReport emergency_report;
      g_position_manager.ProcessClose(
         emergency_signal,
         g_config.emergency_stop
            ? SOLTRADE_CLOSE_EMERGENCY_STOP
            : SOLTRADE_CLOSE_EMERGENCY_DRAWDOWN,
         g_account,
         g_market,
         emergency_report);
      g_position_manager.GetStatus(g_position_status);
      RecordPositionReport(emergency_report);
     }

   const string current_market_reason = g_market.reason;
   if(current_market_reason != g_last_market_reason)
     {
      const string event_type =
         g_market.valid ? "MARKET_DATA_RECOVERED" : "MARKET_DATA_INVALID";
      const string rejection =
         g_market.valid ? "" : current_market_reason;
      g_journal.LogEvent(event_type,
                         "NONE",
                         rejection,
                         current_market_reason,
                         g_market);
      g_last_market_reason = current_market_reason;
     }

   datetime completed_bar_time = 0;
   if(DetectSolTradeNewBar(g_market,
                           g_last_seen_current_bar,
                           completed_bar_time))
     {
      const bool strategy_valid =
         SolTradeEvaluateCurrentCompletedHistory(g_config,
                                                 g_strategy_signal);
      if(strategy_valid &&
         g_strategy_signal.signal_bar_time != completed_bar_time)
        {
         ResetSolTradeStrategySignal(g_strategy_signal);
         g_strategy_signal.evaluated = true;
         g_strategy_signal.entry_reason_code = "SIGNAL_BAR_MISMATCH";
         g_strategy_signal.exit_reason_code  = "SIGNAL_BAR_MISMATCH";
         g_strategy_signal.calculation_error =
            "Copied strategy signal bar does not match detected completed bar";
         g_strategy_signal.entry_reason =
            g_strategy_signal.calculation_error;
         g_strategy_signal.exit_reason =
            g_strategy_signal.calculation_error;
        }

      if(g_strategy_signal.valid)
        {
         const string entry_name =
            SolTradeEntrySignalName(g_strategy_signal.entry_signal);
         const string rejection =
            (g_strategy_signal.entry_signal == SOLTRADE_SIGNAL_NONE)
            ? g_strategy_signal.entry_reason_code + ": " +
               g_strategy_signal.entry_reason
            : "";
         g_journal.LogEvent(
            "STRATEGY_SIGNAL_EVALUATED",
            entry_name,
            rejection,
            SolTradeStrategyLogDetails(g_strategy_signal,
                                       g_market.digits),
            g_market);

         if(g_position_status.position_present &&
            !g_risk_status.emergency_locked &&
            !g_config.emergency_stop)
           {
            SolTradePositionReport close_report;
            g_position_manager.ProcessClose(
               g_strategy_signal,
               SOLTRADE_CLOSE_STRATEGY,
               g_account,
               g_market,
               close_report);
            g_position_manager.GetStatus(g_position_status);
            RecordPositionReport(close_report);
           }

         if(g_strategy_signal.entry_signal == SOLTRADE_SIGNAL_BUY ||
            g_strategy_signal.entry_signal == SOLTRADE_SIGNAL_SELL)
           {
            g_execution_engine.ProcessSignal(g_strategy_signal,
                                             g_account,
                                             g_market,
                                             g_risk_status,
                                             false,
                                             g_last_execution);
            g_execution_engine.GetStatus(g_execution_status);
            g_journal.LogExecution(g_last_execution, g_market);
           }
        }
      else
        {
         g_journal.LogEvent(
            "STRATEGY_SIGNAL_INVALID",
            "NONE",
            g_strategy_signal.entry_reason_code + ": " +
               g_strategy_signal.entry_reason,
            SolTradeStrategyLogDetails(g_strategy_signal,
                                       g_market.digits),
            g_market);
        }
     }

   RenderSolTradeDashboard(g_config,
                           g_account,
                           g_market,
                           g_risk_status,
                           CurrentSolTradeStatus(),
                           g_strategy_signal,
                           g_execution_status,
                           g_last_execution,
                           g_position_status,
                           g_last_position_action);
  }

int OnInit()
  {
   LoadSolTradeConfig();
   ResetSolTradeMarketSnapshot(g_market);
   ResetSolTradeRiskStatus(g_risk_status);
   ResetSolTradeStrategySignal(g_strategy_signal);
   ResetSolTradeExecutionStatus(g_execution_status);
   ResetSolTradeExecutionReport(g_last_execution);
   ResetSolTradePositionStatus(g_position_status);
   ResetSolTradePositionReport(g_last_position_action);

   string reason = "";
   if(!ValidateSolTradeConfig(g_config, reason))
     {
      Print("SolTrade Bot configuration rejected: ", reason);
      return INIT_PARAMETERS_INCORRECT;
     }

   if(!g_backtest_reporter.Initialise(g_config, reason))
     {
      Print("SolTrade Bot Phase 6 research initialisation failed: ",
            reason);
      return INIT_FAILED;
     }
   g_backtest_reporter.GetStatus(g_backtest_status);

   EvaluateSolTradeAccountSafety(g_config, g_account);

   if(!g_journal.Initialise(g_config, g_account, reason))
     {
      Print("SolTrade Bot journal initialisation failed: ", reason);
      return INIT_FAILED;
     }
   g_backtest_reporter.RegisterJournalFilename(
      g_journal.Filename());

   if(!InitialiseSolTradeMarketData(g_config,
                                    g_last_seen_current_bar,
                                    reason))
     {
      g_market.reason = reason;
      g_journal.LogEvent("MARKET_DATA_INITIALISATION_FAILED",
                         "NONE",
                         reason,
                         "Foundation remains fail-closed",
                         g_market);
      Print("SolTrade Bot market-data initialisation failed: ", reason);
      g_journal.Shutdown();
      return INIT_FAILED;
     }

   if(!g_risk_engine.Initialise(g_config,
                                g_account.account_identifier_hash,
                                SolTradeServerTime(),
                                AccountInfoDouble(ACCOUNT_EQUITY),
                                reason))
     {
      g_risk_engine.GetStatus(g_risk_status);
      g_journal.UpdateRiskStatus(g_risk_status);
      g_journal.LogEvent("RISK_ENGINE_INITIALISATION_FAILED",
                         "NONE",
                         g_risk_status.lock_reason,
                         reason,
                         g_market);
      Print("SolTrade Bot risk-engine initialisation failed: ", reason);
      g_journal.Shutdown();
      return INIT_FAILED;
     }

   g_risk_engine.GetStatus(g_risk_status);
   g_journal.UpdateRiskStatus(g_risk_status);
   g_last_risk_revision = g_risk_engine.Revision();
   g_journal.LogEvent("RISK_ENGINE_STARTED",
                      "NONE",
                      "",
                      g_risk_status.last_event,
                      g_market);

   if(!g_execution_engine.Initialise(g_config,
                                     g_account.account_identifier_hash,
                                     reason))
     {
      g_execution_engine.GetStatus(g_execution_status);
      g_journal.LogEvent("EXECUTION_ENGINE_INITIALISATION_FAILED",
                         "NONE",
                         reason,
                         "Execution engine failed closed",
                         g_market);
      Print("SolTrade Bot execution-engine initialisation failed: ", reason);
      g_journal.Shutdown();
      return INIT_FAILED;
     }

   g_execution_engine.GetStatus(g_execution_status);
   g_journal.LogEvent(
      g_execution_status.state_restored
         ? "EXECUTION_STATE_RESTORED"
         : "EXECUTION_STATE_INITIALISED",
      "NONE",
      "",
      "last_signal_bar=" +
         TimeToString(g_execution_status.last_consumed_signal_bar,
                      TIME_DATE | TIME_MINUTES) +
      "; open_positions=" +
         IntegerToString(g_execution_status.open_soltrade_positions) +
      "; active_orders=" +
         IntegerToString(g_execution_status.active_soltrade_orders) +
      "; unprotected_position=" +
         (g_execution_status.unprotected_soltrade_position ? "YES" : "NO"),
      g_market);

   if(!g_position_manager.Initialise(
         g_config,
         g_account.account_identifier_hash,
         reason))
     {
      g_position_manager.GetStatus(g_position_status);
      g_journal.LogEvent("POSITION_MANAGER_INITIALISATION_FAILED",
                         "NONE",
                         reason,
                         "Position Manager failed closed",
                         g_market);
      Print("SolTrade Bot position-manager initialisation failed: ",
            reason);
      g_journal.Shutdown();
      return INIT_FAILED;
     }

   g_position_manager.GetStatus(g_position_status);
   g_last_position_state_event = g_position_status.last_event;
   g_journal.LogEvent(
      g_position_status.state_restored
         ? "POSITION_STATE_RESTORED"
         : "POSITION_STATE_INITIALISED",
      g_position_status.position_present
         ? SolTradePositionDirectionName(g_position_status.position_type)
         : "NONE",
      g_position_status.stop_attached ||
      !g_position_status.position_present
         ? ""
         : "Restored SolTrade position has no attached stop-loss",
      "position_present=" +
         (g_position_status.position_present ? "YES" : "NO") +
      "; position_identifier=" +
         StringFormat("%I64u",
                      g_position_status.position_identifier) +
      "; stop_attached=" +
         (g_position_status.stop_attached ? "YES" : "NO") +
      "; close_attempt_claimed=" +
         (g_position_status.close_attempt_claimed ? "YES" : "NO") +
      "; management_enabled=" +
         (SolTradeBacktestManagementEnabled(
             g_config,
             g_account.detected_environment)
            ? "YES"
            : "NO"),
      g_market);

   g_journal.LogEvent("PHASE6_FOUNDATION_STARTED",
                      "NONE",
                      "",
                      "Phase 6 research-capable build started; demo entry " +
                         (g_config.enable_demo_execution
                            ? "enabled"
                            : "disabled") +
                         "; position management " +
                         (g_config.enable_position_management
                            ? "enabled"
                            : "disabled") +
                         "; tester research " +
                         (g_config.enable_backtest_research
                            ? "enabled"
                            : "disabled") +
                         "; live trading disabled; journal " +
                         g_journal.Filename(),
                      g_market);

   if(!g_account.expected_environment_matches ||
      g_config.emergency_stop ||
      g_account.detected_environment == SOLTRADE_ENV_UNKNOWN ||
      !g_account.execution_environment_eligible)
     {
      g_journal.LogEvent("ACCOUNT_GUARD_REFUSAL",
                         "NONE",
                         g_account.reason,
                         g_account.safety_state,
                         g_market);
     }

   ResetLastError();
   if(!EventSetTimer(g_config.dashboard_refresh_seconds))
     {
      reason = "Cannot start dashboard/health timer; error " +
               IntegerToString(GetLastError());
      g_journal.LogEvent("TIMER_INITIALISATION_FAILED",
                         "NONE",
                         reason,
                         "Foundation cannot monitor safely without its timer",
                         g_market);
      Print("SolTrade Bot timer initialisation failed: ", reason);
      g_journal.Shutdown();
      return INIT_FAILED;
     }

   RefreshSolTradeFoundation();
   return INIT_SUCCEEDED;
  }

void OnTick()
  {
   RefreshSolTradeFoundation();
  }

void OnTimer()
  {
   RefreshSolTradeFoundation();
  }

void OnTradeTransaction(const MqlTradeTransaction &transaction,
                        const MqlTradeRequest &request,
                        const MqlTradeResult &result)
  {
   SolTradeExecutionReport fill_report;
   if(g_execution_engine.HandleTradeTransaction(transaction, fill_report))
     {
      g_last_execution = fill_report;
      g_execution_engine.GetStatus(g_execution_status);
      g_journal.LogExecution(fill_report, g_market);
      g_backtest_reporter.RecordEntry(fill_report, g_market);
     }

   SolTradePositionReport exit_report;
   if(g_position_manager.HandleTradeTransaction(transaction,
                                                exit_report))
     {
      g_last_position_action = exit_report;
      g_position_manager.GetStatus(g_position_status);
      g_execution_engine.RefreshExposure();
      g_execution_engine.GetStatus(g_execution_status);
      g_journal.LogPositionManagement(exit_report, g_market);
      g_backtest_reporter.RecordExit(exit_report, g_market);
      g_last_position_report_key =
         exit_report.event_type + "|" +
         exit_report.reason_code + "|" +
         StringFormat("%I64u", exit_report.position_identifier) + "|" +
         IntegerToString(exit_report.signal_bar_time) + "|" +
         IntegerToString((long)exit_report.broker_return_code) + "|" +
         StringFormat("%I64u", exit_report.deal_ticket);

      string outcome_reason = "";
      const ENUM_SOLTRADE_OUTCOME_RESULT outcome_result =
         g_risk_engine.RecordClosedOutcome(
            "POSITION_EXIT_DEAL_" +
               StringFormat("%I64u", exit_report.deal_ticket),
            exit_report.final_profit_loss,
            SolTradeServerTime(),
            AccountInfoDouble(ACCOUNT_EQUITY),
            outcome_reason);
      g_risk_engine.GetStatus(g_risk_status);
      g_journal.UpdateRiskStatus(g_risk_status);
      g_journal.LogEvent(
         outcome_result == SOLTRADE_OUTCOME_ERROR
            ? "POSITION_OUTCOME_RECORD_FAILED"
            : (outcome_result == SOLTRADE_OUTCOME_DUPLICATE
               ? "POSITION_OUTCOME_DUPLICATE_IGNORED"
               : "POSITION_OUTCOME_RECORDED"),
         exit_report.position_direction,
         outcome_result == SOLTRADE_OUTCOME_ERROR
            ? outcome_reason
            : "",
         "deal_ticket=" +
            StringFormat("%I64u", exit_report.deal_ticket) +
         "; net_profit=" +
            DoubleToString(exit_report.final_profit_loss, 2) +
         "; exit_reason=" + exit_report.exit_reason_code +
         "; risk_event=" + outcome_reason,
         g_market);
     }
  }

double OnTester()
  {
   if(!g_config.enable_backtest_research)
      return 0.0;

   string reason = "";
   const bool finalised =
      g_backtest_reporter.Finalise(reason);
   g_backtest_reporter.GetStatus(g_backtest_status);
   if(finalised)
      Print("SOLTRADE_PHASE6_ARTIFACTS_RECONCILED",
            " | trading_input_hash=",
            g_backtest_status.trading_input_hash,
            " | execution_instance_id=",
            g_config.execution_instance_id);
   else
      Print("SOLTRADE_PHASE6_RUN_INVALID | reason=", reason);
   return finalised ? 1.0 : 0.0;
  }

void OnDeinit(const int reason)
  {
   EventKillTimer();
   g_journal.LogEvent("FOUNDATION_STOPPED",
                      "NONE",
                      "",
                      SolTradeDeinitReason(reason),
                      g_market);
   g_journal.Shutdown();
   ClearSolTradeDashboard();
  }
