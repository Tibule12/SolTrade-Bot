#property copyright "SolTrade Bot"
#property link      ""
#property version   "1.000"
#property strict
#property script_show_inputs
#property description "One-shot Phase 5 connected-demo position-close verification"
#property description "Default-unarmed; approved engines only; permanent markers; no retry."

#include <SolTrade/Config.mqh>
#include <SolTrade/AccountGuard.mqh>
#include <SolTrade/MarketData.mqh>
#include <SolTrade/RiskEngine.mqh>
#include <SolTrade/StrategyBreakout.mqh>
#include <SolTrade/ExecutionEngine.mqh>
#include <SolTrade/PositionManager.mqh>
#include <SolTrade/TradeJournal.mqh>

input group "Explicit mutually-exclusive arming"
input bool ConfirmCreateOneShotDemoPosition = false;
input bool ConfirmCloseOneShotDemoPosition  = false;
input long ApprovedDemoAccount              = 0;

input group "Fixture creation only"
input ENUM_SOLTRADE_ENTRY_SIGNAL FixtureDirection =
   SOLTRADE_SIGNAL_BUY;

input group "Confirmation"
input int ConfirmationTimeoutSeconds = 15;

#define SOLTRADE_CLOSE_VERIFICATION_SYMBOL "EURUSD"
#define SOLTRADE_CLOSE_VERIFICATION_MAGIC  2607202601

#ifdef SOLTRADE_CLOSE_VERIFIER_V2_CONFIGURATION
#define SOLTRADE_SELECTED_RISK_DIRECTORY \
   SOLTRADE_V2_RISK_DIRECTORY
#define SOLTRADE_SELECTED_STATE_DIRECTORY \
   SOLTRADE_V2_STATE_DIRECTORY
#define SOLTRADE_SELECTED_FIXTURE_MARKER_FILENAME_PREFIX \
   SOLTRADE_V2_FIXTURE_MARKER_FILENAME_PREFIX
#define SOLTRADE_SELECTED_CLOSE_MARKER_FILENAME_PREFIX \
   SOLTRADE_V2_CLOSE_MARKER_FILENAME_PREFIX
#define SOLTRADE_SELECTED_FIXTURE_MARKER_SCHEMA \
   SOLTRADE_V2_FIXTURE_MARKER_SCHEMA
#define SOLTRADE_SELECTED_CLOSE_MARKER_SCHEMA \
   SOLTRADE_V2_CLOSE_MARKER_SCHEMA
#define SOLTRADE_SELECTED_PREFLIGHT_STARTED_EVENT \
   SOLTRADE_V2_PREFLIGHT_STARTED_EVENT
#define SOLTRADE_SELECTED_NOT_ARMED_EVENT \
   SOLTRADE_V2_NOT_ARMED_EVENT
#else
#define SOLTRADE_SELECTED_RISK_DIRECTORY \
   "SolTradeBot\\one-shot-close-risk-v1"
#define SOLTRADE_SELECTED_STATE_DIRECTORY \
   "SolTradeBot\\one-shot-close-state-v1"
#define SOLTRADE_SELECTED_FIXTURE_MARKER_FILENAME_PREFIX \
   "one_shot_close_fixture_entry_v1_"
#define SOLTRADE_SELECTED_CLOSE_MARKER_FILENAME_PREFIX \
   "one_shot_position_close_v1_"
#define SOLTRADE_SELECTED_FIXTURE_MARKER_SCHEMA \
   "SOLTRADE_CLOSE_FIXTURE_ENTRY_V1"
#define SOLTRADE_SELECTED_CLOSE_MARKER_SCHEMA \
   "SOLTRADE_ONE_SHOT_POSITION_CLOSE_V1"
#define SOLTRADE_SELECTED_PREFLIGHT_STARTED_EVENT \
   "SOLTRADE_CLOSE_VERIFY_PREFLIGHT_STARTED"
#define SOLTRADE_SELECTED_NOT_ARMED_EVENT \
   "SOLTRADE_CLOSE_VERIFY_NOT_ARMED"
#endif

#define SOLTRADE_CLOSE_VERIFICATION_RISK_DIRECTORY \
   SOLTRADE_SELECTED_RISK_DIRECTORY
#define SOLTRADE_CLOSE_VERIFICATION_STATE_DIRECTORY \
   SOLTRADE_SELECTED_STATE_DIRECTORY
#define SOLTRADE_FIXTURE_MARKER_FILENAME_PREFIX \
   SOLTRADE_SELECTED_FIXTURE_MARKER_FILENAME_PREFIX
#define SOLTRADE_CLOSE_MARKER_FILENAME_PREFIX \
   SOLTRADE_SELECTED_CLOSE_MARKER_FILENAME_PREFIX
#define SOLTRADE_FIXTURE_MARKER_SCHEMA \
   SOLTRADE_SELECTED_FIXTURE_MARKER_SCHEMA
#define SOLTRADE_CLOSE_MARKER_SCHEMA \
   SOLTRADE_SELECTED_CLOSE_MARKER_SCHEMA
#define SOLTRADE_CLOSE_PREFLIGHT_STARTED_EVENT \
   SOLTRADE_SELECTED_PREFLIGHT_STARTED_EVENT
#define SOLTRADE_CLOSE_NOT_ARMED_EVENT \
   SOLTRADE_SELECTED_NOT_ARMED_EVENT

void BuildCloseVerificationConfig(const bool create_fixture,
                                  const bool close_fixture,
                                  SolTradeConfig &config)
  {
   config.strategy_version             = "1.0.0";
   config.approved_strategy_version    = "";
   config.risk_profile                 = "CONSERVATIVE_V1";
   config.approved_risk_profile        = "";
   config.magic_number                 =
      SOLTRADE_CLOSE_VERIFICATION_MAGIC;
   config.symbol                       =
      SOLTRADE_CLOSE_VERIFICATION_SYMBOL;
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
   config.enable_demo_execution        = create_fixture;
   config.enable_position_management   = close_fixture;
   config.approved_demo_account        = ApprovedDemoAccount;
   config.allow_live_trading           = false;
   config.approved_live_account        = 0;
   // The controlled close uses the approved operator emergency-close path.
   // No synthetic Donchian exit is created by this verifier.
   config.emergency_stop               = close_fixture;
   config.enable_csv_journal           = true;
   config.journal_directory            =
      "SolTradeBot\\logs";
   config.risk_state_directory         =
      SOLTRADE_CLOSE_VERIFICATION_RISK_DIRECTORY;
   config.execution_state_directory    =
      SOLTRADE_CLOSE_VERIFICATION_STATE_DIRECTORY;
   config.enable_dashboard             = false;
   config.dashboard_refresh_seconds   = 1;
  }

string FixtureEntryMarkerPath(const string account_identifier_hash)
  {
   return
      SOLTRADE_CLOSE_VERIFICATION_STATE_DIRECTORY + "\\" +
      SOLTRADE_FIXTURE_MARKER_FILENAME_PREFIX +
      account_identifier_hash + "_" +
      StringFormat("%I64u",
                   (ulong)SOLTRADE_CLOSE_VERIFICATION_MAGIC) +
      ".csv";
  }

string PositionCloseMarkerPath(const string account_identifier_hash)
  {
   return
      SOLTRADE_CLOSE_VERIFICATION_STATE_DIRECTORY + "\\" +
      SOLTRADE_CLOSE_MARKER_FILENAME_PREFIX +
      account_identifier_hash + "_" +
      StringFormat("%I64u",
                   (ulong)SOLTRADE_CLOSE_VERIFICATION_MAGIC) +
      ".csv";
  }

bool WriteFixtureEntryMarker(const string marker_path,
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
      reason = "Cannot create fixture-entry marker; error " +
               IntegerToString(GetLastError());
      return false;
     }

   const uint written =
      FileWrite(handle,
                SOLTRADE_FIXTURE_MARKER_SCHEMA,
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
                report.broker_comment,
                StringFormat("%I64u", report.order_ticket),
                StringFormat("%I64u", report.deal_ticket),
                report.reason_code);
   FileFlush(handle);
   FileClose(handle);

   if(written == 0)
     {
      FileDelete(temporary_path);
      reason = "Fixture-entry marker write returned zero bytes";
      return false;
     }

   ResetLastError();
   if(!FileMove(temporary_path, 0, marker_path, FILE_REWRITE))
     {
      reason = "Cannot persist fixture-entry marker; error " +
               IntegerToString(GetLastError());
      FileDelete(temporary_path);
      return false;
     }
   return true;
  }

bool WritePositionCloseMarker(const string marker_path,
                              const string state,
                              const SolTradePositionReport &report,
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
      reason = "Cannot create position-close marker; error " +
               IntegerToString(GetLastError());
      return false;
     }

   const uint written =
      FileWrite(handle,
                SOLTRADE_CLOSE_MARKER_SCHEMA,
                state,
                TimeToString(TimeCurrent(),
                             TIME_DATE | TIME_SECONDS),
                report.position_direction,
                StringFormat("%I64u", report.position_ticket),
                StringFormat("%I64u", report.position_identifier),
                report.stop_attached ? "YES" : "NO",
                DoubleToString(report.volume, 8),
                DoubleToString(report.requested_close_price, 10),
                DoubleToString(report.actual_close_price, 10),
                DoubleToString(report.slippage_points, 2),
                report.order_check_boolean_result ? "true" : "false",
                IntegerToString(report.order_check_last_error),
                IntegerToString((long)report.order_check_retcode),
                report.order_check_comment,
                report.order_send_boolean_result ? "true" : "false",
                IntegerToString(report.order_send_last_error),
                IntegerToString((long)report.broker_return_code),
                report.broker_comment,
                StringFormat("%I64u", report.order_ticket),
                StringFormat("%I64u", report.deal_ticket),
                DoubleToString(report.final_profit_loss, 2),
                report.exit_reason_code,
                report.exit_reason,
                report.reason_code,
                "retry_allowed=NO");
   FileFlush(handle);
   FileClose(handle);

   if(written == 0)
     {
      FileDelete(temporary_path);
      reason = "Position-close marker write returned zero bytes";
      return false;
     }

   ResetLastError();
   if(!FileMove(temporary_path, 0, marker_path, FILE_REWRITE))
     {
      reason = "Cannot persist position-close marker; error " +
               IntegerToString(GetLastError());
      FileDelete(temporary_path);
      return false;
     }
   return true;
  }

void PrintFixtureEntryReport(const string prefix,
                             const SolTradeExecutionReport &report,
                             const int digits)
  {
   Print(prefix,
         " | event=", report.event_type,
         " | reason_code=", report.reason_code,
         " | direction=", report.signal_result,
         " | requested_price=",
            DoubleToString(report.requested_entry, digits),
         " | actual_price=",
            report.actual_entry > 0.0
            ? DoubleToString(report.actual_entry, digits)
            : "UNCONFIRMED",
         " | volume=", DoubleToString(report.volume, 8),
         " | stop_loss=", DoubleToString(report.stop_loss, digits),
         " | order_check_boolean_result=",
            report.order_check_boolean_result ? "true" : "false",
         " | order_check_last_error=",
            IntegerToString(report.order_check_last_error),
         " | order_check_retcode=",
            IntegerToString((long)report.order_check_retcode),
         " | order_check_comment=", report.order_check_comment,
         " | order_send_boolean_result=",
            report.broker_submission_attempted
            ? (report.broker_accepted ? "true" : "false")
            : "false",
         " | broker_return_code=",
            IntegerToString((long)report.broker_return_code),
         " | broker_comment=", report.broker_comment,
         " | order_ticket=", StringFormat("%I64u", report.order_ticket),
         " | deal_ticket=", StringFormat("%I64u", report.deal_ticket),
         " | fill_confirmed=", report.fill_confirmed ? "YES" : "NO",
         " | retry_allowed=NO");
  }

void PrintPositionCloseReport(const string prefix,
                              const SolTradePositionReport &report,
                              const int digits)
  {
   Print(prefix,
         " | event=", report.event_type,
         " | reason_code=", report.reason_code,
         " | direction=", report.position_direction,
         " | position_ticket=",
            StringFormat("%I64u", report.position_ticket),
         " | position_identifier=",
            StringFormat("%I64u", report.position_identifier),
         " | stop_attached=", report.stop_attached ? "YES" : "NO",
         " | requested_close_price=",
            report.requested_close_price > 0.0
            ? DoubleToString(report.requested_close_price, digits)
            : "UNSET",
         " | actual_close_price=",
            report.actual_close_price > 0.0
            ? DoubleToString(report.actual_close_price, digits)
            : "UNCONFIRMED",
         " | slippage_points=",
            DoubleToString(report.slippage_points, 2),
         " | volume=", DoubleToString(report.volume, 8),
         " | order_check_performed=",
            report.order_check_performed ? "YES" : "NO",
         " | order_check_boolean_result=",
            report.order_check_boolean_result ? "true" : "false",
         " | order_check_last_error=",
            IntegerToString(report.order_check_last_error),
         " | order_check_retcode=",
            IntegerToString((long)report.order_check_retcode),
         " | order_check_comment=", report.order_check_comment,
         " | order_send_performed=",
            report.order_send_performed ? "YES" : "NO",
         " | order_send_boolean_result=",
            report.order_send_boolean_result ? "true" : "false",
         " | order_send_last_error=",
            IntegerToString(report.order_send_last_error),
         " | broker_reported_price=",
            report.broker_reported_price > 0.0
            ? DoubleToString(report.broker_reported_price, digits)
            : "UNCONFIRMED",
         " | broker_return_code=",
            IntegerToString((long)report.broker_return_code),
         " | broker_comment=", report.broker_comment,
         " | order_ticket=", StringFormat("%I64u", report.order_ticket),
         " | deal_ticket=", StringFormat("%I64u", report.deal_ticket),
         " | realised_profit_loss=",
            DoubleToString(report.final_profit_loss, 2),
         " | exit_reason_code=", report.exit_reason_code,
         " | exit_reason=", report.exit_reason,
         " | fill_confirmed=", report.fill_confirmed ? "YES" : "NO",
         " | retry_allowed=NO");
  }

int CountUnrelatedPositions(const ulong owned_magic_number)
  {
   int unrelated = 0;
   const int total = PositionsTotal();
   for(int index = 0; index < total; index++)
     {
      const ulong ticket = PositionGetTicket(index);
      if(ticket == 0 || !PositionSelectByTicket(ticket))
         continue;
      if((ulong)PositionGetInteger(POSITION_MAGIC) !=
         owned_magic_number)
         unrelated++;
     }
   return unrelated;
  }

bool ValidateConnectedDemoEnvelope(string &reason_code,
                                   string &reason)
  {
   reason_code = "";
   reason      = "";
   if((bool)MQLInfoInteger(MQL_TESTER))
     {
      reason_code = "CONNECTED_DEMO_REQUIRED";
      reason = "Strategy Tester is not permitted for this verification";
      return false;
     }

   const ENUM_ACCOUNT_TRADE_MODE account_mode =
      (ENUM_ACCOUNT_TRADE_MODE)
      AccountInfoInteger(ACCOUNT_TRADE_MODE);
   if(account_mode != ACCOUNT_TRADE_MODE_DEMO)
     {
      reason_code = "DEMO_ACCOUNT_REQUIRED";
      reason =
         "Every non-demo account is unconditionally rejected";
      return false;
     }

   if(ApprovedDemoAccount <= 0 ||
      AccountInfoInteger(ACCOUNT_LOGIN) != ApprovedDemoAccount)
     {
      reason_code = "DEMO_ACCOUNT_NOT_APPROVED";
      reason = "Exact ApprovedDemoAccount match is required";
      return false;
     }

   if(_Symbol != SOLTRADE_CLOSE_VERIFICATION_SYMBOL)
     {
      reason_code = "EURUSD_CHART_REQUIRED";
      reason = "Attach the script to an exact EURUSD chart";
      return false;
     }

   if(_Period != PERIOD_H1)
     {
      reason_code = "H1_CHART_REQUIRED";
      reason = "Attach the script to EURUSD H1";
      return false;
     }

   if(ConfirmationTimeoutSeconds < 1 ||
      ConfirmationTimeoutSeconds > 30)
     {
      reason_code = "INVALID_CONFIRMATION_TIMEOUT";
      reason = "Confirmation timeout must be between 1 and 30 seconds";
      return false;
     }
   return true;
  }

int RunFixtureCreation(const SolTradeConfig &config,
                       const SolTradeAccountStatus &account,
                       const SolTradeMarketSnapshot &market,
                       CSolTradeJournal &journal,
                       CSolTradeRiskEngine &risk_engine)
  {
   string reason = "";
   SolTradeRiskStatus risk;
   risk_engine.GetStatus(risk);

   CSolTradeExecutionEngine execution_engine;
   if(!execution_engine.Initialise(config,
                                   account.account_identifier_hash,
                                   reason))
     {
      Print("SOLTRADE_CLOSE_VERIFY_CREATE_REJECTED",
            " | reason_code=EXECUTION_ENGINE_INITIALISATION_FAILED",
            " | reason=", reason);
      return 40;
     }

   SolTradeExecutionStatus execution_status;
   execution_engine.GetStatus(execution_status);
   if(execution_status.open_soltrade_positions != 0 ||
      execution_status.active_soltrade_orders != 0 ||
      execution_status.conflicting_symbol_positions != 0)
     {
      Print("SOLTRADE_CLOSE_VERIFY_CREATE_REJECTED",
            " | reason_code=FIXTURE_REQUIRES_EMPTY_EURUSD_EXPOSURE",
            " | open_soltrade_positions=",
               execution_status.open_soltrade_positions,
            " | active_soltrade_orders=",
               execution_status.active_soltrade_orders,
            " | conflicting_symbol_positions=",
               execution_status.conflicting_symbol_positions);
      return 41;
     }

   if(FixtureDirection != SOLTRADE_SIGNAL_BUY &&
      FixtureDirection != SOLTRADE_SIGNAL_SELL)
     {
      Print("SOLTRADE_CLOSE_VERIFY_CREATE_REJECTED",
            " | reason_code=BUY_OR_SELL_REQUIRED");
      return 42;
     }

   SolTradeStrategySignal signal;
   if(!SolTradeEvaluateCurrentCompletedHistory(config, signal))
     {
      Print("SOLTRADE_CLOSE_VERIFY_CREATE_REJECTED",
            " | reason_code=STRATEGY_HISTORY_INVALID",
            " | reason=", signal.calculation_error);
      return 43;
     }

   // The test-only direction override is isolated to this script. It retains
   // the approved completed-history ATR stop and approved ExecutionEngine.
   signal.entry_signal      = FixtureDirection;
   signal.entry_reason_code = "ONE_SHOT_CLOSE_FIXTURE_CREATION";
   signal.entry_reason =
      "Test-only fixture direction using approved completed-history ATR";

   const string marker_path =
      FixtureEntryMarkerPath(account.account_identifier_hash);
   if(FileIsExist(marker_path))
     {
      Print("SOLTRADE_CLOSE_VERIFY_CREATE_ALREADY_DISABLED",
            " | marker=", marker_path,
            " | no position-creation attempt made");
      return 44;
     }

   SolTradeExecutionReport marker_report;
   ResetSolTradeExecutionReport(marker_report);
   marker_report.evaluated       = true;
   marker_report.event_type      =
      "CLOSE_FIXTURE_ENTRY_ATTEMPT_CLAIMED";
   marker_report.reason_code     =
      "CLOSE_FIXTURE_ENTRY_ARMED";
   marker_report.signal_result   =
      SolTradeEntrySignalName(signal.entry_signal);
   marker_report.signal_bar_time = signal.signal_bar_time;
   if(!WriteFixtureEntryMarker(marker_path,
                               "ATTEMPT_CLAIMED",
                               marker_report,
                               reason))
     {
      Print("SOLTRADE_CLOSE_VERIFY_CREATE_REJECTED",
            " | reason_code=FIXTURE_MARKER_FAILED",
            " | reason=", reason);
      return 45;
     }

   SolTradeExecutionReport submission;
   execution_engine.ProcessSignal(signal,
                                  account,
                                  market,
                                  risk,
                                  true,
                                  submission);
   journal.LogExecution(submission, market);
   PrintFixtureEntryReport("SOLTRADE_CLOSE_VERIFY_CREATE_ATTEMPT",
                           submission,
                           market.digits);

   SolTradeExecutionReport final_report = submission;
   int script_result = 46;
   if(submission.broker_accepted)
     {
      const uint started_at = GetTickCount();
      SolTradeExecutionReport confirmation;
      bool confirmed = false;
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
         PrintFixtureEntryReport(
            "SOLTRADE_CLOSE_VERIFY_CREATE_TRANSACTION",
            confirmation,
            market.digits);
         script_result = 0;
        }
      else
        {
         final_report = confirmation;
         journal.LogExecution(confirmation, market);
         PrintFixtureEntryReport(
            "SOLTRADE_CLOSE_VERIFY_CREATE_UNCONFIRMED",
            confirmation,
            market.digits);
         script_result = 47;
        }
     }

   bool fixture_ready = false;
   SolTradeManagedPosition position;
   ResetSolTradeManagedPosition(position);
   int magic_position_count = 0;
   if(final_report.fill_confirmed)
     {
      if(SolTradeFindBrokerManagedPosition(config,
                                           position,
                                           magic_position_count) &&
         magic_position_count == 1 &&
         position.present &&
         position.magic_number ==
            SOLTRADE_CLOSE_VERIFICATION_MAGIC &&
         position.symbol ==
            SOLTRADE_CLOSE_VERIFICATION_SYMBOL &&
         position.stop_attached)
        {
         fixture_ready = true;
        }
      else
        {
         script_result = 48;
         final_report.reason_code =
            "CONFIRMED_ENTRY_FIXTURE_INVALID";
         final_report.reason =
            "The matching entry deal did not produce exactly one protected SolTrade EURUSD position";
        }
     }

   string marker_reason = "";
   const string marker_state =
      fixture_ready
      ? "PROTECTED_FIXTURE_READY_DISABLED"
      : (final_report.fill_confirmed
         ? "ENTRY_CONFIRMED_FIXTURE_INVALID_DISABLED"
         : (submission.broker_accepted
            ? "ENTRY_ACCEPTED_UNCONFIRMED_DISABLED"
            : "ENTRY_REJECTED_DISABLED"));
   if(!WriteFixtureEntryMarker(marker_path,
                               marker_state,
                               final_report,
                               marker_reason))
     {
      Print("SOLTRADE_CLOSE_VERIFY_CREATE_MARKER_UPDATE_FAILED",
            " | reason=", marker_reason,
            " | initial permanent marker remains present");
     }

   if(final_report.fill_confirmed)
     {
      Print(fixture_ready
            ? "SOLTRADE_CLOSE_VERIFY_FIXTURE_READY"
            : "SOLTRADE_CLOSE_VERIFY_FIXTURE_INVALID",
            " | magic_position_count=", magic_position_count,
            " | position_ticket=",
               StringFormat("%I64u", position.ticket),
            " | position_identifier=",
               StringFormat("%I64u", position.identifier),
            " | direction=",
               SolTradePositionDirectionName(position.position_type),
            " | volume=", DoubleToString(position.volume, 8),
            " | stop_attached=",
               position.stop_attached ? "YES" : "NO",
            " | stop_loss=",
               DoubleToString(position.stop_loss, market.digits));
     }

   Print("SOLTRADE_CLOSE_VERIFY_CREATE_DISABLED",
         " | state=", marker_state,
         " | retry_allowed=NO",
         " | close_attempted=NO");
   return script_result;
  }

int RunPositionClose(const SolTradeConfig &config,
                     const SolTradeAccountStatus &account,
                     const SolTradeMarketSnapshot &market,
                     CSolTradeJournal &journal)
  {
   string reason = "";
   const string marker_path =
      PositionCloseMarkerPath(account.account_identifier_hash);
   if(FileIsExist(marker_path))
     {
      Print("SOLTRADE_CLOSE_VERIFY_ALREADY_DISABLED",
            " | marker=", marker_path,
            " | no close attempt made");
      return 60;
     }

   CSolTradePositionManager position_manager;
   if(!position_manager.Initialise(config,
                                   account.account_identifier_hash,
                                   reason))
     {
      Print("SOLTRADE_CLOSE_VERIFY_REJECTED",
            " | reason_code=POSITION_MANAGER_INITIALISATION_FAILED",
            " | reason=", reason);
      return 61;
     }

   SolTradePositionStatus position_status;
   position_manager.GetStatus(position_status);
   if(!position_status.state_valid ||
      position_status.magic_position_count != 1 ||
      !position_status.position_present ||
      position_status.position_magic_number !=
         SOLTRADE_CLOSE_VERIFICATION_MAGIC ||
      position_status.symbol !=
         SOLTRADE_CLOSE_VERIFICATION_SYMBOL)
     {
      Print("SOLTRADE_CLOSE_VERIFY_REJECTED",
            " | reason_code=EXACTLY_ONE_OWNED_EURUSD_POSITION_REQUIRED",
            " | magic_position_count=",
               position_status.magic_position_count,
            " | position_present=",
               position_status.position_present ? "YES" : "NO",
            " | state_error=", position_status.state_error);
      return 62;
     }

   SolTradePositionReport marker_report;
   ResetSolTradePositionReport(marker_report);
   marker_report.evaluated              = true;
   marker_report.event_type             =
      "ONE_SHOT_POSITION_CLOSE_ATTEMPT_CLAIMED";
   marker_report.reason_code            =
      "ONE_SHOT_POSITION_CLOSE_ARMED";
   marker_report.position_ticket        =
      position_status.position_ticket;
   marker_report.position_identifier    =
      position_status.position_identifier;
   marker_report.position_direction     =
      SolTradePositionDirectionName(position_status.position_type);
   marker_report.stop_attached          =
      position_status.stop_attached;
   marker_report.requested_symbol       =
      position_status.symbol;
   marker_report.requested_magic_number =
      position_status.position_magic_number;
   marker_report.volume                 =
      position_status.volume;
   marker_report.exit_reason_code       =
      "EMERGENCY_STOP_EXIT";
   marker_report.exit_reason =
      "Controlled one-shot PositionManager emergency-stop verification";
   if(!WritePositionCloseMarker(marker_path,
                                "ATTEMPT_CLAIMED",
                                marker_report,
                                reason))
     {
      Print("SOLTRADE_CLOSE_VERIFY_REJECTED",
            " | reason_code=CLOSE_MARKER_FAILED",
            " | reason=", reason);
      return 63;
     }

   const int unrelated_positions =
      CountUnrelatedPositions(config.magic_number);
   Print("SOLTRADE_CLOSE_VERIFY_OWNERSHIP_CONFIRMED",
         " | symbol=", position_status.symbol,
         " | magic=",
            StringFormat("%I64u",
                         position_status.position_magic_number),
         " | position_ticket=",
            StringFormat("%I64u", position_status.position_ticket),
         " | position_identifier=",
            StringFormat("%I64u", position_status.position_identifier),
         " | stop_attached=",
            position_status.stop_attached ? "YES" : "NO",
         " | stop_loss=",
            DoubleToString(position_status.stop_loss, market.digits),
         " | unrelated_positions_ignored=", unrelated_positions);

   if(!position_status.stop_attached)
     {
      marker_report.event_type =
         "ONE_SHOT_POSITION_CLOSE_PREFLIGHT_REJECTED";
      marker_report.reason_code =
         "INITIAL_STOP_LOSS_NOT_ATTACHED";
      marker_report.reason =
         "The owned position has no attached initial stop-loss";
      string marker_reason = "";
      WritePositionCloseMarker(marker_path,
                               "MISSING_STOP_REJECTED_DISABLED",
                               marker_report,
                               marker_reason);
      PrintPositionCloseReport(
         "SOLTRADE_CLOSE_VERIFY_REJECTED_NO_RETRY",
         marker_report,
         market.digits);
      Print("SOLTRADE_CLOSE_VERIFY_DISABLED",
            " | state=MISSING_STOP_REJECTED_DISABLED",
            " | retry_allowed=NO");
      return 64;
     }

   SolTradeStrategySignal empty_signal;
   ResetSolTradeStrategySignal(empty_signal);
   SolTradePositionReport submission;
   position_manager.ProcessClose(
      empty_signal,
      SOLTRADE_CLOSE_EMERGENCY_STOP,
      account,
      market,
      submission);
   journal.LogPositionManagement(submission, market);
   PrintPositionCloseReport("SOLTRADE_CLOSE_VERIFY_ATTEMPT",
                            submission,
                            market.digits);

   SolTradePositionReport final_report = submission;
   bool position_fully_closed = false;
   int script_result = 65;
   if(submission.broker_accepted)
     {
      const uint started_at = GetTickCount();
      SolTradePositionReport confirmation;
      bool confirmed = false;
      while((GetTickCount() - started_at) <
            (uint)(ConfirmationTimeoutSeconds * 1000))
        {
         if(position_manager.ConfirmMatchingExitDealFromHistory(
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
         string refresh_reason = "";
         const bool refresh_valid =
            position_manager.Refresh(refresh_reason);
         SolTradePositionStatus refreshed_status;
         position_manager.GetStatus(refreshed_status);
         position_fully_closed =
            refresh_valid && !refreshed_status.position_present;
         if(!position_fully_closed)
           {
            final_report.event_type =
               "MATCHING_EXIT_DEAL_CONFIRMED_POSITION_REMAINS";
            final_report.reason_code =
               "POSITION_NOT_FULLY_CLOSED_NO_RETRY";
            final_report.reason =
               "A matching exit deal exists but the owned broker position remains; no retry is allowed";
            script_result = 67;
           }
         journal.LogPositionManagement(final_report, market);
         PrintPositionCloseReport(
            "SOLTRADE_CLOSE_VERIFY_MATCHING_EXIT_TRANSACTION",
            final_report,
            market.digits);
         if(position_fully_closed)
            script_result = 0;
        }
      else
        {
         final_report = confirmation;
         journal.LogPositionManagement(confirmation, market);
         PrintPositionCloseReport(
            "SOLTRADE_CLOSE_VERIFY_TRANSACTION_UNCONFIRMED",
            confirmation,
            market.digits);
         script_result = 66;
        }
     }

   string marker_reason = "";
   const string marker_state =
      final_report.fill_confirmed && position_fully_closed
      ? "MATCHING_EXIT_CONFIRMED_DISABLED"
      : (final_report.fill_confirmed
         ? "EXIT_DEAL_CONFIRMED_POSITION_REMAINS_DISABLED"
         : (submission.broker_accepted
            ? "CLOSE_ACCEPTED_UNCONFIRMED_DISABLED"
            : "CLOSE_REJECTED_DISABLED"));
   if(!WritePositionCloseMarker(marker_path,
                                marker_state,
                                final_report,
                                marker_reason))
     {
      Print("SOLTRADE_CLOSE_VERIFY_MARKER_UPDATE_FAILED",
            " | reason=", marker_reason,
            " | initial permanent marker remains present");
     }

   Print("SOLTRADE_CLOSE_VERIFY_DISABLED",
         " | state=", marker_state,
         " | broker_return_code=",
            IntegerToString((long)
                            final_report.broker_return_code),
         " | order_ticket=",
            StringFormat("%I64u", final_report.order_ticket),
         " | deal_ticket=",
            StringFormat("%I64u", final_report.deal_ticket),
         " | retry_allowed=NO");
   return script_result;
  }

int RunArmedVerificationAction(const bool create_fixture,
                               const bool close_fixture)
  {
   string reason = "";
   SolTradeConfig config = {};
   BuildCloseVerificationConfig(create_fixture,
                                close_fixture,
                                config);
   if(!ValidateSolTradeConfig(config, reason))
     {
      Print("SOLTRADE_CLOSE_VERIFY_REJECTED",
            " | reason_code=CONFIGURATION_REJECTED",
            " | reason=", reason);
      return 13;
     }

   SolTradeAccountStatus account;
   EvaluateSolTradeAccountSafety(config, account);
   if(account.detected_environment != SOLTRADE_ENV_DEMO ||
      !account.expected_environment_matches)
     {
      Print("SOLTRADE_CLOSE_VERIFY_REJECTED",
            " | reason_code=ACCOUNT_GUARD_REJECTED",
            " | reason=", account.reason);
      return 14;
     }

   if(create_fixture &&
      !account.execution_environment_eligible)
     {
      Print("SOLTRADE_CLOSE_VERIFY_CREATE_REJECTED",
            " | reason_code=ACCOUNT_GUARD_REJECTED",
            " | reason=", account.reason);
      return 15;
     }

   CSolTradeJournal journal;
   if(!journal.Initialise(config, account, reason))
     {
      Print("SOLTRADE_CLOSE_VERIFY_REJECTED",
            " | reason_code=JOURNAL_INITIALISATION_FAILED",
            " | reason=", reason);
      return 16;
     }

   SolTradeMarketSnapshot market;
   ResetSolTradeMarketSnapshot(market);
   datetime seeded_bar = 0;
   if(!InitialiseSolTradeMarketData(config, seeded_bar, reason) ||
      !RefreshSolTradeMarketData(config, market))
     {
      const string market_reason =
         StringLen(reason) > 0 ? reason : market.reason;
      Print("SOLTRADE_CLOSE_VERIFY_REJECTED",
            " | reason_code=MARKET_DATA_INVALID",
            " | reason=", market_reason);
      journal.Shutdown();
      return 17;
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
      Print("SOLTRADE_CLOSE_VERIFY_REJECTED",
            " | reason_code=RISK_ENGINE_INITIALISATION_FAILED",
            " | reason=", reason);
      journal.Shutdown();
      return 18;
     }

   SolTradeRiskStatus risk;
   risk_engine.GetStatus(risk);
   journal.UpdateRiskStatus(risk);

   const int script_result =
      create_fixture
      ? RunFixtureCreation(config,
                           account,
                           market,
                           journal,
                           risk_engine)
      : RunPositionClose(config,
                         account,
                         market,
                         journal);
   journal.Shutdown();
   return script_result;
  }

int OnStart()
  {
   Print(SOLTRADE_CLOSE_PREFLIGHT_STARTED_EVENT,
         " | symbol=", _Symbol,
         " | timeframe=", EnumToString((ENUM_TIMEFRAMES)_Period),
         " | account_mode=",
            SolTradeEnvironmentName(DetectSolTradeEnvironment()),
         " | create_armed=",
            ConfirmCreateOneShotDemoPosition ? "YES" : "NO",
         " | close_armed=",
            ConfirmCloseOneShotDemoPosition ? "YES" : "NO");

   if(!ConfirmCreateOneShotDemoPosition &&
      !ConfirmCloseOneShotDemoPosition)
     {
      Print(SOLTRADE_CLOSE_NOT_ARMED_EVENT,
            " | no position creation or close is authorised");
      return 10;
     }

#ifdef SOLTRADE_CLOSE_VERIFIER_REQUIRE_BOTH_CONFIRMATIONS
   if(!ConfirmCreateOneShotDemoPosition ||
      !ConfirmCloseOneShotDemoPosition)
     {
      Print("SOLTRADE_CLOSE_V2_REJECTED",
            " | reason_code=BOTH_CONFIRMATIONS_REQUIRED",
            " | create and close confirmations must both be true");
      return 11;
     }
#else
   if(ConfirmCreateOneShotDemoPosition &&
      ConfirmCloseOneShotDemoPosition)
     {
      Print("SOLTRADE_CLOSE_VERIFY_REJECTED",
            " | reason_code=MUTUALLY_EXCLUSIVE_ACTION_REQUIRED",
            " | creation and closing cannot be armed together");
      return 11;
     }
#endif

   string reason_code = "";
   string reason      = "";
   if(!ValidateConnectedDemoEnvelope(reason_code, reason))
     {
      Print("SOLTRADE_CLOSE_VERIFY_REJECTED",
            " | reason_code=", reason_code,
            " | reason=", reason);
      return 12;
     }

#ifdef SOLTRADE_CLOSE_VERIFIER_REQUIRE_BOTH_CONFIRMATIONS
   const int creation_result =
      RunArmedVerificationAction(true, false);
   if(creation_result != 0)
      return creation_result;

   // Fixture creation and closing remain separate approved engine calls, but
   // V2 permits them only in this single both-confirmed run. There is no
   // second entry call and no second close call.
   return RunArmedVerificationAction(false, true);
#else
   return RunArmedVerificationAction(
      ConfirmCreateOneShotDemoPosition,
      ConfirmCloseOneShotDemoPosition);
#endif
  }
