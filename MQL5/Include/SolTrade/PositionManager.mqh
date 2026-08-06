#ifndef SOLTRADE_POSITION_MANAGER_MQH
#define SOLTRADE_POSITION_MANAGER_MQH

#include <SolTrade/Config.mqh>
#include <SolTrade/AccountGuard.mqh>
#include <SolTrade/MarketData.mqh>
#include <SolTrade/RiskEngine.mqh>
#include <SolTrade/StrategyBreakout.mqh>
#include <SolTrade/ExecutionEngine.mqh>

#define SOLTRADE_POSITION_STATE_SCHEMA "SOLTRADE_POSITION_STATE_V1"
#define SOLTRADE_CLOSE_COMMENT          "SolTrade TBV1 exit"

enum ENUM_SOLTRADE_CLOSE_TRIGGER
  {
   SOLTRADE_CLOSE_NONE               = 0,
   SOLTRADE_CLOSE_STRATEGY           = 1,
   SOLTRADE_CLOSE_EMERGENCY_DRAWDOWN = 2,
   SOLTRADE_CLOSE_EMERGENCY_STOP     = 3
  };

struct SolTradeManagedPosition
  {
   bool               present;
   ulong              ticket;
   ulong              identifier;
   ulong              magic_number;
   string             symbol;
   ENUM_POSITION_TYPE position_type;
   datetime           open_time;
   double             volume;
   double             open_price;
   double             stop_loss;
   bool               stop_attached;
  };

struct SolTradePositionContext
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
   double                     bid;
   double                     ask;
   double                     point;
   double                     volume_min;
   double                     volume_max;
   double                     volume_step;
   long                       filling_mode;
   ENUM_SYMBOL_TRADE_EXECUTION execution_mode;
  };

struct SolTradeClosePlan
  {
   bool                         evaluated;
   bool                         valid;
   string                       reason_code;
   string                       reason;
   ENUM_SOLTRADE_CLOSE_TRIGGER  trigger;
   string                       exit_reason_code;
   string                       exit_reason;
   datetime                     signal_bar_time;
   ulong                        position_ticket;
   ulong                        position_identifier;
   ulong                        position_magic_number;
   ENUM_POSITION_TYPE           position_type;
   bool                         stop_attached;
   ENUM_TRADE_REQUEST_ACTIONS   request_action;
   ENUM_ORDER_TYPE              close_order_type;
   ENUM_ORDER_TYPE_FILLING      filling_type;
   string                       symbol;
   double                       volume;
   double                       requested_close_price;
   double                       point;
   int                          deviation_points;
  };

struct SolTradePositionReport
  {
   bool     evaluated;
   bool     close_claimed;
   bool     order_check_performed;
   bool     order_check_boolean_result;
   int      order_check_last_error;
   uint     order_check_retcode;
   string   order_check_comment;
   bool     order_send_performed;
   bool     order_send_boolean_result;
   int      order_send_last_error;
   bool     broker_accepted;
   bool     fill_confirmed;
   bool     retry_allowed;
   string   event_type;
   string   reason_code;
   string   reason;
   string   exit_reason_code;
   string   exit_reason;
   datetime signal_bar_time;
   ulong    position_ticket;
   ulong    position_identifier;
   string   position_direction;
   bool     stop_attached;
   string   requested_symbol;
   ulong    requested_magic_number;
   ENUM_TRADE_REQUEST_ACTIONS requested_action;
   ENUM_ORDER_TYPE requested_order_type;
   ENUM_ORDER_TYPE_FILLING requested_filling_mode;
   int      requested_deviation_points;
   double   requested_close_price;
   double   broker_reported_price;
   double   actual_close_price;
   double   slippage_points;
   double   volume;
   uint     broker_return_code;
   string   broker_comment;
   ulong    order_ticket;
   ulong    deal_ticket;
   double   final_profit_loss;
  };

struct SolTradePositionStatus
  {
   bool               initialised;
   bool               state_valid;
   bool               state_restored;
   bool               management_enabled;
   bool               position_present;
   bool               position_rebuilt;
   bool               stop_attached;
   bool               manual_modification_detected;
   int                magic_position_count;
   ulong              position_ticket;
   ulong              position_identifier;
   ulong              position_magic_number;
   string             symbol;
   ENUM_POSITION_TYPE position_type;
   datetime           open_time;
   double             volume;
   double             open_price;
   double             stop_loss;
   bool               close_attempt_claimed;
   ulong              claimed_position_identifier;
   datetime           last_close_signal_bar;
   string             last_exit_reason_code;
   double             last_requested_close_price;
   double             last_actual_close_price;
   ulong              last_order_ticket;
   ulong              last_deal_ticket;
   uint               last_broker_return_code;
   ulong              last_exit_deal_ticket;
   string             last_event;
   string             state_error;
  };

void ResetSolTradeManagedPosition(SolTradeManagedPosition &position)
  {
   position.present        = false;
   position.ticket         = 0;
   position.identifier     = 0;
   position.magic_number   = 0;
   position.symbol         = "";
   position.position_type  = POSITION_TYPE_BUY;
   position.open_time      = 0;
   position.volume         = 0.0;
   position.open_price     = 0.0;
   position.stop_loss      = 0.0;
   position.stop_attached  = false;
  }

void ResetSolTradePositionContext(SolTradePositionContext &context)
  {
   context.detected_environment         = SOLTRADE_ENV_UNKNOWN;
   context.expected_environment_matches = false;
   context.account_login                = 0;
   context.terminal_connected           = false;
   context.terminal_trading_allowed     = false;
   context.program_trading_allowed      = false;
   context.account_trading_allowed      = false;
   context.account_expert_allowed       = false;
   context.market_valid                 = false;
   context.bid                          = 0.0;
   context.ask                          = 0.0;
   context.point                        = 0.0;
   context.volume_min                   = 0.0;
   context.volume_max                   = 0.0;
   context.volume_step                  = 0.0;
   context.filling_mode                 = 0;
   context.execution_mode               = SYMBOL_TRADE_EXECUTION_MARKET;
  }

void ResetSolTradeClosePlan(SolTradeClosePlan &plan)
  {
   plan.evaluated             = false;
   plan.valid                 = false;
   plan.reason_code           = "NOT_EVALUATED";
   plan.reason                = "Position close has not been evaluated";
   plan.trigger               = SOLTRADE_CLOSE_NONE;
   plan.exit_reason_code      = "NONE";
   plan.exit_reason           = "";
   plan.signal_bar_time       = 0;
   plan.position_ticket       = 0;
   plan.position_identifier   = 0;
   plan.position_magic_number = 0;
   plan.position_type         = POSITION_TYPE_BUY;
   plan.stop_attached         = false;
   plan.request_action        = TRADE_ACTION_DEAL;
   plan.close_order_type      = ORDER_TYPE_SELL;
   plan.filling_type          = ORDER_FILLING_FOK;
   plan.symbol                = "";
   plan.volume                = 0.0;
   plan.requested_close_price = 0.0;
   plan.point                 = 0.0;
   plan.deviation_points      = 0;
  }

void ResetSolTradePositionReport(SolTradePositionReport &report)
  {
   report.evaluated                  = false;
   report.close_claimed              = false;
   report.order_check_performed      = false;
   report.order_check_boolean_result = false;
   report.order_check_last_error     = 0;
   report.order_check_retcode        = 0;
   report.order_check_comment        = "";
   report.order_send_performed       = false;
   report.order_send_boolean_result  = false;
   report.order_send_last_error      = 0;
   report.broker_accepted            = false;
   report.fill_confirmed             = false;
   report.retry_allowed              = false;
   report.event_type                 = "POSITION_MANAGEMENT_NOT_EVALUATED";
   report.reason_code                = "NOT_EVALUATED";
   report.reason                     = "Position management has not been evaluated";
   report.exit_reason_code           = "NONE";
   report.exit_reason                = "";
   report.signal_bar_time            = 0;
   report.position_ticket            = 0;
   report.position_identifier        = 0;
   report.position_direction         = "NONE";
   report.stop_attached              = false;
   report.requested_symbol           = "";
   report.requested_magic_number     = 0;
   report.requested_action           = TRADE_ACTION_DEAL;
   report.requested_order_type       = ORDER_TYPE_SELL;
   report.requested_filling_mode     = ORDER_FILLING_FOK;
   report.requested_deviation_points = 0;
   report.requested_close_price      = 0.0;
   report.broker_reported_price      = 0.0;
   report.actual_close_price         = 0.0;
   report.slippage_points            = 0.0;
   report.volume                     = 0.0;
   report.broker_return_code         = 0;
   report.broker_comment             = "";
   report.order_ticket               = 0;
   report.deal_ticket                = 0;
   report.final_profit_loss          = 0.0;
  }

void ResetSolTradePositionStatus(SolTradePositionStatus &status)
  {
   status.initialised                   = false;
   status.state_valid                  = false;
   status.state_restored               = false;
   status.management_enabled           = false;
   status.position_present             = false;
   status.position_rebuilt             = false;
   status.stop_attached                = false;
   status.manual_modification_detected = false;
   status.magic_position_count         = 0;
   status.position_ticket              = 0;
   status.position_identifier          = 0;
   status.position_magic_number        = 0;
   status.symbol                       = "";
   status.position_type                = POSITION_TYPE_BUY;
   status.open_time                    = 0;
   status.volume                       = 0.0;
   status.open_price                   = 0.0;
   status.stop_loss                    = 0.0;
   status.close_attempt_claimed        = false;
   status.claimed_position_identifier  = 0;
   status.last_close_signal_bar        = 0;
   status.last_exit_reason_code        = "";
   status.last_requested_close_price   = 0.0;
   status.last_actual_close_price      = 0.0;
   status.last_order_ticket            = 0;
   status.last_deal_ticket             = 0;
   status.last_broker_return_code      = 0;
   status.last_exit_deal_ticket        = 0;
   status.last_event                   = "Position Manager is not initialised";
   status.state_error                  = "";
  }

string SolTradePositionDirectionName(const ENUM_POSITION_TYPE position_type)
  {
   return position_type == POSITION_TYPE_SELL ? "SELL" : "BUY";
  }

string SolTradeCloseTriggerName(const ENUM_SOLTRADE_CLOSE_TRIGGER trigger)
  {
   switch(trigger)
     {
      case SOLTRADE_CLOSE_STRATEGY:           return "STRATEGY";
      case SOLTRADE_CLOSE_EMERGENCY_DRAWDOWN: return "EMERGENCY_DRAWDOWN";
      case SOLTRADE_CLOSE_EMERGENCY_STOP:     return "EMERGENCY_STOP";
      default:                                return "NONE";
     }
  }

double SolTradeCloseSlippagePoints(
   const ENUM_POSITION_TYPE position_type,
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

   // Positive values are adverse: a long closes lower than requested and a
   // short closes higher than requested.
   if(position_type == POSITION_TYPE_SELL)
      return (actual_price - requested_price) / point;

   return (requested_price - actual_price) / point;
  }

void SolTradeRejectClosePlan(SolTradeClosePlan &plan,
                             const string reason_code,
                             const string reason)
  {
   plan.evaluated   = true;
   plan.valid       = false;
   plan.reason_code = reason_code;
   plan.reason      = reason;
  }

bool SolTradeValidateCloseEnvironment(
   const SolTradeConfig &config,
   const SolTradePositionContext &context,
   string &reason_code,
   string &reason)
  {
   reason_code = "";
   reason      = "";

   // Real-account refusal is evaluated first so neither a configured
   // environment mismatch nor the Algo Trading button can mask or bypass the
   // unconditional Phase 5 prohibition.
   if(context.detected_environment == SOLTRADE_ENV_LIVE)
     {
      reason_code = "REAL_ACCOUNT_POSITION_MANAGEMENT_FORBIDDEN";
      reason =
         "Phase 5 rejects real-account position management regardless of terminal permissions";
      return false;
     }

   if(!context.expected_environment_matches)
     {
      reason_code = "POSITION_ENVIRONMENT_MISMATCH";
      reason = "Configured and detected environments do not match";
      return false;
     }

   if(context.detected_environment == SOLTRADE_ENV_UNKNOWN)
     {
      reason_code = "UNKNOWN_ACCOUNT_POSITION_MANAGEMENT_FORBIDDEN";
      reason = "Unknown account mode cannot manage a position";
      return false;
     }

   if(context.detected_environment == SOLTRADE_ENV_DEMO)
     {
      if(config.approved_demo_account <= 0 ||
         context.account_login != config.approved_demo_account)
        {
         reason_code = "POSITION_DEMO_ACCOUNT_NOT_APPROVED";
         reason = "Connected demo login does not match ApprovedDemoAccount";
         return false;
        }
     }

   if(!context.terminal_connected &&
      context.detected_environment != SOLTRADE_ENV_BACKTEST)
     {
      reason_code = "POSITION_TERMINAL_DISCONNECTED";
      reason = "Terminal is not connected";
      return false;
     }

   if(!context.terminal_trading_allowed ||
      !context.program_trading_allowed ||
      !context.account_trading_allowed ||
      !context.account_expert_allowed)
     {
      reason_code = "POSITION_TRADING_PERMISSION_DISABLED";
      reason =
         "Terminal, program, account, or Expert trading permission is disabled";
      return false;
     }

   return true;
  }

bool SolTradePrepareClosePlan(
   const SolTradeConfig &config,
   const SolTradePositionContext &context,
   const SolTradeManagedPosition &position,
   const SolTradeStrategySignal &signal,
   const ENUM_SOLTRADE_CLOSE_TRIGGER trigger,
   SolTradeClosePlan &plan)
  {
   ResetSolTradeClosePlan(plan);
   plan.evaluated             = true;
   plan.trigger               = trigger;
   plan.signal_bar_time       = signal.signal_bar_time;
   plan.position_ticket       = position.ticket;
   plan.position_identifier   = position.identifier;
   plan.position_magic_number = position.magic_number;
   plan.position_type         = position.position_type;
   plan.stop_attached         = position.stop_attached;
   plan.request_action        = TRADE_ACTION_DEAL;
   plan.symbol                = position.symbol;
   plan.volume                = position.volume;
   plan.point                 = context.point;
   plan.deviation_points      = config.max_slippage_points;

   if(!position.present ||
      position.ticket == 0 ||
      position.identifier == 0)
     {
      SolTradeRejectClosePlan(plan,
                              "NO_MANAGED_POSITION",
                              "No broker position is available to manage");
      return false;
     }

   if(position.magic_number != config.magic_number)
     {
      SolTradeRejectClosePlan(
         plan,
         "POSITION_MAGIC_MISMATCH",
         "Position does not carry the configured SolTrade magic number");
      return false;
     }

   if(position.symbol != config.symbol)
     {
      SolTradeRejectClosePlan(
         plan,
         "POSITION_SYMBOL_MISMATCH",
         "SolTrade V1 manages only the configured EURUSD symbol");
      return false;
     }

   if(!SolTradeBacktestManagementEnabled(
         config,
         context.detected_environment))
     {
      SolTradeRejectClosePlan(
         plan,
         "POSITION_MANAGEMENT_DISABLED",
         context.detected_environment == SOLTRADE_ENV_BACKTEST
            ? "EnableBacktestPositionManagement is false"
            : "EnablePositionManagement is false");
      return false;
     }

   if(context.detected_environment == SOLTRADE_ENV_BACKTEST)
     {
      const datetime decision_time =
         signal.signal_bar_time > 0
         ? signal.signal_bar_time
         : TimeCurrent();
      if(decision_time < config.research_start_inclusive ||
         decision_time >= config.research_end_exclusive)
        {
         SolTradeRejectClosePlan(
            plan,
            "BACKTEST_CLOSE_OUTSIDE_DATASET",
            "Close decision is outside the registered dataset interval");
         return false;
        }
     }

   string reason_code = "";
   string reason      = "";
   if(!SolTradeValidateCloseEnvironment(config,
                                        context,
                                        reason_code,
                                        reason))
     {
      SolTradeRejectClosePlan(plan, reason_code, reason);
      return false;
     }

   if(!context.market_valid ||
      !MathIsValidNumber(context.bid) ||
      !MathIsValidNumber(context.ask) ||
      !MathIsValidNumber(context.point) ||
      context.bid <= 0.0 ||
      context.ask < context.bid ||
      context.point <= 0.0)
     {
      SolTradeRejectClosePlan(
         plan,
         "POSITION_CLOSE_MARKET_INVALID",
         "A valid current quote is required before a close request");
      return false;
     }

   if(position.position_type != POSITION_TYPE_BUY &&
      position.position_type != POSITION_TYPE_SELL)
     {
      SolTradeRejectClosePlan(plan,
                              "POSITION_TYPE_UNSUPPORTED",
                              "Only BUY and SELL positions are supported");
      return false;
     }

   if(trigger == SOLTRADE_CLOSE_EMERGENCY_DRAWDOWN)
     {
      plan.exit_reason_code = "EMERGENCY_DRAWDOWN_EXIT";
      plan.exit_reason =
         "Account emergency drawdown lock requires SolTrade closure";
     }
   else if(trigger == SOLTRADE_CLOSE_EMERGENCY_STOP)
     {
      plan.exit_reason_code = "EMERGENCY_STOP_EXIT";
      plan.exit_reason =
         "EmergencyStop requires SolTrade closure";
     }
   else if(trigger == SOLTRADE_CLOSE_STRATEGY)
     {
      if(!signal.evaluated || !signal.valid ||
         signal.signal_bar_time <= 0)
        {
         SolTradeRejectClosePlan(
            plan,
            "POSITION_EXIT_SIGNAL_INVALID",
            "A valid completed-candle strategy signal is required");
         return false;
        }

      if(position.position_type == POSITION_TYPE_BUY &&
         signal.exit_signal != SOLTRADE_EXIT_LONG)
        {
         SolTradeRejectClosePlan(
            plan,
            "BUY_REQUIRES_EXIT_LONG",
            "A BUY position closes only on approved EXIT_LONG");
         return false;
        }

      if(position.position_type == POSITION_TYPE_SELL &&
         signal.exit_signal != SOLTRADE_EXIT_SHORT)
        {
         SolTradeRejectClosePlan(
            plan,
            "SELL_REQUIRES_EXIT_SHORT",
            "A SELL position closes only on approved EXIT_SHORT");
         return false;
        }

      plan.exit_reason_code = signal.exit_reason_code;
      plan.exit_reason      = signal.exit_reason;
     }
   else
     {
      SolTradeRejectClosePlan(plan,
                              "POSITION_CLOSE_TRIGGER_MISSING",
                              "No approved strategy or emergency trigger exists");
      return false;
     }

   if(!SolTradeValidateOrderVolume(position.volume,
                                   context.volume_min,
                                   context.volume_max,
                                   context.volume_step,
                                   reason))
     {
      SolTradeRejectClosePlan(plan,
                              "POSITION_CLOSE_VOLUME_INVALID",
                              reason);
      return false;
     }

   if(!SolTradeResolveFillingType(context.filling_mode,
                                  context.execution_mode,
                                  plan.filling_type,
                                  reason))
     {
      SolTradeRejectClosePlan(plan,
                              "POSITION_CLOSE_FILLING_INVALID",
                              reason);
      return false;
     }

   plan.close_order_type =
      position.position_type == POSITION_TYPE_BUY
      ? ORDER_TYPE_SELL
      : ORDER_TYPE_BUY;
   plan.requested_close_price =
      position.position_type == POSITION_TYPE_BUY
      ? context.bid
      : context.ask;
   plan.valid       = true;
   plan.reason_code = "POSITION_CLOSE_REQUEST_VALID";
   plan.reason =
      "Magic, direction, environment, quote, volume, and filling checks passed";
   return true;
  }

void SolTradePositionReportFromPlan(const SolTradeClosePlan &plan,
                                    const string event_type,
                                    SolTradePositionReport &report)
  {
   ResetSolTradePositionReport(report);
   report.evaluated                  = true;
   report.event_type                 = event_type;
   report.reason_code                = plan.reason_code;
   report.reason                     = plan.reason;
   report.exit_reason_code           = plan.exit_reason_code;
   report.exit_reason                = plan.exit_reason;
   report.signal_bar_time            = plan.signal_bar_time;
   report.position_ticket            = plan.position_ticket;
   report.position_identifier        = plan.position_identifier;
   report.position_direction         =
      SolTradePositionDirectionName(plan.position_type);
   report.stop_attached              = plan.stop_attached;
   report.requested_symbol           = plan.symbol;
   report.requested_magic_number     = plan.position_magic_number;
   report.requested_action           = plan.request_action;
   report.requested_order_type       = plan.close_order_type;
   report.requested_filling_mode     = plan.filling_type;
   report.requested_deviation_points = plan.deviation_points;
   report.requested_close_price      = plan.requested_close_price;
   report.volume                     = plan.volume;
   report.retry_allowed              = false;
  }

double SolTradeCloseReportSlippage(const SolTradePositionReport &report,
                                   const double point)
  {
   const ENUM_POSITION_TYPE position_type =
      report.position_direction == "SELL"
      ? POSITION_TYPE_SELL
      : POSITION_TYPE_BUY;
   return SolTradeCloseSlippagePoints(position_type,
                                      report.requested_close_price,
                                      report.actual_close_price,
                                      point);
  }

void SolTradeBuildCloseRequest(const SolTradeClosePlan &plan,
                               MqlTradeRequest &request)
  {
   ZeroMemory(request);
   request.action       = plan.request_action;
   request.position     = plan.position_ticket;
   request.magic        = plan.position_magic_number;
   request.symbol       = plan.symbol;
   request.volume       = plan.volume;
   request.price        = plan.requested_close_price;
   request.deviation    = (ulong)plan.deviation_points;
   request.type         = plan.close_order_type;
   request.type_filling = plan.filling_type;
   request.type_time    = ORDER_TIME_GTC;
   request.comment      = SOLTRADE_CLOSE_COMMENT;
  }

bool SolTradeExitDealMatches(
   const ENUM_DEAL_ENTRY entry,
   const string deal_symbol,
   const string expected_symbol,
   const ulong position_identifier,
   const ulong tracked_position_identifier,
   const ulong claimed_position_identifier,
   const ulong deal_ticket,
   const ulong last_exit_deal_ticket)
  {
   if(deal_ticket == 0 ||
      deal_ticket == last_exit_deal_ticket ||
      (entry != DEAL_ENTRY_OUT &&
       entry != DEAL_ENTRY_OUT_BY &&
       entry != DEAL_ENTRY_INOUT) ||
      position_identifier == 0 ||
      (position_identifier != tracked_position_identifier &&
       position_identifier != claimed_position_identifier))
      return false;

   return (StringLen(expected_symbol) > 0 &&
           deal_symbol == expected_symbol);
  }

string SolTradePositionStatePath(const SolTradeConfig &config,
                                 const string account_identifier_hash)
  {
   string state_directory = config.execution_state_directory;
   StringReplace(state_directory, "/", "\\");
   return state_directory + "\\position_" + account_identifier_hash + "_" +
          StringFormat("%I64u", config.magic_number) + ".csv";
  }

bool SolTradeFindBrokerManagedPosition(
   const SolTradeConfig &config,
   SolTradeManagedPosition &position,
   int &magic_position_count)
  {
   ResetSolTradeManagedPosition(position);
   magic_position_count = 0;

   const int total = PositionsTotal();
   for(int index = 0; index < total; index++)
     {
      const ulong ticket = PositionGetTicket(index);
      if(ticket == 0)
         continue;

      const ulong magic = (ulong)PositionGetInteger(POSITION_MAGIC);
      if(magic != config.magic_number)
         continue;

      magic_position_count++;
      if(PositionGetString(POSITION_SYMBOL) != config.symbol)
         continue;

      position.present        = true;
      position.ticket         = ticket;
      position.identifier     =
         (ulong)PositionGetInteger(POSITION_IDENTIFIER);
      position.magic_number   = magic;
      position.symbol         = PositionGetString(POSITION_SYMBOL);
      position.position_type  =
         (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      position.open_time      =
         (datetime)PositionGetInteger(POSITION_TIME);
      position.volume         = PositionGetDouble(POSITION_VOLUME);
      position.open_price     = PositionGetDouble(POSITION_PRICE_OPEN);
      position.stop_loss      = PositionGetDouble(POSITION_SL);
      position.stop_attached  = position.stop_loss > 0.0;
     }

   return true;
  }

class CSolTradePositionManager
  {
private:
   SolTradeConfig         m_config;
   SolTradePositionStatus m_status;
   string                 m_state_path;
   bool                   m_state_exists;

   string StatePayload()
     {
      return
         SOLTRADE_POSITION_STATE_SCHEMA + "|" +
         (m_status.position_present ? "1" : "0") + "|" +
         StringFormat("%I64u", m_status.position_ticket) + "|" +
         StringFormat("%I64u", m_status.position_identifier) + "|" +
         StringFormat("%I64u", m_status.position_magic_number) + "|" +
         m_status.symbol + "|" +
         IntegerToString((int)m_status.position_type) + "|" +
         IntegerToString(m_status.open_time) + "|" +
         DoubleToString(m_status.volume, 8) + "|" +
         DoubleToString(m_status.open_price, 10) + "|" +
         DoubleToString(m_status.stop_loss, 10) + "|" +
         (m_status.close_attempt_claimed ? "1" : "0") + "|" +
         StringFormat("%I64u", m_status.claimed_position_identifier) + "|" +
         IntegerToString(m_status.last_close_signal_bar) + "|" +
         m_status.last_exit_reason_code + "|" +
         DoubleToString(m_status.last_requested_close_price, 10) + "|" +
         DoubleToString(m_status.last_actual_close_price, 10) + "|" +
         StringFormat("%I64u", m_status.last_order_ticket) + "|" +
         StringFormat("%I64u", m_status.last_deal_ticket) + "|" +
         IntegerToString((long)m_status.last_broker_return_code) + "|" +
         StringFormat("%I64u", m_status.last_exit_deal_ticket) + "|" +
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
         reason = "Cannot open temporary position-state file; error " +
                  IntegerToString(GetLastError());
         return false;
        }

      const string payload = StatePayload();
      const uint written =
         FileWrite(handle,
                   SOLTRADE_POSITION_STATE_SCHEMA,
                   m_status.position_present ? "1" : "0",
                   StringFormat("%I64u", m_status.position_ticket),
                   StringFormat("%I64u", m_status.position_identifier),
                   StringFormat("%I64u", m_status.position_magic_number),
                   m_status.symbol,
                   IntegerToString((int)m_status.position_type),
                   IntegerToString(m_status.open_time),
                   DoubleToString(m_status.volume, 8),
                   DoubleToString(m_status.open_price, 10),
                   DoubleToString(m_status.stop_loss, 10),
                   m_status.close_attempt_claimed ? "1" : "0",
                   StringFormat("%I64u",
                                m_status.claimed_position_identifier),
                   IntegerToString(m_status.last_close_signal_bar),
                   m_status.last_exit_reason_code,
                   DoubleToString(m_status.last_requested_close_price, 10),
                   DoubleToString(m_status.last_actual_close_price, 10),
                   StringFormat("%I64u", m_status.last_order_ticket),
                   StringFormat("%I64u", m_status.last_deal_ticket),
                   IntegerToString((long)m_status.last_broker_return_code),
                   StringFormat("%I64u", m_status.last_exit_deal_ticket),
                   m_status.last_event,
                   SolTradeExecutionStateChecksum(payload));
      FileFlush(handle);
      FileClose(handle);

      if(written == 0)
        {
         FileDelete(temporary_path);
         reason = "Position-state write returned zero bytes";
         return false;
        }

      ResetLastError();
      if(!FileMove(temporary_path, 0, m_state_path, FILE_REWRITE))
        {
         reason = "Cannot replace persistent position-state file; error " +
                  IntegerToString(GetLastError());
         FileDelete(temporary_path);
         return false;
        }

      m_state_exists = true;
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
         reason = "Cannot open persistent position-state file; error " +
                  IntegerToString(GetLastError());
         return false;
        }

      string fields[23];
      for(int index = 0; index < 23; index++)
         fields[index] = FileReadString(handle);
      FileClose(handle);

      if(fields[0] != SOLTRADE_POSITION_STATE_SCHEMA)
        {
         reason = "Position-state schema is missing or unsupported";
         return false;
        }

      string payload = fields[0];
      for(int index = 1; index < 22; index++)
         payload += "|" + fields[index];
      if(fields[22] != SolTradeExecutionStateChecksum(payload))
        {
         reason = "Persistent position-state checksum does not match";
         return false;
        }

      m_status.position_present =
         StringToInteger(fields[1]) == 1;
      m_status.position_ticket =
         (ulong)StringToInteger(fields[2]);
      m_status.position_identifier =
         (ulong)StringToInteger(fields[3]);
      m_status.position_magic_number =
         (ulong)StringToInteger(fields[4]);
      m_status.symbol = fields[5];
      m_status.position_type =
         (ENUM_POSITION_TYPE)StringToInteger(fields[6]);
      m_status.open_time =
         (datetime)StringToInteger(fields[7]);
      m_status.volume = StringToDouble(fields[8]);
      m_status.open_price = StringToDouble(fields[9]);
      m_status.stop_loss = StringToDouble(fields[10]);
      m_status.close_attempt_claimed =
         StringToInteger(fields[11]) == 1;
      m_status.claimed_position_identifier =
         (ulong)StringToInteger(fields[12]);
      m_status.last_close_signal_bar =
         (datetime)StringToInteger(fields[13]);
      m_status.last_exit_reason_code = fields[14];
      m_status.last_requested_close_price =
         StringToDouble(fields[15]);
      m_status.last_actual_close_price =
         StringToDouble(fields[16]);
      m_status.last_order_ticket =
         (ulong)StringToInteger(fields[17]);
      m_status.last_deal_ticket =
         (ulong)StringToInteger(fields[18]);
      m_status.last_broker_return_code =
         (uint)StringToInteger(fields[19]);
      m_status.last_exit_deal_ticket =
         (ulong)StringToInteger(fields[20]);
      m_status.last_event = fields[21];

      if((fields[1] != "0" && fields[1] != "1") ||
         (fields[11] != "0" && fields[11] != "1") ||
         (m_status.position_type != POSITION_TYPE_BUY &&
          m_status.position_type != POSITION_TYPE_SELL) ||
         !MathIsValidNumber(m_status.volume) ||
         !MathIsValidNumber(m_status.open_price) ||
         !MathIsValidNumber(m_status.stop_loss) ||
         !MathIsValidNumber(m_status.last_requested_close_price) ||
         !MathIsValidNumber(m_status.last_actual_close_price) ||
         m_status.volume < 0.0 ||
         m_status.open_price < 0.0 ||
         m_status.stop_loss < 0.0 ||
         m_status.last_requested_close_price < 0.0 ||
         m_status.last_actual_close_price < 0.0)
        {
         reason = "Persistent position-state values are invalid";
         return false;
        }

      m_status.stop_attached =
         m_status.position_present && m_status.stop_loss > 0.0;
      return true;
     }

   bool ApplySnapshot(const SolTradeManagedPosition &position,
                      const int magic_position_count,
                      string &reason)
     {
      reason = "";
      if(magic_position_count > SOLTRADE_MAX_OPEN_POSITIONS)
        {
         m_status.state_valid = false;
         m_status.state_error =
            "More than one SolTrade magic-number position exists";
         m_status.last_event = "MULTIPLE_SOLTRADE_POSITIONS_DETECTED";
         return false;
        }

      if(magic_position_count == 1 && !position.present)
        {
         m_status.state_valid = false;
         m_status.state_error =
            "A SolTrade magic-number position exists on an unsupported symbol";
         m_status.last_event = "SOLTRADE_POSITION_SYMBOL_MISMATCH";
         return false;
        }

      bool changed = !m_state_exists;
      m_status.magic_position_count = magic_position_count;
      m_status.manual_modification_detected = false;

      if(position.present)
        {
         const bool same_position =
            (m_status.position_identifier == position.identifier &&
             position.identifier > 0);
         if(!same_position)
           {
            m_status.close_attempt_claimed       = false;
            m_status.claimed_position_identifier = 0;
            m_status.last_close_signal_bar       = 0;
            m_status.last_exit_reason_code       = "";
            m_status.last_requested_close_price  = 0.0;
            m_status.last_actual_close_price     = 0.0;
            m_status.last_order_ticket           = 0;
            m_status.last_deal_ticket            = 0;
            m_status.last_broker_return_code     = 0;
            m_status.last_exit_deal_ticket       = 0;
            changed = true;
           }
         else if(m_status.position_present &&
                 (MathAbs(m_status.volume - position.volume) > 1e-10 ||
                  MathAbs(m_status.stop_loss - position.stop_loss) > 1e-10))
           {
            m_status.manual_modification_detected = true;
            changed = true;
           }

         if(!m_status.position_present ||
            m_status.position_ticket != position.ticket ||
            m_status.position_identifier != position.identifier ||
            m_status.position_magic_number != position.magic_number ||
            m_status.symbol != position.symbol ||
            m_status.position_type != position.position_type ||
            m_status.open_time != position.open_time ||
            MathAbs(m_status.volume - position.volume) > 1e-10 ||
            MathAbs(m_status.open_price - position.open_price) > 1e-10 ||
            MathAbs(m_status.stop_loss - position.stop_loss) > 1e-10)
            changed = true;

         m_status.position_present      = true;
         m_status.position_ticket       = position.ticket;
         m_status.position_identifier   = position.identifier;
         m_status.position_magic_number = position.magic_number;
         m_status.symbol                = position.symbol;
         m_status.position_type         = position.position_type;
         m_status.open_time             = position.open_time;
         m_status.volume                = position.volume;
         m_status.open_price            = position.open_price;
         m_status.stop_loss             = position.stop_loss;
         m_status.stop_attached         = position.stop_attached;
         m_status.position_rebuilt      = m_status.state_restored;

         if(!position.stop_attached)
            m_status.last_event = "SOLTRADE_STOP_LOSS_MISSING";
         else if(m_status.manual_modification_detected)
            m_status.last_event = "SOLTRADE_POSITION_MODIFICATION_DETECTED";
         else if(m_status.state_restored)
            m_status.last_event = "SOLTRADE_POSITION_REBUILT_FROM_BROKER";
         else
            m_status.last_event = "SOLTRADE_POSITION_MONITORED";
        }
      else
        {
         if(m_status.position_present)
            changed = true;
         m_status.position_present  = false;
         m_status.position_ticket   = 0;
         m_status.stop_attached     = false;
         m_status.position_rebuilt  = false;
         if(StringLen(m_status.last_event) == 0 ||
            m_status.last_event == "SOLTRADE_POSITION_MONITORED" ||
            m_status.last_event == "SOLTRADE_POSITION_REBUILT_FROM_BROKER")
            m_status.last_event = "NO_SOLTRADE_POSITION";
        }

      m_status.state_valid = true;
      m_status.state_error = "";
      if(changed && !SaveState(reason))
        {
         m_status.state_valid = false;
         m_status.state_error = reason;
         m_status.last_event  = "POSITION_STATE_PERSIST_FAILED";
         return false;
        }

      return true;
     }

   void BuildRuntimeContext(const SolTradeAccountStatus &account,
                            const SolTradeMarketSnapshot &market,
                            SolTradePositionContext &context)
     {
      ResetSolTradePositionContext(context);
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
      context.bid          = market.bid;
      context.ask          = market.ask;
      context.point        = market.point;
      context.volume_min   = market.volume_min;
      context.volume_max   = market.volume_max;
      context.volume_step  = market.volume_step;
      context.filling_mode =
         SymbolInfoInteger(m_config.symbol, SYMBOL_FILLING_MODE);
      context.execution_mode =
         (ENUM_SYMBOL_TRADE_EXECUTION)
         SymbolInfoInteger(m_config.symbol, SYMBOL_TRADE_EXEMODE);
     }

   void BuildCurrentPosition(SolTradeManagedPosition &position)
     {
      ResetSolTradeManagedPosition(position);
      position.present       = m_status.position_present;
      position.ticket        = m_status.position_ticket;
      position.identifier    = m_status.position_identifier;
      position.magic_number  = m_status.position_magic_number;
      position.symbol        = m_status.symbol;
      position.position_type = m_status.position_type;
      position.open_time     = m_status.open_time;
      position.volume        = m_status.volume;
      position.open_price    = m_status.open_price;
      position.stop_loss     = m_status.stop_loss;
      position.stop_attached = m_status.stop_attached;
     }

   bool RecordReport(const SolTradePositionReport &report,
                     string &reason)
     {
      m_status.last_actual_close_price =
         report.actual_close_price;
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
         m_status.last_event  = "POSITION_STATE_PERSIST_FAILED";
         return false;
        }
      return true;
     }

public:
   CSolTradePositionManager()
     {
      ResetSolTradePositionStatus(m_status);
      m_state_path   = "";
      m_state_exists = false;
     }

   bool Initialise(const SolTradeConfig &config,
                   const string account_identifier_hash,
                   string &reason)
     {
      reason       = "";
      m_config     = config;
      m_state_path =
         SolTradePositionStatePath(config, account_identifier_hash);
      m_state_exists = false;
      ResetSolTradePositionStatus(m_status);

      bool found = false;
      if(!LoadState(found, reason))
        {
         m_status.initialised = true;
         m_status.state_valid = false;
         m_status.state_error = reason;
         m_status.last_event  = "POSITION_STATE_REJECTED";
         return false;
        }

      m_state_exists                = found;
      m_status.initialised          = true;
      m_status.state_valid          = true;
      m_status.state_restored       = found;
      m_status.management_enabled   =
         SolTradeBacktestManagementEnabled(
            config,
            DetectSolTradeEnvironment());
      m_status.last_event =
         found ? "POSITION_STATE_RESTORED" : "POSITION_STATE_INITIALISED";
      return Refresh(reason);
     }

   bool InitialiseForTest(const SolTradeConfig &config,
                          const string account_identifier_hash,
                          const SolTradeManagedPosition &position,
                          const int magic_position_count,
                          string &reason)
     {
      reason       = "";
      m_config     = config;
      m_state_path =
         SolTradePositionStatePath(config, account_identifier_hash);
      m_state_exists = false;
      ResetSolTradePositionStatus(m_status);

      bool found = false;
      if(!LoadState(found, reason))
         return false;

      m_state_exists              = found;
      m_status.initialised        = true;
      m_status.state_valid        = true;
      m_status.state_restored     = found;
      m_status.management_enabled =
         SolTradeBacktestManagementEnabled(
            config,
            DetectSolTradeEnvironment());
      return ApplySnapshot(position, magic_position_count, reason);
     }

   bool Refresh(string &reason)
     {
      reason = "";
      if(!m_status.initialised)
        {
         reason = "Position Manager is not initialised";
         return false;
        }

      SolTradeManagedPosition position;
      int magic_position_count = 0;
      if(!SolTradeFindBrokerManagedPosition(m_config,
                                            position,
                                            magic_position_count))
        {
         reason = "Broker position scan failed";
         return false;
        }
      return ApplySnapshot(position, magic_position_count, reason);
     }

   bool RefreshForTest(const SolTradeManagedPosition &position,
                       const int magic_position_count,
                       string &reason)
     {
      return ApplySnapshot(position, magic_position_count, reason);
     }

   bool ClaimCloseAttempt(const SolTradeClosePlan &plan,
                          string &reason)
     {
      reason = "";
      if(!m_status.initialised || !m_status.state_valid)
        {
         reason = "Position Manager state is not valid";
         return false;
        }

      if(!plan.valid ||
         !m_status.position_present ||
         plan.position_identifier == 0 ||
         plan.position_identifier != m_status.position_identifier)
        {
         reason =
            "Only the current fully validated SolTrade position can be claimed";
         return false;
        }

      if(m_status.close_attempt_claimed &&
         m_status.claimed_position_identifier ==
            plan.position_identifier)
        {
         reason =
            "A close attempt is already consumed for this position";
         return false;
        }

      m_status.close_attempt_claimed       = true;
      m_status.claimed_position_identifier = plan.position_identifier;
      m_status.last_close_signal_bar       = plan.signal_bar_time;
      m_status.last_exit_reason_code       = plan.exit_reason_code;
      m_status.last_requested_close_price  =
         plan.requested_close_price;
      m_status.last_actual_close_price     = 0.0;
      m_status.last_order_ticket           = 0;
      m_status.last_deal_ticket            = 0;
      m_status.last_broker_return_code     = 0;
      m_status.last_event                  = "POSITION_CLOSE_ATTEMPT_CLAIMED";
      if(!SaveState(reason))
        {
         m_status.state_valid = false;
         m_status.state_error = reason;
         m_status.last_event  = "POSITION_STATE_PERSIST_FAILED";
         return false;
        }

      return true;
     }

   void ProcessClose(const SolTradeStrategySignal &signal,
                     const ENUM_SOLTRADE_CLOSE_TRIGGER trigger,
                     const SolTradeAccountStatus &account,
                     const SolTradeMarketSnapshot &market,
                     SolTradePositionReport &report)
     {
      ResetSolTradePositionReport(report);
      string state_reason = "";
      if(!Refresh(state_reason))
        {
         report.evaluated   = true;
         report.event_type = "POSITION_STATE_INVALID";
         report.reason_code = "POSITION_STATE_INVALID";
         report.reason      = state_reason;
         return;
        }

      if(!m_status.position_present)
         return;

      SolTradePositionContext context;
      BuildRuntimeContext(account, market, context);
      SolTradeManagedPosition position;
      BuildCurrentPosition(position);
      SolTradeClosePlan plan;
      if(!SolTradePrepareClosePlan(m_config,
                                   context,
                                   position,
                                   signal,
                                   trigger,
                                   plan))
        {
         SolTradePositionReportFromPlan(plan,
                                        "POSITION_CLOSE_REJECTED",
                                        report);
         return;
        }

      if(!ClaimCloseAttempt(plan, state_reason))
        {
         plan.reason_code = "DUPLICATE_POSITION_CLOSE_ATTEMPT";
         plan.reason      = state_reason;
         SolTradePositionReportFromPlan(
            plan,
            "POSITION_CLOSE_DUPLICATE_REJECTED",
            report);
         return;
        }

      SolTradePositionReportFromPlan(plan,
                                     "POSITION_CLOSE_CLAIMED",
                                     report);
      report.close_claimed = true;

      // Re-select immediately before the broker checks so a changed ticket,
      // magic, symbol, type, or volume can never redirect the close request.
      if(!PositionSelectByTicket(plan.position_ticket) ||
         (ulong)PositionGetInteger(POSITION_MAGIC) !=
            m_config.magic_number ||
         PositionGetString(POSITION_SYMBOL) != m_config.symbol ||
         (ulong)PositionGetInteger(POSITION_IDENTIFIER) !=
            plan.position_identifier ||
         (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE) !=
            plan.position_type ||
         MathAbs(PositionGetDouble(POSITION_VOLUME) - plan.volume) > 1e-10)
        {
         report.event_type  = "POSITION_CHANGED_BEFORE_CLOSE_NO_RETRY";
         report.reason_code = "POSITION_CHANGED_AFTER_CLAIM";
         report.reason =
            "Broker position changed after the persistent close claim";
         RecordReport(report, state_reason);
         return;
        }

      MqlTradeRequest request;
      SolTradeBuildCloseRequest(plan, request);

      MqlTradeCheckResult check;
      ZeroMemory(check);
      ResetLastError();
      const bool check_succeeded = OrderCheck(request, check);
      const int check_error = GetLastError();
      report.order_check_performed      = true;
      report.order_check_boolean_result = check_succeeded;
      report.order_check_last_error     = check_error;
      report.order_check_retcode        = check.retcode;
      report.order_check_comment        = check.comment;

      if(!SolTradeOrderCheckAccepted(check_succeeded, check.retcode))
        {
         report.event_type =
            "POSITION_CLOSE_ORDER_CHECK_REJECTED_NO_RETRY";
         report.reason_code =
            check_succeeded
            ? "POSITION_CLOSE_CHECK_RETCODE_REJECTED"
            : "POSITION_CLOSE_CHECK_CALL_FAILED";
         report.reason =
            "OrderCheck rejected the close; boolean_result=" +
            (check_succeeded ? "true" : "false") +
            "; last_error=" + IntegerToString(check_error) +
            "; retcode=" + IntegerToString((long)check.retcode) +
            "; comment=" + check.comment;
         RecordReport(report, state_reason);
         return;
        }

      MqlTradeResult result;
      ZeroMemory(result);
      ResetLastError();
      const bool send_succeeded = OrderSend(request, result);
      const int send_error = GetLastError();
      report.order_send_performed      = true;
      report.order_send_boolean_result = send_succeeded;
      report.order_send_last_error     = send_error;
      report.broker_accepted =
         send_succeeded &&
         SolTradeBrokerRetcodeAccepted(result.retcode);
      report.broker_reported_price = result.price;
      report.broker_return_code     = result.retcode;
      report.broker_comment         = result.comment;
      report.order_ticket           = result.order;
      report.deal_ticket            = result.deal;
      report.fill_confirmed         = false;
      report.retry_allowed          = false;

      if(report.broker_accepted)
        {
         report.event_type =
            "POSITION_CLOSE_ACCEPTED_AWAITING_TRANSACTION";
         report.reason_code =
            "POSITION_CLOSE_BROKER_ACCEPTED";
         report.reason =
            "Close request accepted; matching exit deal is not yet confirmed";
        }
      else
        {
         report.event_type = "POSITION_CLOSE_REJECTED_NO_RETRY";
         report.reason_code = "POSITION_CLOSE_BROKER_REJECTED";
         report.reason =
            "OrderSend returned " +
            SolTradeBrokerRetcodeName(result.retcode) +
            "; no automatic retry is allowed";
        }

      if(!RecordReport(report, state_reason))
        {
         report.reason_code = "POSITION_STATE_PERSIST_FAILED";
         report.reason += "; " + state_reason;
        }
     }

   bool HandleTradeTransaction(
      const MqlTradeTransaction &transaction,
      SolTradePositionReport &report)
     {
      ResetSolTradePositionReport(report);
      if(!m_status.initialised ||
         transaction.type != TRADE_TRANSACTION_DEAL_ADD ||
         transaction.deal == 0 ||
         transaction.deal == m_status.last_exit_deal_ticket)
         return false;

      if(!HistoryDealSelect(transaction.deal))
         return false;

      const ENUM_DEAL_ENTRY entry =
         (ENUM_DEAL_ENTRY)
         HistoryDealGetInteger(transaction.deal, DEAL_ENTRY);
      const ulong position_identifier =
         (ulong)HistoryDealGetInteger(transaction.deal,
                                      DEAL_POSITION_ID);
      const string deal_symbol =
         HistoryDealGetString(transaction.deal, DEAL_SYMBOL);
      if(!SolTradeExitDealMatches(
            entry,
            deal_symbol,
            m_config.symbol,
            position_identifier,
            m_status.position_identifier,
            m_status.claimed_position_identifier,
            transaction.deal,
            m_status.last_exit_deal_ticket))
         return false;

      report.evaluated           = true;
      report.event_type          = "POSITION_EXIT_TRANSACTION_CONFIRMED";
      report.reason_code         = "MATCHING_EXIT_DEAL_CONFIRMED";
      report.reason =
         "Matching DEAL_ENTRY_OUT transaction confirms the position exit";
      report.position_ticket     = m_status.position_ticket;
      report.position_identifier = position_identifier;
      report.position_direction =
         SolTradePositionDirectionName(m_status.position_type);
      report.stop_attached       = m_status.stop_attached;
      report.requested_symbol    = m_config.symbol;
      report.requested_magic_number = m_config.magic_number;
      report.requested_close_price =
         m_status.last_requested_close_price;
      report.actual_close_price =
         HistoryDealGetDouble(transaction.deal, DEAL_PRICE);
      report.volume =
         HistoryDealGetDouble(transaction.deal, DEAL_VOLUME);
      report.order_ticket =
         (ulong)HistoryDealGetInteger(transaction.deal, DEAL_ORDER);
      report.deal_ticket         = transaction.deal;
      report.broker_return_code  =
         m_status.last_broker_return_code;
      report.broker_accepted     = true;
      report.fill_confirmed      = true;
      report.retry_allowed       = false;
      report.final_profit_loss =
         HistoryDealGetDouble(transaction.deal, DEAL_PROFIT) +
         HistoryDealGetDouble(transaction.deal, DEAL_COMMISSION) +
         HistoryDealGetDouble(transaction.deal, DEAL_SWAP) +
         HistoryDealGetDouble(transaction.deal, DEAL_FEE);
      report.slippage_points =
         SolTradeCloseReportSlippage(
            report,
            SymbolInfoDouble(m_config.symbol, SYMBOL_POINT));

      if(m_status.close_attempt_claimed &&
         m_status.claimed_position_identifier ==
            position_identifier)
        {
         report.close_claimed    = true;
         report.exit_reason_code = m_status.last_exit_reason_code;
         report.exit_reason =
            "Confirmed manager-requested " +
            m_status.last_exit_reason_code;
        }
      else
        {
         const ENUM_DEAL_REASON deal_reason =
            (ENUM_DEAL_REASON)
            HistoryDealGetInteger(transaction.deal, DEAL_REASON);
         if(deal_reason == DEAL_REASON_SL)
           {
            report.exit_reason_code = "STOP_LOSS_EXIT";
            report.exit_reason = "Broker stop-loss closed the position";
           }
         else if(deal_reason == DEAL_REASON_TP)
           {
            report.exit_reason_code = "EXTERNAL_TAKE_PROFIT_EXIT";
            report.exit_reason =
               "An external take-profit closed the position";
           }
         else
           {
            report.exit_reason_code = "MANUAL_OR_EXTERNAL_EXIT";
            report.exit_reason =
               "The position was closed outside Position Manager";
           }
        }

      m_status.position_present       = false;
      m_status.position_ticket        = 0;
      m_status.stop_attached          = false;
      m_status.last_actual_close_price =
         report.actual_close_price;
      m_status.last_order_ticket      = report.order_ticket;
      m_status.last_deal_ticket       = report.deal_ticket;
      m_status.last_exit_deal_ticket  = report.deal_ticket;
      m_status.last_event             =
         "POSITION_EXIT_TRANSACTION_CONFIRMED";

      string state_reason = "";
      if(!SaveState(state_reason))
        {
         m_status.state_valid = false;
         m_status.state_error = state_reason;
         report.reason_code   = "POSITION_STATE_PERSIST_FAILED";
         report.reason += "; " + state_reason;
        }
      return true;
     }

   bool ConfirmMatchingExitDealFromHistory(
      const SolTradePositionReport &submission,
      SolTradePositionReport &confirmation)
     {
      confirmation = submission;
      confirmation.event_type =
         "MATCHING_POSITION_EXIT_NOT_CONFIRMED";
      confirmation.reason_code =
         "MATCHING_EXIT_DEAL_NOT_FOUND";
      confirmation.reason =
         "No matching exit deal is currently available in account history";
      confirmation.actual_close_price = 0.0;
      confirmation.slippage_points    = 0.0;
      confirmation.final_profit_loss  = 0.0;
      confirmation.fill_confirmed     = false;
      confirmation.retry_allowed      = false;

      if(!m_status.initialised ||
         !m_status.state_valid ||
         !m_status.close_attempt_claimed ||
         !submission.close_claimed ||
         !submission.order_send_performed ||
         !submission.broker_accepted ||
         submission.position_identifier == 0 ||
         (submission.order_ticket == 0 &&
          submission.deal_ticket == 0))
        {
         confirmation.reason_code =
            "CLOSE_SUBMISSION_NOT_ELIGIBLE_FOR_CONFIRMATION";
         confirmation.reason =
            "Only an accepted, persisted close submission with a broker ticket can be matched";
         return false;
        }

      datetime history_to = TimeCurrent();
      if(history_to <= 0)
         history_to = TimeLocal();
      const datetime history_from =
         history_to > 86400 ? history_to - 86400 : 0;
      ResetLastError();
      if(!HistorySelect(history_from, history_to + 60))
        {
         confirmation.reason_code = "EXIT_DEAL_HISTORY_UNAVAILABLE";
         confirmation.reason =
            "MetaTrader could not select recent exit-deal history; error " +
            IntegerToString(GetLastError());
         return false;
        }

      ulong matching_deal = 0;
      const int deals_total = HistoryDealsTotal();
      for(int index = deals_total - 1; index >= 0; index--)
        {
         const ulong deal_ticket = HistoryDealGetTicket(index);
         if(deal_ticket == 0 ||
            deal_ticket == m_status.last_exit_deal_ticket)
            continue;

         if((ulong)HistoryDealGetInteger(deal_ticket, DEAL_MAGIC) !=
            m_config.magic_number)
            continue;

         if(HistoryDealGetString(deal_ticket, DEAL_SYMBOL) !=
            m_config.symbol)
            continue;

         const ENUM_DEAL_ENTRY entry =
            (ENUM_DEAL_ENTRY)
            HistoryDealGetInteger(deal_ticket, DEAL_ENTRY);
         if(entry != DEAL_ENTRY_OUT &&
            entry != DEAL_ENTRY_OUT_BY &&
            entry != DEAL_ENTRY_INOUT)
            continue;

         if((ulong)HistoryDealGetInteger(deal_ticket,
                                         DEAL_POSITION_ID) !=
            submission.position_identifier)
            continue;

         const ulong deal_order =
            (ulong)HistoryDealGetInteger(deal_ticket, DEAL_ORDER);
         if(submission.order_ticket > 0 &&
            deal_order != submission.order_ticket)
            continue;

         if(submission.deal_ticket > 0 &&
            deal_ticket != submission.deal_ticket)
            continue;

         matching_deal = deal_ticket;
         break;
        }

      if(matching_deal == 0)
         return false;

      MqlTradeTransaction transaction;
      ZeroMemory(transaction);
      transaction.type = TRADE_TRANSACTION_DEAL_ADD;
      transaction.deal = matching_deal;

      SolTradePositionReport matched;
      if(!HandleTradeTransaction(transaction, matched))
         return false;

      // The deal is authoritative for actual price, realised P/L, order, and
      // deal tickets. Preserve the immediate OrderCheck/OrderSend diagnostics
      // from the accepted submission for the combined one-shot record.
      matched.order_check_performed =
         submission.order_check_performed;
      matched.order_check_boolean_result =
         submission.order_check_boolean_result;
      matched.order_check_last_error =
         submission.order_check_last_error;
      matched.order_check_retcode =
         submission.order_check_retcode;
      matched.order_check_comment =
         submission.order_check_comment;
      matched.order_send_performed =
         submission.order_send_performed;
      matched.order_send_boolean_result =
         submission.order_send_boolean_result;
      matched.order_send_last_error =
         submission.order_send_last_error;
      matched.broker_reported_price =
         submission.broker_reported_price;
      matched.broker_return_code =
         submission.broker_return_code;
      matched.broker_comment =
         submission.broker_comment;
      matched.requested_action =
         submission.requested_action;
      matched.requested_order_type =
         submission.requested_order_type;
      matched.requested_filling_mode =
         submission.requested_filling_mode;
      matched.requested_deviation_points =
         submission.requested_deviation_points;
      matched.signal_bar_time =
         submission.signal_bar_time;
      matched.retry_allowed = false;
      confirmation = matched;
      return true;
     }

   void GetStatus(SolTradePositionStatus &status)
     {
      status = m_status;
     }

   string StatePath()
     {
      return m_state_path;
     }
  };

#endif // SOLTRADE_POSITION_MANAGER_MQH
