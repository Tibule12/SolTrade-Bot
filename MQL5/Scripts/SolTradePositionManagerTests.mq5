#property copyright "SolTrade Bot"
#property link      ""
#property version   "1.000"
#property strict
#property script_show_inputs
#property description "Deterministic Phase 5 Position Manager tests"
#property description "Never submits, modifies, or closes a broker position."

#include <SolTrade/Config.mqh>
#include <SolTrade/AccountGuard.mqh>
#include <SolTrade/MarketData.mqh>
#include <SolTrade/RiskEngine.mqh>
#include <SolTrade/StrategyBreakout.mqh>
#include <SolTrade/ExecutionEngine.mqh>
#include <SolTrade/PositionManager.mqh>

int g_position_tests_passed = 0;
int g_position_tests_failed = 0;

void PositionCheckTrue(const bool condition, const string name)
  {
   if(condition)
     {
      g_position_tests_passed++;
      Print("PASS | ", name);
     }
   else
     {
      g_position_tests_failed++;
      Print("FAIL | ", name);
     }
  }

void PositionCheckText(const string actual,
                       const string expected,
                       const string name)
  {
   const bool passed = actual == expected;
   PositionCheckTrue(passed,
                     name + " | actual=" + actual +
                     " expected=" + expected);
  }

void PositionCheckNear(const double actual,
                       const double expected,
                       const double tolerance,
                       const string name)
  {
   const bool passed =
      MathIsValidNumber(actual) &&
      MathAbs(actual - expected) <= tolerance;
   PositionCheckTrue(
      passed,
      name + " | actual=" + DoubleToString(actual, 10) +
      " expected=" + DoubleToString(expected, 10));
  }

void BuildPositionTestConfig(SolTradeConfig &config)
  {
   config.strategy_version            = "1.0.0";
   config.approved_strategy_version   = "";
   config.risk_profile                = "CONSERVATIVE_V1";
   config.approved_risk_profile       = "";
   config.magic_number                = 2607250501;
   config.symbol                      = "EURUSD";
   config.timeframe                   = PERIOD_H1;
   config.minimum_history_bars        = 222;
   config.max_tick_age_seconds        = 120;
   config.max_spread_points           = 30;
   config.max_spread_atr_percent      = 10.0;
   config.max_slippage_points         = 10;
   config.risk_per_trade_percent      = 0.25;
   config.daily_loss_limit_percent    = 1.0;
   config.weekly_loss_limit_percent   = 2.5;
   config.emergency_drawdown_percent  = 5.0;
   config.production_baseline_equity  = 10000.0;
   config.consecutive_loss_limit      = 3;
   config.reset_emergency_lock        = false;
   config.expected_environment        = SOLTRADE_ENV_DEMO;
   config.enable_demo_execution       = false;
   config.enable_position_management  = true;
   config.approved_demo_account       = 424242;
   config.allow_live_trading          = false;
   config.approved_live_account       = 0;
   config.emergency_stop              = false;
   config.enable_csv_journal          = true;
   config.journal_directory =
      "SolTradeBot\\test-position-journal";
   config.risk_state_directory =
      "SolTradeBot\\test-position-risk";
   config.execution_state_directory =
      "SolTradeBot\\test-position-state\\phase5";
   config.enable_dashboard            = false;
   config.dashboard_refresh_seconds   = 1;
  }

void BuildPositionContext(SolTradePositionContext &context)
  {
   ResetSolTradePositionContext(context);
   context.detected_environment         = SOLTRADE_ENV_DEMO;
   context.expected_environment_matches = true;
   context.account_login                = 424242;
   context.terminal_connected           = true;
   context.terminal_trading_allowed     = true;
   context.program_trading_allowed      = true;
   context.account_trading_allowed      = true;
   context.account_expert_allowed       = true;
   context.market_valid                 = true;
   context.bid                          = 1.13615;
   context.ask                          = 1.13617;
   context.point                        = 0.00001;
   context.volume_min                   = 0.01;
   context.volume_max                   = 100.0;
   context.volume_step                  = 0.01;
   context.filling_mode                 = SYMBOL_FILLING_FOK;
   context.execution_mode               = SYMBOL_TRADE_EXECUTION_MARKET;
  }

void BuildManagedPosition(const SolTradeConfig &config,
                          const ENUM_POSITION_TYPE position_type,
                          const ulong identifier,
                          SolTradeManagedPosition &position)
  {
   ResetSolTradeManagedPosition(position);
   position.present       = true;
   position.ticket        = identifier + 1000;
   position.identifier    = identifier;
   position.magic_number  = config.magic_number;
   position.symbol        = config.symbol;
   position.position_type = position_type;
   position.open_time     = D'2026.07.28 10:00:00';
   position.volume        = 0.01;
   position.open_price    = 1.13617;
   position.stop_loss =
      position_type == POSITION_TYPE_BUY ? 1.13437 : 1.13797;
   position.stop_attached = true;
  }

void BuildExitSignal(const ENUM_SOLTRADE_EXIT_SIGNAL exit_signal,
                     SolTradeStrategySignal &signal)
  {
   ResetSolTradeStrategySignal(signal);
   signal.evaluated       = true;
   signal.valid           = true;
   signal.exit_signal     = exit_signal;
   signal.signal_bar_time = D'2026.07.28 11:00:00';
   if(exit_signal == SOLTRADE_EXIT_LONG)
     {
      signal.exit_reason_code = "LONG_EXIT_BREAKOUT";
      signal.exit_reason =
         "Close is strictly below the preceding 10-bar low";
     }
   else if(exit_signal == SOLTRADE_EXIT_SHORT)
     {
      signal.exit_reason_code = "SHORT_EXIT_BREAKOUT";
      signal.exit_reason =
         "Close is strictly above the preceding 10-bar high";
     }
   else
     {
      signal.exit_reason_code = "NO_EXIT_BREAKOUT";
      signal.exit_reason =
         "Close remains inside the preceding 10-bar exit channel";
     }
  }

void RunDirectionAndRequestTests()
  {
   SolTradeConfig config = {};
   BuildPositionTestConfig(config);
   string reason = "";
   PositionCheckTrue(ValidateSolTradeConfig(config, reason),
                     "CONFIG Phase 5 test configuration accepted");

   SolTradePositionContext context;
   BuildPositionContext(context);
   SolTradeManagedPosition position;
   SolTradeStrategySignal signal;
   SolTradeClosePlan plan;

   BuildManagedPosition(config, POSITION_TYPE_BUY, 7001, position);
   BuildExitSignal(SOLTRADE_EXIT_LONG, signal);
   PositionCheckTrue(
      SolTradePrepareClosePlan(config,
                               context,
                               position,
                               signal,
                               SOLTRADE_CLOSE_STRATEGY,
                               plan),
      "BUY EXIT_LONG is approved");
   PositionCheckTrue(plan.close_order_type == ORDER_TYPE_SELL,
                     "BUY close request uses SELL");
   PositionCheckNear(plan.requested_close_price,
                     context.bid,
                     1e-10,
                     "BUY requested close uses Bid");
   PositionCheckText(plan.exit_reason_code,
                     "LONG_EXIT_BREAKOUT",
                     "BUY exit reason is Donchian EXIT_LONG");
   PositionCheckTrue(plan.position_magic_number ==
                     config.magic_number,
                     "BUY close retains SolTrade magic");
   PositionCheckTrue(plan.position_ticket == position.ticket,
                     "BUY close targets exact position ticket");
   PositionCheckTrue(plan.stop_attached,
                     "BUY attached stop is verified");

   MqlTradeRequest request;
   SolTradeBuildCloseRequest(plan, request);
   PositionCheckTrue(request.action == TRADE_ACTION_DEAL,
                     "BUY close request action");
   PositionCheckTrue(request.position == position.ticket,
                     "BUY close request exact position");
   PositionCheckTrue(request.magic == config.magic_number,
                     "BUY close request exact magic");
   PositionCheckTrue(request.type == ORDER_TYPE_SELL,
                     "BUY close request opposite order type");
   PositionCheckNear(request.volume,
                     0.01,
                     1e-10,
                     "BUY close request full volume");
   PositionCheckNear(request.price,
                     context.bid,
                     1e-10,
                     "BUY close request price");

   BuildExitSignal(SOLTRADE_EXIT_SHORT, signal);
   PositionCheckTrue(
      !SolTradePrepareClosePlan(config,
                                context,
                                position,
                                signal,
                                SOLTRADE_CLOSE_STRATEGY,
                                plan),
      "BUY EXIT_SHORT is rejected");
   PositionCheckText(plan.reason_code,
                     "BUY_REQUIRES_EXIT_LONG",
                     "BUY wrong-direction rejection");

   BuildExitSignal(SOLTRADE_EXIT_NONE, signal);
   PositionCheckTrue(
      !SolTradePrepareClosePlan(config,
                                context,
                                position,
                                signal,
                                SOLTRADE_CLOSE_STRATEGY,
                                plan),
      "BUY no-exit signal is rejected");

   BuildManagedPosition(config, POSITION_TYPE_SELL, 7002, position);
   BuildExitSignal(SOLTRADE_EXIT_SHORT, signal);
   PositionCheckTrue(
      SolTradePrepareClosePlan(config,
                               context,
                               position,
                               signal,
                               SOLTRADE_CLOSE_STRATEGY,
                               plan),
      "SELL EXIT_SHORT is approved");
   PositionCheckTrue(plan.close_order_type == ORDER_TYPE_BUY,
                     "SELL close request uses BUY");
   PositionCheckNear(plan.requested_close_price,
                     context.ask,
                     1e-10,
                     "SELL requested close uses Ask");
   PositionCheckText(plan.exit_reason_code,
                     "SHORT_EXIT_BREAKOUT",
                     "SELL exit reason is Donchian EXIT_SHORT");

   BuildExitSignal(SOLTRADE_EXIT_LONG, signal);
   PositionCheckTrue(
      !SolTradePrepareClosePlan(config,
                                context,
                                position,
                                signal,
                                SOLTRADE_CLOSE_STRATEGY,
                                plan),
      "SELL EXIT_LONG is rejected");
   PositionCheckText(plan.reason_code,
                     "SELL_REQUIRES_EXIT_SHORT",
                     "SELL wrong-direction rejection");
  }

void RunOwnershipAndSafetyTests()
  {
   SolTradeConfig config = {};
   BuildPositionTestConfig(config);
   SolTradePositionContext context;
   BuildPositionContext(context);
   SolTradeManagedPosition position;
   BuildManagedPosition(config, POSITION_TYPE_BUY, 7101, position);
   SolTradeStrategySignal signal;
   BuildExitSignal(SOLTRADE_EXIT_LONG, signal);
   SolTradeClosePlan plan;

   position.magic_number = 0;
   PositionCheckTrue(
      !SolTradePrepareClosePlan(config,
                                context,
                                position,
                                signal,
                                SOLTRADE_CLOSE_STRATEGY,
                                plan),
      "MANUAL position without SolTrade magic is rejected");
   PositionCheckText(plan.reason_code,
                     "POSITION_MAGIC_MISMATCH",
                     "MANUAL position ownership reason");

   BuildManagedPosition(config, POSITION_TYPE_BUY, 7102, position);
   position.symbol = "GBPUSD";
   PositionCheckTrue(
      !SolTradePrepareClosePlan(config,
                                context,
                                position,
                                signal,
                                SOLTRADE_CLOSE_STRATEGY,
                                plan),
      "OTHER-SYMBOL SolTrade position is rejected");

   BuildManagedPosition(config, POSITION_TYPE_BUY, 7103, position);
   config.enable_position_management = false;
   PositionCheckTrue(
      !SolTradePrepareClosePlan(config,
                                context,
                                position,
                                signal,
                                SOLTRADE_CLOSE_STRATEGY,
                                plan),
      "DEFAULT-OFF position management rejects close");
   PositionCheckText(plan.reason_code,
                     "POSITION_MANAGEMENT_DISABLED",
                     "DEFAULT-OFF rejection reason");

   BuildPositionTestConfig(config);
   context.detected_environment = SOLTRADE_ENV_LIVE;
   PositionCheckTrue(
      !SolTradePrepareClosePlan(config,
                                context,
                                position,
                                signal,
                                SOLTRADE_CLOSE_STRATEGY,
                                plan),
      "REAL-ACCOUNT position close rejected");
   PositionCheckText(plan.reason_code,
                     "REAL_ACCOUNT_POSITION_MANAGEMENT_FORBIDDEN",
                     "REAL-ACCOUNT rejection reason");

   context.expected_environment_matches = false;
   context.terminal_trading_allowed      = false;
   PositionCheckTrue(
      !SolTradePrepareClosePlan(config,
                                context,
                                position,
                                signal,
                                SOLTRADE_CLOSE_STRATEGY,
                                plan),
      "REAL-ACCOUNT remains rejected before environment and Algo gates");
   PositionCheckText(plan.reason_code,
                     "REAL_ACCOUNT_POSITION_MANAGEMENT_FORBIDDEN",
                     "REAL-ACCOUNT unconditional rejection reason");

   BuildPositionContext(context);
   context.account_login = 111111;
   PositionCheckTrue(
      !SolTradePrepareClosePlan(config,
                                context,
                                position,
                                signal,
                                SOLTRADE_CLOSE_STRATEGY,
                                plan),
      "UNAPPROVED-DEMO position close rejected");

   BuildPositionContext(context);
   context.terminal_trading_allowed = false;
   PositionCheckTrue(
      !SolTradePrepareClosePlan(config,
                                context,
                                position,
                                signal,
                                SOLTRADE_CLOSE_STRATEGY,
                                plan),
      "TRADING-PERMISSION disabled close rejected");

   BuildPositionContext(context);
   context.market_valid = false;
   PositionCheckTrue(
      !SolTradePrepareClosePlan(config,
                                context,
                                position,
                                signal,
                                SOLTRADE_CLOSE_STRATEGY,
                                plan),
      "INVALID-MARKET close rejected");

   BuildPositionContext(context);
   position.volume = 0.015;
   PositionCheckTrue(
      !SolTradePrepareClosePlan(config,
                                context,
                                position,
                                signal,
                                SOLTRADE_CLOSE_STRATEGY,
                                plan),
      "INVALID-CLOSE-VOLUME rejected");

   BuildPositionTestConfig(config);
   config.allow_live_trading = true;
   string reason = "";
   PositionCheckTrue(!ValidateSolTradeConfig(config, reason),
                     "AllowLiveTrading remains impossible in Phase 6");
   PositionCheckText(reason,
                     "AllowLiveTrading must remain false through Phase 6",
                     "Phase 6 live flag rejection reason");
  }

void RunEmergencyAndProtectionTests()
  {
   SolTradeConfig config = {};
   BuildPositionTestConfig(config);
   SolTradePositionContext context;
   BuildPositionContext(context);
   SolTradeManagedPosition position;
   SolTradeStrategySignal signal;
   ResetSolTradeStrategySignal(signal);
   SolTradeClosePlan plan;

   BuildManagedPosition(config, POSITION_TYPE_BUY, 7201, position);
   PositionCheckTrue(
      SolTradePrepareClosePlan(
         config,
         context,
         position,
         signal,
         SOLTRADE_CLOSE_EMERGENCY_DRAWDOWN,
         plan),
      "EMERGENCY-DRAWDOWN closes BUY without strategy signal");
   PositionCheckText(plan.exit_reason_code,
                     "EMERGENCY_DRAWDOWN_EXIT",
                     "EMERGENCY-DRAWDOWN exit reason");

   BuildManagedPosition(config, POSITION_TYPE_SELL, 7202, position);
   PositionCheckTrue(
      SolTradePrepareClosePlan(config,
                               context,
                               position,
                               signal,
                               SOLTRADE_CLOSE_EMERGENCY_STOP,
                               plan),
      "EMERGENCY-STOP closes SELL without strategy signal");
   PositionCheckText(plan.exit_reason_code,
                     "EMERGENCY_STOP_EXIT",
                     "EMERGENCY-STOP exit reason");

   position.stop_loss     = 0.0;
   position.stop_attached = false;
   BuildExitSignal(SOLTRADE_EXIT_SHORT, signal);
   PositionCheckTrue(
      SolTradePrepareClosePlan(config,
                               context,
                               position,
                               signal,
                               SOLTRADE_CLOSE_STRATEGY,
                               plan),
      "MISSING-STOP position can still reduce risk by approved exit");
   PositionCheckTrue(!plan.stop_attached,
                     "MISSING-STOP verification is retained in plan");

   PositionCheckNear(
      SolTradeCloseSlippagePoints(POSITION_TYPE_BUY,
                                  1.13615,
                                  1.13610,
                                  0.00001),
      5.0,
      1e-8,
      "BUY close adverse slippage");
   PositionCheckNear(
      SolTradeCloseSlippagePoints(POSITION_TYPE_SELL,
                                  1.13617,
                                  1.13622,
                                  0.00001),
      5.0,
      1e-8,
      "SELL close adverse slippage");
   PositionCheckNear(
      SolTradeCloseSlippagePoints(POSITION_TYPE_BUY,
                                  1.13615,
                                  1.13620,
                                  0.00001),
      -5.0,
      1e-8,
      "BUY close favourable slippage");

   SolTradePositionReport report;
   ResetSolTradePositionReport(report);
   PositionCheckTrue(!report.retry_allowed,
                     "Close report defaults to no retry");
   PositionCheckTrue(!report.order_send_performed,
                     "Deterministic report has no broker call");
  }

void RunTransactionMatchingTests()
  {
   PositionCheckTrue(
      SolTradeExitDealMatches(DEAL_ENTRY_OUT,
                              "EURUSD",
                              "EURUSD",
                              8001,
                              8001,
                              0,
                              9001,
                              0),
      "EXIT-DEAL matching tracked position accepted");
   PositionCheckTrue(
      SolTradeExitDealMatches(DEAL_ENTRY_OUT,
                              "EURUSD",
                              "EURUSD",
                              8001,
                              0,
                              8001,
                              9002,
                              0),
      "EXIT-DEAL matching claimed position accepted");
   PositionCheckTrue(
      !SolTradeExitDealMatches(DEAL_ENTRY_IN,
                               "EURUSD",
                               "EURUSD",
                               8001,
                               8001,
                               0,
                               9003,
                               0),
      "ENTRY-DEAL is not treated as an exit");
   PositionCheckTrue(
      !SolTradeExitDealMatches(DEAL_ENTRY_OUT,
                               "GBPUSD",
                               "EURUSD",
                               8001,
                               8001,
                               0,
                               9004,
                               0),
      "UNRELATED-SYMBOL exit deal ignored");
   PositionCheckTrue(
      !SolTradeExitDealMatches(DEAL_ENTRY_OUT,
                               "EURUSD",
                               "EURUSD",
                               9999,
                               8001,
                               0,
                               9005,
                               0),
      "UNRELATED-POSITION exit deal ignored");
   PositionCheckTrue(
      !SolTradeExitDealMatches(DEAL_ENTRY_OUT,
                               "EURUSD",
                               "EURUSD",
                               8001,
                               8001,
                               0,
                               9006,
                               9006),
      "DUPLICATE exit deal ignored");
  }

void RunRestartAndDuplicateTests()
  {
   SolTradeConfig config = {};
   BuildPositionTestConfig(config);
   config.magic_number = 2607250599;
   config.execution_state_directory =
      "SolTradeBot\\test-position-state\\phase5-restart-isolated";
   const string account_hash = "PHASE5_RESTART_UNIQUE";
   const string state_path =
      SolTradePositionStatePath(config, account_hash);
   FileDelete(state_path);
   FileDelete(state_path + ".tmp");
   PositionCheckTrue(!FileIsExist(state_path),
                     "RESTART namespace starts clean");

   SolTradeManagedPosition position;
   BuildManagedPosition(config, POSITION_TYPE_BUY, 8301, position);
   string reason = "";
   CSolTradePositionManager first_manager;
   PositionCheckTrue(
      first_manager.InitialiseForTest(config,
                                      account_hash,
                                      position,
                                      1,
                                      reason),
      "RESTART first manager snapshots broker position");
   SolTradePositionStatus status;
   first_manager.GetStatus(status);
   PositionCheckTrue(!status.state_restored,
                     "RESTART first manager creates fresh state");
   PositionCheckTrue(status.position_present,
                     "RESTART first manager tracks position");
   PositionCheckTrue(status.stop_attached,
                     "RESTART first manager verifies stop");

   SolTradePositionContext context;
   BuildPositionContext(context);
   SolTradeStrategySignal signal;
   BuildExitSignal(SOLTRADE_EXIT_LONG, signal);
   SolTradeClosePlan plan;
   PositionCheckTrue(
      SolTradePrepareClosePlan(config,
                               context,
                               position,
                               signal,
                               SOLTRADE_CLOSE_STRATEGY,
                               plan),
      "RESTART close plan prepared");
   PositionCheckTrue(first_manager.ClaimCloseAttempt(plan, reason),
                     "DUPLICATE first close claim persisted");
   PositionCheckTrue(!first_manager.ClaimCloseAttempt(plan, reason),
                     "DUPLICATE second close claim rejected");

   CSolTradePositionManager restarted_manager;
   PositionCheckTrue(
      restarted_manager.InitialiseForTest(config,
                                          account_hash,
                                          position,
                                          1,
                                          reason),
      "RESTART second manager restores position state");
   restarted_manager.GetStatus(status);
   PositionCheckTrue(status.state_restored,
                     "RESTART restored flag");
   PositionCheckTrue(status.position_rebuilt,
                     "RESTART position rebuilt from broker snapshot");
   PositionCheckTrue(status.position_identifier == 8301,
                     "RESTART exact position identifier restored");
   PositionCheckTrue(status.close_attempt_claimed,
                     "RESTART consumed close attempt restored");
   PositionCheckTrue(status.claimed_position_identifier == 8301,
                     "RESTART close claim belongs to tracked position");

   SolTradeManagedPosition changed_position = position;
   changed_position.volume = 0.02;
   PositionCheckTrue(
      restarted_manager.RefreshForTest(changed_position, 1, reason),
      "MANUAL volume change remains monitorable");
   restarted_manager.GetStatus(status);
   PositionCheckTrue(status.manual_modification_detected,
                     "MANUAL volume modification detected");

   SolTradeManagedPosition unprotected = changed_position;
   unprotected.stop_loss     = 0.0;
   unprotected.stop_attached = false;
   PositionCheckTrue(
      restarted_manager.RefreshForTest(unprotected, 1, reason),
      "MISSING-STOP snapshot remains monitorable");
   restarted_manager.GetStatus(status);
   PositionCheckTrue(!status.stop_attached,
                     "MISSING-STOP detected after restart");

   SolTradeManagedPosition new_position;
   BuildManagedPosition(config, POSITION_TYPE_SELL, 8302, new_position);
   PositionCheckTrue(
      restarted_manager.RefreshForTest(new_position, 1, reason),
      "NEW-POSITION snapshot accepted");
   restarted_manager.GetStatus(status);
   PositionCheckTrue(!status.close_attempt_claimed,
                     "NEW-POSITION clears prior close claim");
   PositionCheckTrue(status.position_identifier == 8302,
                     "NEW-POSITION identifier tracked");

   PositionCheckTrue(
      !restarted_manager.RefreshForTest(new_position, 2, reason),
      "MULTIPLE SolTrade positions fail closed");
   restarted_manager.GetStatus(status);
   PositionCheckTrue(!status.state_valid,
                     "MULTIPLE position state invalid");

   FileDelete(state_path);
   FileDelete(state_path + ".tmp");
   PositionCheckTrue(!FileIsExist(state_path),
                     "RESTART isolated state cleaned");
  }

void OnStart()
  {
   Print("SolTrade Phase 5 Position Manager deterministic tests started");
   Print("This script never submits, modifies, or closes a broker position.");

   RunDirectionAndRequestTests();
   RunOwnershipAndSafetyTests();
   RunEmergencyAndProtectionTests();
   RunTransactionMatchingTests();
   RunRestartAndDuplicateTests();

   PrintFormat("SolTrade Position Manager tests complete: %d passed, %d failed",
               g_position_tests_passed,
               g_position_tests_failed);
   if(g_position_tests_failed == 0)
      Print("ALL SOLTRADE PHASE 5 POSITION MANAGER TESTS PASSED");
   else
      Print("SOLTRADE PHASE 5 POSITION MANAGER TESTS FAILED");
  }
