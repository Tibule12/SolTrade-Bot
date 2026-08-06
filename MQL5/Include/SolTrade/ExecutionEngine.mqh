#ifndef SOLTRADE_EXECUTION_ENGINE_MQH
#define SOLTRADE_EXECUTION_ENGINE_MQH

#include <SolTrade/Config.mqh>
#include <SolTrade/AccountGuard.mqh>
#include <SolTrade/MarketData.mqh>
#include <SolTrade/RiskEngine.mqh>
#include <SolTrade/StrategyBreakout.mqh>

#define SOLTRADE_EXECUTION_STATE_SCHEMA "SOLTRADE_EXECUTION_STATE_V1"
#define SOLTRADE_ORDER_COMMENT           "SolTrade TBV1"

struct SolTradeExecutionContext
  {
   ENUM_SOLTRADE_ENVIRONMENT detected_environment;
   bool                       expected_environment_matches;
   long                       account_login;
   bool                       terminal_connected;
   bool                       terminal_trading_allowed;
   bool                       program_trading_allowed;
   bool                       account_trading_allowed;
   bool                       account_expert_allowed;
   bool                       market_valid;
   bool                       risk_locked;
   string                     risk_lock_reason;
   datetime                   last_consumed_signal_bar;
   int                        open_soltrade_positions;
   int                        active_soltrade_orders;
   int                        conflicting_symbol_positions;
   double                     equity;
   double                     free_margin;
   double                     bid;
   double                     ask;
   double                     point;
   double                     tick_size;
   double                     tick_value_loss;
   double                     volume_min;
   double                     volume_max;
   double                     volume_step;
   int                        digits;
   int                        spread_points;
   int                        stops_level_points;
   long                       order_mode;
   long                       filling_mode;
   ENUM_SYMBOL_TRADE_EXECUTION execution_mode;
  };

struct SolTradeExecutionPlan
  {
   bool                    evaluated;
   bool                    ready_for_margin;
   bool                    valid;
   string                  reason_code;
   string                  reason;
   string                  signal_result;
   datetime                signal_bar_time;
   ENUM_TRADE_REQUEST_ACTIONS request_action;
   ENUM_ORDER_TYPE         order_type;
   ENUM_ORDER_TYPE_FILLING filling_type;
   string                  symbol;
   double                  requested_entry;
   double                  stop_loss;
   double                  stop_distance;
   double                  protective_stop_distance;
   double                  volume;
   double                  risk_budget;
   double                  expected_risk;
   double                  spread_price;
   int                     spread_points;
   double                  margin_required;
   double                  margin_free;
   ulong                   magic_number;
   int                     deviation_points;
   double                  broker_volume_min;
   double                  broker_volume_step;
   int                     broker_stops_level_points;
   long                    broker_supported_filling_mode;
  };

struct SolTradeExecutionReport
  {
   bool     evaluated;
   bool     broker_submission_attempted;
   bool     broker_accepted;
   bool     fill_confirmed;
   bool     retry_allowed;
   string   event_type;
   string   reason_code;
   string   reason;
   string   signal_result;
   datetime signal_bar_time;
   ENUM_TRADE_REQUEST_ACTIONS requested_action;
   ENUM_ORDER_TYPE requested_order_type;
   ENUM_ORDER_TYPE_FILLING requested_filling_mode;
   string   requested_symbol;
   double   requested_entry;
   double   broker_reported_price;
   double   actual_entry;
   int      spread_points;
   double   slippage_points;
   double   stop_loss;
   double   volume;
   double   risk_amount;
   double   margin_required;
   ulong    order_ticket;
   ulong    deal_ticket;
   ulong    requested_magic_number;
   int      requested_deviation_points;
   double   broker_volume_min;
   double   broker_volume_step;
   int      broker_stops_level_points;
   long     broker_supported_filling_mode;
   bool     order_check_performed;
   bool     order_check_boolean_result;
   int      order_check_last_error;
   uint     order_check_retcode;
   string   order_check_comment;
   uint     broker_return_code;
   int      terminal_error;
   string   broker_comment;
  };

struct SolTradeExecutionStatus
  {
   bool     initialised;
   bool     state_valid;
   bool     state_restored;
   datetime last_consumed_signal_bar;
   string   last_direction;
   double   last_requested_entry;
   double   last_actual_entry;
   int      last_spread_points;
   double   last_stop_loss;
   double   last_volume;
   double   last_risk_amount;
   ulong    last_order_ticket;
   ulong    last_deal_ticket;
   uint     last_broker_return_code;
   int      open_soltrade_positions;
   int      active_soltrade_orders;
   int      conflicting_symbol_positions;
   bool     unprotected_soltrade_position;
   string   last_event;
   string   state_error;
  };

void ResetSolTradeExecutionContext(SolTradeExecutionContext &context)
  {
   context.detected_environment          = SOLTRADE_ENV_UNKNOWN;
   context.expected_environment_matches  = false;
   context.account_login                 = 0;
   context.terminal_connected            = false;
   context.terminal_trading_allowed      = false;
   context.program_trading_allowed       = false;
   context.account_trading_allowed       = false;
   context.account_expert_allowed        = false;
   context.market_valid                  = false;
   context.risk_locked                   = true;
   context.risk_lock_reason              = "Risk state has not been evaluated";
   context.last_consumed_signal_bar      = 0;
   context.open_soltrade_positions       = 0;
   context.active_soltrade_orders        = 0;
   context.conflicting_symbol_positions  = 0;
   context.equity                        = 0.0;
   context.free_margin                   = 0.0;
   context.bid                           = 0.0;
   context.ask                           = 0.0;
   context.point                         = 0.0;
   context.tick_size                     = 0.0;
   context.tick_value_loss               = 0.0;
   context.volume_min                    = 0.0;
   context.volume_max                    = 0.0;
   context.volume_step                   = 0.0;
   context.digits                        = 0;
   context.spread_points                 = 0;
   context.stops_level_points            = 0;
   context.order_mode                    = 0;
   context.filling_mode                  = 0;
   context.execution_mode                = SYMBOL_TRADE_EXECUTION_MARKET;
  }

void ResetSolTradeExecutionPlan(SolTradeExecutionPlan &plan)
  {
   plan.evaluated                = false;
   plan.ready_for_margin         = false;
   plan.valid                    = false;
   plan.reason_code              = "NOT_EVALUATED";
   plan.reason                   = "Execution request has not been evaluated";
   plan.signal_result            = "NONE";
   plan.signal_bar_time          = 0;
   plan.request_action           = TRADE_ACTION_DEAL;
   plan.order_type               = ORDER_TYPE_BUY;
   plan.filling_type             = ORDER_FILLING_FOK;
   plan.symbol                   = "";
   plan.requested_entry          = 0.0;
   plan.stop_loss                = 0.0;
   plan.stop_distance            = 0.0;
   plan.protective_stop_distance = 0.0;
   plan.volume                   = 0.0;
   plan.risk_budget              = 0.0;
   plan.expected_risk            = 0.0;
   plan.spread_price             = 0.0;
   plan.spread_points            = 0;
   plan.margin_required          = 0.0;
   plan.margin_free              = 0.0;
   plan.magic_number             = 0;
   plan.deviation_points         = 0;
   plan.broker_volume_min        = 0.0;
   plan.broker_volume_step       = 0.0;
   plan.broker_stops_level_points = 0;
   plan.broker_supported_filling_mode = 0;
  }

void ResetSolTradeExecutionReport(SolTradeExecutionReport &report)
  {
   report.evaluated                   = false;
   report.broker_submission_attempted = false;
   report.broker_accepted             = false;
   report.fill_confirmed              = false;
   report.retry_allowed               = false;
   report.event_type                  = "EXECUTION_NOT_EVALUATED";
   report.reason_code                 = "NOT_EVALUATED";
   report.reason                      =
      "Execution request has not been evaluated";
   report.signal_result               = "NONE";
   report.signal_bar_time             = 0;
   report.requested_action            = TRADE_ACTION_DEAL;
   report.requested_order_type        = ORDER_TYPE_BUY;
   report.requested_filling_mode      = ORDER_FILLING_FOK;
   report.requested_symbol            = "";
   report.requested_entry             = 0.0;
   report.broker_reported_price       = 0.0;
   report.actual_entry                = 0.0;
   report.spread_points               = 0;
   report.slippage_points             = 0.0;
   report.stop_loss                   = 0.0;
   report.volume                      = 0.0;
   report.risk_amount                 = 0.0;
   report.margin_required             = 0.0;
   report.order_ticket                = 0;
   report.deal_ticket                 = 0;
   report.requested_magic_number      = 0;
   report.requested_deviation_points  = 0;
   report.broker_volume_min           = 0.0;
   report.broker_volume_step          = 0.0;
   report.broker_stops_level_points   = 0;
   report.broker_supported_filling_mode = 0;
   report.order_check_performed       = false;
   report.order_check_boolean_result  = false;
   report.order_check_last_error      = 0;
   report.order_check_retcode         = 0;
   report.order_check_comment         = "";
   report.broker_return_code          = 0;
   report.terminal_error              = 0;
   report.broker_comment              = "";
  }

void ResetSolTradeExecutionStatus(SolTradeExecutionStatus &status)
  {
   status.initialised                    = false;
   status.state_valid                   = false;
   status.state_restored                = false;
   status.last_consumed_signal_bar      = 0;
   status.last_direction                = "NONE";
   status.last_requested_entry          = 0.0;
   status.last_actual_entry             = 0.0;
   status.last_spread_points            = 0;
   status.last_stop_loss                = 0.0;
   status.last_volume                   = 0.0;
   status.last_risk_amount              = 0.0;
   status.last_order_ticket             = 0;
   status.last_deal_ticket              = 0;
   status.last_broker_return_code       = 0;
   status.open_soltrade_positions       = 0;
   status.active_soltrade_orders        = 0;
   status.conflicting_symbol_positions  = 0;
   status.unprotected_soltrade_position = false;
   status.last_event                    =
      "Execution engine is not initialised";
   status.state_error                   = "";
  }

void SolTradeRejectExecutionPlan(SolTradeExecutionPlan &plan,
                                 const string reason_code,
                                 const string reason)
  {
   plan.evaluated        = true;
   plan.ready_for_margin = false;
   plan.valid            = false;
   plan.reason_code      = reason_code;
   plan.reason           = reason;
  }

void SolTradeReportFromPlan(const SolTradeExecutionPlan &plan,
                            const string event_type,
                            SolTradeExecutionReport &report)
  {
   ResetSolTradeExecutionReport(report);
   report.evaluated          = true;
   report.event_type         = event_type;
   report.reason_code        = plan.reason_code;
   report.reason             = plan.reason;
   report.signal_result      = plan.signal_result;
   report.signal_bar_time    = plan.signal_bar_time;
   report.requested_action   = plan.request_action;
   report.requested_order_type = plan.order_type;
   report.requested_filling_mode = plan.filling_type;
   report.requested_symbol   = plan.symbol;
   report.requested_entry    = plan.requested_entry;
   report.spread_points      = plan.spread_points;
   report.stop_loss          = plan.stop_loss;
   report.volume             = plan.volume;
   report.risk_amount        = plan.expected_risk;
   report.margin_required    = plan.margin_required;
   report.requested_magic_number =
      plan.magic_number;
   report.requested_deviation_points =
      plan.deviation_points;
   report.broker_volume_min =
      plan.broker_volume_min;
   report.broker_volume_step =
      plan.broker_volume_step;
   report.broker_stops_level_points =
      plan.broker_stops_level_points;
   report.broker_supported_filling_mode =
      plan.broker_supported_filling_mode;
  }

void SolTradeAttachOrderCheckDiagnostics(
   const bool boolean_result,
   const int last_error,
   const MqlTradeCheckResult &check,
   SolTradeExecutionReport &report)
  {
   report.order_check_performed      = true;
   report.order_check_boolean_result = boolean_result;
   report.order_check_last_error     = last_error;
   report.order_check_retcode        = check.retcode;
   report.order_check_comment        = check.comment;
  }

bool SolTradeOrderCheckAccepted(const bool boolean_result,
                                const uint check_retcode)
  {
   // MqlTradeCheckResult uses retcode 0 for a successful check. The
   // TRADE_RETCODE_DONE value belongs to the later MqlTradeResult returned by
   // OrderSend and must not be required (or accepted) here. Any false boolean
   // result or non-zero check code remains fail-closed.
   return (boolean_result && check_retcode == 0);
  }

bool SolTradeValidateExecutionEnvironment(
   const SolTradeConfig &config,
   const SolTradeExecutionContext &context,
   string &reason_code,
   string &reason)
  {
   reason_code = "";
   reason      = "";

   if(!context.expected_environment_matches)
     {
      reason_code = "ENVIRONMENT_MISMATCH";
      reason = "Configured and detected environments do not match";
      return false;
     }

   if(config.emergency_stop)
     {
      reason_code = "EMERGENCY_STOP_ACTIVE";
      reason = "EmergencyStop is enabled";
      return false;
     }

   if(context.detected_environment == SOLTRADE_ENV_LIVE)
     {
      reason_code = "REAL_ACCOUNT_FORBIDDEN_PHASE4";
      reason =
         "Phase 4 rejects real-account order placement regardless of terminal permissions";
      return false;
     }

   if(context.detected_environment == SOLTRADE_ENV_DEMO)
     {
      if(!config.enable_demo_execution)
        {
         reason_code = "DEMO_EXECUTION_DISABLED";
         reason = "EnableDemoExecution is false";
         return false;
        }

      if(config.approved_demo_account <= 0 ||
         context.account_login != config.approved_demo_account)
        {
         reason_code = "DEMO_ACCOUNT_NOT_APPROVED";
         reason =
            "Connected demo account does not match ApprovedDemoAccount";
         return false;
        }
     }
   else if(context.detected_environment == SOLTRADE_ENV_BACKTEST)
     {
      if(!config.enable_backtest_research ||
         !config.enable_backtest_execution ||
         !config.enable_backtest_position_management)
        {
         reason_code = "BACKTEST_RESEARCH_DISABLED";
         reason =
            "Phase 6 tester execution and management gates are not armed together";
         return false;
        }

     }
   else
     {
      reason_code = "ACCOUNT_MODE_INVALID";
      reason = "Execution is permitted only in Strategy Tester or approved demo";
      return false;
     }

   if(context.detected_environment != SOLTRADE_ENV_BACKTEST &&
      !context.terminal_connected)
     {
      reason_code = "TERMINAL_DISCONNECTED";
      reason = "Terminal is disconnected";
      return false;
     }

   if(!context.terminal_trading_allowed ||
      !context.program_trading_allowed ||
      !context.account_trading_allowed ||
      !context.account_expert_allowed)
     {
      reason_code = "TRADING_PERMISSION_DISABLED";
      reason =
         "Terminal, program, account, or Expert Advisor trading permission is disabled";
      return false;
     }

   return true;
  }

bool SolTradeValidateOrderVolume(const double volume,
                                 const double volume_min,
                                 const double volume_max,
                                 const double volume_step,
                                 string &reason)
  {
   reason = "";
   if(!MathIsValidNumber(volume) ||
      !MathIsValidNumber(volume_min) ||
      !MathIsValidNumber(volume_max) ||
      !MathIsValidNumber(volume_step) ||
      volume <= 0.0 ||
      volume_min <= 0.0 ||
      volume_max < volume_min ||
      volume_step <= 0.0)
     {
      reason = "Volume or broker volume metadata is invalid";
      return false;
     }

   const double tolerance = 1e-8;
   if(volume + tolerance < volume_min ||
      volume > volume_max + tolerance)
     {
      reason = "Volume is outside the broker minimum/maximum range";
      return false;
     }

   const double grid_steps = (volume - volume_min) / volume_step;
   if(MathAbs(grid_steps - MathRound(grid_steps)) > tolerance)
     {
      reason = "Volume is not aligned to the broker lot step";
      return false;
     }

   return true;
  }

double SolTradeNormaliseProtectiveStop(const ENUM_ORDER_TYPE order_type,
                                       const double raw_stop,
                                       const double tick_size,
                                       const int digits)
  {
   if(order_type == ORDER_TYPE_BUY)
      return NormalizeDouble(
         MathFloor((raw_stop / tick_size) + 1e-10) * tick_size,
         digits);

   return NormalizeDouble(
      MathCeil((raw_stop / tick_size) - 1e-10) * tick_size,
      digits);
  }

bool SolTradeResolveFillingType(
   const long filling_mode,
   const ENUM_SYMBOL_TRADE_EXECUTION execution_mode,
   ENUM_ORDER_TYPE_FILLING &filling_type,
   string &reason)
  {
   reason = "";
   if((filling_mode & SYMBOL_FILLING_FOK) == SYMBOL_FILLING_FOK)
     {
      filling_type = ORDER_FILLING_FOK;
      return true;
     }

   if((filling_mode & SYMBOL_FILLING_IOC) == SYMBOL_FILLING_IOC)
     {
      filling_type = ORDER_FILLING_IOC;
      return true;
     }

   if(execution_mode != SYMBOL_TRADE_EXECUTION_MARKET)
     {
      filling_type = ORDER_FILLING_RETURN;
      return true;
     }

   reason =
      "Market-execution symbol provides neither FOK nor IOC filling";
   return false;
  }

bool SolTradePrepareExecutionPlan(
   const SolTradeConfig &config,
   const SolTradeStrategySignal &signal,
   const SolTradeExecutionContext &context,
   SolTradeExecutionPlan &plan)
  {
   ResetSolTradeExecutionPlan(plan);
   plan.evaluated       = true;
   plan.signal_result   =
      SolTradeEntrySignalName(signal.entry_signal);
   plan.signal_bar_time = signal.signal_bar_time;
   plan.request_action  = TRADE_ACTION_DEAL;
   plan.symbol          = config.symbol;
   plan.magic_number    = config.magic_number;
   plan.deviation_points = config.max_slippage_points;
   plan.spread_points   = context.spread_points;
   plan.broker_volume_min =
      context.volume_min;
   plan.broker_volume_step =
      context.volume_step;
   plan.broker_stops_level_points =
      context.stops_level_points;
   plan.broker_supported_filling_mode =
      context.filling_mode;

   string reason_code = "";
   string reason      = "";
   if(!SolTradeValidateExecutionEnvironment(config,
                                             context,
                                             reason_code,
                                             reason))
     {
      SolTradeRejectExecutionPlan(plan, reason_code, reason);
      return false;
     }

   if(!signal.evaluated || !signal.valid ||
      (signal.entry_signal != SOLTRADE_SIGNAL_BUY &&
       signal.entry_signal != SOLTRADE_SIGNAL_SELL))
     {
      SolTradeRejectExecutionPlan(
         plan,
         "NO_VALID_ENTRY_SIGNAL",
         "Execution requires a valid BUY or SELL completed-candle signal");
      return false;
     }

   if(signal.signal_bar_time <= 0)
     {
      SolTradeRejectExecutionPlan(
         plan,
         "INVALID_SIGNAL_CANDLE",
         "Signal candle time is invalid");
      return false;
     }

   if(context.detected_environment == SOLTRADE_ENV_BACKTEST &&
      (signal.signal_bar_time <
          config.research_start_inclusive ||
       signal.signal_bar_time >=
          config.research_end_exclusive))
     {
      SolTradeRejectExecutionPlan(
         plan,
         "BACKTEST_SIGNAL_OUTSIDE_DATASET",
         "Completed signal candle is outside the registered dataset interval");
      return false;
     }

   if(context.last_consumed_signal_bar > 0 &&
      signal.signal_bar_time <= context.last_consumed_signal_bar)
     {
      const bool duplicate =
         (signal.signal_bar_time == context.last_consumed_signal_bar);
      SolTradeRejectExecutionPlan(
         plan,
         duplicate
            ? "DUPLICATE_SIGNAL_CANDLE"
            : "STALE_SIGNAL_CANDLE",
         duplicate
            ? "This completed candle already produced an execution attempt"
            : "Signal candle predates the last persisted execution attempt");
      return false;
     }

   if(context.risk_locked)
     {
      SolTradeRejectExecutionPlan(
         plan,
         "RISK_ENGINE_LOCKED",
         context.risk_lock_reason);
      return false;
     }

   if(!context.market_valid)
     {
      SolTradeRejectExecutionPlan(
         plan,
         "MARKET_DATA_INVALID",
         "Validated market data is required for execution");
      return false;
     }

   if(context.open_soltrade_positions < 0 ||
      context.active_soltrade_orders < 0 ||
      context.conflicting_symbol_positions < 0)
     {
      SolTradeRejectExecutionPlan(
         plan,
         "POSITION_STATE_INVALID",
         "Broker position/order counts are invalid");
      return false;
     }

   if(context.open_soltrade_positions > 0)
     {
      SolTradeRejectExecutionPlan(
         plan,
         "EXISTING_SOLTRADE_POSITION",
         "Only one SolTrade position may be open at a time");
      return false;
     }

   if(context.active_soltrade_orders > 0)
     {
      SolTradeRejectExecutionPlan(
         plan,
         "EXISTING_SOLTRADE_ORDER",
         "An existing SolTrade order is still active");
      return false;
     }

   if(context.conflicting_symbol_positions > 0)
     {
      SolTradeRejectExecutionPlan(
         plan,
         "CONFLICTING_SYMBOL_POSITION",
         "An unrelated position exists on the configured symbol");
      return false;
     }

   if((context.order_mode & SYMBOL_ORDER_MARKET) != SYMBOL_ORDER_MARKET)
     {
      SolTradeRejectExecutionPlan(
         plan,
         "MARKET_ORDERS_NOT_ALLOWED",
         "Broker symbol does not permit market orders");
      return false;
     }

   if((context.order_mode & SYMBOL_ORDER_SL) != SYMBOL_ORDER_SL)
     {
      SolTradeRejectExecutionPlan(
         plan,
         "STOP_LOSS_NOT_ALLOWED",
         "Broker symbol cannot accept the compulsory initial stop-loss");
      return false;
     }

   SolTradeSpreadValidation spread_validation;
   if(!SolTradeValidateSpread(context.spread_points,
                              context.point,
                              signal.atr_14,
                              config.max_spread_points,
                              config.max_spread_atr_percent,
                              spread_validation))
     {
      SolTradeRejectExecutionPlan(
         plan,
         "SPREAD_REJECTED",
         spread_validation.reason);
      return false;
     }
   plan.spread_price = spread_validation.spread_price;

   if(!MathIsValidNumber(context.bid) ||
      !MathIsValidNumber(context.ask) ||
      context.bid <= 0.0 ||
      context.ask < context.bid ||
      !MathIsValidNumber(signal.initial_stop_distance) ||
      signal.initial_stop_distance <= 0.0)
     {
      SolTradeRejectExecutionPlan(
         plan,
         "ORDER_PRICE_INVALID",
         "Entry quote or strategy stop distance is invalid");
      return false;
     }

   plan.order_type =
      (signal.entry_signal == SOLTRADE_SIGNAL_BUY)
      ? ORDER_TYPE_BUY
      : ORDER_TYPE_SELL;
   plan.requested_entry =
      (plan.order_type == ORDER_TYPE_BUY)
      ? context.ask
      : context.bid;

   const double raw_stop =
      (plan.order_type == ORDER_TYPE_BUY)
      ? plan.requested_entry - signal.initial_stop_distance
      : plan.requested_entry + signal.initial_stop_distance;
   if(raw_stop <= 0.0)
     {
      SolTradeRejectExecutionPlan(
         plan,
         "STOP_PRICE_INVALID",
         "Calculated initial stop-loss price is invalid");
      return false;
     }

   plan.stop_loss =
      SolTradeNormaliseProtectiveStop(plan.order_type,
                                      raw_stop,
                                      context.tick_size,
                                      context.digits);
   plan.stop_distance =
      MathAbs(plan.requested_entry - plan.stop_loss);
   plan.protective_stop_distance =
      (plan.order_type == ORDER_TYPE_BUY)
      ? context.bid - plan.stop_loss
      : plan.stop_loss - context.ask;

   SolTradeStopValidation stop_validation;
   if(!SolTradeValidateStopDistance(plan.protective_stop_distance,
                                    context.tick_size,
                                    context.point,
                                    context.stops_level_points,
                                    stop_validation))
     {
      SolTradeRejectExecutionPlan(
         plan,
         "STOP_DISTANCE_REJECTED",
         stop_validation.reason);
      return false;
     }

   SolTradeRiskCalculation risk;
   if(!SolTradeCalculatePositionSize(context.equity,
                                     config.risk_per_trade_percent,
                                     plan.stop_distance,
                                     context.tick_size,
                                     context.tick_value_loss,
                                     context.volume_min,
                                     context.volume_max,
                                     context.volume_step,
                                     risk))
     {
      SolTradeRejectExecutionPlan(
         plan,
         "POSITION_SIZE_REJECTED",
         risk.reason);
      return false;
     }

   if(!SolTradeValidateOrderVolume(risk.normalised_volume,
                                   context.volume_min,
                                   context.volume_max,
                                   context.volume_step,
                                   reason))
     {
      SolTradeRejectExecutionPlan(
         plan,
         "VOLUME_REJECTED",
         reason);
      return false;
     }

   if(!SolTradeResolveFillingType(context.filling_mode,
                                  context.execution_mode,
                                  plan.filling_type,
                                  reason))
     {
      SolTradeRejectExecutionPlan(
         plan,
         "FILLING_MODE_REJECTED",
         reason);
      return false;
     }

   plan.volume        = risk.normalised_volume;
   plan.risk_budget   = risk.risk_money;
   plan.expected_risk = risk.expected_loss;
   plan.ready_for_margin = true;
   plan.valid            = false;
   plan.reason_code      = "MARGIN_CHECK_REQUIRED";
   plan.reason           =
      "Request parameters are valid and require margin validation";
   return true;
  }

bool SolTradeApplyMarginValidation(const bool calculation_succeeded,
                                   const double margin_required,
                                   const double margin_free,
                                   SolTradeExecutionPlan &plan)
  {
   plan.margin_required = margin_required;
   plan.margin_free     = margin_free;
   plan.valid           = false;

   if(!plan.ready_for_margin)
     {
      plan.reason_code = "REQUEST_NOT_READY_FOR_MARGIN";
      plan.reason =
         "Order parameters must pass validation before margin is checked";
      return false;
     }

   if(!calculation_succeeded ||
      !MathIsValidNumber(margin_required) ||
      !MathIsValidNumber(margin_free) ||
      margin_required < 0.0 ||
      margin_free < 0.0)
     {
      plan.reason_code = "MARGIN_CALCULATION_FAILED";
      plan.reason = "Broker margin requirement could not be calculated";
      return false;
     }

   if(margin_required > margin_free + SOLTRADE_MONEY_TOLERANCE)
     {
      plan.reason_code = "INSUFFICIENT_MARGIN";
      plan.reason = "Required margin exceeds current free margin";
      return false;
     }

   plan.valid       = true;
   plan.reason_code = "EXECUTION_REQUEST_VALID";
   plan.reason      =
      "Environment, risk, spread, stop, volume, and margin checks passed";
   return true;
  }

bool SolTradeApplySaferMinimumVolume(
   const SolTradeExecutionContext &context,
   SolTradeExecutionPlan &plan)
  {
   if(!plan.ready_for_margin ||
      plan.volume <= 0.0 ||
      plan.expected_risk <= 0.0)
     {
      plan.valid       = false;
      plan.reason_code = "MINIMUM_VOLUME_POLICY_NOT_READY";
      plan.reason =
         "A valid risk-calculated plan is required before applying the one-shot minimum-volume policy";
      return false;
     }

   string reason = "";
   if(!SolTradeValidateOrderVolume(context.volume_min,
                                   context.volume_min,
                                   context.volume_max,
                                   context.volume_step,
                                   reason))
     {
      plan.valid       = false;
      plan.reason_code = "MINIMUM_VOLUME_REJECTED";
      plan.reason      = reason;
      return false;
     }

   if(context.volume_min > plan.volume + 1e-10)
     {
      plan.valid       = false;
      plan.reason_code = "MINIMUM_VOLUME_EXCEEDS_RISK_SIZE";
      plan.reason =
         "Broker minimum volume exceeds the approved risk-calculated volume";
      return false;
     }

   const double loss_per_lot = plan.expected_risk / plan.volume;
   const double minimum_risk = loss_per_lot * context.volume_min;
   if(!MathIsValidNumber(minimum_risk) ||
      minimum_risk <= 0.0 ||
      minimum_risk >
         plan.risk_budget + SOLTRADE_MONEY_TOLERANCE)
     {
      plan.valid       = false;
      plan.reason_code = "MINIMUM_VOLUME_RISK_REJECTED";
      plan.reason =
         "Broker minimum volume does not fit the approved monetary risk budget";
      return false;
     }

   plan.volume        = context.volume_min;
   plan.expected_risk = minimum_risk;
   plan.valid         = false;
   plan.reason_code   = "SAFER_MINIMUM_VOLUME_SELECTED";
   plan.reason        =
      "One-shot verification selected the broker minimum because it does not exceed the approved risk-calculated size";
   return true;
  }

bool SolTradeBrokerRetcodeAccepted(const uint retcode)
  {
   return (retcode == TRADE_RETCODE_DONE ||
           retcode == TRADE_RETCODE_DONE_PARTIAL ||
           retcode == TRADE_RETCODE_PLACED);
  }

bool SolTradeBrokerRetcodeReportsFill(const uint retcode)
  {
   return (retcode == TRADE_RETCODE_DONE ||
           retcode == TRADE_RETCODE_DONE_PARTIAL);
  }

string SolTradeBrokerRetcodeName(const uint retcode)
  {
   switch(retcode)
     {
      case TRADE_RETCODE_REQUOTE:       return "REQUOTE";
      case TRADE_RETCODE_REJECT:        return "REJECT";
      case TRADE_RETCODE_CANCEL:        return "CANCEL";
      case TRADE_RETCODE_PLACED:        return "PLACED";
      case TRADE_RETCODE_DONE:          return "DONE";
      case TRADE_RETCODE_DONE_PARTIAL:  return "DONE_PARTIAL";
      case TRADE_RETCODE_ERROR:         return "ERROR";
      case TRADE_RETCODE_TIMEOUT:       return "TIMEOUT";
      case TRADE_RETCODE_INVALID:       return "INVALID";
      case TRADE_RETCODE_INVALID_VOLUME:return "INVALID_VOLUME";
      case TRADE_RETCODE_INVALID_PRICE: return "INVALID_PRICE";
      case TRADE_RETCODE_INVALID_STOPS: return "INVALID_STOPS";
      case TRADE_RETCODE_TRADE_DISABLED:return "TRADE_DISABLED";
      case TRADE_RETCODE_MARKET_CLOSED: return "MARKET_CLOSED";
      case TRADE_RETCODE_NO_MONEY:      return "NO_MONEY";
      case TRADE_RETCODE_PRICE_CHANGED: return "PRICE_CHANGED";
      case TRADE_RETCODE_PRICE_OFF:     return "PRICE_OFF";
      case TRADE_RETCODE_TOO_MANY_REQUESTS:
         return "TOO_MANY_REQUESTS";
      default:
         return "RETCODE_" + IntegerToString((long)retcode);
     }
  }

string SolTradeSupportedFillingModesName(const long filling_mode)
  {
   string modes = "";
   if((filling_mode & SYMBOL_FILLING_FOK) == SYMBOL_FILLING_FOK)
      modes = "FOK";
   if((filling_mode & SYMBOL_FILLING_IOC) == SYMBOL_FILLING_IOC)
      modes += (StringLen(modes) > 0 ? "|" : "") + "IOC";
   if((filling_mode & SYMBOL_FILLING_BOC) == SYMBOL_FILLING_BOC)
      modes += (StringLen(modes) > 0 ? "|" : "") + "BOC";

   return StringLen(modes) > 0 ? modes : "NONE_OR_RETURN_ONLY";
  }

double SolTradeExecutionSlippagePoints(
   const string direction,
   const double requested_price,
   const double actual_price,
   const double point)
  {
   if(!MathIsValidNumber(requested_price) ||
      !MathIsValidNumber(actual_price) ||
      !MathIsValidNumber(point) ||
      requested_price <= 0.0 ||
      actual_price <= 0.0 ||
      point <= 0.0)
      return 0.0;

   if(direction == "SELL")
      return (requested_price - actual_price) / point;

   return (actual_price - requested_price) / point;
  }

string SolTradeExecutionStateChecksum(const string payload)
  {
   uint hash = 2166136261;
   for(int index = 0; index < StringLen(payload); index++)
     {
      hash ^= (uint)StringGetCharacter(payload, index);
      hash = (uint)(hash * (uint)16777619);
     }

   return StringFormat("%08lX", hash);
  }

string SolTradeExecutionStatePath(const SolTradeConfig &config,
                                  const string account_identifier_hash)
  {
   string state_directory = config.execution_state_directory;
   StringReplace(state_directory, "/", "\\");
   return state_directory + "\\execution_" + account_identifier_hash + "_" +
          StringFormat("%I64u", config.magic_number) + ".csv";
  }

int SolTradeCountOpenMagicPositions(const ulong magic_number,
                                    bool &unprotected)
  {
   int count = 0;
   unprotected = false;
   const int total = PositionsTotal();
   for(int index = 0; index < total; index++)
     {
      const ulong ticket = PositionGetTicket(index);
      if(ticket == 0)
         continue;

      if((ulong)PositionGetInteger(POSITION_MAGIC) != magic_number)
         continue;

      count++;
      if(PositionGetDouble(POSITION_SL) <= 0.0)
         unprotected = true;
     }

   return count;
  }

int SolTradeCountActiveMagicOrders(const ulong magic_number)
  {
   int count = 0;
   const int total = OrdersTotal();
   for(int index = 0; index < total; index++)
     {
      const ulong ticket = OrderGetTicket(index);
      if(ticket == 0)
         continue;

      if((ulong)OrderGetInteger(ORDER_MAGIC) == magic_number)
         count++;
     }

   return count;
  }

int SolTradeCountConflictingSymbolPositions(const string symbol,
                                            const ulong magic_number)
  {
   int count = 0;
   const int total = PositionsTotal();
   for(int index = 0; index < total; index++)
     {
      const ulong ticket = PositionGetTicket(index);
      if(ticket == 0)
         continue;

      if(PositionGetString(POSITION_SYMBOL) == symbol &&
         (ulong)PositionGetInteger(POSITION_MAGIC) != magic_number)
         count++;
     }

   return count;
  }

class CSolTradeExecutionEngine
  {
private:
   SolTradeConfig           m_config;
   SolTradeExecutionStatus  m_status;
   string                   m_state_path;
   long                     m_revision;

   string StatePayload()
     {
      return
         SOLTRADE_EXECUTION_STATE_SCHEMA + "|" +
         IntegerToString(m_status.last_consumed_signal_bar) + "|" +
         m_status.last_direction + "|" +
         DoubleToString(m_status.last_requested_entry, 10) + "|" +
         DoubleToString(m_status.last_actual_entry, 10) + "|" +
         IntegerToString(m_status.last_spread_points) + "|" +
         DoubleToString(m_status.last_stop_loss, 10) + "|" +
         DoubleToString(m_status.last_volume, 8) + "|" +
         DoubleToString(m_status.last_risk_amount, 8) + "|" +
         StringFormat("%I64u", m_status.last_order_ticket) + "|" +
         StringFormat("%I64u", m_status.last_deal_ticket) + "|" +
         IntegerToString((long)m_status.last_broker_return_code) + "|" +
         m_status.last_event;
     }

   bool SaveState(string &reason)
     {
      reason = "";
      const string temporary_path = m_state_path + ".tmp";
      FileDelete(temporary_path);

      ResetLastError();
      const int handle =
         FileOpen(temporary_path, FILE_WRITE | FILE_CSV | FILE_ANSI, ',');
      if(handle == INVALID_HANDLE)
        {
         reason = "Cannot open temporary execution-state file; error " +
                  IntegerToString(GetLastError());
         return false;
        }

      const string payload = StatePayload();
      const uint written =
         FileWrite(handle,
                   SOLTRADE_EXECUTION_STATE_SCHEMA,
                   IntegerToString(m_status.last_consumed_signal_bar),
                   m_status.last_direction,
                   DoubleToString(m_status.last_requested_entry, 10),
                   DoubleToString(m_status.last_actual_entry, 10),
                   IntegerToString(m_status.last_spread_points),
                   DoubleToString(m_status.last_stop_loss, 10),
                   DoubleToString(m_status.last_volume, 8),
                   DoubleToString(m_status.last_risk_amount, 8),
                   StringFormat("%I64u", m_status.last_order_ticket),
                   StringFormat("%I64u", m_status.last_deal_ticket),
                   IntegerToString((long)m_status.last_broker_return_code),
                   m_status.last_event,
                   SolTradeExecutionStateChecksum(payload));
      FileFlush(handle);
      FileClose(handle);

      if(written == 0)
        {
         FileDelete(temporary_path);
         reason = "Execution-state write returned zero bytes";
         return false;
        }

      ResetLastError();
      if(!FileMove(temporary_path, 0, m_state_path, FILE_REWRITE))
        {
         reason = "Cannot replace persistent execution-state file; error " +
                  IntegerToString(GetLastError());
         FileDelete(temporary_path);
         return false;
        }

      return true;
     }

   bool LoadState(bool &found, string &reason)
     {
      found  = false;
      reason = "";
      if(!FileIsExist(m_state_path))
         return true;

      found = true;
      ResetLastError();
      const int handle =
         FileOpen(m_state_path, FILE_READ | FILE_CSV | FILE_ANSI, ',');
      if(handle == INVALID_HANDLE)
        {
         reason = "Cannot open persistent execution-state file; error " +
                  IntegerToString(GetLastError());
         return false;
        }

      const string schema             = FileReadString(handle);
      const string signal_bar_text    = FileReadString(handle);
      const string direction          = FileReadString(handle);
      const string requested_text     = FileReadString(handle);
      const string actual_text        = FileReadString(handle);
      const string spread_text        = FileReadString(handle);
      const string stop_text          = FileReadString(handle);
      const string volume_text        = FileReadString(handle);
      const string risk_text          = FileReadString(handle);
      const string order_text         = FileReadString(handle);
      const string deal_text          = FileReadString(handle);
      const string retcode_text       = FileReadString(handle);
      const string last_event         = FileReadString(handle);
      const string checksum           = FileReadString(handle);
      FileClose(handle);

      if(schema != SOLTRADE_EXECUTION_STATE_SCHEMA)
        {
         reason = "Execution-state schema is missing or unsupported";
         return false;
        }

      const string payload =
         schema + "|" + signal_bar_text + "|" + direction + "|" +
         requested_text + "|" + actual_text + "|" + spread_text + "|" +
         stop_text + "|" + volume_text + "|" + risk_text + "|" +
         order_text + "|" + deal_text + "|" + retcode_text + "|" +
         last_event;
      if(checksum != SolTradeExecutionStateChecksum(payload))
        {
         reason = "Persistent execution-state checksum does not match";
         return false;
        }

      m_status.last_consumed_signal_bar =
         (datetime)StringToInteger(signal_bar_text);
      m_status.last_direction          = direction;
      m_status.last_requested_entry    = StringToDouble(requested_text);
      m_status.last_actual_entry       = StringToDouble(actual_text);
      m_status.last_spread_points      =
         (int)StringToInteger(spread_text);
      m_status.last_stop_loss          = StringToDouble(stop_text);
      m_status.last_volume             = StringToDouble(volume_text);
      m_status.last_risk_amount        = StringToDouble(risk_text);
      m_status.last_order_ticket       = (ulong)StringToInteger(order_text);
      m_status.last_deal_ticket        = (ulong)StringToInteger(deal_text);
      m_status.last_broker_return_code =
         (uint)StringToInteger(retcode_text);
      m_status.last_event              = last_event;

      if(m_status.last_consumed_signal_bar < 0 ||
         (direction != "NONE" &&
          direction != "BUY" &&
          direction != "SELL") ||
         !MathIsValidNumber(m_status.last_requested_entry) ||
         !MathIsValidNumber(m_status.last_actual_entry) ||
         !MathIsValidNumber(m_status.last_stop_loss) ||
         !MathIsValidNumber(m_status.last_volume) ||
         !MathIsValidNumber(m_status.last_risk_amount) ||
         m_status.last_spread_points < 0 ||
         m_status.last_requested_entry < 0.0 ||
         m_status.last_actual_entry < 0.0 ||
         m_status.last_stop_loss < 0.0 ||
         m_status.last_volume < 0.0 ||
         m_status.last_risk_amount < 0.0)
        {
         reason = "Persistent execution-state values are invalid";
         return false;
        }

      return true;
     }

   void RecordPlanInStatus(const SolTradeExecutionPlan &plan)
     {
      m_status.last_consumed_signal_bar = plan.signal_bar_time;
      m_status.last_direction           = plan.signal_result;
      m_status.last_requested_entry     = plan.requested_entry;
      m_status.last_actual_entry        = 0.0;
      m_status.last_spread_points       = plan.spread_points;
      m_status.last_stop_loss           = plan.stop_loss;
      m_status.last_volume              = plan.volume;
      m_status.last_risk_amount         = plan.expected_risk;
      m_status.last_order_ticket        = 0;
      m_status.last_deal_ticket         = 0;
      m_status.last_broker_return_code  = 0;
      m_status.last_event               = "ORDER_ATTEMPT_CLAIMED";
     }

   void BuildRuntimeContext(const SolTradeAccountStatus &account,
                            const SolTradeMarketSnapshot &market,
                            const SolTradeRiskStatus &risk,
                            SolTradeExecutionContext &context)
     {
      ResetSolTradeExecutionContext(context);
      context.detected_environment =
         account.detected_environment;
      context.expected_environment_matches =
         account.expected_environment_matches;
      context.account_login =
         AccountInfoInteger(ACCOUNT_LOGIN);
      context.terminal_connected =
         account.terminal_connected;
      context.terminal_trading_allowed =
         account.terminal_autotrading_allowed;
      context.program_trading_allowed =
         account.program_trading_allowed;
      context.account_trading_allowed =
         account.account_trading_allowed;
      context.account_expert_allowed =
         account.account_expert_allowed;
      context.market_valid = market.valid;
      context.risk_locked =
         (!risk.state_valid ||
          risk.daily_locked ||
          risk.weekly_locked ||
          risk.emergency_locked ||
          risk.consecutive_locked ||
          m_config.emergency_stop);
      context.risk_lock_reason = risk.lock_reason;
      context.last_consumed_signal_bar =
         m_status.last_consumed_signal_bar;
      context.open_soltrade_positions =
         m_status.open_soltrade_positions;
      context.active_soltrade_orders =
         m_status.active_soltrade_orders;
      context.conflicting_symbol_positions =
         m_status.conflicting_symbol_positions;
      context.equity          = AccountInfoDouble(ACCOUNT_EQUITY);
      context.free_margin     = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
      context.bid             = market.bid;
      context.ask             = market.ask;
      context.point           = market.point;
      context.tick_size       = market.tick_size;
      context.tick_value_loss =
         SymbolInfoDouble(m_config.symbol, SYMBOL_TRADE_TICK_VALUE_LOSS);
      context.volume_min      = market.volume_min;
      context.volume_max      = market.volume_max;
      context.volume_step     = market.volume_step;
      context.digits          = market.digits;
      context.spread_points   = market.spread_points;
      context.stops_level_points =
         (int)SymbolInfoInteger(m_config.symbol, SYMBOL_TRADE_STOPS_LEVEL);
      context.order_mode =
         SymbolInfoInteger(m_config.symbol, SYMBOL_ORDER_MODE);
      context.filling_mode =
         SymbolInfoInteger(m_config.symbol, SYMBOL_FILLING_MODE);
      context.execution_mode =
         (ENUM_SYMBOL_TRADE_EXECUTION)
         SymbolInfoInteger(m_config.symbol, SYMBOL_TRADE_EXEMODE);
     }

   void BuildTradeRequest(const SolTradeExecutionPlan &plan,
                          MqlTradeRequest &request)
     {
      ZeroMemory(request);
      request.action       = plan.request_action;
      request.magic        = plan.magic_number;
      request.symbol       = plan.symbol;
      request.volume       = plan.volume;
      request.price        = plan.requested_entry;
      request.sl           = plan.stop_loss;
      request.tp           = 0.0;
      request.deviation    = (ulong)plan.deviation_points;
      request.type         = plan.order_type;
      request.type_filling = plan.filling_type;
      request.type_time    = ORDER_TIME_GTC;
      request.comment      = SOLTRADE_ORDER_COMMENT;
     }

public:
   CSolTradeExecutionEngine()
     {
      ResetSolTradeExecutionStatus(m_status);
      m_state_path = "";
      m_revision   = 0;
     }

   bool Initialise(const SolTradeConfig &config,
                   const string account_identifier_hash,
                   string &reason)
     {
      reason       = "";
      m_config     = config;
      m_state_path =
         SolTradeExecutionStatePath(config, account_identifier_hash);
      m_revision = 0;
      ResetSolTradeExecutionStatus(m_status);

      bool found = false;
      if(!LoadState(found, reason))
        {
         m_status.initialised = true;
         m_status.state_valid = false;
         m_status.state_error = reason;
         m_status.last_event  = "EXECUTION_STATE_REJECTED";
         return false;
        }

      m_status.initialised   = true;
      m_status.state_valid   = true;
      m_status.state_restored = found;
      if(found)
         m_status.last_event = "EXECUTION_STATE_RESTORED";
      else
        {
         m_status.last_event = "EXECUTION_STATE_INITIALISED";
         if(!SaveState(reason))
           {
            m_status.state_valid = false;
            m_status.state_error = reason;
            return false;
           }
        }

      RefreshExposure();
      m_revision++;
      return true;
     }

   void RefreshExposure()
     {
      bool unprotected = false;
      m_status.open_soltrade_positions =
         SolTradeCountOpenMagicPositions(m_config.magic_number,
                                         unprotected);
      m_status.active_soltrade_orders =
         SolTradeCountActiveMagicOrders(m_config.magic_number);
      m_status.conflicting_symbol_positions =
         SolTradeCountConflictingSymbolPositions(m_config.symbol,
                                                  m_config.magic_number);
      m_status.unprotected_soltrade_position = unprotected;
     }

   bool ClaimExecutionAttempt(const SolTradeExecutionPlan &plan,
                              string &reason)
     {
      reason = "";
      if(!m_status.initialised || !m_status.state_valid)
        {
         reason = "Execution state is not valid";
         return false;
        }

      if(!plan.valid || plan.signal_bar_time <= 0)
        {
         reason = "Only a fully validated execution plan can be claimed";
         return false;
        }

      if(m_status.last_consumed_signal_bar > 0 &&
         plan.signal_bar_time <= m_status.last_consumed_signal_bar)
        {
         reason =
            (plan.signal_bar_time == m_status.last_consumed_signal_bar)
            ? "Duplicate completed-candle execution attempt rejected"
            : "Stale completed-candle execution attempt rejected";
         return false;
        }

      RecordPlanInStatus(plan);
      if(!SaveState(reason))
        {
         m_status.state_valid = false;
         m_status.state_error = reason;
         m_status.last_event  = "EXECUTION_STATE_PERSIST_FAILED";
         return false;
        }

      m_revision++;
      return true;
     }

   bool RecordBrokerReport(const SolTradeExecutionReport &report,
                           string &reason)
     {
      reason = "";
      if(!m_status.initialised || !m_status.state_valid)
        {
         reason = "Execution state is not valid";
         return false;
        }

      m_status.last_actual_entry =
         report.actual_entry;
      m_status.last_order_ticket =
         report.order_ticket;
      m_status.last_deal_ticket =
         report.deal_ticket;
      m_status.last_broker_return_code =
         report.broker_return_code;
      m_status.last_event = report.event_type;

      if(!SaveState(reason))
        {
         m_status.state_valid = false;
         m_status.state_error = reason;
         m_status.last_event  = "EXECUTION_STATE_PERSIST_FAILED";
         return false;
        }

      m_revision++;
      return true;
     }

   void ProcessSignal(const SolTradeStrategySignal &signal,
                      const SolTradeAccountStatus &account,
                      const SolTradeMarketSnapshot &market,
                      const SolTradeRiskStatus &risk,
                      const bool use_safer_minimum_volume,
                      SolTradeExecutionReport &report)
     {
      ResetSolTradeExecutionReport(report);
      RefreshExposure();

      if(!m_status.initialised || !m_status.state_valid)
        {
         report.evaluated   = true;
         report.event_type = "EXECUTION_STATE_INVALID";
         report.reason_code = "EXECUTION_STATE_INVALID";
         report.reason      =
            StringLen(m_status.state_error) > 0
            ? m_status.state_error
            : "Execution engine state is not valid";
         report.signal_result =
            SolTradeEntrySignalName(signal.entry_signal);
         report.signal_bar_time = signal.signal_bar_time;
         return;
        }

      SolTradeExecutionContext context;
      BuildRuntimeContext(account, market, risk, context);

      SolTradeExecutionPlan plan;
      if(!SolTradePrepareExecutionPlan(m_config,
                                       signal,
                                       context,
                                       plan))
        {
         SolTradeReportFromPlan(plan, "EXECUTION_REJECTED", report);
         return;
        }

      if(use_safer_minimum_volume &&
         !SolTradeApplySaferMinimumVolume(context, plan))
        {
         SolTradeReportFromPlan(plan, "EXECUTION_REJECTED", report);
         return;
        }

      double margin_required = 0.0;
      ResetLastError();
      const bool margin_calculated =
         OrderCalcMargin(plan.order_type,
                         m_config.symbol,
                         plan.volume,
                         plan.requested_entry,
                         margin_required);
      const int margin_error = GetLastError();
      if(!SolTradeApplyMarginValidation(margin_calculated,
                                        margin_required,
                                        context.free_margin,
                                        plan))
        {
         SolTradeReportFromPlan(plan, "EXECUTION_REJECTED", report);
         report.terminal_error = margin_error;
         return;
        }

      string state_reason = "";
      if(!ClaimExecutionAttempt(plan, state_reason))
        {
         plan.reason_code = "EXECUTION_CLAIM_REJECTED";
         plan.reason      = state_reason;
         SolTradeReportFromPlan(plan,
                                "EXECUTION_STATE_REJECTED",
                                report);
         return;
        }

      MqlTradeRequest request;
      BuildTradeRequest(plan, request);

      MqlTradeCheckResult check;
      ZeroMemory(check);
      ResetLastError();
      const bool check_succeeded = OrderCheck(request, check);
      // Capture immediately. No intervening terminal call may overwrite the
      // diagnostic required to explain a failed OrderCheck call.
      const int check_error = GetLastError();
      if(!SolTradeOrderCheckAccepted(check_succeeded,
                                     check.retcode))
        {
         plan.reason_code =
            check_succeeded
            ? "ORDER_CHECK_RETCODE_REJECTED"
            : "ORDER_CHECK_CALL_FAILED";
         plan.reason =
            "OrderCheck result rejected; boolean_result=" +
            (check_succeeded ? "true" : "false") +
            "; last_error=" +
            IntegerToString(check_error) +
            "; check_retcode=" +
            IntegerToString((long)check.retcode) +
            "; check_comment=" +
            check.comment;
         SolTradeReportFromPlan(plan,
                                "ORDER_CHECK_REJECTED_NO_RETRY",
                                report);
         SolTradeAttachOrderCheckDiagnostics(check_succeeded,
                                              check_error,
                                              check,
                                              report);
         report.terminal_error = check_error;
         if(!RecordBrokerReport(report, state_reason))
           {
            report.reason_code = "EXECUTION_STATE_PERSIST_FAILED";
            report.reason += "; " + state_reason;
           }
         return;
        }

      MqlTradeResult result;
      ZeroMemory(result);
      ResetLastError();
      const bool send_succeeded = OrderSend(request, result);
      const int send_error = GetLastError();

      SolTradeReportFromPlan(plan,
                             "ORDER_REJECTED_NO_RETRY",
                             report);
      report.broker_submission_attempted = true;
      report.broker_accepted =
         (send_succeeded &&
          SolTradeBrokerRetcodeAccepted(result.retcode));
      report.fill_confirmed     = false;
      report.retry_allowed      = false;
      report.broker_reported_price = result.price;
      // OrderSend acceptance and its returned price do not by themselves prove
      // that a deal was added. The journal's actual-entry field remains empty
      // until HandleTradeTransaction observes the matching entry deal.
      report.actual_entry       = 0.0;
      report.order_ticket       = result.order;
      report.deal_ticket        = result.deal;
      report.broker_return_code = result.retcode;
      report.terminal_error     = send_error;
      report.broker_comment     = result.comment;
      report.slippage_points = 0.0;
      SolTradeAttachOrderCheckDiagnostics(check_succeeded,
                                           check_error,
                                           check,
                                           report);

      if(report.broker_accepted)
        {
         report.event_type  =
            "ORDER_REQUEST_ACCEPTED_AWAITING_TRANSACTION";
         report.reason_code =
            SolTradeBrokerRetcodeReportsFill(result.retcode)
            ? "BROKER_REPORTED_FILL_AWAITING_CONFIRMATION"
            : "BROKER_REQUEST_ACCEPTED_AWAITING_CONFIRMATION";
         report.reason =
            "Broker returned " +
            SolTradeBrokerRetcodeName(result.retcode) +
            "; fill remains unconfirmed until a matching trade transaction";
        }
      else
        {
         report.reason_code = "BROKER_REJECTED";
         report.reason =
            "OrderSend returned " +
            SolTradeBrokerRetcodeName(result.retcode) +
            "; the candle is consumed and no automatic retry is allowed";
        }

      if(!RecordBrokerReport(report, state_reason))
        {
         report.reason_code = "EXECUTION_STATE_PERSIST_FAILED";
         report.reason += "; " + state_reason;
        }
     }

   bool ConfirmMatchingEntryDealFromHistory(
      const SolTradeExecutionReport &submission,
      SolTradeExecutionReport &confirmation)
     {
      ResetSolTradeExecutionReport(confirmation);
      confirmation.evaluated       = true;
      confirmation.event_type      =
         "MATCHING_TRADE_TRANSACTION_NOT_CONFIRMED";
      confirmation.reason_code     =
         "MATCHING_ENTRY_DEAL_NOT_FOUND";
      confirmation.reason          =
         "No matching entry deal is currently available in account history";
      confirmation.signal_result   = submission.signal_result;
      confirmation.signal_bar_time = submission.signal_bar_time;
      confirmation.requested_action =
         submission.requested_action;
      confirmation.requested_order_type =
         submission.requested_order_type;
      confirmation.requested_filling_mode =
         submission.requested_filling_mode;
      confirmation.requested_symbol =
         submission.requested_symbol;
      confirmation.requested_entry = submission.requested_entry;
      confirmation.spread_points   = submission.spread_points;
      confirmation.stop_loss       = submission.stop_loss;
      confirmation.volume          = submission.volume;
      confirmation.risk_amount     = submission.risk_amount;
      confirmation.margin_required = submission.margin_required;
      confirmation.order_ticket    = submission.order_ticket;
      confirmation.deal_ticket     = submission.deal_ticket;
      confirmation.requested_magic_number =
         submission.requested_magic_number;
      confirmation.requested_deviation_points =
         submission.requested_deviation_points;
      confirmation.broker_volume_min =
         submission.broker_volume_min;
      confirmation.broker_volume_step =
         submission.broker_volume_step;
      confirmation.broker_stops_level_points =
         submission.broker_stops_level_points;
      confirmation.broker_supported_filling_mode =
         submission.broker_supported_filling_mode;
      confirmation.order_check_performed =
         submission.order_check_performed;
      confirmation.order_check_boolean_result =
         submission.order_check_boolean_result;
      confirmation.order_check_last_error =
         submission.order_check_last_error;
      confirmation.order_check_retcode =
         submission.order_check_retcode;
      confirmation.order_check_comment =
         submission.order_check_comment;
      confirmation.broker_return_code =
         submission.broker_return_code;
      confirmation.broker_comment =
         submission.broker_comment;
      confirmation.retry_allowed = false;

      if(!m_status.initialised ||
         !m_status.state_valid ||
         !submission.broker_submission_attempted ||
         !submission.broker_accepted)
        {
         confirmation.reason_code =
            "SUBMISSION_NOT_ELIGIBLE_FOR_CONFIRMATION";
         confirmation.reason =
            "Only an accepted, persisted broker submission can be matched";
         return false;
        }

      datetime history_to = TimeCurrent();
      if(history_to <= 0)
         history_to = TimeLocal();
      const datetime history_from =
         history_to > 86400 ? history_to - 86400 : 0;
      if(!HistorySelect(history_from, history_to + 60))
        {
         confirmation.reason_code = "DEAL_HISTORY_UNAVAILABLE";
         confirmation.reason =
            "MetaTrader could not select recent deal history";
         confirmation.terminal_error = GetLastError();
         return false;
        }

      ulong matching_deal = 0;
      const int deals_total = HistoryDealsTotal();
      for(int index = deals_total - 1; index >= 0; index--)
        {
         const ulong deal_ticket = HistoryDealGetTicket(index);
         if(deal_ticket == 0)
            continue;

         if((ulong)HistoryDealGetInteger(deal_ticket, DEAL_MAGIC) !=
            m_config.magic_number)
            continue;

         if(HistoryDealGetString(deal_ticket, DEAL_SYMBOL) !=
            m_config.symbol)
            continue;

         if((ENUM_DEAL_ENTRY)
               HistoryDealGetInteger(deal_ticket, DEAL_ENTRY) !=
            DEAL_ENTRY_IN)
            continue;

         const ulong deal_order =
            (ulong)HistoryDealGetInteger(deal_ticket, DEAL_ORDER);
         if(submission.order_ticket > 0 &&
            deal_order != submission.order_ticket)
            continue;

         if(submission.deal_ticket > 0 &&
            deal_ticket != submission.deal_ticket)
            continue;

         const datetime deal_time =
            (datetime)HistoryDealGetInteger(deal_ticket, DEAL_TIME);
         if(m_status.last_consumed_signal_bar > 0 &&
            deal_time < m_status.last_consumed_signal_bar)
            continue;

         matching_deal = deal_ticket;
         break;
        }

      if(matching_deal == 0)
         return false;

      confirmation.event_type =
         "MATCHING_TRADE_TRANSACTION_CONFIRMED";
      confirmation.reason_code =
         "MATCHING_ENTRY_DEAL_CONFIRMED";
      confirmation.reason =
         "A matching DEAL_ENTRY_IN history record confirms the TRADE_TRANSACTION_DEAL_ADD result";
      confirmation.actual_entry =
         HistoryDealGetDouble(matching_deal, DEAL_PRICE);
      confirmation.broker_reported_price =
         submission.broker_reported_price;
      confirmation.volume =
         HistoryDealGetDouble(matching_deal, DEAL_VOLUME);
      confirmation.order_ticket =
         (ulong)HistoryDealGetInteger(matching_deal, DEAL_ORDER);
      confirmation.deal_ticket      = matching_deal;
      confirmation.broker_accepted  = true;
      confirmation.fill_confirmed   = true;
      confirmation.retry_allowed    = false;
      confirmation.slippage_points =
         SolTradeExecutionSlippagePoints(
            confirmation.signal_result,
            confirmation.requested_entry,
            confirmation.actual_entry,
            SymbolInfoDouble(m_config.symbol, SYMBOL_POINT));

      const double tick_size =
         SymbolInfoDouble(m_config.symbol, SYMBOL_TRADE_TICK_SIZE);
      const double tick_value_loss =
         SymbolInfoDouble(m_config.symbol, SYMBOL_TRADE_TICK_VALUE_LOSS);
      if(tick_size > 0.0 &&
         tick_value_loss > 0.0 &&
         confirmation.stop_loss > 0.0 &&
         confirmation.actual_entry > 0.0 &&
         confirmation.volume > 0.0)
        {
         const double actual_stop_ticks =
            MathAbs(confirmation.actual_entry -
                    confirmation.stop_loss) / tick_size;
         const double actual_fill_risk =
            actual_stop_ticks *
            tick_value_loss *
            confirmation.volume;
         if(MathIsValidNumber(actual_fill_risk) &&
            actual_fill_risk > 0.0)
            confirmation.risk_amount = actual_fill_risk;
        }

      string state_reason = "";
      if(!RecordBrokerReport(confirmation, state_reason))
        {
         confirmation.reason_code = "EXECUTION_STATE_PERSIST_FAILED";
         confirmation.reason += "; " + state_reason;
        }
      RefreshExposure();
      return true;
     }

   bool HandleTradeTransaction(const MqlTradeTransaction &transaction,
                               SolTradeExecutionReport &report)
     {
      ResetSolTradeExecutionReport(report);
      if(!m_status.initialised ||
         transaction.type != TRADE_TRANSACTION_DEAL_ADD ||
         transaction.deal == 0)
         return false;

      if((ulong)HistoryDealGetInteger(transaction.deal, DEAL_MAGIC) !=
         m_config.magic_number)
         return false;

      const ENUM_DEAL_ENTRY deal_entry =
         (ENUM_DEAL_ENTRY)
         HistoryDealGetInteger(transaction.deal, DEAL_ENTRY);
      if(deal_entry != DEAL_ENTRY_IN)
         return false;

      report.evaluated          = true;
      report.event_type         = "ORDER_FILL_CONFIRMED";
      report.reason_code        = "BROKER_FILL_CONFIRMED";
      report.reason             =
         "Matching SolTrade entry deal was added to broker history";
      report.signal_result      = m_status.last_direction;
      report.signal_bar_time    =
         m_status.last_consumed_signal_bar;
      report.requested_entry    =
         m_status.last_requested_entry;
      report.actual_entry       =
         transaction.price > 0.0
         ? transaction.price
         : HistoryDealGetDouble(transaction.deal, DEAL_PRICE);
      report.spread_points      = m_status.last_spread_points;
      report.stop_loss          = m_status.last_stop_loss;
      report.volume             =
         transaction.volume > 0.0
         ? transaction.volume
         : HistoryDealGetDouble(transaction.deal, DEAL_VOLUME);
      report.risk_amount        = m_status.last_risk_amount;
      const double tick_size =
         SymbolInfoDouble(m_config.symbol, SYMBOL_TRADE_TICK_SIZE);
      const double tick_value_loss =
         SymbolInfoDouble(m_config.symbol, SYMBOL_TRADE_TICK_VALUE_LOSS);
      if(tick_size > 0.0 &&
         tick_value_loss > 0.0 &&
         report.stop_loss > 0.0 &&
         report.actual_entry > 0.0 &&
         report.volume > 0.0)
        {
         const double actual_stop_ticks =
            MathAbs(report.actual_entry - report.stop_loss) / tick_size;
         const double actual_fill_risk =
            actual_stop_ticks * tick_value_loss * report.volume;
         if(MathIsValidNumber(actual_fill_risk) &&
            actual_fill_risk > 0.0)
            report.risk_amount = actual_fill_risk;
        }
      report.order_ticket       = transaction.order;
      report.deal_ticket        = transaction.deal;
      report.broker_return_code = m_status.last_broker_return_code;
      report.broker_accepted    = true;
      report.fill_confirmed     = true;
      report.retry_allowed      = false;
      report.slippage_points =
         SolTradeExecutionSlippagePoints(
            report.signal_result,
            report.requested_entry,
            report.actual_entry,
            SymbolInfoDouble(m_config.symbol, SYMBOL_POINT));
      report.broker_reported_price = report.actual_entry;

      string reason = "";
      RecordBrokerReport(report, reason);
      RefreshExposure();
      if(StringLen(reason) > 0)
        {
         report.reason_code = "EXECUTION_STATE_PERSIST_FAILED";
         report.reason += "; " + reason;
        }
      return true;
     }

   void GetStatus(SolTradeExecutionStatus &status)
     {
      status = m_status;
     }

   string StatePath()
     {
      return m_state_path;
     }

   long Revision()
     {
      return m_revision;
     }
  };

#endif // SOLTRADE_EXECUTION_ENGINE_MQH
