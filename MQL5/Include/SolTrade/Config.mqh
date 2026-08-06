#ifndef SOLTRADE_CONFIG_MQH
#define SOLTRADE_CONFIG_MQH

// Runtime environments are detected from MetaTrader. AUTO_DETECT is an
// expectation setting only; it can never turn a real account into a demo one.
enum ENUM_SOLTRADE_ENVIRONMENT
  {
   SOLTRADE_ENV_AUTO_DETECT = 0,
   SOLTRADE_ENV_BACKTEST    = 1,
   SOLTRADE_ENV_DEMO        = 2,
   SOLTRADE_ENV_LIVE        = 3,
   SOLTRADE_ENV_UNKNOWN     = 4
  };

enum ENUM_SOLTRADE_BACKTEST_DATASET
  {
   SOLTRADE_DATASET_NONE          = 0,
   SOLTRADE_DATASET_DEVELOPMENT   = 1,
   SOLTRADE_DATASET_VALIDATION    = 2,
   SOLTRADE_DATASET_OUT_OF_SAMPLE = 3
  };

enum ENUM_SOLTRADE_COST_PROFILE
  {
   SOLTRADE_COST_NONE   = 0,
   SOLTRADE_COST_NORMAL = 1,
   SOLTRADE_COST_HIGH   = 2,
   SOLTRADE_COST_STRESS = 3
  };

struct SolTradeConfig
  {
   string                     strategy_version;
   string                     approved_strategy_version;
   string                     risk_profile;
   string                     approved_risk_profile;
   ulong                      magic_number;

   string                     symbol;
   ENUM_TIMEFRAMES            timeframe;
   int                        minimum_history_bars;
   int                        max_tick_age_seconds;
   int                        max_spread_points;
   double                     max_spread_atr_percent;
   int                        max_slippage_points;

   double                     risk_per_trade_percent;
   double                     daily_loss_limit_percent;
   double                     weekly_loss_limit_percent;
   double                     emergency_drawdown_percent;
   double                     production_baseline_equity;
   int                        consecutive_loss_limit;
   bool                       reset_emergency_lock;

   ENUM_SOLTRADE_ENVIRONMENT  expected_environment;
   bool                       enable_demo_execution;
   bool                       enable_position_management;
   long                       approved_demo_account;
   bool                       allow_live_trading;
   long                       approved_live_account;
   bool                       emergency_stop;

   bool                       enable_backtest_research;
   bool                       enable_backtest_execution;
   bool                       enable_backtest_position_management;
   string                     research_manifest_id;
   string                     execution_instance_id;
   ENUM_SOLTRADE_BACKTEST_DATASET research_dataset;
   ENUM_SOLTRADE_COST_PROFILE research_cost_profile;
   datetime                   research_start_inclusive;
   datetime                   research_end_exclusive;
   string                     research_history_fingerprint;
   string                     research_latency_fingerprint;
   int                        research_latency_sample_count;
   int                        research_frozen_delay_ms;
   string                     research_source_commit;
   string                     research_build_fingerprint;
   int                        research_expected_terminal_build;
   string                     research_expected_broker_server;
   double                     research_expected_initial_deposit;
   string                     research_expected_deposit_currency;
   int                        research_expected_leverage;
   string                     research_expected_trading_input_hash;
   string                     research_state_root;
   string                     research_artifact_root;

   bool                       enable_csv_journal;
   string                     journal_directory;
   string                     risk_state_directory;
   string                     execution_state_directory;
   bool                       enable_dashboard;
   int                        dashboard_refresh_seconds;
  };

string SolTradeEnvironmentName(const ENUM_SOLTRADE_ENVIRONMENT environment)
  {
   switch(environment)
     {
      case SOLTRADE_ENV_AUTO_DETECT: return "AUTO_DETECT";
      case SOLTRADE_ENV_BACKTEST:    return "BACKTEST";
      case SOLTRADE_ENV_DEMO:        return "DEMO";
      case SOLTRADE_ENV_LIVE:        return "LIVE";
      default:                       return "UNKNOWN";
     }
  }

string SolTradeTimeframeName(const ENUM_TIMEFRAMES timeframe)
  {
   if(timeframe == PERIOD_H1)
      return "H1";

   return EnumToString(timeframe);
  }

string SolTradeBacktestDatasetName(
   const ENUM_SOLTRADE_BACKTEST_DATASET dataset)
  {
   switch(dataset)
     {
      case SOLTRADE_DATASET_DEVELOPMENT:   return "DEVELOPMENT";
      case SOLTRADE_DATASET_VALIDATION:    return "VALIDATION";
      case SOLTRADE_DATASET_OUT_OF_SAMPLE: return "OUT_OF_SAMPLE";
      default:                             return "NONE";
     }
  }

string SolTradeCostProfileName(
   const ENUM_SOLTRADE_COST_PROFILE profile)
  {
   switch(profile)
     {
      case SOLTRADE_COST_NORMAL: return "NORMAL";
      case SOLTRADE_COST_HIGH:   return "HIGH";
      case SOLTRADE_COST_STRESS: return "STRESS";
      default:                   return "NONE";
     }
  }

double SolTradeSupplementaryCostMultiplier(
   const ENUM_SOLTRADE_COST_PROFILE profile)
  {
   switch(profile)
     {
      case SOLTRADE_COST_NORMAL: return 0.0;
      case SOLTRADE_COST_HIGH:   return 0.50;
      case SOLTRADE_COST_STRESS: return 1.00;
      default:                   return -1.0;
     }
  }

bool SolTradeSafeRelativePath(const string value)
  {
   if(StringLen(value) == 0 ||
      StringFind(value, "..") >= 0 ||
      StringFind(value, ":") >= 0)
      return false;

   const ushort first_character = StringGetCharacter(value, 0);
   return (first_character != StringGetCharacter("\\", 0) &&
           first_character != StringGetCharacter("/", 0));
  }

bool SolTradeSafeIdentifier(const string value)
  {
   const int length = StringLen(value);
   if(length < 1 || length > 80)
      return false;

   for(int index = 0; index < length; index++)
     {
      const ushort character = StringGetCharacter(value, index);
      const bool alpha_numeric =
         (character >= 'A' && character <= 'Z') ||
         (character >= 'a' && character <= 'z') ||
         (character >= '0' && character <= '9');
      if(!alpha_numeric &&
         character != '-' &&
         character != '_')
         return false;
     }
   return true;
  }

bool SolTradeHexText(const string value, const int required_length)
  {
   if(StringLen(value) != required_length)
      return false;

   for(int index = 0; index < required_length; index++)
     {
      const ushort character = StringGetCharacter(value, index);
      const bool hexadecimal =
         (character >= '0' && character <= '9') ||
         (character >= 'A' && character <= 'F') ||
         (character >= 'a' && character <= 'f');
      if(!hexadecimal)
         return false;
     }
   return true;
  }

bool SolTradeBacktestManagementEnabled(
   const SolTradeConfig &config,
   const ENUM_SOLTRADE_ENVIRONMENT detected_environment)
  {
   if(detected_environment == SOLTRADE_ENV_BACKTEST)
      return (config.enable_backtest_research &&
              config.enable_backtest_position_management);

   return config.enable_position_management;
  }

bool ValidateSolTradeConfig(const SolTradeConfig &config, string &reason)
  {
   reason = "";

   if(StringLen(config.strategy_version) == 0)
     {
      reason = "StrategyVersion must not be empty";
      return false;
     }

   if(StringLen(config.risk_profile) == 0)
     {
      reason = "RiskProfile must not be empty";
      return false;
     }

   if(config.magic_number == 0)
     {
      reason = "MagicNumber must be positive";
      return false;
     }

   if(StringLen(config.symbol) == 0)
     {
      reason = "TradeSymbol must not be empty";
      return false;
     }

   if(StringFind(config.symbol, "EURUSD") != 0)
     {
      reason = "Trend Breakout V1 requires EURUSD (an optional broker suffix is allowed)";
      return false;
     }

   // Version 1 is intentionally fixed to EURUSD H1. A broker suffix can be
   // supplied in TradeSymbol, but the timeframe cannot be relaxed silently.
   if(config.timeframe != PERIOD_H1)
     {
      reason = "Trend Breakout V1 requires SignalTimeframe PERIOD_H1";
      return false;
     }

   if(config.minimum_history_bars < 222)
     {
      reason =
         "MinimumHistoryBars must be at least 222 (forming bar plus 221 completed strategy bars)";
      return false;
     }

   if(config.max_tick_age_seconds <= 0)
     {
      reason = "MaxTickAgeSeconds must be positive";
      return false;
     }

   if(config.max_spread_points <= 0)
     {
      reason = "MaxSpreadPoints must be positive";
      return false;
     }

   if(!MathIsValidNumber(config.max_spread_atr_percent) ||
      config.max_spread_atr_percent <= 0.0 ||
      config.max_spread_atr_percent >= 100.0)
     {
      reason = "MaxSpreadAtrPercent must be between 0 and 100";
      return false;
     }

   if(config.max_slippage_points < 0 ||
      config.max_slippage_points > 1000)
     {
      reason = "MaxSlippagePoints must be between 0 and 1000";
      return false;
     }

   if(!MathIsValidNumber(config.risk_per_trade_percent) ||
      config.risk_per_trade_percent <= 0.0 ||
      config.risk_per_trade_percent > 1.0)
     {
      reason = "RiskPerTradePercent must be greater than 0 and no more than 1";
      return false;
     }

   if(!MathIsValidNumber(config.daily_loss_limit_percent) ||
      config.daily_loss_limit_percent <= 0.0 ||
      config.daily_loss_limit_percent >= 100.0)
     {
      reason = "DailyLossLimitPercent must be between 0 and 100";
      return false;
     }

   if(!MathIsValidNumber(config.weekly_loss_limit_percent) ||
      config.weekly_loss_limit_percent < config.daily_loss_limit_percent ||
      config.weekly_loss_limit_percent >= 100.0)
     {
      reason = "WeeklyLossLimitPercent must be at least the daily limit and below 100";
      return false;
     }

   if(!MathIsValidNumber(config.emergency_drawdown_percent) ||
      config.emergency_drawdown_percent < config.weekly_loss_limit_percent ||
      config.emergency_drawdown_percent >= 100.0)
     {
      reason = "EmergencyDrawdownPercent must be at least the weekly limit and below 100";
      return false;
     }

   if(!MathIsValidNumber(config.production_baseline_equity) ||
      config.production_baseline_equity < 0.0)
     {
      reason = "ProductionBaselineEquity cannot be negative";
      return false;
     }

   if(config.consecutive_loss_limit <= 0)
     {
      reason = "ConsecutiveLossLimit must be positive";
      return false;
     }

   if(!SolTradeSafeRelativePath(config.risk_state_directory))
     {
      reason = "RiskStateDirectory must be a safe relative MT5 sandbox path";
      return false;
     }

   if(config.expected_environment == SOLTRADE_ENV_UNKNOWN)
     {
      reason = "ExpectedEnvironment cannot be UNKNOWN";
      return false;
     }

   if(config.approved_demo_account < 0)
     {
      reason = "ApprovedDemoAccount cannot be negative";
      return false;
     }

   if((config.enable_demo_execution ||
       config.enable_position_management) &&
      config.approved_demo_account <= 0)
     {
      reason =
         "ApprovedDemoAccount must be configured before demo execution or position management is enabled";
      return false;
     }

   // Phase 5 is limited to Strategy Tester and explicitly approved demo
   // accounts. A configuration change cannot enable real-account execution.
   if(config.allow_live_trading)
     {
      reason = "AllowLiveTrading must remain false through Phase 6";
      return false;
     }

   if(!config.enable_backtest_research &&
      (config.enable_backtest_execution ||
       config.enable_backtest_position_management))
     {
      reason =
         "Backtest execution and management require EnableBacktestResearch";
      return false;
     }

   if(config.enable_backtest_research)
     {
      if(config.expected_environment != SOLTRADE_ENV_BACKTEST)
        {
         reason =
            "Phase 6 research requires ExpectedEnvironment BACKTEST";
         return false;
        }

      if(!config.enable_backtest_execution ||
         !config.enable_backtest_position_management)
        {
         reason =
            "Phase 6 requires backtest execution and position management together";
         return false;
        }

      if(config.enable_demo_execution ||
         config.enable_position_management ||
         config.approved_demo_account != 0)
        {
         reason =
            "Phase 6 research cannot enable or approve connected-demo automation";
         return false;
        }

      if(config.approved_live_account != 0)
        {
         reason =
            "Phase 6 research cannot configure an approved live account";
         return false;
        }

      if(config.emergency_stop || config.reset_emergency_lock)
        {
         reason =
            "Phase 6 authoritative runs require inactive manual reset and emergency inputs";
         return false;
        }

      if(!SolTradeSafeIdentifier(config.research_manifest_id))
        {
         reason = "ResearchManifestId is missing or unsafe";
         return false;
        }

      if(!SolTradeSafeIdentifier(config.execution_instance_id))
        {
         reason = "ExecutionInstanceId is missing or unsafe";
         return false;
        }

      if(config.research_dataset == SOLTRADE_DATASET_NONE)
        {
         reason = "ResearchDataset must be registered";
         return false;
        }

      if(config.research_cost_profile == SOLTRADE_COST_NONE ||
         SolTradeSupplementaryCostMultiplier(
            config.research_cost_profile) < 0.0)
        {
         reason = "ResearchCostProfile must be NORMAL, HIGH, or STRESS";
         return false;
        }

      if(config.research_start_inclusive <= 0 ||
         config.research_end_exclusive <=
            config.research_start_inclusive)
        {
         reason =
            "Research dates require an inclusive start before the exclusive end";
         return false;
        }

      if(!SolTradeHexText(config.research_history_fingerprint, 64))
        {
         reason = "ResearchHistoryFingerprint must be a SHA-256 value";
         return false;
        }

      if(!SolTradeHexText(config.research_latency_fingerprint, 64) ||
         config.research_latency_sample_count < 30)
        {
         reason =
            "Research latency evidence requires a SHA-256 value and at least 30 samples";
         return false;
        }

      if(config.research_frozen_delay_ms < 100 ||
         (config.research_frozen_delay_ms % 50) != 0)
        {
         reason =
            "ResearchFrozenDelayMs must be at least 100 and aligned to 50 ms";
         return false;
        }

      if(!SolTradeHexText(config.research_source_commit, 40) ||
         !SolTradeHexText(config.research_build_fingerprint, 64))
        {
         reason =
            "Research source commit and build fingerprint are invalid";
         return false;
        }

      if(config.research_expected_terminal_build <= 0 ||
         StringLen(config.research_expected_broker_server) == 0 ||
         !MathIsValidNumber(
            config.research_expected_initial_deposit) ||
         config.research_expected_initial_deposit <= 0.0 ||
         StringLen(config.research_expected_deposit_currency) == 0 ||
         config.research_expected_leverage <= 0)
        {
         reason =
            "Research terminal, broker, deposit, currency, and leverage metadata must be frozen";
         return false;
        }

      if(!SolTradeHexText(
            config.research_expected_trading_input_hash, 64))
        {
         reason =
            "ResearchExpectedTradingInputHash must be a SHA-256 value";
         return false;
        }

      if(!SolTradeSafeRelativePath(config.research_state_root) ||
         !SolTradeSafeRelativePath(config.research_artifact_root))
        {
         reason =
            "Research state and artifact roots must be safe relative paths";
         return false;
        }
     }

   if(!config.enable_csv_journal)
     {
      reason = "EnableCsvJournal must remain true";
      return false;
     }

   if(!SolTradeSafeRelativePath(config.journal_directory))
     {
      reason = "JournalDirectory must be a safe relative MT5 sandbox path";
      return false;
     }

   if(!SolTradeSafeRelativePath(config.execution_state_directory))
     {
      reason =
         "ExecutionStateDirectory must be a safe relative MT5 sandbox path";
      return false;
     }

   if(config.dashboard_refresh_seconds < 1 ||
      config.dashboard_refresh_seconds > 60)
     {
      reason = "DashboardRefreshSeconds must be between 1 and 60";
      return false;
     }

   return true;
  }

#endif // SOLTRADE_CONFIG_MQH
