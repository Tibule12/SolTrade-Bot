#property copyright "SolTrade Bot"
#property link      ""
#property version   "1.000"
#property strict
#property script_show_inputs
#property description "One-shot Phase 4 connected-demo entry verification"
#property description "Uses the approved ExecutionEngine; never retries or closes a position."

#include <SolTrade/Config.mqh>
#include <SolTrade/AccountGuard.mqh>
#include <SolTrade/MarketData.mqh>
#include <SolTrade/RiskEngine.mqh>
#include <SolTrade/StrategyBreakout.mqh>
#include <SolTrade/ExecutionEngine.mqh>
#include <SolTrade/TradeJournal.mqh>

input group "Explicit one-shot arming"
input bool ConfirmOneShotDemoOrder = false;
input long ApprovedDemoAccount     = 0;
input ENUM_SOLTRADE_ENTRY_SIGNAL VerificationDirection =
   SOLTRADE_SIGNAL_BUY;

input group "Identity"
input ulong MagicNumber = 2607202601;

input group "Confirmation"
input int ConfirmationTimeoutSeconds = 15;

#define SOLTRADE_VERIFICATION_SYMBOL "EURUSD"

void BuildOneShotConfig(SolTradeConfig &config)
  {
   config.strategy_version             = "1.0.0";
   config.approved_strategy_version    = "";
   config.risk_profile                 = "CONSERVATIVE_V1";
   config.approved_risk_profile        = "";
   config.magic_number                 = MagicNumber;
   config.symbol                       = SOLTRADE_VERIFICATION_SYMBOL;
   config.timeframe                    = PERIOD_H1;
   config.minimum_history_bars         = 222;
   config.max_tick_age_seconds         = 120;
   config.max_spread_points            = 30;
   config.max_spread_atr_percent       = 10.0;
   config.max_slippage_points          = 10;
   config.risk_per_trade_percent       = 0.25;
   config.daily_loss_limit_percent     = 1.0;
   config.weekly_loss_limit_percent    = 2.5;
   config.emergency_drawdown_percent   = 5.0;
   config.production_baseline_equity   =
      AccountInfoDouble(ACCOUNT_EQUITY);
   config.consecutive_loss_limit       = 3;
   config.reset_emergency_lock         = false;
   config.expected_environment         = SOLTRADE_ENV_DEMO;
   config.enable_demo_execution        = true;
   config.enable_position_management   = false;
   config.approved_demo_account        = ApprovedDemoAccount;
   config.allow_live_trading           = false;
   config.approved_live_account        = 0;
   config.emergency_stop               = false;
   config.enable_csv_journal           = true;
   config.journal_directory            = "SolTradeBot\\logs";
   config.risk_state_directory         = "SolTradeBot\\state";
   config.execution_state_directory    = "SolTradeBot\\state";
   config.enable_dashboard             = false;
   config.dashboard_refresh_seconds    = 1;
  }

string OneShotMarkerPath(const string account_identifier_hash,
                         const ulong magic_number)
  {
   return "SolTradeBot\\state\\one_shot_demo_" +
          "diagnostic_v2_" + account_identifier_hash + "_" +
          StringFormat("%I64u", magic_number) + ".csv";
  }

bool WriteOneShotMarker(const string marker_path,
                        const string state,
                        const SolTradeExecutionReport &report,
                        string &reason)
  {
   reason = "";
   const string temporary_path = marker_path + ".tmp";
   FileDelete(temporary_path);
   ResetLastError();
   const int handle =
      FileOpen(temporary_path, FILE_WRITE | FILE_CSV | FILE_ANSI, ',');
   if(handle == INVALID_HANDLE)
     {
      reason = "Cannot create one-shot marker; error " +
               IntegerToString(GetLastError());
      return false;
     }

   const uint written =
      FileWrite(handle,
                "SOLTRADE_ONE_SHOT_DEMO_DIAGNOSTIC_V2",
                state,
                TimeToString(TimeCurrent(),
                             TIME_DATE | TIME_SECONDS),
                report.signal_result,
                IntegerToString(report.signal_bar_time),
                DoubleToString(report.requested_entry, 10),
                DoubleToString(report.actual_entry, 10),
                DoubleToString(report.volume, 8),
                DoubleToString(report.stop_loss, 10),
                IntegerToString((long)report.broker_return_code),
                StringFormat("%I64u", report.order_ticket),
                StringFormat("%I64u", report.deal_ticket),
                report.reason_code);
   FileFlush(handle);
   FileClose(handle);

   if(written == 0)
     {
      FileDelete(temporary_path);
      reason = "One-shot marker write returned zero bytes";
      return false;
     }

   ResetLastError();
   if(!FileMove(temporary_path, 0, marker_path, FILE_REWRITE))
     {
      reason = "Cannot persist one-shot marker; error " +
               IntegerToString(GetLastError());
      FileDelete(temporary_path);
      return false;
     }

   return true;
  }

void PrintOneShotReport(const string prefix,
                        const SolTradeExecutionReport &report,
                        const int digits)
  {
   Print(prefix,
         " | event=", report.event_type,
         " | reason_code=", report.reason_code,
         " | direction=", report.signal_result,
         " | requested_price=",
            DoubleToString(report.requested_entry, digits),
         " | fill_price=",
            report.actual_entry > 0.0
            ? DoubleToString(report.actual_entry, digits)
            : "UNCONFIRMED",
         " | spread_points=", report.spread_points,
         " | slippage_points=",
            DoubleToString(report.slippage_points, 2),
         " | volume=", DoubleToString(report.volume, 8),
         " | stop_loss=", DoubleToString(report.stop_loss, digits),
         " | risk_amount=", DoubleToString(report.risk_amount, 2),
         " | broker_return_code=",
            IntegerToString((long)report.broker_return_code),
         " | order_check_boolean_result=",
            report.order_check_boolean_result ? "true" : "false",
         " | order_check_last_error=",
            IntegerToString(report.order_check_last_error),
         " | order_check_retcode=",
            IntegerToString((long)report.order_check_retcode),
         " | order_check_comment=", report.order_check_comment,
         " | requested_action=",
            EnumToString(report.requested_action),
            "(", IntegerToString((int)report.requested_action), ")",
         " | requested_order_type=",
            EnumToString(report.requested_order_type),
            "(", IntegerToString((int)report.requested_order_type), ")",
         " | requested_filling_mode=",
            EnumToString(report.requested_filling_mode),
            "(", IntegerToString((int)report.requested_filling_mode), ")",
         " | requested_deviation_points=",
            IntegerToString(report.requested_deviation_points),
         " | requested_symbol=", report.requested_symbol,
         " | requested_magic_number=",
            StringFormat("%I64u", report.requested_magic_number),
         " | broker_volume_min=",
            DoubleToString(report.broker_volume_min, 8),
         " | broker_volume_step=",
            DoubleToString(report.broker_volume_step, 8),
         " | broker_stops_level_points=",
            IntegerToString(report.broker_stops_level_points),
         " | broker_supported_filling_mode=",
            SolTradeSupportedFillingModesName(
               report.broker_supported_filling_mode),
            "(", IntegerToString(
                    report.broker_supported_filling_mode), ")",
         " | order_ticket=", StringFormat("%I64u", report.order_ticket),
         " | deal_ticket=", StringFormat("%I64u", report.deal_ticket),
         " | broker_attempted=",
            report.broker_submission_attempted ? "YES" : "NO",
         " | broker_accepted=", report.broker_accepted ? "YES" : "NO",
         " | fill_confirmed=", report.fill_confirmed ? "YES" : "NO",
         " | retry_allowed=NO");
  }

int OnStart()
  {
   Print("SOLTRADE_ONE_SHOT_PREFLIGHT_STARTED",
         " | symbol=", _Symbol,
         " | account_mode=",
            SolTradeEnvironmentName(DetectSolTradeEnvironment()),
         " | armed=", ConfirmOneShotDemoOrder ? "YES" : "NO");

   if(!ConfirmOneShotDemoOrder)
     {
      Print("SOLTRADE_ONE_SHOT_NOT_ARMED",
            " | ConfirmOneShotDemoOrder must be true");
      return 10;
     }

   if((bool)MQLInfoInteger(MQL_TESTER))
     {
      Print("SOLTRADE_ONE_SHOT_REJECTED",
            " | reason_code=CONNECTED_DEMO_REQUIRED",
            " | Strategy Tester is not permitted for this verification");
      return 11;
     }

   const ENUM_ACCOUNT_TRADE_MODE account_mode =
      (ENUM_ACCOUNT_TRADE_MODE)
      AccountInfoInteger(ACCOUNT_TRADE_MODE);
   if(account_mode != ACCOUNT_TRADE_MODE_DEMO)
     {
      Print("SOLTRADE_ONE_SHOT_REJECTED",
            " | reason_code=DEMO_ACCOUNT_REQUIRED",
            " | every non-demo account is unconditionally rejected");
      return 12;
     }

   if(ApprovedDemoAccount <= 0 ||
      AccountInfoInteger(ACCOUNT_LOGIN) != ApprovedDemoAccount)
     {
      Print("SOLTRADE_ONE_SHOT_REJECTED",
            " | reason_code=DEMO_ACCOUNT_NOT_APPROVED",
            " | exact ApprovedDemoAccount match is required");
      return 13;
     }

   if(_Symbol != SOLTRADE_VERIFICATION_SYMBOL)
     {
      Print("SOLTRADE_ONE_SHOT_REJECTED",
            " | reason_code=EURUSD_CHART_REQUIRED",
            " | attach the script to an exact EURUSD chart");
      return 14;
     }

   if(VerificationDirection != SOLTRADE_SIGNAL_BUY &&
      VerificationDirection != SOLTRADE_SIGNAL_SELL)
     {
      Print("SOLTRADE_ONE_SHOT_REJECTED",
            " | reason_code=BUY_OR_SELL_REQUIRED");
      return 15;
     }

   if(ConfirmationTimeoutSeconds < 1 ||
      ConfirmationTimeoutSeconds > 30)
     {
      Print("SOLTRADE_ONE_SHOT_REJECTED",
            " | reason_code=INVALID_CONFIRMATION_TIMEOUT",
            " | timeout must be between 1 and 30 seconds");
      return 16;
     }

   SolTradeConfig config = {};
   BuildOneShotConfig(config);
   string reason = "";
   if(!ValidateSolTradeConfig(config, reason))
     {
      Print("SOLTRADE_ONE_SHOT_REJECTED",
            " | reason_code=CONFIGURATION_REJECTED",
            " | reason=", reason);
      return 17;
     }

   SolTradeAccountStatus account;
   EvaluateSolTradeAccountSafety(config, account);
   if(!account.execution_environment_eligible)
     {
      Print("SOLTRADE_ONE_SHOT_REJECTED",
            " | reason_code=ACCOUNT_GUARD_REJECTED",
            " | reason=", account.reason);
      return 18;
     }

   CSolTradeJournal journal;
   if(!journal.Initialise(config, account, reason))
     {
      Print("SOLTRADE_ONE_SHOT_REJECTED",
            " | reason_code=JOURNAL_INITIALISATION_FAILED",
            " | reason=", reason);
      return 19;
     }

   SolTradeMarketSnapshot market;
   ResetSolTradeMarketSnapshot(market);
   datetime seeded_bar = 0;
   if(!InitialiseSolTradeMarketData(config, seeded_bar, reason) ||
      !RefreshSolTradeMarketData(config, market))
     {
      const string market_reason =
         StringLen(reason) > 0 ? reason : market.reason;
      journal.LogEvent("ONE_SHOT_PREFLIGHT_REJECTED",
                       "NONE",
                       market_reason,
                       "Market data is not valid",
                       market);
      Print("SOLTRADE_ONE_SHOT_REJECTED",
            " | reason_code=MARKET_DATA_INVALID",
            " | reason=", market_reason);
      journal.Shutdown();
      return 20;
     }

   CSolTradeRiskEngine risk_engine;
   datetime server_time = TimeTradeServer();
   if(server_time <= 0)
      server_time = TimeCurrent();
   if(!risk_engine.Initialise(config,
                              account.account_identifier_hash,
                              server_time,
                              AccountInfoDouble(ACCOUNT_EQUITY),
                              reason))
     {
      journal.LogEvent("ONE_SHOT_PREFLIGHT_REJECTED",
                       "NONE",
                       reason,
                       "Risk Engine failed closed",
                       market);
      Print("SOLTRADE_ONE_SHOT_REJECTED",
            " | reason_code=RISK_ENGINE_INITIALISATION_FAILED",
            " | reason=", reason);
      journal.Shutdown();
      return 21;
     }

   SolTradeRiskStatus risk;
   risk_engine.GetStatus(risk);
   journal.UpdateRiskStatus(risk);

   CSolTradeExecutionEngine execution_engine;
   if(!execution_engine.Initialise(config,
                                   account.account_identifier_hash,
                                   reason))
     {
      journal.LogEvent("ONE_SHOT_PREFLIGHT_REJECTED",
                       "NONE",
                       reason,
                       "Execution Engine failed closed",
                       market);
      Print("SOLTRADE_ONE_SHOT_REJECTED",
            " | reason_code=EXECUTION_ENGINE_INITIALISATION_FAILED",
            " | reason=", reason);
      journal.Shutdown();
      return 22;
     }

   SolTradeStrategySignal signal;
   if(!SolTradeEvaluateCurrentCompletedHistory(config, signal))
     {
      journal.LogEvent("ONE_SHOT_PREFLIGHT_REJECTED",
                       "NONE",
                       signal.calculation_error,
                       "Cannot obtain approved ATR stop distance",
                       market);
      Print("SOLTRADE_ONE_SHOT_REJECTED",
            " | reason_code=STRATEGY_HISTORY_INVALID",
            " | reason=", signal.calculation_error);
      journal.Shutdown();
      return 23;
     }

   // This controlled direction override exists only in this one-shot script.
   // The production EA continues to pass only real Trend Breakout V1 signals.
   signal.entry_signal      = VerificationDirection;
   signal.entry_reason_code = "ONE_SHOT_DEMO_EXECUTION_VERIFICATION";
   signal.entry_reason =
      "Test-only direction using the approved completed-history ATR stop";

   const string marker_path =
      OneShotMarkerPath(account.account_identifier_hash,
                        config.magic_number);
   if(FileIsExist(marker_path))
     {
      journal.LogEvent("ONE_SHOT_ALREADY_DISABLED",
                       SolTradeEntrySignalName(signal.entry_signal),
                       "Persistent one-shot marker already exists",
                       marker_path,
                       market);
      Print("SOLTRADE_ONE_SHOT_ALREADY_DISABLED",
            " | marker=", marker_path,
            " | no order attempt made");
      journal.Shutdown();
      return 24;
     }

   SolTradeExecutionReport marker_report;
   ResetSolTradeExecutionReport(marker_report);
   marker_report.evaluated       = true;
   marker_report.event_type      = "ONE_SHOT_ATTEMPT_CLAIMED";
   marker_report.reason_code     = "ONE_SHOT_ARMED";
   marker_report.signal_result   =
      SolTradeEntrySignalName(signal.entry_signal);
   marker_report.signal_bar_time = signal.signal_bar_time;
   if(!WriteOneShotMarker(marker_path,
                          "ATTEMPT_CLAIMED",
                          marker_report,
                          reason))
     {
      journal.LogEvent("ONE_SHOT_PREFLIGHT_REJECTED",
                       marker_report.signal_result,
                       reason,
                       "No order is allowed without a persistent one-shot marker",
                       market);
      Print("SOLTRADE_ONE_SHOT_REJECTED",
            " | reason_code=ONE_SHOT_MARKER_FAILED",
            " | reason=", reason);
      journal.Shutdown();
      return 25;
     }

   journal.LogEvent("ONE_SHOT_ATTEMPT_CLAIMED",
                    marker_report.signal_result,
                    "",
                    "Persistent marker created before the sole execution-engine call",
                    market);

   SolTradeExecutionReport submission;
   execution_engine.ProcessSignal(signal,
                                  account,
                                  market,
                                  risk,
                                  true,
                                  submission);
   journal.LogExecution(submission, market);
   PrintOneShotReport("SOLTRADE_ONE_SHOT_ATTEMPT",
                      submission,
                      market.digits);

   SolTradeExecutionReport final_report = submission;
   int script_result = 30;
   if(submission.broker_accepted)
     {
      const uint started_at = GetTickCount();
      bool confirmed = false;
      SolTradeExecutionReport confirmation;
      while((GetTickCount() - started_at) <
            (uint)(ConfirmationTimeoutSeconds * 1000))
        {
         if(execution_engine.ConfirmMatchingEntryDealFromHistory(
               submission,
               confirmation))
           {
            confirmed = true;
            break;
           }
         Sleep(200);
        }

      if(confirmed)
        {
         final_report = confirmation;
         journal.LogExecution(confirmation, market);
         PrintOneShotReport(
            "SOLTRADE_ONE_SHOT_MATCHING_TRADE_TRANSACTION",
            confirmation,
            market.digits);
         script_result = 0;
        }
      else
        {
         final_report = confirmation;
         journal.LogExecution(confirmation, market);
         PrintOneShotReport(
            "SOLTRADE_ONE_SHOT_TRANSACTION_UNCONFIRMED",
            confirmation,
            market.digits);
         script_result = 31;
        }
     }
   else
     {
      Print("SOLTRADE_ONE_SHOT_REJECTED_NO_RETRY",
            " | reason_code=", submission.reason_code,
            " | broker_return_code=",
               IntegerToString((long)submission.broker_return_code),
            " | order_check_boolean_result=",
               submission.order_check_boolean_result ? "true" : "false",
            " | order_check_last_error=",
               IntegerToString(submission.order_check_last_error),
            " | order_check_retcode=",
               IntegerToString((long)submission.order_check_retcode),
            " | order_check_comment=",
               submission.order_check_comment);
      script_result = 32;
     }

   string marker_reason = "";
   const string final_marker_state =
      final_report.fill_confirmed
      ? "MATCHING_TRANSACTION_CONFIRMED_DISABLED"
      : (submission.broker_accepted
         ? "ACCEPTED_UNCONFIRMED_DISABLED"
         : "REJECTED_DISABLED");
   if(!WriteOneShotMarker(marker_path,
                          final_marker_state,
                          final_report,
                          marker_reason))
     {
      Print("SOLTRADE_ONE_SHOT_MARKER_UPDATE_FAILED",
            " | reason=", marker_reason,
            " | initial disable marker remains present");
     }

   journal.LogEvent("ONE_SHOT_VERIFICATION_DISABLED",
                    final_report.signal_result,
                    "",
                    "state=" + final_marker_state +
                    "; marker=" + marker_path +
                    "; retry_allowed=NO",
                    market);
   Print("SOLTRADE_ONE_SHOT_DISABLED",
         " | state=", final_marker_state,
         " | marker=", marker_path,
         " | retry_allowed=NO",
         " | script will now terminate");
   journal.Shutdown();
   return script_result;
  }
