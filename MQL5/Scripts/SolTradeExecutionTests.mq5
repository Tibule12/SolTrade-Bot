#property copyright "SolTrade Bot"
#property link      ""
#property version   "1.000"
#property strict
#property description "Deterministic Phase 4 demo/test execution tests"
#property description "Builds requests and state fixtures only; never submits an order."

#include <SolTrade/ExecutionEngine.mqh>

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

void CheckNear(const double actual,
               const double expected,
               const double tolerance,
               const string test_name)
  {
   if(MathIsValidNumber(actual) &&
      MathAbs(actual - expected) <= tolerance)
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

void BuildExecutionTestConfig(SolTradeConfig &config)
  {
   config.strategy_version             = "1.0.0";
   config.approved_strategy_version    = "";
   config.risk_profile                 = "CONSERVATIVE_V1";
   config.approved_risk_profile        = "";
   config.magic_number                 = 2607240404;
   config.symbol                       = "EURUSD";
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
   config.production_baseline_equity   = 10000.0;
   config.consecutive_loss_limit       = 3;
   config.reset_emergency_lock         = false;
   config.expected_environment         = SOLTRADE_ENV_DEMO;
   config.enable_demo_execution        = true;
   config.approved_demo_account        = 424242;
   config.allow_live_trading           = false;
   config.approved_live_account        = 0;
   config.emergency_stop               = false;
   config.enable_csv_journal           = true;
   config.journal_directory            = "SolTradeBot\\test-logs\\phase4";
   config.risk_state_directory         = "SolTradeBot\\test-state\\phase4";
   config.execution_state_directory    =
      "SolTradeBot\\test-execution-state\\phase4";
   config.enable_dashboard             = true;
   config.dashboard_refresh_seconds    = 1;
  }

void BuildExecutionContext(SolTradeExecutionContext &context)
  {
   ResetSolTradeExecutionContext(context);
   context.detected_environment         = SOLTRADE_ENV_DEMO;
   context.expected_environment_matches = true;
   context.account_login                = 424242;
   context.terminal_connected           = true;
   context.terminal_trading_allowed     = true;
   context.program_trading_allowed      = true;
   context.account_trading_allowed      = true;
   context.account_expert_allowed       = true;
   context.market_valid                 = true;
   context.risk_locked                  = false;
   context.risk_lock_reason             = "Risk checks permit evaluation";
   context.last_consumed_signal_bar     = 0;
   context.open_soltrade_positions      = 0;
   context.active_soltrade_orders       = 0;
   context.conflicting_symbol_positions = 0;
   context.equity                       = 10000.0;
   context.free_margin                  = 9000.0;
   context.bid                          = 1.10000;
   context.ask                          = 1.10002;
   context.point                        = 0.00001;
   context.tick_size                    = 0.00001;
   context.tick_value_loss              = 1.0;
   context.volume_min                   = 0.01;
   context.volume_max                   = 100.0;
   context.volume_step                  = 0.01;
   context.digits                       = 5;
   context.spread_points                = 2;
   context.stops_level_points           = 10;
   context.order_mode                   =
      SYMBOL_ORDER_MARKET | SYMBOL_ORDER_SL;
   context.filling_mode                 = SYMBOL_FILLING_FOK;
   context.execution_mode               = SYMBOL_TRADE_EXECUTION_MARKET;
  }

void BuildEntrySignal(const ENUM_SOLTRADE_ENTRY_SIGNAL direction,
                      SolTradeStrategySignal &signal)
  {
   ResetSolTradeStrategySignal(signal);
   signal.evaluated             = true;
   signal.valid                 = true;
   signal.entry_signal          = direction;
   signal.signal_bar_time       = D'2026.07.28 10:00:00';
   signal.signal_close          =
      (direction == SOLTRADE_SIGNAL_BUY) ? 1.10100 : 1.09900;
   signal.atr_14                = 0.00100;
   signal.initial_stop_distance = 0.00200;
   signal.entry_reason_code     =
      (direction == SOLTRADE_SIGNAL_BUY)
      ? "BUY_BREAKOUT_ABOVE_EMA200"
      : "SELL_BREAKOUT_BELOW_EMA200";
   signal.entry_reason          = "Deterministic Phase 4 fixture";
  }

void RunValidDemoRequestTests()
  {
   SolTradeConfig config = {};
   BuildExecutionTestConfig(config);
   string reason = "";
   CheckTrue(ValidateSolTradeConfig(config, reason),
             "VALID-DEMO configuration accepted");

   SolTradeExecutionContext context;
   BuildExecutionContext(context);

   SolTradeStrategySignal signal;
   BuildEntrySignal(SOLTRADE_SIGNAL_BUY, signal);
   SolTradeExecutionPlan plan;
   CheckTrue(SolTradePrepareExecutionPlan(config,
                                           signal,
                                           context,
                                           plan),
             "VALID-DEMO-BUY request parameters accepted");
   CheckTrue(plan.ready_for_margin,
             "VALID-DEMO-BUY reaches margin gate");
   CheckTrue(SolTradeApplyMarginValidation(true,
                                           500.0,
                                           context.free_margin,
                                           plan),
             "VALID-DEMO-BUY margin accepted");
   CheckTrue(plan.valid,
             "VALID-DEMO-BUY request is submission-ready");
   CheckText(plan.signal_result,
             "BUY",
             "VALID-DEMO-BUY direction");
   CheckNear(plan.requested_entry,
             1.10002,
             1e-10,
             "VALID-DEMO-BUY requested Ask");
   CheckNear(plan.stop_loss,
             1.09802,
             1e-10,
             "VALID-DEMO-BUY compulsory stop-loss");
   CheckNear(plan.volume,
             0.12,
             1e-10,
             "VALID-DEMO-BUY lot-step-rounded volume");
   CheckNear(plan.risk_budget,
             25.0,
             1e-10,
             "VALID-DEMO-BUY 0.25-percent risk budget");
   CheckNear(plan.expected_risk,
             24.0,
             1e-8,
             "VALID-DEMO-BUY normalised risk");
   CheckTrue(plan.magic_number == config.magic_number,
             "VALID-DEMO-BUY SolTrade magic number");

   BuildEntrySignal(SOLTRADE_SIGNAL_SELL, signal);
   signal.signal_bar_time = D'2026.07.28 11:00:00';
   CheckTrue(SolTradePrepareExecutionPlan(config,
                                           signal,
                                           context,
                                           plan),
             "VALID-DEMO-SELL request parameters accepted");
   CheckTrue(SolTradeApplyMarginValidation(true,
                                           500.0,
                                           context.free_margin,
                                           plan),
             "VALID-DEMO-SELL margin accepted");
   CheckText(plan.signal_result,
             "SELL",
             "VALID-DEMO-SELL direction");
   CheckNear(plan.requested_entry,
             1.10000,
             1e-10,
             "VALID-DEMO-SELL requested Bid");
   CheckNear(plan.stop_loss,
             1.10200,
             1e-10,
             "VALID-DEMO-SELL compulsory stop-loss");
   CheckNear(plan.volume,
             0.12,
             1e-10,
             "VALID-DEMO-SELL lot-step-rounded volume");
   CheckNear(plan.expected_risk,
             24.0,
             1e-8,
             "VALID-DEMO-SELL normalised risk");
  }

void RunEnvironmentSafetyTests()
  {
   SolTradeConfig config = {};
   BuildExecutionTestConfig(config);
   SolTradeExecutionContext context;
   BuildExecutionContext(context);
   SolTradeStrategySignal signal;
   BuildEntrySignal(SOLTRADE_SIGNAL_BUY, signal);
   SolTradeExecutionPlan plan;

   context.detected_environment = SOLTRADE_ENV_LIVE;
   context.account_login        = 424242;
   CheckTrue(!SolTradePrepareExecutionPlan(config,
                                            signal,
                                            context,
                                            plan),
             "REAL-ACCOUNT request rejected");
   CheckText(plan.reason_code,
             "REAL_ACCOUNT_FORBIDDEN_PHASE4",
             "REAL-ACCOUNT rejection reason");

   BuildExecutionContext(context);
   context.terminal_trading_allowed = false;
   CheckTrue(!SolTradePrepareExecutionPlan(config,
                                            signal,
                                            context,
                                            plan),
             "LIVE-TRADING-DISABLED request rejected");
   CheckText(plan.reason_code,
             "TRADING_PERMISSION_DISABLED",
             "LIVE-TRADING-DISABLED rejection reason");

   BuildExecutionTestConfig(config);
   config.allow_live_trading = true;
   string reason = "";
   CheckTrue(!ValidateSolTradeConfig(config, reason),
             "AllowLiveTrading cannot be enabled through Phase 6");
   CheckText(reason,
             "AllowLiveTrading must remain false through Phase 6",
             "Phase 6 live flag rejection reason");

   BuildExecutionTestConfig(config);
   config.enable_demo_execution = false;
   BuildExecutionContext(context);
   CheckTrue(!SolTradePrepareExecutionPlan(config,
                                            signal,
                                            context,
                                            plan),
             "DEMO-DISABLED request rejected");
   CheckText(plan.reason_code,
             "DEMO_EXECUTION_DISABLED",
             "DEMO-DISABLED rejection reason");

   BuildExecutionTestConfig(config);
   BuildExecutionContext(context);
   context.account_login = 111111;
   CheckTrue(!SolTradePrepareExecutionPlan(config,
                                            signal,
                                            context,
                                            plan),
             "UNAPPROVED-DEMO request rejected");
   CheckText(plan.reason_code,
             "DEMO_ACCOUNT_NOT_APPROVED",
             "UNAPPROVED-DEMO rejection reason");

   BuildExecutionTestConfig(config);
   config.expected_environment = SOLTRADE_ENV_BACKTEST;
   config.enable_demo_execution = false;
   config.approved_demo_account = 0;
   config.enable_backtest_research = true;
   config.enable_backtest_execution = true;
   config.enable_backtest_position_management = true;
   config.research_start_inclusive =
      D'2026.07.28 00:00:00';
   config.research_end_exclusive =
      D'2026.07.29 00:00:00';
   BuildExecutionContext(context);
   context.detected_environment         = SOLTRADE_ENV_BACKTEST;
   context.expected_environment_matches = true;
   context.account_login                = 0;
   CheckTrue(SolTradePrepareExecutionPlan(config,
                                           signal,
                                           context,
                                           plan),
             "STRATEGY-TESTER request accepted without demo login");
  }

void RunValidationRejectionTests()
  {
   SolTradeConfig config = {};
   BuildExecutionTestConfig(config);
   SolTradeExecutionContext context;
   BuildExecutionContext(context);
   SolTradeStrategySignal signal;
   BuildEntrySignal(SOLTRADE_SIGNAL_BUY, signal);
   SolTradeExecutionPlan plan;
   string reason = "";

   CheckTrue(!SolTradeValidateOrderVolume(0.015,
                                          0.01,
                                          100.0,
                                          0.01,
                                          reason),
             "INVALID-VOLUME off-step lot rejected");
   CheckText(reason,
             "Volume is not aligned to the broker lot step",
             "INVALID-VOLUME rejection reason");

   BuildExecutionContext(context);
   context.volume_step = 0.0;
   CheckTrue(!SolTradePrepareExecutionPlan(config,
                                            signal,
                                            context,
                                            plan),
             "INVALID-VOLUME broker metadata rejected");
   CheckText(plan.reason_code,
             "POSITION_SIZE_REJECTED",
             "INVALID-VOLUME broker metadata reason code");

   BuildExecutionContext(context);
   context.stops_level_points = 300;
   CheckTrue(!SolTradePrepareExecutionPlan(config,
                                            signal,
                                            context,
                                            plan),
             "INVALID-STOP-DISTANCE rejected");
   CheckText(plan.reason_code,
             "STOP_DISTANCE_REJECTED",
             "INVALID-STOP-DISTANCE reason code");

   BuildExecutionContext(context);
   CheckTrue(SolTradePrepareExecutionPlan(config,
                                           signal,
                                           context,
                                           plan),
             "INSUFFICIENT-MARGIN reaches margin gate");
   CheckTrue(!SolTradeApplyMarginValidation(true,
                                            9500.0,
                                            9000.0,
                                            plan),
             "INSUFFICIENT-MARGIN rejected");
   CheckText(plan.reason_code,
             "INSUFFICIENT_MARGIN",
             "INSUFFICIENT-MARGIN reason code");

   BuildExecutionContext(context);
   context.spread_points = 31;
   CheckTrue(!SolTradePrepareExecutionPlan(config,
                                            signal,
                                            context,
                                            plan),
             "EXCESSIVE-SPREAD absolute limit rejected");
   CheckText(plan.reason_code,
             "SPREAD_REJECTED",
             "EXCESSIVE-SPREAD absolute reason code");

   BuildExecutionContext(context);
   context.spread_points = 11;
   CheckTrue(!SolTradePrepareExecutionPlan(config,
                                            signal,
                                            context,
                                            plan),
             "EXCESSIVE-SPREAD ATR-relative limit rejected");
   CheckText(plan.reason_code,
             "SPREAD_REJECTED",
             "EXCESSIVE-SPREAD ATR-relative reason code");

   BuildExecutionContext(context);
   context.last_consumed_signal_bar = signal.signal_bar_time;
   CheckTrue(!SolTradePrepareExecutionPlan(config,
                                            signal,
                                            context,
                                            plan),
             "DUPLICATE-CANDLE request rejected");
   CheckText(plan.reason_code,
             "DUPLICATE_SIGNAL_CANDLE",
             "DUPLICATE-CANDLE reason code");

   BuildExecutionContext(context);
   context.open_soltrade_positions = 1;
   CheckTrue(!SolTradePrepareExecutionPlan(config,
                                            signal,
                                            context,
                                            plan),
             "EXISTING-POSITION request rejected");
   CheckText(plan.reason_code,
             "EXISTING_SOLTRADE_POSITION",
             "EXISTING-POSITION reason code");
  }

void RunBrokerResultTests()
  {
   CheckTrue(SolTradeBrokerRetcodeAccepted(TRADE_RETCODE_DONE),
             "BROKER-DONE accepted for transaction confirmation");
   CheckTrue(SolTradeBrokerRetcodeAccepted(TRADE_RETCODE_DONE_PARTIAL),
             "BROKER-DONE-PARTIAL accepted for transaction confirmation");
   CheckTrue(SolTradeBrokerRetcodeAccepted(TRADE_RETCODE_PLACED),
             "BROKER-PLACED accepted for transaction confirmation");
   CheckTrue(!SolTradeBrokerRetcodeAccepted(TRADE_RETCODE_REJECT),
             "BROKER-REJECT classified as rejection");
   CheckTrue(!SolTradeBrokerRetcodeAccepted(TRADE_RETCODE_INVALID_STOPS),
             "BROKER-INVALID-STOPS classified as rejection");
   CheckTrue(!SolTradeBrokerRetcodeAccepted(TRADE_RETCODE_NO_MONEY),
             "BROKER-NO-MONEY classified as rejection");
   CheckTrue(!SolTradeBrokerRetcodeAccepted(
                TRADE_RETCODE_TOO_MANY_REQUESTS),
             "BROKER-TOO-MANY-REQUESTS classified without retry");

   SolTradeExecutionReport report;
   ResetSolTradeExecutionReport(report);
   CheckTrue(!report.retry_allowed,
             "BROKER rejection report defaults to no retry");
   CheckText(SolTradeBrokerRetcodeName(TRADE_RETCODE_REJECT),
             "REJECT",
             "BROKER rejection structured name");
  }

void RunRestartStateTests()
  {
   SolTradeConfig config = {};
   BuildExecutionTestConfig(config);
   config.execution_state_directory =
      "SolTradeBot\\test-execution-state\\phase4-restart-isolated";
   config.magic_number = 2607240499;
   const string account_hash = "PHASE4_RESTART_UNIQUE";
   const string state_path =
      SolTradeExecutionStatePath(config, account_hash);
   FileDelete(state_path);
   FileDelete(state_path + ".tmp");
   CheckTrue(!FileIsExist(state_path),
             "RESTART state namespace starts clean");

   string reason = "";
   CSolTradeExecutionEngine first_engine;
   CheckTrue(first_engine.Initialise(config,
                                     account_hash,
                                     reason),
             "RESTART first engine initialises");
   SolTradeExecutionStatus status;
   first_engine.GetStatus(status);
   CheckTrue(!status.state_restored,
             "RESTART first engine creates fresh state");
   CheckTrue(status.last_consumed_signal_bar == 0,
             "RESTART fresh duplicate cache is empty");

   SolTradeExecutionContext context;
   BuildExecutionContext(context);
   SolTradeStrategySignal signal;
   BuildEntrySignal(SOLTRADE_SIGNAL_BUY, signal);
   SolTradeExecutionPlan plan;
   CheckTrue(SolTradePrepareExecutionPlan(config,
                                           signal,
                                           context,
                                           plan),
             "RESTART fixture reaches margin gate");
   CheckTrue(SolTradeApplyMarginValidation(true,
                                           500.0,
                                           context.free_margin,
                                           plan),
             "RESTART fixture margin accepted");
   CheckTrue(first_engine.ClaimExecutionAttempt(plan, reason),
             "RESTART completed candle claimed atomically");
   CheckTrue(!first_engine.ClaimExecutionAttempt(plan, reason),
             "RESTART duplicate claim rejected before broker call");

   CSolTradeExecutionEngine restarted_engine;
   CheckTrue(restarted_engine.Initialise(config,
                                         account_hash,
                                         reason),
             "RESTART second engine restores state");
   restarted_engine.GetStatus(status);
   CheckTrue(status.state_restored,
             "RESTART persistent state restoration confirmed");
   CheckTrue(status.last_consumed_signal_bar == signal.signal_bar_time,
             "RESTART consumed candle restored");
   CheckText(status.last_direction,
             "BUY",
             "RESTART request direction restored");
   CheckNear(status.last_requested_entry,
             1.10002,
             1e-10,
             "RESTART requested entry restored");
   CheckNear(status.last_stop_loss,
             1.09802,
             1e-10,
             "RESTART compulsory stop restored");
   CheckNear(status.last_volume,
             0.12,
             1e-10,
             "RESTART lot size restored");

   context.last_consumed_signal_bar =
      status.last_consumed_signal_bar;
   CheckTrue(!SolTradePrepareExecutionPlan(config,
                                            signal,
                                            context,
                                            plan),
             "RESTART restored candle cannot resubmit");
   CheckText(plan.reason_code,
             "DUPLICATE_SIGNAL_CANDLE",
             "RESTART duplicate protection reason");

   FileDelete(state_path);
   FileDelete(state_path + ".tmp");
   CheckTrue(!FileIsExist(state_path),
             "RESTART isolated state cleaned after test");
  }

void OnStart()
  {
   RunValidDemoRequestTests();
   RunEnvironmentSafetyTests();
   RunValidationRejectionTests();
   RunBrokerResultTests();
   RunRestartStateTests();

   PrintFormat("SolTrade Execution tests complete: %d passed, %d failed",
               g_tests_passed,
               g_tests_failed);
   if(g_tests_failed == 0)
      Print("ALL SOLTRADE PHASE 4 EXECUTION TESTS PASSED");
   else
      Print("SOLTRADE PHASE 4 EXECUTION TESTS FAILED");
  }
