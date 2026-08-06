#ifndef SOLTRADE_TRADE_JOURNAL_MQH
#define SOLTRADE_TRADE_JOURNAL_MQH

#include <SolTrade/Config.mqh>
#include <SolTrade/AccountGuard.mqh>
#include <SolTrade/MarketData.mqh>
#include <SolTrade/RiskEngine.mqh>
#include <SolTrade/ExecutionEngine.mqh>
#include <SolTrade/PositionManager.mqh>

class CSolTradeJournal
  {
private:
   int                    m_handle;
   SolTradeConfig         m_config;
   SolTradeAccountStatus  m_account;
   SolTradeRiskStatus     m_risk;
   string                 m_filename;

   string SafeCsvText(string value)
     {
      StringReplace(value, ",", ";");
      StringReplace(value, "\r", " ");
      StringReplace(value, "\n", " ");
      return value;
     }

   void WriteHeader()
     {
      FileWrite(m_handle,
                "timestamp",
                "event_type",
                "account_mode",
                "account_identifier_hash",
                "broker",
                "symbol",
                "timeframe",
                "bid",
                "ask",
                "spread_points",
                "strategy_version",
                "signal_result",
                "rejection_reason",
                "requested_entry",
                "actual_entry",
                "slippage_points",
                "stop_loss",
                "lot_size",
                "risk_amount",
                "balance",
                "equity",
                "daily_drawdown_percent",
                "weekly_drawdown_percent",
                "order_ticket",
                "broker_return_code",
                "final_profit_loss",
                "exit_reason",
                "details");
     }

public:
   CSolTradeJournal()
     {
      m_handle   = INVALID_HANDLE;
      m_filename = "";
      ResetSolTradeRiskStatus(m_risk);
     }

   bool Initialise(const SolTradeConfig &config,
                   const SolTradeAccountStatus &account,
                   string &reason)
     {
      reason    = "";
      m_config  = config;
      m_account = account;

      datetime journal_time = TimeCurrent();
      if(journal_time <= 0)
         journal_time = TimeLocal();

      string date_text = TimeToString(journal_time, TIME_DATE);
      StringReplace(date_text, ".", "-");

      string directory = config.journal_directory;
      StringReplace(directory, "/", "\\");
      m_filename = directory + "\\soltrade_" +
                   account.account_identifier_hash + "_" +
                   date_text + ".csv";

      ResetLastError();
      // FileOpen creates missing relative subfolders inside the MT5 file
      // sandbox. No absolute or external path is accepted by configuration.
      m_handle = FileOpen(m_filename,
                          FILE_READ | FILE_WRITE | FILE_CSV | FILE_ANSI |
                          FILE_SHARE_READ,
                          ',');

      if(m_handle == INVALID_HANDLE)
        {
         reason = "Cannot open journal file; error " +
                  IntegerToString(GetLastError());
         return false;
        }

      if(FileSize(m_handle) == 0)
         WriteHeader();
      else
         FileSeek(m_handle, 0, SEEK_END);

      FileFlush(m_handle);
      return true;
     }

   void LogEvent(const string event_type,
                 const string signal_result,
                 const string rejection_reason,
                 const string details,
                 const SolTradeMarketSnapshot &snapshot)
     {
      if(m_handle == INVALID_HANDLE)
         return;

      datetime event_time = TimeCurrent();
      if(event_time <= 0)
         event_time = TimeLocal();

      const string bid_text =
         (snapshot.bid > 0.0)
         ? DoubleToString(snapshot.bid, snapshot.digits)
         : "";
      const string ask_text =
         (snapshot.ask > 0.0)
         ? DoubleToString(snapshot.ask, snapshot.digits)
         : "";
      const string spread_text =
         (snapshot.bid > 0.0 && snapshot.ask >= snapshot.bid)
         ? IntegerToString(snapshot.spread_points)
         : "";

      // Non-execution events leave order and fill fields blank rather than
      // carrying invented values. Phase 4 execution events use LogExecution.
      FileWrite(m_handle,
                TimeToString(event_time, TIME_DATE | TIME_SECONDS),
                SafeCsvText(event_type),
                SolTradeEnvironmentName(m_account.detected_environment),
                m_account.account_identifier_hash,
                SafeCsvText(m_account.broker),
                SafeCsvText(m_config.symbol),
                SolTradeTimeframeName(m_config.timeframe),
                bid_text,
                ask_text,
                spread_text,
                SafeCsvText(m_config.strategy_version),
                SafeCsvText(signal_result),
                SafeCsvText(rejection_reason),
                "",
                "",
                "",
                "",
                "",
                m_risk.initialised
                   ? DoubleToString(m_risk.risk_budget, 2)
                   : "",
                DoubleToString(AccountInfoDouble(ACCOUNT_BALANCE), 2),
                DoubleToString(AccountInfoDouble(ACCOUNT_EQUITY), 2),
                m_risk.initialised
                   ? DoubleToString(m_risk.daily_drawdown_percent, 4)
                   : "",
                m_risk.initialised
                   ? DoubleToString(m_risk.weekly_drawdown_percent, 4)
                   : "",
                "",
                "",
                "",
                "",
                SafeCsvText(details));
      FileFlush(m_handle);
     }

   void LogExecution(const SolTradeExecutionReport &report,
                     const SolTradeMarketSnapshot &snapshot)
     {
      if(m_handle == INVALID_HANDLE)
         return;

      datetime event_time = TimeCurrent();
      if(event_time <= 0)
         event_time = TimeLocal();

      const string bid_text =
         (snapshot.bid > 0.0)
         ? DoubleToString(snapshot.bid, snapshot.digits)
         : "";
      const string ask_text =
         (snapshot.ask > 0.0)
         ? DoubleToString(snapshot.ask, snapshot.digits)
         : "";
      const string requested_text =
         (report.requested_entry > 0.0)
         ? DoubleToString(report.requested_entry, snapshot.digits)
         : "";
      const string actual_text =
         (report.actual_entry > 0.0)
         ? DoubleToString(report.actual_entry, snapshot.digits)
         : "";
      const string stop_text =
         (report.stop_loss > 0.0)
         ? DoubleToString(report.stop_loss, snapshot.digits)
         : "";
      const string volume_text =
         (report.volume > 0.0)
         ? DoubleToString(report.volume, 8)
         : "";
      const string risk_text =
         (report.risk_amount > 0.0)
         ? DoubleToString(report.risk_amount, 2)
         : "";
      const string slippage_text =
         (report.actual_entry > 0.0)
         ? DoubleToString(report.slippage_points, 2)
         : "";
      const string ticket_text =
         (report.order_ticket > 0)
         ? StringFormat("%I64u", report.order_ticket)
         : "";
      const string retcode_text =
         (report.broker_return_code > 0)
         ? IntegerToString((long)report.broker_return_code)
         : "";
      const string rejection =
         report.broker_accepted
         ? ""
         : report.reason_code + ": " + report.reason;
      const string details =
         "reason_code=" + report.reason_code +
         "; reason=" + report.reason +
         "; broker_comment=" + report.broker_comment +
         "; broker_reported_price=" +
            (report.broker_reported_price > 0.0
               ? DoubleToString(report.broker_reported_price,
                                snapshot.digits)
               : "") +
         "; terminal_error=" +
            IntegerToString(report.terminal_error) +
         "; order_check_performed=" +
            (report.order_check_performed ? "YES" : "NO") +
         "; order_check_boolean_result=" +
            (report.order_check_boolean_result ? "true" : "false") +
         "; order_check_last_error=" +
            IntegerToString(report.order_check_last_error) +
         "; order_check_retcode=" +
            IntegerToString((long)report.order_check_retcode) +
         "; order_check_comment=" +
            report.order_check_comment +
         "; requested_action=" +
            EnumToString(report.requested_action) +
            "(" + IntegerToString((int)report.requested_action) + ")" +
         "; requested_order_type=" +
            EnumToString(report.requested_order_type) +
            "(" + IntegerToString((int)report.requested_order_type) + ")" +
         "; requested_filling_mode=" +
            EnumToString(report.requested_filling_mode) +
            "(" + IntegerToString((int)report.requested_filling_mode) + ")" +
         "; requested_volume=" +
            DoubleToString(report.volume, 8) +
         "; requested_price=" +
            DoubleToString(report.requested_entry, snapshot.digits) +
         "; requested_stop_loss=" +
            DoubleToString(report.stop_loss, snapshot.digits) +
         "; requested_deviation_points=" +
            IntegerToString(report.requested_deviation_points) +
         "; requested_symbol=" +
            report.requested_symbol +
         "; requested_magic_number=" +
            StringFormat("%I64u", report.requested_magic_number) +
         "; broker_volume_min=" +
            DoubleToString(report.broker_volume_min, 8) +
         "; broker_volume_step=" +
            DoubleToString(report.broker_volume_step, 8) +
         "; broker_stops_level_points=" +
            IntegerToString(report.broker_stops_level_points) +
         "; broker_supported_filling_mode=" +
            SolTradeSupportedFillingModesName(
               report.broker_supported_filling_mode) +
            "(" +
            IntegerToString(report.broker_supported_filling_mode) + ")" +
         "; margin_required=" +
            DoubleToString(report.margin_required, 2) +
         "; deal_ticket=" +
            StringFormat("%I64u", report.deal_ticket) +
         "; fill_confirmed=" +
            (report.fill_confirmed ? "YES" : "NO") +
         "; retry_allowed=NO";

      FileWrite(m_handle,
                TimeToString(event_time, TIME_DATE | TIME_SECONDS),
                SafeCsvText(report.event_type),
                SolTradeEnvironmentName(m_account.detected_environment),
                m_account.account_identifier_hash,
                SafeCsvText(m_account.broker),
                SafeCsvText(m_config.symbol),
                SolTradeTimeframeName(m_config.timeframe),
                bid_text,
                ask_text,
                IntegerToString(report.spread_points),
                SafeCsvText(m_config.strategy_version),
                SafeCsvText(report.signal_result),
                SafeCsvText(rejection),
                requested_text,
                actual_text,
                slippage_text,
                stop_text,
                volume_text,
                risk_text,
                DoubleToString(AccountInfoDouble(ACCOUNT_BALANCE), 2),
                DoubleToString(AccountInfoDouble(ACCOUNT_EQUITY), 2),
                m_risk.initialised
                   ? DoubleToString(m_risk.daily_drawdown_percent, 4)
                   : "",
                m_risk.initialised
                   ? DoubleToString(m_risk.weekly_drawdown_percent, 4)
                   : "",
                ticket_text,
                retcode_text,
                "",
                "",
                SafeCsvText(details));
      FileFlush(m_handle);
     }

   void LogPositionManagement(
      const SolTradePositionReport &report,
      const SolTradeMarketSnapshot &snapshot)
     {
      if(m_handle == INVALID_HANDLE)
         return;

      datetime event_time = TimeCurrent();
      if(event_time <= 0)
         event_time = TimeLocal();

      const string requested_text =
         report.requested_close_price > 0.0
         ? DoubleToString(report.requested_close_price, snapshot.digits)
         : "";
      const string actual_text =
         report.actual_close_price > 0.0
         ? DoubleToString(report.actual_close_price, snapshot.digits)
         : "";
      const string slippage_text =
         report.actual_close_price > 0.0
         ? DoubleToString(report.slippage_points, 2)
         : "";
      const string volume_text =
         report.volume > 0.0
         ? DoubleToString(report.volume, 8)
         : "";
      const string rejection =
         report.broker_accepted || report.fill_confirmed
         ? ""
         : report.reason_code + ": " + report.reason;
      const string details =
         "reason_code=" + report.reason_code +
         "; reason=" + report.reason +
         "; exit_reason_code=" + report.exit_reason_code +
         "; exit_reason=" + report.exit_reason +
         "; position_ticket=" +
            StringFormat("%I64u", report.position_ticket) +
         "; position_identifier=" +
            StringFormat("%I64u", report.position_identifier) +
         "; position_direction=" + report.position_direction +
         "; stop_attached=" +
            (report.stop_attached ? "YES" : "NO") +
         "; close_claimed=" +
            (report.close_claimed ? "YES" : "NO") +
         "; requested_close_price=" + requested_text +
         "; actual_close_price=" + actual_text +
         "; requested_action=" +
            EnumToString(report.requested_action) +
            "(" + IntegerToString((int)report.requested_action) + ")" +
         "; requested_order_type=" +
            EnumToString(report.requested_order_type) +
            "(" + IntegerToString((int)report.requested_order_type) + ")" +
         "; requested_filling_mode=" +
            EnumToString(report.requested_filling_mode) +
            "(" + IntegerToString((int)report.requested_filling_mode) + ")" +
         "; requested_deviation_points=" +
            IntegerToString(report.requested_deviation_points) +
         "; requested_symbol=" + report.requested_symbol +
         "; requested_magic_number=" +
            StringFormat("%I64u", report.requested_magic_number) +
         "; order_check_performed=" +
            (report.order_check_performed ? "YES" : "NO") +
         "; order_check_boolean_result=" +
            (report.order_check_boolean_result ? "true" : "false") +
         "; order_check_last_error=" +
            IntegerToString(report.order_check_last_error) +
         "; order_check_retcode=" +
            IntegerToString((long)report.order_check_retcode) +
         "; order_check_comment=" + report.order_check_comment +
         "; order_send_performed=" +
            (report.order_send_performed ? "YES" : "NO") +
         "; order_send_boolean_result=" +
            (report.order_send_boolean_result ? "true" : "false") +
         "; order_send_last_error=" +
            IntegerToString(report.order_send_last_error) +
         "; broker_reported_price=" +
            (report.broker_reported_price > 0.0
               ? DoubleToString(report.broker_reported_price,
                                snapshot.digits)
               : "") +
         "; broker_comment=" + report.broker_comment +
         "; order_ticket=" +
            StringFormat("%I64u", report.order_ticket) +
         "; deal_ticket=" +
            StringFormat("%I64u", report.deal_ticket) +
         "; fill_confirmed=" +
            (report.fill_confirmed ? "YES" : "NO") +
         "; retry_allowed=NO";

      FileWrite(m_handle,
                TimeToString(event_time, TIME_DATE | TIME_SECONDS),
                SafeCsvText(report.event_type),
                SolTradeEnvironmentName(m_account.detected_environment),
                m_account.account_identifier_hash,
                SafeCsvText(m_account.broker),
                SafeCsvText(m_config.symbol),
                SolTradeTimeframeName(m_config.timeframe),
                snapshot.bid > 0.0
                   ? DoubleToString(snapshot.bid, snapshot.digits)
                   : "",
                snapshot.ask > 0.0
                   ? DoubleToString(snapshot.ask, snapshot.digits)
                   : "",
                snapshot.bid > 0.0 && snapshot.ask >= snapshot.bid
                   ? IntegerToString(snapshot.spread_points)
                   : "",
                SafeCsvText(m_config.strategy_version),
                SafeCsvText(report.position_direction),
                SafeCsvText(rejection),
                requested_text,
                actual_text,
                slippage_text,
                "",
                volume_text,
                "",
                DoubleToString(AccountInfoDouble(ACCOUNT_BALANCE), 2),
                DoubleToString(AccountInfoDouble(ACCOUNT_EQUITY), 2),
                m_risk.initialised
                   ? DoubleToString(m_risk.daily_drawdown_percent, 4)
                   : "",
                m_risk.initialised
                   ? DoubleToString(m_risk.weekly_drawdown_percent, 4)
                   : "",
                report.order_ticket > 0
                   ? StringFormat("%I64u", report.order_ticket)
                   : "",
                report.broker_return_code > 0
                   ? IntegerToString((long)report.broker_return_code)
                   : "",
                report.fill_confirmed
                   ? DoubleToString(report.final_profit_loss, 2)
                   : "",
                SafeCsvText(report.exit_reason_code + ": " +
                            report.exit_reason),
                SafeCsvText(details));
      FileFlush(m_handle);
     }

   void UpdateRiskStatus(const SolTradeRiskStatus &risk)
     {
      m_risk = risk;
     }

   string Filename()
     {
      return m_filename;
     }

   void Shutdown()
     {
      if(m_handle == INVALID_HANDLE)
         return;

      FileFlush(m_handle);
      FileClose(m_handle);
      m_handle = INVALID_HANDLE;
     }
  };

#endif // SOLTRADE_TRADE_JOURNAL_MQH
