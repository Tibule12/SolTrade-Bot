#ifndef SOLTRADE_DASHBOARD_MQH
#define SOLTRADE_DASHBOARD_MQH

#include <SolTrade/Config.mqh>
#include <SolTrade/AccountGuard.mqh>
#include <SolTrade/MarketData.mqh>
#include <SolTrade/RiskEngine.mqh>
#include <SolTrade/StrategyBreakout.mqh>
#include <SolTrade/ExecutionEngine.mqh>
#include <SolTrade/PositionManager.mqh>

string SolTradeYesNo(const bool value)
  {
   return value ? "YES" : "NO";
  }

void RenderSolTradeDashboard(const SolTradeConfig &config,
                             const SolTradeAccountStatus &account,
                             const SolTradeMarketSnapshot &market,
                             const SolTradeRiskStatus &risk,
                             const string status,
                             const SolTradeStrategySignal &strategy,
                             const SolTradeExecutionStatus &execution,
                             const SolTradeExecutionReport &last_execution,
                             const SolTradePositionStatus &position,
                             const SolTradePositionReport &last_position)
  {
   if(!config.enable_dashboard)
     {
      Comment("");
      return;
     }

   string spread_text = "N/A";
   if(market.bid > 0.0 && market.ask >= market.bid)
      spread_text = IntegerToString(market.spread_points) + " points";

   string emergency_drawdown_text = "N/A (baseline not configured)";
   if(risk.initialised && risk.emergency_armed)
      emergency_drawdown_text =
         DoubleToString(risk.emergency_drawdown_percent, 2) + "%";

   const string daily_profit_loss_text =
      risk.initialised
      ? DoubleToString(risk.daily_profit_loss, 2) + " (" +
         DoubleToString(risk.daily_drawdown_percent, 2) + "% drawdown)"
      : "N/A";
   const string weekly_profit_loss_text =
      risk.initialised
      ? DoubleToString(risk.weekly_profit_loss, 2) + " (" +
         DoubleToString(risk.weekly_drawdown_percent, 2) + "% drawdown)"
      : "N/A";

   string entry_signal_text = "WAITING";
   string exit_signal_text  = "WAITING";
   string signal_bar_text   = "N/A";
   string entry_reason_text = strategy.entry_reason;
   string exit_reason_text  = strategy.exit_reason;
   string indicator_text    = "N/A";
   string execution_attempt_text = "NONE";
   string managed_position_text  = "NONE";
   string position_action_text   = "NONE";

   if(strategy.evaluated && !strategy.valid)
     {
      entry_signal_text = "INVALID";
      exit_signal_text  = "INVALID";
      entry_reason_text =
         strategy.entry_reason_code + ": " + strategy.entry_reason;
      exit_reason_text =
         strategy.exit_reason_code + ": " + strategy.exit_reason;
     }
   else if(strategy.valid)
     {
      entry_signal_text =
         SolTradeEntrySignalName(strategy.entry_signal);
      exit_signal_text =
         SolTradeExitSignalName(strategy.exit_signal);
      signal_bar_text =
         TimeToString(strategy.signal_bar_time,
                      TIME_DATE | TIME_MINUTES);
      entry_reason_text =
         strategy.entry_reason_code + ": " + strategy.entry_reason;
      exit_reason_text =
         strategy.exit_reason_code + ": " + strategy.exit_reason;
      indicator_text =
         "Close " + DoubleToString(strategy.signal_close, market.digits) +
         " | EMA200 " + DoubleToString(strategy.ema_200, market.digits) +
         " | ATR14 " + DoubleToString(strategy.atr_14, market.digits) +
         "\nEntry D20 H/L: " +
         DoubleToString(strategy.entry_channel_high, market.digits) +
         " / " +
         DoubleToString(strategy.entry_channel_low, market.digits) +
         "\nExit D10 H/L: " +
         DoubleToString(strategy.exit_channel_high, market.digits) +
         " / " +
         DoubleToString(strategy.exit_channel_low, market.digits) +
         "\nInitial stop distance (2 ATR): " +
         DoubleToString(strategy.initial_stop_distance, market.digits);
     }

   if(last_execution.evaluated)
     {
      execution_attempt_text =
         last_execution.event_type + " | " +
         last_execution.reason_code + "\nRequested / fill: " +
         DoubleToString(last_execution.requested_entry, market.digits) +
         " / " +
         (last_execution.actual_entry > 0.0
            ? DoubleToString(last_execution.actual_entry, market.digits)
            : "UNCONFIRMED") +
         " | lots " + DoubleToString(last_execution.volume, 2) +
         " | SL " +
         DoubleToString(last_execution.stop_loss, market.digits) +
         " | retcode " +
         IntegerToString((long)last_execution.broker_return_code);
     }

   if(position.position_present)
     {
      managed_position_text =
         SolTradePositionDirectionName(position.position_type) +
         " | ticket " +
         StringFormat("%I64u", position.position_ticket) +
         " | identifier " +
         StringFormat("%I64u", position.position_identifier) +
         " | lots " + DoubleToString(position.volume, 2) +
         " | open " +
         DoubleToString(position.open_price, market.digits) +
         " | SL " +
         (position.stop_attached
            ? DoubleToString(position.stop_loss, market.digits)
            : "MISSING");
     }

   if(last_position.evaluated)
     {
      position_action_text =
         last_position.event_type + " | " +
         last_position.reason_code + "\nExit: " +
         last_position.exit_reason_code +
         " | requested / actual " +
         DoubleToString(last_position.requested_close_price,
                        market.digits) +
         " / " +
         (last_position.actual_close_price > 0.0
            ? DoubleToString(last_position.actual_close_price,
                             market.digits)
            : "UNCONFIRMED") +
         " | retcode " +
         IntegerToString((long)last_position.broker_return_code) +
         " | retry NO";
     }

   const string panel =
      "SolTrade Bot\n" +
      "Status: " + status + "\n" +
      "Build scope: PHASE 6 TESTER RESEARCH; LIVE TRADING DISABLED\n" +
      "Strategy version: " + config.strategy_version + "\n" +
      "Account mode: " +
         SolTradeEnvironmentName(account.detected_environment) + "\n" +
      "Broker: " + account.broker + "\n" +
      "Symbol / timeframe: " + config.symbol + " / " +
         SolTradeTimeframeName(config.timeframe) + "\n" +
      "Balance: " +
         DoubleToString(AccountInfoDouble(ACCOUNT_BALANCE), 2) + "\n" +
      "Equity: " +
         DoubleToString(AccountInfoDouble(ACCOUNT_EQUITY), 2) + "\n" +
      "Emergency drawdown: " + emergency_drawdown_text + "\n" +
      "Daily P/L: " + daily_profit_loss_text + "\n" +
      "Weekly P/L: " + weekly_profit_loss_text + "\n" +
      "Consecutive losses: " +
         IntegerToString(risk.consecutive_losses) + " / " +
         IntegerToString(config.consecutive_loss_limit) + "\n" +
      "Risk lock: " +
         SolTradeYesNo(!risk.state_valid ||
                       risk.daily_locked ||
                       risk.weekly_locked ||
                       risk.emergency_locked ||
                       risk.consecutive_locked) + "\n" +
      "Demo execution enabled: " +
         SolTradeYesNo(config.enable_demo_execution) + "\n" +
      "Position management enabled: " +
         SolTradeYesNo(config.enable_position_management) + "\n" +
      "Execution environment eligible: " +
         SolTradeYesNo(account.execution_environment_eligible) + "\n" +
      "Execution state valid: " +
         SolTradeYesNo(execution.state_valid) + "\n" +
      "Open SolTrade positions: " +
         IntegerToString(execution.open_soltrade_positions) + "\n" +
      "Active SolTrade orders: " +
         IntegerToString(execution.active_soltrade_orders) + "\n" +
      "Conflicting symbol positions: " +
         IntegerToString(execution.conflicting_symbol_positions) + "\n" +
      "Unprotected SolTrade position detected: " +
         SolTradeYesNo(execution.unprotected_soltrade_position) + "\n" +
      "Position Manager state valid / restored: " +
         SolTradeYesNo(position.state_valid) + " / " +
         SolTradeYesNo(position.state_restored) + "\n" +
      "Managed position: " + managed_position_text + "\n" +
      "Stop-loss attached: " +
         SolTradeYesNo(!position.position_present ||
                       position.stop_attached) + "\n" +
      "Close attempt consumed: " +
         SolTradeYesNo(position.close_attempt_claimed) + "\n" +
      "Risk per trade: " +
         DoubleToString(config.risk_per_trade_percent, 2) +
         "% = " + DoubleToString(risk.risk_budget, 2) + "\n" +
      "Current spread: " + spread_text + "\n" +
      "Signal bar: " + signal_bar_text + "\n" +
      "Entry signal: " + entry_signal_text + "\n" +
      "Entry reason: " + entry_reason_text + "\n" +
      "Exit signal: " + exit_signal_text + "\n" +
      "Exit reason: " + exit_reason_text + "\n" +
      "Indicators: " + indicator_text + "\n" +
      "Last execution: " + execution_attempt_text + "\n" +
      "Last position action: " + position_action_text + "\n" +
      "Position state event: " + position.last_event + "\n" +
      "Execution state event: " + execution.last_event + "\n" +
      "Terminal connected: " +
         SolTradeYesNo(account.terminal_connected) + "\n" +
      "AutoTrading permission: " +
         SolTradeYesNo(account.terminal_autotrading_allowed &&
                       account.program_trading_allowed &&
                       account.account_trading_allowed &&
                       account.account_expert_allowed) + "\n" +
      "Emergency stop: " + SolTradeYesNo(config.emergency_stop);

   Comment(panel);
  }

void ClearSolTradeDashboard()
  {
   Comment("");
  }

#endif // SOLTRADE_DASHBOARD_MQH
