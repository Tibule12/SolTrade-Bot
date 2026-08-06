#property copyright "SolTrade Bot"
#property link      ""
#property version   "1.000"
#property strict
#property description "Deterministic Phase 6 tester-gate and reporting safety tests"
#property description "Pure fixtures only; never starts a tester run or calls a broker."

#include <SolTrade/BacktestResearch.mqh>

int g_phase6_passed = 0;
int g_phase6_failed = 0;

bool Phase6ProductionEaDetached()
  {
   long chart_id = ChartFirst();
   while(chart_id >= 0)
     {
      const string expert_name =
         ChartGetString(chart_id, CHART_EXPERT_NAME);
      if(StringFind(expert_name, "SolTradeBot") >= 0)
         return false;
      chart_id = ChartNext(chart_id);
     }
   return true;
  }

void Phase6Check(const bool condition, const string name)
  {
   if(condition)
     {
      g_phase6_passed++;
      Print("PASS: ", name);
     }
   else
     {
      g_phase6_failed++;
      Print("FAIL: ", name);
     }
  }

void Phase6CheckText(const string actual,
                     const string expected,
                     const string name)
  {
   const bool condition = (actual == expected);
   Phase6Check(condition, name);
   if(!condition)
      Print("  actual=", actual, " expected=", expected);
  }

void Phase6CheckNear(const double actual,
                     const double expected,
                     const double tolerance,
                     const string name)
  {
   const bool condition =
      MathIsValidNumber(actual) &&
      MathAbs(actual - expected) <= tolerance;
   Phase6Check(condition, name);
   if(!condition)
      PrintFormat("  actual=%.10f expected=%.10f",
                  actual,
                  expected);
  }

void BuildPhase6Config(SolTradeConfig &config)
  {
   ZeroMemory(config);
   config.strategy_version             = "1.0.0";
   config.approved_strategy_version    = "";
   config.risk_profile                 = "CONSERVATIVE_V1";
   config.approved_risk_profile        = "";
   config.magic_number                 = 2607202601;
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
   config.expected_environment         = SOLTRADE_ENV_BACKTEST;
   config.enable_demo_execution        = false;
   config.enable_position_management   = false;
   config.approved_demo_account        = 0;
   config.allow_live_trading           = false;
   config.approved_live_account        = 0;
   config.emergency_stop               = false;
   config.enable_backtest_research     = true;
   config.enable_backtest_execution    = true;
   config.enable_backtest_position_management = true;
   config.research_manifest_id         = "PHASE6-PROPOSED-V1";
   config.execution_instance_id        = "AUTH-DEV-NORMAL";
   config.research_dataset             =
      SOLTRADE_DATASET_DEVELOPMENT;
   config.research_cost_profile        =
      SOLTRADE_COST_NORMAL;
   config.research_start_inclusive     =
      D'2024.01.01 00:00:00';
   config.research_end_exclusive       =
      D'2025.04.01 00:00:00';
   config.research_history_fingerprint =
      "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa";
   config.research_latency_fingerprint =
      "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb";
   config.research_latency_sample_count = 30;
   config.research_frozen_delay_ms       = 200;
   config.research_source_commit =
      "2ef739517d7cbb503bc95b99f0865945190c5823";
   config.research_build_fingerprint =
      "cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc";
   config.research_expected_terminal_build = 6067;
   config.research_expected_broker_server = "easyMarkets-Live";
   config.research_expected_initial_deposit = 10000.0;
   config.research_expected_deposit_currency = "USD";
   config.research_expected_leverage = 200;
   config.research_expected_trading_input_hash =
      "dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd";
   config.research_state_root =
      "SolTradeBot\\phase6-test-state";
   config.research_artifact_root =
      "SolTradeBot\\phase6-test-artifacts";
   config.enable_csv_journal = true;
   config.journal_directory =
      "SolTradeBot\\phase6-test-journal";
   config.risk_state_directory =
      "SolTradeBot\\phase6-test-risk";
   config.execution_state_directory =
      "SolTradeBot\\phase6-test-execution";
   config.enable_dashboard = false;
   config.dashboard_refresh_seconds = 1;

   string material = "";
   string trading_hash = "";
   string reason = "";
   if(SolTradeCalculateTradingInputHash(
         config,
         material,
         trading_hash,
         reason))
      config.research_expected_trading_input_hash =
         trading_hash;
  }

void BuildPhase6ExecutionContext(SolTradeExecutionContext &context)
  {
   ResetSolTradeExecutionContext(context);
   context.detected_environment = SOLTRADE_ENV_BACKTEST;
   context.expected_environment_matches = true;
   context.terminal_connected = false;
   context.terminal_trading_allowed = true;
   context.program_trading_allowed = true;
   context.account_trading_allowed = true;
   context.account_expert_allowed = true;
   context.market_valid = true;
   context.risk_locked = false;
   context.equity = 10000.0;
   context.free_margin = 9000.0;
   context.bid = 1.10000;
   context.ask = 1.10002;
   context.point = 0.00001;
   context.tick_size = 0.00001;
   context.tick_value_loss = 1.0;
   context.volume_min = 0.01;
   context.volume_max = 100.0;
   context.volume_step = 0.01;
   context.digits = 5;
   context.spread_points = 2;
   context.stops_level_points = 10;
   context.order_mode = SYMBOL_ORDER_MARKET | SYMBOL_ORDER_SL;
   context.filling_mode = SYMBOL_FILLING_FOK;
   context.execution_mode = SYMBOL_TRADE_EXECUTION_MARKET;
  }

void BuildPhase6Signal(SolTradeStrategySignal &signal)
  {
   ResetSolTradeStrategySignal(signal);
   signal.evaluated = true;
   signal.valid = true;
   signal.entry_signal = SOLTRADE_SIGNAL_BUY;
   signal.signal_bar_time = D'2024.06.01 12:00:00';
   signal.signal_close = 1.10100;
   signal.atr_14 = 0.00100;
   signal.initial_stop_distance = 0.00200;
   signal.entry_reason_code = "BUY_BREAKOUT_ABOVE_EMA200";
   signal.entry_reason = "Phase 6 deterministic fixture";
  }

void RunHashAndIsolationTests()
  {
   string digest = "";
   string reason = "";
   Phase6Check(SolTradeSha256Hex("abc", digest, reason),
               "SHA-256 calculation succeeds");
   Phase6CheckText(
      digest,
      "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad",
      "SHA-256 known vector");

   SolTradeConfig authoritative;
   BuildPhase6Config(authoritative);
   string authoritative_material = "";
   string authoritative_hash = "";
   Phase6Check(
      SolTradeCalculateTradingInputHash(
         authoritative,
         authoritative_material,
         authoritative_hash,
         reason),
      "Authoritative trading-input hash calculated");
   Phase6CheckText(
      authoritative_hash,
      "c4647a6ab2d2a532de5a52b47c27f399872766e8ce8fdb80bb8fde75d178750c",
      "MQL canonical hash matches independent manifest generator");
   Phase6Check(
      StringFind(authoritative_material,
                 "tester_tick_model=EVERY_TICK_BASED_ON_REAL_TICKS\n") >= 0 &&
      StringFind(authoritative_material,
                 "tester_execution_delay_mode=FIXED\n") >= 0 &&
      StringFind(authoritative_material,
                 "risk_state_schema=SOLTRADE_RISK_STATE_V1\n") >= 0,
      "Canonical material freezes tick model, delay mode, and actual schemas");

   SolTradeConfig replica = authoritative;
   replica.execution_instance_id = "REPLICA-DEV-NORMAL";
   string replica_material = "";
   string replica_hash = "";
   Phase6Check(
      SolTradeCalculateTradingInputHash(
         replica,
         replica_material,
         replica_hash,
         reason),
      "Replica trading-input hash calculated");
   Phase6CheckText(replica_hash,
                   authoritative_hash,
                   "ExecutionInstanceId excluded from trading-input hash");
   Phase6CheckText(replica_material,
                   authoritative_material,
                   "Canonical trading inputs ignore instance identity");
   Phase6Check(
      StringFind(authoritative_material,
                 authoritative.execution_instance_id) < 0,
      "Canonical material contains no authoritative instance ID");
   Phase6Check(
      StringFind(replica_material,
                 replica.execution_instance_id) < 0,
      "Canonical material contains no replica instance ID");

   SolTradeConfig changed_risk = authoritative;
   changed_risk.risk_per_trade_percent = 0.30;
   string changed_material = "";
   string changed_hash = "";
   SolTradeCalculateTradingInputHash(
      changed_risk,
      changed_material,
      changed_hash,
      reason);
   Phase6Check(changed_hash != authoritative_hash,
               "Trading risk change changes canonical hash");

   SolTradeConfig changed_cost = authoritative;
   changed_cost.research_cost_profile = SOLTRADE_COST_HIGH;
   SolTradeCalculateTradingInputHash(
      changed_cost,
      changed_material,
      changed_hash,
      reason);
   Phase6Check(changed_hash != authoritative_hash,
               "Cost profile change changes canonical hash");

   SolTradeApplyResearchIsolation(authoritative,
                                  authoritative_hash);
   SolTradeApplyResearchIsolation(replica,
                                  replica_hash);
   Phase6Check(
      authoritative.risk_state_directory !=
         replica.risk_state_directory,
      "Authoritative and replica risk state are isolated");
   Phase6Check(
      authoritative.execution_state_directory !=
         replica.execution_state_directory,
      "Authoritative and replica execution state are isolated");
   Phase6Check(
      authoritative.journal_directory !=
         replica.journal_directory,
      "Authoritative and replica artifacts are isolated");
   Phase6Check(
      StringFind(authoritative.risk_state_directory,
                 authoritative_hash) >= 0,
      "State path contains canonical trading-input hash");
  }

void RunConfigurationAndRuntimeGateTests()
  {
   SolTradeConfig config;
   BuildPhase6Config(config);
   string reason = "";
   Phase6Check(ValidateSolTradeConfig(config, reason),
               "Valid Phase 6 configuration accepted");

   SolTradeConfig disabled = config;
   disabled.enable_backtest_research = false;
   Phase6Check(!ValidateSolTradeConfig(disabled, reason),
               "Backtest capabilities cannot remain armed when research is disabled");

   SolTradeConfig partial = config;
   partial.enable_backtest_position_management = false;
   Phase6Check(!ValidateSolTradeConfig(partial, reason),
               "Tester execution and management must be armed together");

   SolTradeConfig demo_leak = config;
   demo_leak.enable_demo_execution = true;
   demo_leak.approved_demo_account = 123456;
   Phase6Check(!ValidateSolTradeConfig(demo_leak, reason),
               "Phase 6 configuration rejects demo automation");

   SolTradeConfig live_leak = config;
   live_leak.allow_live_trading = true;
   Phase6Check(!ValidateSolTradeConfig(live_leak, reason),
               "Phase 6 configuration rejects live trading");

   SolTradeConfig bad_samples = config;
   bad_samples.research_latency_sample_count = 29;
   Phase6Check(!ValidateSolTradeConfig(bad_samples, reason),
               "Fewer than 30 latency samples rejected");

   SolTradeConfig bad_delay = config;
   bad_delay.research_frozen_delay_ms = 225;
   Phase6Check(!ValidateSolTradeConfig(bad_delay, reason),
               "Frozen D must align upward to 50 milliseconds");

   Phase6Check(
      SolTradeValidateResearchRuntime(
         config,
         true,
         SOLTRADE_ENV_BACKTEST,
         6067,
         "easyMarkets-Live",
         10000.0,
         "USD",
         200,
         reason),
      "Exact frozen tester runtime accepted");
   Phase6Check(
      !SolTradeValidateResearchRuntime(
         config,
         false,
         SOLTRADE_ENV_DEMO,
         6067,
         "easyMarkets-Live",
         10000.0,
         "USD",
         200,
         reason),
      "Connected demo cannot satisfy tester runtime gate");
   Phase6Check(
      !SolTradeValidateResearchRuntime(
         config,
         true,
         SOLTRADE_ENV_BACKTEST,
         6068,
         "easyMarkets-Live",
         10000.0,
         "USD",
         200,
         reason),
      "Terminal build mismatch rejected");
  }

void RunInstanceNonTradingTests()
  {
   SolTradeConfig authoritative;
   BuildPhase6Config(authoritative);
   SolTradeConfig replica = authoritative;
   replica.execution_instance_id = "REPLICA-DEV-NORMAL";

   SolTradeExecutionContext context;
   BuildPhase6ExecutionContext(context);
   SolTradeStrategySignal signal;
   BuildPhase6Signal(signal);
   SolTradeExecutionPlan authoritative_plan;
   SolTradeExecutionPlan replica_plan;

   Phase6Check(
      SolTradePrepareExecutionPlan(authoritative,
                                   signal,
                                   context,
                                   authoritative_plan),
      "Authoritative pure execution plan accepted");
   Phase6Check(
      SolTradePrepareExecutionPlan(replica,
                                   signal,
                                   context,
                                   replica_plan),
      "Replica pure execution plan accepted");
   Phase6CheckText(replica_plan.signal_result,
                   authoritative_plan.signal_result,
                   "Instance ID cannot change signal direction");
   Phase6CheckNear(replica_plan.volume,
                   authoritative_plan.volume,
                   1e-12,
                   "Instance ID cannot change position size");
   Phase6CheckNear(replica_plan.requested_entry,
                   authoritative_plan.requested_entry,
                   1e-12,
                   "Instance ID cannot change requested entry");
   Phase6CheckNear(replica_plan.stop_loss,
                   authoritative_plan.stop_loss,
                   1e-12,
                   "Instance ID cannot change stop-loss");
   Phase6Check(
      replica_plan.magic_number ==
         authoritative_plan.magic_number,
      "Instance ID cannot change magic number");

   authoritative.enable_backtest_research = false;
   SolTradeExecutionPlan disabled_plan;
   Phase6Check(
      !SolTradePrepareExecutionPlan(authoritative,
                                    signal,
                                    context,
                                    disabled_plan),
      "Default-off tester gate rejects execution");
   Phase6CheckText(disabled_plan.reason_code,
                   "BACKTEST_RESEARCH_DISABLED",
                   "Default-off tester rejection reason");

   BuildPhase6Config(authoritative);
   signal.signal_bar_time =
      authoritative.research_start_inclusive - 3600;
   Phase6Check(
      !SolTradePrepareExecutionPlan(authoritative,
                                    signal,
                                    context,
                                    disabled_plan),
      "Warm-up-period signal rejected");
   Phase6CheckText(disabled_plan.reason_code,
                   "BACKTEST_SIGNAL_OUTSIDE_DATASET",
                   "Warm-up-period rejection reason");
  }

void BuildMetricTrades(const int count,
                       SolTradeResearchTrade &trades[])
  {
   ArrayResize(trades, count);
   for(int index = 0; index < count; index++)
     {
      ResetSolTradeResearchTrade(trades[index]);
      trades[index].position_identifier = (ulong)(index + 1);
      // Spread the fixture across the registered subperiod buckets so the
      // sample-size assertion tests the 50-trade gate, not concentration.
      trades[index].entry_time =
         D'2026.01.01 00:00:00' + (index * 86400);
      trades[index].exit_time =
         trades[index].entry_time + 3600;
      trades[index].native_trade_net = 10.0;
      trades[index].native_friction = 2.0;
      trades[index].naturally_closed = true;
      string reason = "";
      SolTradeApplySupplementaryCashFlow(
         trades[index],
         0.0,
         reason);
     }
  }

void RunCashFlowAndMetricTests()
  {
   Phase6CheckNear(
      SolTradeSupplementaryCostMultiplier(SOLTRADE_COST_NORMAL),
      0.0,
      1e-12,
      "Normal supplementary multiplier");
   Phase6CheckNear(
      SolTradeSupplementaryCostMultiplier(SOLTRADE_COST_HIGH),
      0.50,
      1e-12,
      "High supplementary multiplier");
   Phase6CheckNear(
      SolTradeSupplementaryCostMultiplier(SOLTRADE_COST_STRESS),
      1.00,
      1e-12,
      "Stress supplementary multiplier");
   Phase6CheckNear(
      SolTradeAdjustedTradeNet(100.0, 20.0, 0.0),
      100.0,
      1e-12,
      "Normal adjusted trade does not subtract native friction twice");
   Phase6CheckNear(
      SolTradeAdjustedTradeNet(100.0, 20.0, 0.50),
      90.0,
      1e-12,
      "High adjusted trade subtracts half native friction");
   Phase6CheckNear(
      SolTradeAdjustedTradeNet(100.0, 20.0, 1.00),
      80.0,
      1e-12,
      "Stress adjusted trade subtracts one native friction");

   SolTradeResearchTrade cashflows[];
   ArrayResize(cashflows, 4);
   const double native_net[4] = {100.0, -50.0, 75.0, -25.0};
   for(int index = 0; index < 4; index++)
     {
      ResetSolTradeResearchTrade(cashflows[index]);
      cashflows[index].position_identifier = (ulong)(index + 1);
      cashflows[index].entry_time =
         D'2026.01.01 00:00:00' + (index * 86400);
      cashflows[index].exit_time =
         cashflows[index].entry_time + 3600;
      cashflows[index].native_trade_net = native_net[index];
      cashflows[index].native_friction = 10.0;
      cashflows[index].naturally_closed = true;
      string reason = "";
      Phase6Check(
         SolTradeApplySupplementaryCashFlow(
            cashflows[index],
            0.50,
            reason),
         "Chronological cash-flow adjustment accepted " +
            IntegerToString(index + 1));
     }

   SolTradeResearchMetrics metrics;
   Phase6Check(
      SolTradeCalculateResearchMetrics(
         cashflows,
         10000.0,
         D'2026.01.01 00:00:00',
         D'2026.02.01 00:00:00',
         metrics),
      "Adjusted chronological metrics calculated");
   Phase6CheckNear(metrics.net_profit,
                   80.0,
                   1e-10,
                   "Adjusted net rebuilt from trade cash flows");
   Phase6CheckNear(metrics.gross_profit,
                   165.0,
                   1e-10,
                   "Adjusted gross profit rebuilt");
   Phase6CheckNear(metrics.gross_loss,
                   85.0,
                   1e-10,
                   "Adjusted gross loss rebuilt");
   Phase6CheckNear(metrics.expectancy,
                   20.0,
                   1e-10,
                   "Adjusted expectancy rebuilt");
   Phase6CheckNear(metrics.profit_factor,
                   165.0 / 85.0,
                   1e-10,
                   "Adjusted profit factor rebuilt");
   Phase6CheckNear(metrics.ending_equity,
                   10080.0,
                   1e-10,
                   "Adjusted equity curve rebuilt");

   SolTradeResearchTrade fifty_trades[];
   BuildMetricTrades(50, fifty_trades);
   Phase6Check(
      SolTradeCalculateResearchMetrics(
         fifty_trades,
         10000.0,
         D'2026.01.01 00:00:00',
         D'2026.03.01 00:00:00',
         metrics),
      "Fifty-trade OOS metrics calculated");
   Phase6CheckText(
      SolTradeResearchAcceptanceLabel(
         SOLTRADE_DATASET_OUT_OF_SAMPLE,
         SOLTRADE_COST_NORMAL,
         metrics),
      "PASS",
      "Fifty closed OOS trades can pass sample gate");

   SolTradeResearchTrade forty_nine_trades[];
   BuildMetricTrades(49, forty_nine_trades);
   SolTradeCalculateResearchMetrics(
      forty_nine_trades,
      10000.0,
      D'2026.01.01 00:00:00',
      D'2026.03.01 00:00:00',
      metrics);
   Phase6CheckText(
      SolTradeResearchAcceptanceLabel(
         SOLTRADE_DATASET_OUT_OF_SAMPLE,
         SOLTRADE_COST_NORMAL,
         metrics),
      "INCONCLUSIVE_INSUFFICIENT_SAMPLE",
      "Forty-nine closed OOS trades cannot pass");

   SolTradeResearchMetrics boundary_metrics;
   ResetSolTradeResearchMetrics(boundary_metrics);
   boundary_metrics.valid = true;
   boundary_metrics.closed_trades = 50;
   boundary_metrics.net_profit = 100.0;
   boundary_metrics.expectancy = 2.0;
   boundary_metrics.profit_factor = 1.15;
   boundary_metrics.maximum_equity_drawdown_percent = 7.99;
   boundary_metrics.best_trade_contribution_percent = 20.0;
   boundary_metrics.best_period_contribution_percent = 40.0;
   Phase6CheckText(
      SolTradeResearchAcceptanceLabel(
         SOLTRADE_DATASET_OUT_OF_SAMPLE,
         SOLTRADE_COST_NORMAL,
         boundary_metrics),
      "RESEARCH_REJECTED",
      "Normal profit factor must be strictly above 1.15");

   boundary_metrics.profit_factor = 1.1500001;
   boundary_metrics.maximum_equity_drawdown_percent = 8.0;
   Phase6CheckText(
      SolTradeResearchAcceptanceLabel(
         SOLTRADE_DATASET_OUT_OF_SAMPLE,
         SOLTRADE_COST_NORMAL,
         boundary_metrics),
      "RESEARCH_REJECTED",
      "Normal drawdown must be strictly below 8 percent");

   boundary_metrics.profit_factor = 1.05;
   boundary_metrics.maximum_equity_drawdown_percent = 10.0;
   Phase6CheckText(
      SolTradeResearchAcceptanceLabel(
         SOLTRADE_DATASET_OUT_OF_SAMPLE,
         SOLTRADE_COST_HIGH,
         boundary_metrics),
      "PASS",
      "High-cost exact registered thresholds pass");

   boundary_metrics.profit_factor = 1.00;
   boundary_metrics.maximum_equity_drawdown_percent = 12.0;
   Phase6CheckText(
      SolTradeResearchAcceptanceLabel(
         SOLTRADE_DATASET_OUT_OF_SAMPLE,
         SOLTRADE_COST_STRESS,
         boundary_metrics),
      "PASS",
      "Stress-cost exact registered thresholds pass");

   boundary_metrics.best_trade_contribution_percent = 20.0001;
   Phase6CheckText(
      SolTradeResearchAcceptanceLabel(
         SOLTRADE_DATASET_OUT_OF_SAMPLE,
         SOLTRADE_COST_STRESS,
         boundary_metrics),
      "RESEARCH_REJECTED",
      "Best trade above 20 percent concentration is rejected");
   boundary_metrics.best_trade_contribution_percent = 20.0;
   boundary_metrics.best_period_contribution_percent = 40.0001;
   Phase6CheckText(
      SolTradeResearchAcceptanceLabel(
         SOLTRADE_DATASET_OUT_OF_SAMPLE,
         SOLTRADE_COST_STRESS,
         boundary_metrics),
      "RESEARCH_REJECTED",
      "Best period above 40 percent concentration is rejected");
  }

void RunConsistencyTests()
  {
   SolTradeResearchMetrics development;
   SolTradeResearchMetrics validation;
   SolTradeResearchMetrics out_of_sample;
   ResetSolTradeResearchMetrics(development);
   ResetSolTradeResearchMetrics(validation);
   ResetSolTradeResearchMetrics(out_of_sample);
   development.valid = true;
   validation.valid = true;
   out_of_sample.valid = true;
   development.expectancy = 10.0;
   validation.expectancy = 8.0;
   out_of_sample.expectancy = 6.0;
   development.annualized_return_percent = 4.0;
   validation.annualized_return_percent = 3.0;
   out_of_sample.annualized_return_percent = 2.0;
   development.profit_factor = 1.30;
   validation.profit_factor = 1.20;
   out_of_sample.profit_factor = 1.00;
   string reason = "";
   Phase6Check(
      SolTradeResearchConsistencyPasses(
         development,
         validation,
         out_of_sample,
         10000.0,
         reason),
      "Permitted cross-dataset variation accepted");

   out_of_sample.expectancy = 4.0;
   Phase6Check(
      !SolTradeResearchConsistencyPasses(
         development,
         validation,
         out_of_sample,
         10000.0,
         reason),
      "Expectancy below half of maximum rejected");

   out_of_sample.expectancy = 6.0;
   out_of_sample.profit_factor = 0.80;
   Phase6Check(
      !SolTradeResearchConsistencyPasses(
         development,
         validation,
         out_of_sample,
         10000.0,
         reason),
      "Profit-factor spread above 0.40 rejected");
  }

void OnStart()
  {
   HistorySelect(0, TimeCurrent());
   const int history_deals_before = HistoryDealsTotal();
   const int orders_before = OrdersTotal();
   const int positions_before = PositionsTotal();
   PrintFormat(
      "SOLTRADE_PHASE6_CONNECTED_PREFLIGHT | algo_trading=%s | orders=%d | positions=%d | history_deals=%d | production_ea_detached=%s | demo_execution=DISABLED | position_management=DISABLED | live_trading=DISABLED",
      (bool)TerminalInfoInteger(TERMINAL_TRADE_ALLOWED)
         ? "ON" : "OFF",
      orders_before,
      positions_before,
      history_deals_before,
      Phase6ProductionEaDetached() ? "YES" : "NO");
   Print("SolTrade Phase 6 deterministic safety tests started.");
   Print("This script never calls OrderCheck, OrderSend, or Strategy Tester.");
   RunHashAndIsolationTests();
   RunConfigurationAndRuntimeGateTests();
   RunInstanceNonTradingTests();
   RunCashFlowAndMetricTests();
   RunConsistencyTests();
   PrintFormat("SolTrade Phase 6 safety tests complete: %d passed, %d failed",
               g_phase6_passed,
               g_phase6_failed);
   if(g_phase6_failed == 0)
      Print("ALL SOLTRADE PHASE 6 SAFETY TESTS PASSED");
   else
      Print("SOLTRADE PHASE 6 SAFETY TESTS FAILED");
   HistorySelect(0, TimeCurrent());
   const int history_deals_after = HistoryDealsTotal();
   PrintFormat(
      "SOLTRADE_PHASE6_CONNECTED_POSTRUN | orders=%d | positions=%d | new_orders=%d | new_positions=%d | new_deals=%d | production_ea_detached=%s",
      OrdersTotal(),
      PositionsTotal(),
      OrdersTotal() - orders_before,
      PositionsTotal() - positions_before,
      history_deals_after - history_deals_before,
      Phase6ProductionEaDetached() ? "YES" : "NO");
  }
