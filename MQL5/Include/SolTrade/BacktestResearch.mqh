#ifndef SOLTRADE_BACKTEST_RESEARCH_MQH
#define SOLTRADE_BACKTEST_RESEARCH_MQH

#include <SolTrade/Config.mqh>
#include <SolTrade/MarketData.mqh>
#include <SolTrade/ExecutionEngine.mqh>
#include <SolTrade/PositionManager.mqh>

#define SOLTRADE_RESEARCH_SCHEMA          "SOLTRADE_PHASE6_RESEARCH_V1"
#define SOLTRADE_RESEARCH_CASHFLOW_SCHEMA "SOLTRADE_PHASE6_CASHFLOW_V1"
#define SOLTRADE_RESEARCH_STATE_SCHEMA    "SOLTRADE_PHASE6_STATE_V1"

struct SolTradeResearchTrade
  {
   ulong    position_identifier;
   datetime entry_time;
   datetime exit_time;
   double   native_trade_net;
   double   spread_cost;
   double   commission_cost;
   double   swap_cost;
   double   fee_cost;
   double   adverse_entry_slippage_cost;
   double   adverse_exit_slippage_cost;
   double   native_friction;
   double   supplementary_multiplier;
   double   supplementary_charge;
   double   adjusted_trade_net;
   double   equity_before;
   double   equity_after;
   bool     naturally_closed;
   bool     crosses_start_boundary;
   bool     crosses_end_boundary;
  };

struct SolTradeResearchMetrics
  {
   bool   valid;
   string reason;
   int    closed_trades;
   double net_profit;
   double gross_profit;
   double gross_loss;
   double expectancy;
   double profit_factor;
   double maximum_equity_drawdown_percent;
   double annualized_return_percent;
   double best_trade_contribution_percent;
   double best_period_contribution_percent;
   double ending_equity;
  };

struct SolTradeResearchReconciliation
  {
   bool   valid;
   string reason;
   int    history_deals;
   int    closed_trades;
   double history_deal_net;
   double reconstructed_native_net;
   double native_tester_net;
   double history_difference;
   double tester_difference;
  };

struct SolTradeResearchRuntimeStatus
  {
   bool     initialised;
   bool     valid;
   bool     finalised;
   string   reason;
   string   trading_input_hash;
   string   canonical_material;
   string   state_directory;
   string   artifact_directory;
   datetime actual_first_tick;
   datetime actual_final_tick;
   datetime warmup_first_bar;
  };

void ResetSolTradeResearchTrade(SolTradeResearchTrade &trade)
  {
   trade.position_identifier          = 0;
   trade.entry_time                   = 0;
   trade.exit_time                    = 0;
   trade.native_trade_net             = 0.0;
   trade.spread_cost                  = 0.0;
   trade.commission_cost              = 0.0;
   trade.swap_cost                    = 0.0;
   trade.fee_cost                     = 0.0;
   trade.adverse_entry_slippage_cost  = 0.0;
   trade.adverse_exit_slippage_cost   = 0.0;
   trade.native_friction              = 0.0;
   trade.supplementary_multiplier     = 0.0;
   trade.supplementary_charge         = 0.0;
   trade.adjusted_trade_net           = 0.0;
   trade.equity_before                = 0.0;
   trade.equity_after                 = 0.0;
   trade.naturally_closed             = false;
   trade.crosses_start_boundary       = false;
   trade.crosses_end_boundary         = false;
  }

void ResetSolTradeResearchMetrics(SolTradeResearchMetrics &metrics)
  {
   metrics.valid                              = false;
   metrics.reason                             = "Not calculated";
   metrics.closed_trades                      = 0;
   metrics.net_profit                         = 0.0;
   metrics.gross_profit                       = 0.0;
   metrics.gross_loss                         = 0.0;
   metrics.expectancy                         = 0.0;
   metrics.profit_factor                      = 0.0;
   metrics.maximum_equity_drawdown_percent    = 0.0;
   metrics.annualized_return_percent          = 0.0;
   metrics.best_trade_contribution_percent    = 0.0;
   metrics.best_period_contribution_percent   = 0.0;
   metrics.ending_equity                      = 0.0;
  }

void ResetSolTradeResearchReconciliation(
   SolTradeResearchReconciliation &reconciliation)
  {
   reconciliation.valid                    = false;
   reconciliation.reason                   = "Not reconciled";
   reconciliation.history_deals            = 0;
   reconciliation.closed_trades            = 0;
   reconciliation.history_deal_net         = 0.0;
   reconciliation.reconstructed_native_net = 0.0;
   reconciliation.native_tester_net         = 0.0;
   reconciliation.history_difference       = 0.0;
   reconciliation.tester_difference        = 0.0;
  }

void ResetSolTradeResearchRuntimeStatus(
   SolTradeResearchRuntimeStatus &status)
  {
   status.initialised       = false;
   status.valid             = false;
   status.finalised         = false;
   status.reason            = "Phase 6 research is not initialised";
   status.trading_input_hash = "";
   status.canonical_material = "";
   status.state_directory   = "";
   status.artifact_directory = "";
   status.actual_first_tick = 0;
   status.actual_final_tick = 0;
   status.warmup_first_bar  = 0;
  }

string SolTradeCanonicalBool(const bool value)
  {
   return value ? "1" : "0";
  }

string SolTradeCanonicalDouble(const double value)
  {
   return DoubleToString(value, 10);
  }

string SolTradeCanonicalField(const string key, const string value)
  {
   return key + "=" + value + "\n";
  }

string SolTradeBuildTradingInputMaterial(const SolTradeConfig &config)
  {
   string material = "";
   material += SolTradeCanonicalField("schema",
                                       SOLTRADE_RESEARCH_SCHEMA);
   material += SolTradeCanonicalField("strategy_version",
                                       config.strategy_version);
   material += SolTradeCanonicalField("approved_strategy_version",
                                       config.approved_strategy_version);
   material += SolTradeCanonicalField("risk_profile",
                                       config.risk_profile);
   material += SolTradeCanonicalField("approved_risk_profile",
                                       config.approved_risk_profile);
   material += SolTradeCanonicalField(
      "magic_number",
      StringFormat("%I64u", config.magic_number));
   material += SolTradeCanonicalField("symbol", config.symbol);
   material += SolTradeCanonicalField(
      "timeframe",
      IntegerToString((int)config.timeframe));
   material += SolTradeCanonicalField(
      "minimum_history_bars",
      IntegerToString(config.minimum_history_bars));
   material += SolTradeCanonicalField(
      "max_tick_age_seconds",
      IntegerToString(config.max_tick_age_seconds));
   material += SolTradeCanonicalField(
      "max_spread_points",
      IntegerToString(config.max_spread_points));
   material += SolTradeCanonicalField(
      "max_spread_atr_percent",
      SolTradeCanonicalDouble(config.max_spread_atr_percent));
   material += SolTradeCanonicalField(
      "max_slippage_points",
      IntegerToString(config.max_slippage_points));
   material += SolTradeCanonicalField(
      "risk_per_trade_percent",
      SolTradeCanonicalDouble(config.risk_per_trade_percent));
   material += SolTradeCanonicalField(
      "daily_loss_limit_percent",
      SolTradeCanonicalDouble(config.daily_loss_limit_percent));
   material += SolTradeCanonicalField(
      "weekly_loss_limit_percent",
      SolTradeCanonicalDouble(config.weekly_loss_limit_percent));
   material += SolTradeCanonicalField(
      "emergency_drawdown_percent",
      SolTradeCanonicalDouble(config.emergency_drawdown_percent));
   material += SolTradeCanonicalField(
      "production_baseline_equity",
      SolTradeCanonicalDouble(config.production_baseline_equity));
   material += SolTradeCanonicalField(
      "consecutive_loss_limit",
      IntegerToString(config.consecutive_loss_limit));
   material += SolTradeCanonicalField(
      "reset_emergency_lock",
      SolTradeCanonicalBool(config.reset_emergency_lock));
   material += SolTradeCanonicalField(
      "expected_environment",
      IntegerToString((int)config.expected_environment));
   material += SolTradeCanonicalField(
      "enable_demo_execution",
      SolTradeCanonicalBool(config.enable_demo_execution));
   material += SolTradeCanonicalField(
      "enable_position_management",
      SolTradeCanonicalBool(config.enable_position_management));
   material += SolTradeCanonicalField(
      "approved_demo_account",
      IntegerToString(config.approved_demo_account));
   material += SolTradeCanonicalField(
      "allow_live_trading",
      SolTradeCanonicalBool(config.allow_live_trading));
   material += SolTradeCanonicalField(
      "approved_live_account",
      IntegerToString(config.approved_live_account));
   material += SolTradeCanonicalField(
      "emergency_stop",
      SolTradeCanonicalBool(config.emergency_stop));
   material += SolTradeCanonicalField(
      "enable_backtest_research",
      SolTradeCanonicalBool(config.enable_backtest_research));
   material += SolTradeCanonicalField(
      "enable_backtest_execution",
      SolTradeCanonicalBool(config.enable_backtest_execution));
   material += SolTradeCanonicalField(
      "enable_backtest_position_management",
      SolTradeCanonicalBool(
         config.enable_backtest_position_management));
   material += SolTradeCanonicalField(
      "research_manifest_id",
      config.research_manifest_id);
   material += SolTradeCanonicalField(
      "research_dataset",
      IntegerToString((int)config.research_dataset));
   material += SolTradeCanonicalField(
      "research_cost_profile",
      IntegerToString((int)config.research_cost_profile));
   material += SolTradeCanonicalField(
      "research_start_inclusive",
      IntegerToString((long)config.research_start_inclusive));
   material += SolTradeCanonicalField(
      "research_end_exclusive",
      IntegerToString((long)config.research_end_exclusive));
   material += SolTradeCanonicalField(
      "research_history_fingerprint",
      config.research_history_fingerprint);
   material += SolTradeCanonicalField(
      "research_latency_fingerprint",
      config.research_latency_fingerprint);
   material += SolTradeCanonicalField(
      "research_latency_sample_count",
      IntegerToString(config.research_latency_sample_count));
   material += SolTradeCanonicalField(
      "research_frozen_delay_ms",
      IntegerToString(config.research_frozen_delay_ms));
   material += SolTradeCanonicalField(
      "tester_tick_model",
      "EVERY_TICK_BASED_ON_REAL_TICKS");
   material += SolTradeCanonicalField(
      "tester_execution_delay_mode",
      "FIXED");
   material += SolTradeCanonicalField(
      "supplementary_cost_multiplier",
      SolTradeCanonicalDouble(
         SolTradeSupplementaryCostMultiplier(
            config.research_cost_profile)));
   material += SolTradeCanonicalField(
      "research_source_commit",
      config.research_source_commit);
   material += SolTradeCanonicalField(
      "research_build_fingerprint",
      config.research_build_fingerprint);
   material += SolTradeCanonicalField(
      "research_expected_terminal_build",
      IntegerToString(config.research_expected_terminal_build));
   material += SolTradeCanonicalField(
      "research_expected_broker_server",
      config.research_expected_broker_server);
   material += SolTradeCanonicalField(
      "research_expected_initial_deposit",
      SolTradeCanonicalDouble(
         config.research_expected_initial_deposit));
   material += SolTradeCanonicalField(
      "research_expected_deposit_currency",
      config.research_expected_deposit_currency);
   material += SolTradeCanonicalField(
      "research_expected_leverage",
      IntegerToString(config.research_expected_leverage));
   material += SolTradeCanonicalField(
      "enable_csv_journal",
      SolTradeCanonicalBool(config.enable_csv_journal));
   material += SolTradeCanonicalField(
      "enable_dashboard",
      SolTradeCanonicalBool(config.enable_dashboard));
   material += SolTradeCanonicalField(
      "dashboard_refresh_seconds",
      IntegerToString(config.dashboard_refresh_seconds));

   // Fixed approved strategy constants are hashed explicitly. They are not
   // tester parameters and cannot be changed by ExecutionInstanceId.
   material += SolTradeCanonicalField("ema_period", "200");
   material += SolTradeCanonicalField("donchian_entry_period", "20");
   material += SolTradeCanonicalField("donchian_exit_period", "10");
   material += SolTradeCanonicalField("atr_period", "14");
   material += SolTradeCanonicalField("initial_stop_atr_multiple",
                                       "2.0000000000");
   material += SolTradeCanonicalField("execution_state_schema",
                                       "SOLTRADE_EXECUTION_STATE_V1");
   material += SolTradeCanonicalField("position_state_schema",
                                       "SOLTRADE_POSITION_STATE_V1");
   material += SolTradeCanonicalField("risk_state_schema",
                                       SOLTRADE_RISK_STATE_SCHEMA);
   material += SolTradeCanonicalField("research_state_schema",
                                       SOLTRADE_RESEARCH_STATE_SCHEMA);
   return material;
  }

bool SolTradeSha256Hex(const string source,
                       string &digest_hex,
                       string &reason)
  {
   digest_hex = "";
   reason     = "";

   uchar source_bytes[];
   const int copied =
      StringToCharArray(source,
                        source_bytes,
                        0,
                        WHOLE_ARRAY,
                        CP_UTF8);
   if(copied <= 0)
     {
      reason = "Cannot encode canonical material as UTF-8";
      return false;
     }

   if(ArraySize(source_bytes) > 0 &&
      source_bytes[ArraySize(source_bytes) - 1] == 0)
      ArrayResize(source_bytes, ArraySize(source_bytes) - 1);

   uchar key[];
   ArrayResize(key, 0);
   uchar digest[];
   ResetLastError();
   const int digest_size =
      CryptEncode(CRYPT_HASH_SHA256,
                  source_bytes,
                  key,
                  digest);
   if(digest_size != 32)
     {
      reason = "SHA-256 failed; error " +
               IntegerToString(GetLastError());
      return false;
     }

   for(int index = 0; index < digest_size; index++)
      digest_hex += StringFormat("%02x", (int)digest[index]);
   return true;
  }

bool SolTradeCalculateTradingInputHash(
   const SolTradeConfig &config,
   string &canonical_material,
   string &trading_input_hash,
   string &reason)
  {
   canonical_material =
      SolTradeBuildTradingInputMaterial(config);
   return SolTradeSha256Hex(canonical_material,
                            trading_input_hash,
                            reason);
  }

string SolTradeResearchRunDirectory(const string root,
                                    const string trading_input_hash,
                                    const string execution_instance_id)
  {
   string clean_root = root;
   StringReplace(clean_root, "/", "\\");
   return clean_root + "\\" + trading_input_hash + "\\" +
          execution_instance_id;
  }

void SolTradeApplyResearchIsolation(
   SolTradeConfig &config,
   const string trading_input_hash)
  {
   if(!config.enable_backtest_research)
      return;

   const string state_directory =
      SolTradeResearchRunDirectory(config.research_state_root,
                                   trading_input_hash,
                                   config.execution_instance_id);
   const string artifact_directory =
      SolTradeResearchRunDirectory(config.research_artifact_root,
                                   trading_input_hash,
                                   config.execution_instance_id);
   config.risk_state_directory =
      state_directory + "\\risk";
   config.execution_state_directory =
      state_directory + "\\execution";
   config.journal_directory =
      artifact_directory + "\\journal";
  }

bool SolTradeResearchDirectoryHasEntries(
   const string directory,
   bool &has_entries)
  {
   has_entries = false;
   string returned_name = "";
   ResetLastError();
   const long search_handle =
      FileFindFirst(directory + "\\*", returned_name);
   if(search_handle == INVALID_HANDLE)
      return true;

   has_entries = true;
   FileFindClose(search_handle);
   return true;
  }

bool SolTradeValidateResearchRuntime(
   const SolTradeConfig &config,
   const bool is_tester,
   const ENUM_SOLTRADE_ENVIRONMENT detected_environment,
   const int actual_terminal_build,
   const string actual_broker_server,
   const double actual_initial_deposit,
   const string actual_deposit_currency,
   const int actual_leverage,
   string &reason)
  {
   reason = "";
   if(!config.enable_backtest_research)
     {
      reason = "EnableBacktestResearch is false";
      return false;
     }

   if(!is_tester ||
      detected_environment != SOLTRADE_ENV_BACKTEST)
     {
      reason =
         "Phase 6 research is permitted only inside Strategy Tester";
      return false;
     }

   if(actual_terminal_build !=
      config.research_expected_terminal_build)
     {
      reason = "Terminal build differs from frozen manifest";
      return false;
     }

   if(actual_broker_server !=
      config.research_expected_broker_server)
     {
      reason = "Broker server differs from frozen manifest";
      return false;
     }

   if(!MathIsValidNumber(actual_initial_deposit) ||
      MathAbs(actual_initial_deposit -
              config.research_expected_initial_deposit) > 0.01)
     {
      reason = "Initial tester deposit differs from frozen manifest";
      return false;
     }

   if(actual_deposit_currency !=
      config.research_expected_deposit_currency)
     {
      reason = "Tester deposit currency differs from frozen manifest";
      return false;
     }

   if(actual_leverage != config.research_expected_leverage)
     {
      reason = "Tester leverage differs from frozen manifest";
      return false;
     }
   return true;
  }

double SolTradeAdjustedTradeNet(const double native_trade_net,
                                const double native_friction,
                                const double supplementary_multiplier)
  {
   if(!MathIsValidNumber(native_trade_net) ||
      !MathIsValidNumber(native_friction) ||
      !MathIsValidNumber(supplementary_multiplier) ||
      native_friction < 0.0 ||
      supplementary_multiplier < 0.0)
      return 0.0;

   // Native trade net already contains native friction. Only the additional
   // registered multiplier is subtracted; native costs are never charged twice.
   return native_trade_net -
          (native_friction * supplementary_multiplier);
  }

bool SolTradeApplySupplementaryCashFlow(
   SolTradeResearchTrade &trade,
   const double multiplier,
   string &reason)
  {
   reason = "";
   if(!MathIsValidNumber(trade.native_trade_net) ||
      !MathIsValidNumber(trade.native_friction) ||
      trade.native_friction < 0.0 ||
      !MathIsValidNumber(multiplier) ||
      multiplier < 0.0)
     {
      reason = "Trade cash flow or supplementary multiplier is invalid";
      return false;
     }

   trade.supplementary_multiplier = multiplier;
   trade.supplementary_charge =
      trade.native_friction * multiplier;
   trade.adjusted_trade_net =
      trade.native_trade_net - trade.supplementary_charge;
   return true;
  }

bool SolTradeCalculateResearchMetrics(
   SolTradeResearchTrade &trades[],
   const double starting_equity,
   const datetime start_inclusive,
   const datetime end_exclusive,
   SolTradeResearchMetrics &metrics)
  {
   ResetSolTradeResearchMetrics(metrics);
   if(!MathIsValidNumber(starting_equity) ||
      starting_equity <= 0.0 ||
      start_inclusive <= 0 ||
      end_exclusive <= start_inclusive)
     {
      metrics.reason = "Metric boundaries or starting equity are invalid";
      return false;
     }

   const long test_duration =
      (long)(end_exclusive - start_inclusive);
   const bool use_calendar_years =
      test_duration >= (long)(4.0 * 365.2425 * 86400.0);

   int first_year = 0;
   int period_count = 5;
   if(use_calendar_years)
     {
      MqlDateTime start_parts;
      MqlDateTime end_parts;
      TimeToStruct(start_inclusive, start_parts);
      TimeToStruct(end_exclusive - 1, end_parts);
      first_year   = start_parts.year;
      period_count = end_parts.year - start_parts.year + 1;
     }

   double period_profit[];
   ArrayResize(period_profit, period_count);
   ArrayInitialize(period_profit, 0.0);

   double equity = starting_equity;
   double peak   = starting_equity;
   double maximum_drawdown_percent = 0.0;
   double best_trade = 0.0;
   datetime previous_exit = 0;

   for(int index = 0; index < ArraySize(trades); index++)
     {
      if(!trades[index].naturally_closed)
         continue;

      if(trades[index].exit_time < start_inclusive ||
         trades[index].exit_time >= end_exclusive ||
         (previous_exit > 0 &&
          trades[index].exit_time < previous_exit))
        {
         metrics.reason =
            "Closed trade sequence is outside boundaries or not chronological";
         return false;
        }

      previous_exit = trades[index].exit_time;
      trades[index].equity_before = equity;
      equity += trades[index].adjusted_trade_net;
      trades[index].equity_after = equity;

      metrics.closed_trades++;
      metrics.net_profit += trades[index].adjusted_trade_net;
      if(trades[index].adjusted_trade_net >= 0.0)
         metrics.gross_profit += trades[index].adjusted_trade_net;
      else
         metrics.gross_loss +=
            -trades[index].adjusted_trade_net;

      if(trades[index].adjusted_trade_net > best_trade)
         best_trade = trades[index].adjusted_trade_net;

      int period_index = 0;
      if(use_calendar_years)
        {
         MqlDateTime exit_parts;
         TimeToStruct(trades[index].exit_time, exit_parts);
         period_index = exit_parts.year - first_year;
        }
      else
        {
         period_index =
            (int)(((long)(trades[index].exit_time -
                         start_inclusive) * 5) /
                  test_duration);
        }
      if(period_index < 0)
         period_index = 0;
      if(period_index >= period_count)
         period_index = period_count - 1;
      period_profit[period_index] +=
         trades[index].adjusted_trade_net;

      if(equity > peak)
         peak = equity;
      if(peak > 0.0)
        {
         const double drawdown_percent =
            100.0 * (peak - equity) / peak;
         if(drawdown_percent > maximum_drawdown_percent)
            maximum_drawdown_percent = drawdown_percent;
        }
     }

   if(metrics.closed_trades <= 0)
     {
      metrics.reason = "No naturally closed trades are available";
      return false;
     }

   double best_period = 0.0;
   for(int index = 0; index < period_count; index++)
     {
      if(period_profit[index] > best_period)
         best_period = period_profit[index];
     }

   metrics.expectancy =
      metrics.net_profit / metrics.closed_trades;
   metrics.profit_factor =
      metrics.gross_loss > 0.0
      ? metrics.gross_profit / metrics.gross_loss
      : DBL_MAX;
   metrics.maximum_equity_drawdown_percent =
      maximum_drawdown_percent;
   metrics.annualized_return_percent =
      100.0 * (metrics.net_profit / starting_equity) *
      (365.2425 * 86400.0 / test_duration);
   metrics.ending_equity = equity;

   if(metrics.net_profit > 0.0)
     {
      metrics.best_trade_contribution_percent =
         100.0 * best_trade / metrics.net_profit;
      metrics.best_period_contribution_percent =
         100.0 * best_period / metrics.net_profit;
     }
   else
     {
      metrics.best_trade_contribution_percent  = DBL_MAX;
      metrics.best_period_contribution_percent = DBL_MAX;
     }

   metrics.valid  = true;
   metrics.reason = "Chronological adjusted cash-flow metrics calculated";
   return true;
  }

string SolTradeResearchAcceptanceLabel(
   const ENUM_SOLTRADE_BACKTEST_DATASET dataset,
   const ENUM_SOLTRADE_COST_PROFILE profile,
   const SolTradeResearchMetrics &metrics)
  {
   if(!metrics.valid)
      return "INVALID_TEST_EVIDENCE";

   if(dataset == SOLTRADE_DATASET_OUT_OF_SAMPLE &&
      metrics.closed_trades < 50)
      return "INCONCLUSIVE_INSUFFICIENT_SAMPLE";

   double minimum_profit_factor = 0.0;
   double maximum_drawdown      = 0.0;
   switch(profile)
     {
      case SOLTRADE_COST_NORMAL:
         minimum_profit_factor = 1.15;
         maximum_drawdown      = 8.0;
         break;
      case SOLTRADE_COST_HIGH:
         minimum_profit_factor = 1.05;
         maximum_drawdown      = 10.0;
         break;
      case SOLTRADE_COST_STRESS:
         minimum_profit_factor = 1.00;
         maximum_drawdown      = 12.0;
         break;
      default:
         return "INVALID_TEST_EVIDENCE";
     }

   const bool drawdown_passes =
      profile == SOLTRADE_COST_NORMAL
      ? metrics.maximum_equity_drawdown_percent < maximum_drawdown
      : metrics.maximum_equity_drawdown_percent <= maximum_drawdown;
   const bool profit_factor_passes =
      profile == SOLTRADE_COST_NORMAL
      ? metrics.profit_factor > minimum_profit_factor
      : metrics.profit_factor >= minimum_profit_factor;
   if(metrics.net_profit <= 0.0 ||
      metrics.expectancy <= 0.0 ||
      !profit_factor_passes ||
      !drawdown_passes ||
      metrics.best_trade_contribution_percent > 20.0 ||
      metrics.best_period_contribution_percent > 40.0)
      return "RESEARCH_REJECTED";

   return "PASS";
  }

bool SolTradeResearchConsistencyPasses(
   const SolTradeResearchMetrics &development,
   const SolTradeResearchMetrics &validation,
   const SolTradeResearchMetrics &out_of_sample,
   const double starting_equity,
   string &reason)
  {
   reason = "";
   if(!development.valid ||
      !validation.valid ||
      !out_of_sample.valid ||
      starting_equity <= 0.0)
     {
      reason = "All three valid dataset metrics are required";
      return false;
     }

   const double normalized_expectancy[3] =
     {
      development.expectancy / starting_equity,
      validation.expectancy / starting_equity,
      out_of_sample.expectancy / starting_equity
     };
   const double annualized_return[3] =
     {
      development.annualized_return_percent,
      validation.annualized_return_percent,
      out_of_sample.annualized_return_percent
     };
   const double profit_factor[3] =
     {
      development.profit_factor,
      validation.profit_factor,
      out_of_sample.profit_factor
     };

   double minimum_expectancy = normalized_expectancy[0];
   double maximum_expectancy = normalized_expectancy[0];
   double minimum_return     = annualized_return[0];
   double maximum_return     = annualized_return[0];
   double minimum_pf         = profit_factor[0];
   double maximum_pf         = profit_factor[0];
   for(int index = 0; index < 3; index++)
     {
      if(normalized_expectancy[index] <= 0.0 ||
         annualized_return[index] <= 0.0)
        {
         reason = "Dataset expectancy and annualized return must be positive";
         return false;
        }
      minimum_expectancy =
         MathMin(minimum_expectancy, normalized_expectancy[index]);
      maximum_expectancy =
         MathMax(maximum_expectancy, normalized_expectancy[index]);
      minimum_return =
         MathMin(minimum_return, annualized_return[index]);
      maximum_return =
         MathMax(maximum_return, annualized_return[index]);
      minimum_pf = MathMin(minimum_pf, profit_factor[index]);
      maximum_pf = MathMax(maximum_pf, profit_factor[index]);
     }

   if(minimum_expectancy < 0.50 * maximum_expectancy)
     {
      reason = "Normalized expectancy varies by more than the permitted factor";
      return false;
     }
   if(minimum_return < 0.50 * maximum_return)
     {
      reason = "Annualized return varies by more than the permitted factor";
      return false;
     }
   if(maximum_pf - minimum_pf > 0.40)
     {
      reason = "Profit-factor spread exceeds 0.40";
      return false;
     }
   return true;
  }

class CSolTradeBacktestReporter
  {
private:
   SolTradeConfig                m_config;
   SolTradeResearchRuntimeStatus m_status;
   SolTradeResearchTrade         m_trades[];
   double                        m_initial_deposit;
   string                        m_journal_filename;

   int FindTrade(const ulong position_identifier)
     {
      for(int index = 0; index < ArraySize(m_trades); index++)
        {
         if(m_trades[index].position_identifier ==
            position_identifier)
            return index;
        }
      return -1;
     }

   int EnsureTrade(const ulong position_identifier)
     {
      int index = FindTrade(position_identifier);
      if(index >= 0)
         return index;

      index = ArraySize(m_trades);
      ArrayResize(m_trades, index + 1);
      ResetSolTradeResearchTrade(m_trades[index]);
      m_trades[index].position_identifier =
         position_identifier;
      return index;
     }

   bool WriteManifestArtifact(string &reason)
     {
      reason = "";
      const string filename =
         m_status.artifact_directory + "\\run_manifest.csv";
      ResetLastError();
      const int handle =
         FileOpen(filename,
                  FILE_WRITE | FILE_CSV | FILE_ANSI,
                  ',');
      if(handle == INVALID_HANDLE)
        {
         reason = "Cannot create Phase 6 run manifest; error " +
                  IntegerToString(GetLastError());
         return false;
        }

      FileWrite(handle, "field", "value");
      FileWrite(handle, "schema", SOLTRADE_RESEARCH_SCHEMA);
      FileWrite(handle, "manifest_id",
                m_config.research_manifest_id);
      FileWrite(handle, "trading_input_hash",
                m_status.trading_input_hash);
      FileWrite(handle, "execution_instance_id",
                m_config.execution_instance_id);
      FileWrite(handle, "dataset",
                SolTradeBacktestDatasetName(
                   m_config.research_dataset));
      FileWrite(handle, "cost_profile",
                SolTradeCostProfileName(
                   m_config.research_cost_profile));
      FileWrite(handle, "supplementary_multiplier",
                DoubleToString(
                   SolTradeSupplementaryCostMultiplier(
                      m_config.research_cost_profile), 2));
      FileWrite(handle, "start_inclusive",
                TimeToString(m_config.research_start_inclusive,
                             TIME_DATE | TIME_SECONDS));
      FileWrite(handle, "end_exclusive",
                TimeToString(m_config.research_end_exclusive,
                             TIME_DATE | TIME_SECONDS));
      FileWrite(handle, "actual_first_tick",
                TimeToString(m_status.actual_first_tick,
                             TIME_DATE | TIME_SECONDS));
      FileWrite(handle, "actual_final_tick",
                TimeToString(m_status.actual_final_tick,
                             TIME_DATE | TIME_SECONDS));
      FileWrite(handle, "warmup_first_bar",
                TimeToString(m_status.warmup_first_bar,
                             TIME_DATE | TIME_SECONDS));
      FileWrite(handle, "history_fingerprint",
                m_config.research_history_fingerprint);
      FileWrite(handle, "latency_fingerprint",
                m_config.research_latency_fingerprint);
      FileWrite(handle, "latency_sample_count",
                IntegerToString(
                   m_config.research_latency_sample_count));
      FileWrite(handle, "frozen_delay_ms",
                IntegerToString(
                   m_config.research_frozen_delay_ms));
      FileWrite(handle, "terminal_build",
                IntegerToString(
                   (int)TerminalInfoInteger(TERMINAL_BUILD)));
      FileWrite(handle, "broker_server",
                AccountInfoString(ACCOUNT_SERVER));
      FileWrite(handle, "source_commit",
                m_config.research_source_commit);
      FileWrite(handle, "build_fingerprint",
                m_config.research_build_fingerprint);
      FileWrite(handle, "canonical_material_sha256",
                m_status.trading_input_hash);
      FileWrite(handle, "execution_instance_affects_trading_hash",
                "NO");
      FileWrite(handle, "journal_filename",
                m_journal_filename);
      FileClose(handle);

      const string material_filename =
         m_status.artifact_directory +
         "\\canonical_trading_inputs.txt";
      ResetLastError();
      const int material_handle =
         FileOpen(material_filename,
                  FILE_WRITE | FILE_TXT | FILE_ANSI);
      if(material_handle == INVALID_HANDLE)
        {
         reason =
            "Cannot create canonical trading-input artifact; error " +
            IntegerToString(GetLastError());
         return false;
        }
      FileWriteString(material_handle, m_status.canonical_material);
      FileClose(material_handle);
      return true;
     }

   bool RebuildTradesFromHistory(
      SolTradeResearchReconciliation &reconciliation,
      string &reason)
     {
      ResetSolTradeResearchReconciliation(reconciliation);
      reason = "";
      // Preserve event-time spread and adverse-slippage observations while
      // rebuilding native cash flows from authoritative deal history.
      for(int index = 0; index < ArraySize(m_trades); index++)
        {
         const ulong position_identifier =
            m_trades[index].position_identifier;
         const double spread_cost =
            m_trades[index].spread_cost;
         const double adverse_entry_slippage_cost =
            m_trades[index].adverse_entry_slippage_cost;
         const double adverse_exit_slippage_cost =
            m_trades[index].adverse_exit_slippage_cost;
         ResetSolTradeResearchTrade(m_trades[index]);
         m_trades[index].position_identifier =
            position_identifier;
         m_trades[index].spread_cost = spread_cost;
         m_trades[index].adverse_entry_slippage_cost =
            adverse_entry_slippage_cost;
         m_trades[index].adverse_exit_slippage_cost =
            adverse_exit_slippage_cost;
        }

      ResetLastError();
      if(!HistorySelect(m_config.research_start_inclusive,
                        m_config.research_end_exclusive))
        {
         reason = "Cannot select registered tester deal history; error " +
                  IntegerToString(GetLastError());
         reconciliation.reason = reason;
         return false;
        }

      const int deals_total = HistoryDealsTotal();
      for(int deal_index = 0;
          deal_index < deals_total;
          deal_index++)
        {
         const ulong deal_ticket =
            HistoryDealGetTicket(deal_index);
         if(deal_ticket == 0 ||
            (ulong)HistoryDealGetInteger(
               deal_ticket, DEAL_MAGIC) != m_config.magic_number ||
            HistoryDealGetString(deal_ticket, DEAL_SYMBOL) !=
               m_config.symbol)
            continue;

         const datetime deal_time =
            (datetime)HistoryDealGetInteger(
               deal_ticket, DEAL_TIME);
         if(deal_time < m_config.research_start_inclusive ||
            deal_time >= m_config.research_end_exclusive)
            continue;

         const ulong position_identifier =
            (ulong)HistoryDealGetInteger(
               deal_ticket, DEAL_POSITION_ID);
         if(position_identifier == 0)
            continue;

         const int trade_index =
            EnsureTrade(position_identifier);
         const ENUM_DEAL_ENTRY entry =
            (ENUM_DEAL_ENTRY)HistoryDealGetInteger(
               deal_ticket, DEAL_ENTRY);
         if(entry == DEAL_ENTRY_IN ||
            entry == DEAL_ENTRY_INOUT)
           {
            if(m_trades[trade_index].entry_time == 0 ||
               deal_time < m_trades[trade_index].entry_time)
               m_trades[trade_index].entry_time = deal_time;
           }
         if(entry == DEAL_ENTRY_OUT ||
            entry == DEAL_ENTRY_OUT_BY ||
            entry == DEAL_ENTRY_INOUT)
           {
            if(deal_time > m_trades[trade_index].exit_time)
               m_trades[trade_index].exit_time = deal_time;
            m_trades[trade_index].naturally_closed = true;
           }

         const double profit =
            HistoryDealGetDouble(deal_ticket, DEAL_PROFIT);
         const double commission =
            HistoryDealGetDouble(deal_ticket, DEAL_COMMISSION);
         const double swap =
            HistoryDealGetDouble(deal_ticket, DEAL_SWAP);
         const double fee =
            HistoryDealGetDouble(deal_ticket, DEAL_FEE);
         const double deal_net =
            profit + commission + swap + fee;
         m_trades[trade_index].native_trade_net += deal_net;
         m_trades[trade_index].commission_cost +=
            MathAbs(commission);
         m_trades[trade_index].swap_cost += MathAbs(swap);
         m_trades[trade_index].fee_cost += MathAbs(fee);
         reconciliation.history_deals++;
         reconciliation.history_deal_net += deal_net;
        }

      const double multiplier =
         SolTradeSupplementaryCostMultiplier(
            m_config.research_cost_profile);
      for(int index = 0; index < ArraySize(m_trades); index++)
        {
         if(m_trades[index].entry_time == 0)
            m_trades[index].crosses_start_boundary = true;
         if(!m_trades[index].naturally_closed)
            m_trades[index].crosses_end_boundary = true;
         m_trades[index].native_friction =
            m_trades[index].spread_cost +
            m_trades[index].commission_cost +
            m_trades[index].swap_cost +
            m_trades[index].fee_cost +
            m_trades[index].adverse_entry_slippage_cost +
            m_trades[index].adverse_exit_slippage_cost;
         if(!SolTradeApplySupplementaryCashFlow(
               m_trades[index],
               multiplier,
               reason))
           {
            reconciliation.reason = reason;
            return false;
           }
         if(m_trades[index].naturally_closed)
            reconciliation.closed_trades++;
         // Reconciliation covers every in-window deal, including the
         // explicitly reported cash flow of a position that remains open at
         // the exclusive dataset boundary. Acceptance statistics below use
         // naturally closed trades only.
         reconciliation.reconstructed_native_net +=
            m_trades[index].native_trade_net;
        }

      reconciliation.native_tester_net =
         TesterStatistics(STAT_PROFIT);
      reconciliation.history_difference =
         reconciliation.history_deal_net -
         reconciliation.reconstructed_native_net;
      reconciliation.tester_difference =
         reconciliation.native_tester_net -
         reconciliation.reconstructed_native_net;
      const double tolerance = 0.01;
      reconciliation.valid =
         MathAbs(reconciliation.history_difference) <= tolerance &&
         MathAbs(reconciliation.tester_difference) <= tolerance;
      reconciliation.reason =
         reconciliation.valid
         ? "History, reconstructed trades, and native tester net reconcile"
         : "Deal history, reconstructed trades, and native tester net do not reconcile";
      // A numeric mismatch is valid diagnostic output, not a reporting I/O
      // failure. The caller writes the INVALID reconciliation artifact and
      // only then rejects the run.
      return true;
     }

   bool WriteTradeCashFlows(string &reason)
     {
      reason = "";
      const string filename =
         m_status.artifact_directory + "\\trade_cashflows.csv";
      ResetLastError();
      const int handle =
         FileOpen(filename,
                  FILE_WRITE | FILE_CSV | FILE_ANSI,
                  ',');
      if(handle == INVALID_HANDLE)
        {
         reason = "Cannot create trade cash-flow artifact; error " +
                  IntegerToString(GetLastError());
         return false;
        }

      FileWrite(handle,
                "schema",
                "position_identifier",
                "entry_time",
                "exit_time",
                "native_trade_net",
                "spread_cost",
                "commission_cost",
                "swap_cost",
                "fee_cost",
                "adverse_entry_slippage_cost",
                "adverse_exit_slippage_cost",
                "native_friction",
                "supplementary_multiplier",
                "supplementary_charge",
                "adjusted_trade_net",
                "equity_before",
                "equity_after",
                "naturally_closed",
                "crosses_start_boundary",
                "crosses_end_boundary");
      for(int index = 0; index < ArraySize(m_trades); index++)
        {
         FileWrite(
            handle,
            SOLTRADE_RESEARCH_CASHFLOW_SCHEMA,
            StringFormat(
               "%I64u",
               m_trades[index].position_identifier),
            TimeToString(m_trades[index].entry_time,
                         TIME_DATE | TIME_SECONDS),
            TimeToString(m_trades[index].exit_time,
                         TIME_DATE | TIME_SECONDS),
            DoubleToString(m_trades[index].native_trade_net, 8),
            DoubleToString(m_trades[index].spread_cost, 8),
            DoubleToString(m_trades[index].commission_cost, 8),
            DoubleToString(m_trades[index].swap_cost, 8),
            DoubleToString(m_trades[index].fee_cost, 8),
            DoubleToString(
               m_trades[index].adverse_entry_slippage_cost, 8),
            DoubleToString(
               m_trades[index].adverse_exit_slippage_cost, 8),
            DoubleToString(m_trades[index].native_friction, 8),
            DoubleToString(
               m_trades[index].supplementary_multiplier, 2),
            DoubleToString(
               m_trades[index].supplementary_charge, 8),
            DoubleToString(m_trades[index].adjusted_trade_net, 8),
            DoubleToString(m_trades[index].equity_before, 8),
            DoubleToString(m_trades[index].equity_after, 8),
            m_trades[index].naturally_closed ? "YES" : "NO",
            m_trades[index].crosses_start_boundary ? "YES" : "NO",
            m_trades[index].crosses_end_boundary ? "YES" : "NO");
        }
      FileClose(handle);
      return true;
     }

   bool WriteSummaryArtifacts(
      const SolTradeResearchMetrics &metrics,
      const SolTradeResearchReconciliation &reconciliation,
      string &reason)
     {
      reason = "";
      const string native_filename =
         m_status.artifact_directory + "\\native_mt5_summary.csv";
      const int native_handle =
         FileOpen(native_filename,
                  FILE_WRITE | FILE_CSV | FILE_ANSI,
                  ',');
      if(native_handle == INVALID_HANDLE)
        {
         reason = "Cannot create native MT5 summary";
         return false;
        }
      FileWrite(native_handle, "layer", "metric", "value");
      FileWrite(native_handle, "NATIVE_MT5", "net_profit",
                DoubleToString(
                   reconciliation.native_tester_net, 8));
      FileWrite(native_handle, "NATIVE_MT5", "closed_trades",
                IntegerToString(
                   (int)TesterStatistics(STAT_TRADES)));
      FileWrite(native_handle, "NATIVE_MT5", "profit_factor",
                DoubleToString(
                   TesterStatistics(STAT_PROFIT_FACTOR), 8));
      FileWrite(native_handle, "NATIVE_MT5", "expected_payoff",
                DoubleToString(
                   TesterStatistics(STAT_EXPECTED_PAYOFF), 8));
      FileWrite(native_handle, "NATIVE_MT5",
                "maximum_equity_drawdown_percent",
                DoubleToString(
                   TesterStatistics(STAT_EQUITY_DDREL_PERCENT), 8));
      FileClose(native_handle);

      const string supplementary_filename =
         m_status.artifact_directory +
         "\\supplementary_adjusted_summary.csv";
      const int supplementary_handle =
         FileOpen(supplementary_filename,
                  FILE_WRITE | FILE_CSV | FILE_ANSI,
                  ',');
      if(supplementary_handle == INVALID_HANDLE)
        {
         reason = "Cannot create supplementary adjusted summary";
         return false;
        }
      FileWrite(supplementary_handle,
                "layer",
                "metric",
                "value");
      FileWrite(supplementary_handle,
                "SUPPLEMENTARY_NOT_BROKER_NATIVE",
                "adjusted_net_profit",
                DoubleToString(metrics.net_profit, 8));
      FileWrite(supplementary_handle,
                "SUPPLEMENTARY_NOT_BROKER_NATIVE",
                "adjusted_expectancy",
                DoubleToString(metrics.expectancy, 8));
      FileWrite(supplementary_handle,
                "SUPPLEMENTARY_NOT_BROKER_NATIVE",
                "adjusted_profit_factor",
                DoubleToString(metrics.profit_factor, 8));
      FileWrite(supplementary_handle,
                "SUPPLEMENTARY_NOT_BROKER_NATIVE",
                "adjusted_maximum_drawdown_percent",
                DoubleToString(
                   metrics.maximum_equity_drawdown_percent, 8));
      FileWrite(supplementary_handle,
                "SUPPLEMENTARY_NOT_BROKER_NATIVE",
                "adjusted_annualized_return_percent",
                DoubleToString(
                   metrics.annualized_return_percent, 8));
      FileWrite(supplementary_handle,
                "SUPPLEMENTARY_NOT_BROKER_NATIVE",
                "best_trade_contribution_percent",
                DoubleToString(
                   metrics.best_trade_contribution_percent, 8));
      FileWrite(supplementary_handle,
                "SUPPLEMENTARY_NOT_BROKER_NATIVE",
                "best_period_contribution_percent",
                DoubleToString(
                   metrics.best_period_contribution_percent, 8));
      FileWrite(supplementary_handle,
                "SUPPLEMENTARY_NOT_BROKER_NATIVE",
                "acceptance_label",
                reconciliation.valid
                ? SolTradeResearchAcceptanceLabel(
                     m_config.research_dataset,
                     m_config.research_cost_profile,
                     metrics)
                : "INVALID_TEST_EVIDENCE");
      FileClose(supplementary_handle);

      const string reconciliation_filename =
         m_status.artifact_directory + "\\reconciliation.csv";
      const int reconciliation_handle =
         FileOpen(reconciliation_filename,
                  FILE_WRITE | FILE_CSV | FILE_ANSI,
                  ',');
      if(reconciliation_handle == INVALID_HANDLE)
        {
         reason = "Cannot create reconciliation artifact";
         return false;
        }
      FileWrite(reconciliation_handle, "field", "value");
      FileWrite(reconciliation_handle, "status",
                reconciliation.valid ? "PASS" : "INVALID");
      FileWrite(reconciliation_handle, "reason",
                reconciliation.reason);
      FileWrite(reconciliation_handle, "history_deals",
                IntegerToString(reconciliation.history_deals));
      FileWrite(reconciliation_handle, "closed_trades",
                IntegerToString(reconciliation.closed_trades));
      FileWrite(reconciliation_handle, "history_deal_net",
                DoubleToString(
                   reconciliation.history_deal_net, 8));
      FileWrite(reconciliation_handle,
                "reconstructed_native_net",
                DoubleToString(
                   reconciliation.reconstructed_native_net, 8));
      FileWrite(reconciliation_handle, "native_tester_net",
                DoubleToString(
                   reconciliation.native_tester_net, 8));
      FileWrite(reconciliation_handle, "history_difference",
                DoubleToString(
                   reconciliation.history_difference, 8));
      FileWrite(reconciliation_handle, "tester_difference",
                DoubleToString(
                   reconciliation.tester_difference, 8));
      FileClose(reconciliation_handle);
      return true;
     }

public:
   CSolTradeBacktestReporter()
     {
      ResetSolTradeResearchRuntimeStatus(m_status);
      ArrayResize(m_trades, 0);
      m_initial_deposit = 0.0;
      m_journal_filename = "";
     }

   bool Initialise(SolTradeConfig &config, string &reason)
     {
      reason = "";
      ResetSolTradeResearchRuntimeStatus(m_status);
      ArrayResize(m_trades, 0);
      m_journal_filename = "";
      m_config = config;

      if(!config.enable_backtest_research)
        {
         m_status.reason = "Phase 6 research remains disabled";
         return true;
        }

      string material = "";
      string trading_hash = "";
      if(!SolTradeCalculateTradingInputHash(
            config,
            material,
            trading_hash,
            reason))
        {
         m_status.reason = reason;
         return false;
        }

      if(trading_hash !=
         config.research_expected_trading_input_hash)
        {
         reason =
            "Computed trading-input hash differs from frozen manifest";
         m_status.reason = reason;
         return false;
        }

      if(!SolTradeValidateResearchRuntime(
            config,
            (bool)MQLInfoInteger(MQL_TESTER),
            DetectSolTradeEnvironment(),
            (int)TerminalInfoInteger(TERMINAL_BUILD),
            AccountInfoString(ACCOUNT_SERVER),
            AccountInfoDouble(ACCOUNT_BALANCE),
            AccountInfoString(ACCOUNT_CURRENCY),
            (int)AccountInfoInteger(ACCOUNT_LEVERAGE),
            reason))
        {
         m_status.reason = reason;
         return false;
        }

      SolTradeApplyResearchIsolation(config, trading_hash);
      const string state_directory =
         SolTradeResearchRunDirectory(
            config.research_state_root,
            trading_hash,
            config.execution_instance_id);
      const string artifact_directory =
         SolTradeResearchRunDirectory(
            config.research_artifact_root,
            trading_hash,
            config.execution_instance_id);
      bool state_collision = false;
      bool artifact_collision = false;
      SolTradeResearchDirectoryHasEntries(state_directory,
                                          state_collision);
      SolTradeResearchDirectoryHasEntries(artifact_directory,
                                          artifact_collision);
      if(state_collision || artifact_collision)
        {
         reason =
            "ExecutionInstanceId state/artifact namespace is not empty";
         m_status.reason = reason;
         return false;
        }

      m_config = config;
      m_initial_deposit =
         config.research_expected_initial_deposit;
      m_status.initialised = true;
      m_status.valid       = true;
      m_status.reason      = "Phase 6 tester reporting initialised";
      m_status.trading_input_hash = trading_hash;
      m_status.canonical_material = material;
      m_status.state_directory = state_directory;
      m_status.artifact_directory = artifact_directory;
      m_status.warmup_first_bar =
         iTime(config.symbol,
               config.timeframe,
               config.minimum_history_bars - 1);
      return true;
     }

   void RegisterJournalFilename(const string filename)
     {
      if(m_status.initialised && m_status.valid)
         m_journal_filename = filename;
     }

   void ObserveTick(const SolTradeMarketSnapshot &market)
     {
      if(!m_status.initialised ||
         !m_status.valid ||
         market.tick_time <= 0)
         return;

      if(m_status.actual_first_tick == 0 ||
         market.tick_time < m_status.actual_first_tick)
         m_status.actual_first_tick = market.tick_time;
      if(market.tick_time > m_status.actual_final_tick)
         m_status.actual_final_tick = market.tick_time;
     }

   void RecordEntry(const SolTradeExecutionReport &report,
                    const SolTradeMarketSnapshot &market)
     {
      if(!m_status.initialised ||
         !m_status.valid ||
         !report.fill_confirmed ||
         report.deal_ticket == 0)
         return;

      const ulong position_identifier =
         (ulong)HistoryDealGetInteger(
            report.deal_ticket,
            DEAL_POSITION_ID);
      if(position_identifier == 0)
         return;
      const int index = EnsureTrade(position_identifier);
      const double tick_value_loss =
         SymbolInfoDouble(m_config.symbol,
                          SYMBOL_TRADE_TICK_VALUE_LOSS);
      if(market.tick_size > 0.0 &&
         market.point > 0.0 &&
         tick_value_loss > 0.0 &&
         report.volume > 0.0)
        {
         const double point_cost =
            (market.point / market.tick_size) *
            tick_value_loss *
            report.volume;
         m_trades[index].spread_cost =
            MathMax(0, report.spread_points) * point_cost;
         m_trades[index].adverse_entry_slippage_cost =
            MathMax(0.0, report.slippage_points) *
            point_cost;
        }
     }

   void RecordExit(const SolTradePositionReport &report,
                   const SolTradeMarketSnapshot &market)
     {
      if(!m_status.initialised ||
         !m_status.valid ||
         !report.fill_confirmed ||
         report.position_identifier == 0)
         return;

      const int index =
         EnsureTrade(report.position_identifier);
      const double tick_value_loss =
         SymbolInfoDouble(m_config.symbol,
                          SYMBOL_TRADE_TICK_VALUE_LOSS);
      if(market.tick_size > 0.0 &&
         market.point > 0.0 &&
         tick_value_loss > 0.0 &&
         report.volume > 0.0)
        {
         const double point_cost =
            (market.point / market.tick_size) *
            tick_value_loss *
            report.volume;
         m_trades[index].adverse_exit_slippage_cost =
            MathMax(0.0, report.slippage_points) *
            point_cost;
        }
     }

   bool Finalise(string &reason)
     {
      reason = "";
      if(!m_status.initialised)
        {
         reason = "Phase 6 reporter was not initialised";
         return false;
        }
      if(!m_status.valid)
        {
         reason = m_status.reason;
         return false;
        }
      if(StringLen(m_journal_filename) == 0 ||
         !FileIsExist(m_journal_filename))
        {
         reason =
            "Required Phase 6 journal artifact is missing";
         m_status.valid  = false;
         m_status.reason = reason;
         return false;
        }

      if(m_status.actual_first_tick <
            m_config.research_start_inclusive ||
         m_status.actual_final_tick >=
            m_config.research_end_exclusive)
        {
         reason =
            "Actual first/final ticks violate inclusive/exclusive boundaries";
         m_status.valid  = false;
         m_status.reason = reason;
         return false;
        }

      if(!WriteManifestArtifact(reason))
        {
         m_status.valid  = false;
         m_status.reason = reason;
         return false;
        }

      SolTradeResearchReconciliation reconciliation;
      if(!RebuildTradesFromHistory(reconciliation, reason))
        {
         m_status.valid  = false;
         m_status.reason = reconciliation.reason;
         return false;
        }

      SolTradeResearchMetrics metrics;
      if(!SolTradeCalculateResearchMetrics(
            m_trades,
            m_initial_deposit,
            m_config.research_start_inclusive,
            m_config.research_end_exclusive,
            metrics))
        {
         reason = metrics.reason;
         m_status.valid  = false;
         m_status.reason = reason;
         return false;
        }

      if(!WriteTradeCashFlows(reason) ||
         !WriteSummaryArtifacts(metrics,
                                reconciliation,
                                reason))
        {
         m_status.valid  = false;
         m_status.reason = reason;
         return false;
        }

      if(!reconciliation.valid)
        {
         reason = reconciliation.reason;
         m_status.valid  = false;
         m_status.reason = reason;
         return false;
        }

      m_status.finalised = true;
      m_status.reason =
         "Phase 6 artifacts written and reconciled";
      return true;
     }

   void GetStatus(SolTradeResearchRuntimeStatus &status)
     {
      status = m_status;
     }
  };

#endif // SOLTRADE_BACKTEST_RESEARCH_MQH
