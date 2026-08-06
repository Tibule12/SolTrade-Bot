#property copyright "SolTrade Bot"
#property link      ""
#property version   "1.000"
#property strict
#property description "Deterministic Phase 2 Risk Engine tests"
#property description "No market orders or strategy signals are used."

#include <SolTrade/RiskEngine.mqh>

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

void CheckOutcomeResult(const ENUM_SOLTRADE_OUTCOME_RESULT actual,
                        const ENUM_SOLTRADE_OUTCOME_RESULT expected,
                        const string reason,
                        const string test_name)
  {
   if(actual == expected)
     {
      g_tests_passed++;
      PrintFormat("PASS: %s | result=%d reason=%s",
                  test_name,
                  (int)actual,
                  reason);
     }
   else
     {
      g_tests_failed++;
      PrintFormat("FAIL: %s | actual_result=%d expected_result=%d reason=%s",
                  test_name,
                  (int)actual,
                  (int)expected,
                  reason);
     }
  }

void BuildTestConfig(const double production_baseline,
                     const string scenario_id,
                     SolTradeConfig &config)
  {
   config.risk_per_trade_percent      = 0.25;
   config.daily_loss_limit_percent    = 1.0;
   config.weekly_loss_limit_percent   = 2.5;
   config.emergency_drawdown_percent  = 5.0;
   config.production_baseline_equity  = production_baseline;
   config.consecutive_loss_limit      = 3;
   config.reset_emergency_lock        = false;
   config.emergency_stop              = false;
   config.risk_state_directory        =
      "SolTradeBot\\test-state\\" + scenario_id;
  }

void RunAccountScenario(const double starting_equity,
                        const double expected_volume,
                        const double expected_loss,
                        const string label,
                        const string scenario_id)
  {
   string reason = "";
   CheckTrue(StringLen(scenario_id) > 0 &&
             StringFind(scenario_id, ",") < 0 &&
             StringFind(scenario_id, "\n") < 0,
             label + " machine-safe scenario identifier");

   double risk_budget = 0.0;
   CheckTrue(
      SolTradeCalculateRiskBudget(starting_equity,
                                  0.25,
                                  risk_budget,
                                  reason),
      label + " risk budget is valid");
   CheckNear(risk_budget,
             starting_equity * 0.0025,
             1e-10,
             label + " risk budget");

   // Deterministic EURUSD-like metadata:
   // tick size 0.00001, loss-side tick value $1 per one lot,
   // 123-tick stop, 0.01 lot step.
   SolTradeRiskCalculation calculation;
   CheckTrue(
      SolTradeCalculatePositionSize(starting_equity,
                                    0.25,
                                    0.00123,
                                    0.00001,
                                    1.0,
                                    0.01,
                                    100.0,
                                    0.01,
                                    calculation),
      label + " volume calculation is valid");
   CheckNear(calculation.normalised_volume,
             expected_volume,
             1e-10,
             label + " lot-step rounding");
   CheckNear(calculation.expected_loss,
             expected_loss,
             1e-8,
             label + " expected stop loss");
   CheckTrue(
      calculation.expected_loss <=
         calculation.risk_money + SOLTRADE_MONEY_TOLERANCE,
      label + " normalised loss stays within budget");

   CheckTrue(
      !SolTradeCalculatePositionSize(starting_equity,
                                     0.25,
                                     0.0,
                                     0.00001,
                                     1.0,
                                     0.01,
                                     100.0,
                                     0.01,
                                     calculation),
      label + " zero stop distance rejected");
   CheckTrue(
      !SolTradeCalculatePositionSize(starting_equity,
                                     0.25,
                                     -0.00100,
                                     0.00001,
                                     1.0,
                                     0.01,
                                     100.0,
                                     0.01,
                                     calculation),
      label + " negative stop distance rejected");
   CheckTrue(
      !SolTradeCalculatePositionSize(starting_equity,
                                     0.25,
                                     0.10000,
                                     0.00001,
                                     1.0,
                                     0.01,
                                     100.0,
                                     0.01,
                                     calculation),
      label + " below-minimum volume rejected without rounding up");

   CheckTrue(
      SolTradeCalculatePositionSize(starting_equity,
                                    0.25,
                                    0.00123,
                                    0.00001,
                                    1.0,
                                    0.01,
                                    100.0,
                                    0.03,
                                    calculation),
      label + " offset broker volume grid is valid");
   const double expected_offset_volume =
      (starting_equity < 1000.0) ? 0.01 : 0.19;
   CheckNear(calculation.normalised_volume,
             expected_offset_volume,
             1e-10,
             label + " broker-minimum-offset step rounding");

   CheckTrue(
      SolTradeValidatePositionCapacity(0, reason),
      label + " zero open SolTrade positions accepted");
   CheckTrue(
      !SolTradeValidatePositionCapacity(1, reason),
      label + " second SolTrade position rejected");
   CheckTrue(
      !SolTradeValidatePositionCapacity(-1, reason),
      label + " invalid SolTrade position count rejected");

   SolTradeConfig config = {};
   BuildTestConfig(starting_equity, scenario_id, config);
   config.magic_number =
      (starting_equity < 1000.0)
      ? (ulong)2607202500
      : (ulong)2607210000;
   const datetime start_time = D'2026.07.27 08:00:00';
   const string persistence_hash = "RISKTEST_" + scenario_id;
   const string state_path =
      config.risk_state_directory + "\\risk_" + persistence_hash + "_" +
      StringFormat("%I64u", config.magic_number) + ".csv";

   FileDelete(state_path);
   FileDelete(state_path + ".tmp");
   CheckTrue(!FileIsExist(state_path),
             label + " persistent state starts clean");
   CheckTrue(!FileIsExist(state_path + ".tmp"),
             label + " persistent temporary state starts clean");

   CSolTradeRiskEngine daily_engine;
   CheckTrue(
      daily_engine.InitialiseForTesting(config,
                                        start_time,
                                        starting_equity,
                                        reason),
      label + " daily engine initialised");
   CheckTrue(
      daily_engine.Refresh(start_time + 60,
                           starting_equity * 0.99,
                           reason),
      label + " daily threshold evaluated");
   SolTradeRiskStatus status;
   daily_engine.GetStatus(status);
   CheckTrue(status.daily_locked,
             label + " daily lock at exactly 1 percent");
   CheckNear(status.daily_drawdown_percent,
             1.0,
             1e-8,
             label + " daily drawdown percentage");

   CSolTradeRiskEngine weekly_engine;
   CheckTrue(
      weekly_engine.InitialiseForTesting(config,
                                         start_time,
                                         starting_equity,
                                         reason),
      label + " weekly engine initialised");
   CheckTrue(
      weekly_engine.Refresh(start_time + 60,
                            starting_equity * 0.975,
                            reason),
      label + " weekly threshold evaluated");
   weekly_engine.GetStatus(status);
   CheckTrue(status.weekly_locked,
             label + " weekly lock at exactly 2.5 percent");
   CheckNear(status.weekly_drawdown_percent,
             2.5,
             1e-8,
             label + " weekly drawdown percentage");

   CSolTradeRiskEngine emergency_engine;
   CheckTrue(
      emergency_engine.InitialiseForTesting(config,
                                            start_time,
                                            starting_equity,
                                            reason),
      label + " emergency engine initialised");
   CheckTrue(
      emergency_engine.Refresh(start_time + 60,
                               starting_equity * 0.95,
                               reason),
      label + " emergency threshold evaluated");
   emergency_engine.GetStatus(status);
   CheckTrue(status.emergency_locked,
             label + " emergency lock at exactly 5 percent");
   CheckNear(status.emergency_drawdown_percent,
             5.0,
             1e-8,
             label + " emergency drawdown percentage");
   CheckTrue(
      emergency_engine.Refresh(start_time + 120,
                               starting_equity,
                               reason),
      label + " emergency recovery observation evaluated");
   emergency_engine.GetStatus(status);
   CheckTrue(status.emergency_locked,
             label + " emergency lock remains latched after equity recovery");

   CSolTradeRiskEngine loss_engine;
   CheckTrue(
      loss_engine.InitialiseForTesting(config,
                                       start_time,
                                       starting_equity,
                                       reason),
      label + " consecutive-loss engine initialised");
   loss_engine.GetStatus(status);
   CheckTrue(status.consecutive_losses == 0 &&
             !status.consecutive_locked,
             label + " consecutive-loss state starts clean");
   CheckTrue(StringLen(loss_engine.LastOutcomeId()) == 0,
             label + " duplicate-outcome cache starts empty");

   ENUM_SOLTRADE_OUTCOME_RESULT outcome_result =
      loss_engine.RecordClosedOutcome(scenario_id + "-LOSS-1",
                                      -1.0,
                                      start_time + 60,
                                      starting_equity,
                                      reason);
   CheckOutcomeResult(outcome_result,
                      SOLTRADE_OUTCOME_RECORDED,
                      reason,
                      label + " first loss recorded");

   outcome_result =
      loss_engine.RecordClosedOutcome(scenario_id + "-LOSS-2",
                                      -1.0,
                                      start_time + 120,
                                      starting_equity,
                                      reason);
   CheckOutcomeResult(outcome_result,
                      SOLTRADE_OUTCOME_RECORDED,
                      reason,
                      label + " second loss recorded");

   outcome_result =
      loss_engine.RecordClosedOutcome(scenario_id + "-LOSS-3",
                                      -1.0,
                                      start_time + 180,
                                      starting_equity,
                                      reason);
   CheckOutcomeResult(outcome_result,
                      SOLTRADE_OUTCOME_RECORDED,
                      reason,
                      label + " third loss recorded");

   loss_engine.GetStatus(status);
   CheckTrue(status.consecutive_locked &&
             status.consecutive_losses == 3,
             label + " third loss activates lock");

   outcome_result =
      loss_engine.RecordClosedOutcome(scenario_id + "-LOSS-3",
                                      -99.0,
                                      start_time + 240,
                                      starting_equity,
                                      reason);
   CheckOutcomeResult(outcome_result,
                      SOLTRADE_OUTCOME_DUPLICATE,
                      reason,
                      label + " duplicate outcome ignored");
   loss_engine.GetStatus(status);
   CheckTrue(status.consecutive_losses == 3,
             label + " duplicate does not increment streak");

   CheckTrue(
      loss_engine.Refresh(D'2026.07.28 08:00:00',
                          starting_equity,
                          reason),
      label + " next broker day evaluated");
   loss_engine.GetStatus(status);
   CheckTrue(!status.consecutive_locked &&
             status.consecutive_losses == 0,
             label + " consecutive-loss pause clears next broker day");

   CSolTradeRiskEngine streak_engine;
   CheckTrue(
      streak_engine.InitialiseForTesting(config,
                                         start_time,
                                         starting_equity,
                                         reason),
      label + " streak reset engine initialised");
   streak_engine.GetStatus(status);
   CheckTrue(status.consecutive_losses == 0 &&
             !status.consecutive_locked,
             label + " streak-reset state starts clean");
   CheckTrue(StringLen(streak_engine.LastOutcomeId()) == 0,
             label + " streak-reset duplicate cache starts empty");

   outcome_result =
      streak_engine.RecordClosedOutcome(scenario_id + "-STREAK-LOSS",
                                        -1.0,
                                        start_time + 60,
                                        starting_equity,
                                        reason);
   CheckOutcomeResult(outcome_result,
                      SOLTRADE_OUTCOME_RECORDED,
                      reason,
                      label + " streak-reset loss recorded");

   outcome_result =
      streak_engine.RecordClosedOutcome(scenario_id + "-STREAK-BREAKEVEN",
                                        0.0,
                                        start_time + 120,
                                        starting_equity,
                                        reason);
   CheckOutcomeResult(outcome_result,
                      SOLTRADE_OUTCOME_RECORDED,
                      reason,
                      label + " streak-reset breakeven recorded");
   streak_engine.GetStatus(status);
   CheckTrue(status.consecutive_losses == 1,
             label + " breakeven preserves loss streak");

   outcome_result =
      streak_engine.RecordClosedOutcome(scenario_id + "-STREAK-WIN",
                                        1.0,
                                        start_time + 180,
                                        starting_equity,
                                        reason);
   CheckOutcomeResult(outcome_result,
                      SOLTRADE_OUTCOME_RECORDED,
                      reason,
                      label + " streak-reset win recorded");
   streak_engine.GetStatus(status);
   CheckTrue(status.consecutive_losses == 0,
             label + " positive result resets loss streak");

   CSolTradeRiskEngine persistent_engine;
   CheckTrue(
      persistent_engine.Initialise(config,
                                   persistence_hash,
                                   start_time,
                                   starting_equity,
                                   reason),
      label + " persistent state initialised");
   CheckTrue(
      persistent_engine.Refresh(start_time + 60,
                                starting_equity * 0.99,
                                reason),
      label + " persistent daily lock written");
   CheckTrue(FileIsExist(state_path),
             label + " persistent risk-state file exists");
   CheckTrue(!FileIsExist(state_path + ".tmp"),
             label + " temporary state file was atomically replaced");

   CSolTradeRiskEngine restored_engine;
   CheckTrue(
      restored_engine.Initialise(config,
                                 persistence_hash,
                                 start_time + 120,
                                 starting_equity * 0.99,
                                 reason),
      label + " persistent state restored");
   restored_engine.GetStatus(status);
   CheckTrue(status.daily_locked,
             label + " daily lock survives engine restart");
   CheckNear(status.daily_start_equity,
             starting_equity,
             1e-8,
             label + " daily baseline survives engine restart");

   const int corrupt_handle =
      FileOpen(state_path, FILE_WRITE | FILE_CSV | FILE_ANSI, ',');
   CheckTrue(corrupt_handle != INVALID_HANDLE,
             label + " test can create corrupt state fixture");
   if(corrupt_handle != INVALID_HANDLE)
     {
      FileWrite(corrupt_handle, "CORRUPTED");
      FileClose(corrupt_handle);
     }

   CSolTradeRiskEngine corrupt_engine;
   CheckTrue(
      !corrupt_engine.Initialise(config,
                                persistence_hash,
                                start_time + 180,
                                starting_equity,
                                reason),
      label + " corrupt persistent state fails closed");

   FileDelete(state_path);
   FileDelete(state_path + ".tmp");
   CheckTrue(!FileIsExist(state_path),
             label + " persistent state cleanup confirmed");
   CheckTrue(!FileIsExist(state_path + ".tmp"),
             label + " persistent temporary-state cleanup confirmed");
  }

void RunSharedValidationCases()
  {
   SolTradeStopValidation stop_validation;
   CheckTrue(
      !SolTradeValidateStopDistance(0.00010,
                                    0.00001,
                                    0.00001,
                                    15,
                                    stop_validation),
      "Broker minimum stop distance rejects a 10-point stop");
   CheckNear(stop_validation.minimum_distance,
             0.00015,
             1e-12,
             "Broker minimum stop distance is 15 points");
   CheckTrue(
      SolTradeValidateStopDistance(0.00015,
                                   0.00001,
                                   0.00001,
                                   15,
                                   stop_validation),
      "Stop distance passes at broker minimum equality");

   SolTradeRiskCalculation invalid_metadata_calculation;
   CheckTrue(
      !SolTradeCalculatePositionSize(10000.0,
                                     0.25,
                                     0.00123,
                                     0.0,
                                     1.0,
                                     0.01,
                                     100.0,
                                     0.01,
                                     invalid_metadata_calculation),
      "Zero tick size is rejected");
   CheckTrue(
      !SolTradeCalculatePositionSize(10000.0,
                                     0.25,
                                     0.00123,
                                     0.00001,
                                     0.0,
                                     0.01,
                                     100.0,
                                     0.01,
                                     invalid_metadata_calculation),
      "Zero loss-side tick value is rejected");

   SolTradeSpreadValidation spread_validation;
   CheckTrue(
      SolTradeValidateSpread(20,
                             0.00001,
                             0.00200,
                             30,
                             10.0,
                             spread_validation),
      "Spread passes both limits at ATR-limit equality");
   CheckTrue(
      !SolTradeValidateSpread(21,
                              0.00001,
                              0.00200,
                              30,
                              10.0,
                              spread_validation),
      "Spread fails ATR-relative limit while absolute limit passes");
   CheckTrue(
      !SolTradeValidateSpread(31,
                              0.00001,
                              0.01000,
                              30,
                              10.0,
                              spread_validation),
      "Spread fails absolute limit while ATR-relative limit passes");
  }

void OnStart()
  {
   Print("SolTrade Phase 2 deterministic Risk Engine tests started");

   RunAccountScenario(500.0, 0.01, 1.23, "$500", "EQ500");
   RunAccountScenario(10000.0,
                      0.20,
                      24.60,
                      "$10,000",
                      "EQ10000");
   RunSharedValidationCases();

   PrintFormat("SolTrade Risk Engine tests complete: %d passed, %d failed",
               g_tests_passed,
               g_tests_failed);

   if(g_tests_failed == 0)
      Print("ALL SOLTRADE PHASE 2 RISK TESTS PASSED");
   else
      Print("SOLTRADE PHASE 2 RISK TESTS FAILED");
  }
