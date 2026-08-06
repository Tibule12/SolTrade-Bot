#ifndef SOLTRADE_ACCOUNT_GUARD_MQH
#define SOLTRADE_ACCOUNT_GUARD_MQH

#include <SolTrade/Config.mqh>

struct SolTradeAccountStatus
  {
   ENUM_SOLTRADE_ENVIRONMENT detected_environment;
   bool                       expected_environment_matches;
   bool                       live_gates_passed;
   bool                       demo_gates_passed;
   bool                       execution_environment_eligible;
   bool                       terminal_connected;
   bool                       terminal_autotrading_allowed;
   bool                       program_trading_allowed;
   bool                       account_trading_allowed;
   bool                       account_expert_allowed;
   string                     account_identifier_hash;
   string                     broker;
   string                     server;
   string                     safety_state;
   string                     reason;
  };

ENUM_SOLTRADE_ENVIRONMENT DetectSolTradeEnvironment()
  {
   if((bool)MQLInfoInteger(MQL_TESTER))
      return SOLTRADE_ENV_BACKTEST;

   const ENUM_ACCOUNT_TRADE_MODE trade_mode =
      (ENUM_ACCOUNT_TRADE_MODE)AccountInfoInteger(ACCOUNT_TRADE_MODE);

   if(trade_mode == ACCOUNT_TRADE_MODE_DEMO)
      return SOLTRADE_ENV_DEMO;

   if(trade_mode == ACCOUNT_TRADE_MODE_REAL)
      return SOLTRADE_ENV_LIVE;

   return SOLTRADE_ENV_UNKNOWN;
  }

// This is a stable pseudonymous logging token, not a cryptographic identity
// proof. The raw account login is deliberately never returned to the journal.
string SolTradeAccountIdentifierHash()
  {
   string source = IntegerToString(AccountInfoInteger(ACCOUNT_LOGIN)) + "|" +
                   AccountInfoString(ACCOUNT_SERVER) + "|" +
                   AccountInfoString(ACCOUNT_COMPANY);
   uint hash = 2166136261;

   for(int index = 0; index < StringLen(source); index++)
     {
      hash ^= (uint)StringGetCharacter(source, index);
      hash = (uint)(hash * (uint)16777619);
     }

   return StringFormat("%08lX", hash);
  }

bool SolTradeExpectedEnvironmentMatches(
   const ENUM_SOLTRADE_ENVIRONMENT expected,
   const ENUM_SOLTRADE_ENVIRONMENT detected)
  {
   return (expected == SOLTRADE_ENV_AUTO_DETECT || expected == detected);
  }

void EvaluateSolTradeAccountSafety(const SolTradeConfig &config,
                                   SolTradeAccountStatus &status)
  {
   status.detected_environment          = DetectSolTradeEnvironment();
   status.expected_environment_matches =
      SolTradeExpectedEnvironmentMatches(config.expected_environment,
                                         status.detected_environment);
   status.live_gates_passed             = false;
   status.demo_gates_passed             = false;
   status.execution_environment_eligible = false;
   status.terminal_connected            =
      (bool)TerminalInfoInteger(TERMINAL_CONNECTED);
   status.terminal_autotrading_allowed  =
      (bool)TerminalInfoInteger(TERMINAL_TRADE_ALLOWED);
   status.program_trading_allowed       =
      (bool)MQLInfoInteger(MQL_TRADE_ALLOWED);
   status.account_trading_allowed       =
      (bool)AccountInfoInteger(ACCOUNT_TRADE_ALLOWED);
   status.account_expert_allowed        =
      (bool)AccountInfoInteger(ACCOUNT_TRADE_EXPERT);
   status.account_identifier_hash       = SolTradeAccountIdentifierHash();
   status.broker                        = AccountInfoString(ACCOUNT_COMPANY);
   status.server                        = AccountInfoString(ACCOUNT_SERVER);
   status.safety_state                  = "EXECUTION LOCKED";
   status.reason                        =
      "Phase 6 execution environment has not passed its gates";

   if(!status.expected_environment_matches)
     {
      status.safety_state = "ENVIRONMENT LOCKED";
      status.reason =
         "Expected " + SolTradeEnvironmentName(config.expected_environment) +
         " but detected " +
         SolTradeEnvironmentName(status.detected_environment);
      return;
     }

   if(config.emergency_stop)
     {
      status.safety_state = "EMERGENCY STOPPED";
      status.reason = "EmergencyStop is enabled";
      return;
     }

   if(status.detected_environment == SOLTRADE_ENV_UNKNOWN)
     {
      status.safety_state = "ACCOUNT MODE INVALID";
      status.reason = "MetaTrader account mode could not be determined";
      return;
     }

   if(status.detected_environment == SOLTRADE_ENV_BACKTEST)
     {
      if(!config.enable_backtest_research)
        {
         status.safety_state = "BACKTEST RESEARCH DISABLED";
         status.reason = "EnableBacktestResearch is false";
         return;
        }

      if(!config.enable_backtest_execution ||
         !config.enable_backtest_position_management)
        {
         status.safety_state = "BACKTEST CAPABILITIES LOCKED";
         status.reason =
            "Backtest execution and position management must be enabled together";
         return;
        }

      const datetime tester_time = TimeCurrent();
      if(tester_time < config.research_start_inclusive ||
         tester_time >= config.research_end_exclusive)
        {
         status.safety_state = "BACKTEST DATASET TIME LOCKED";
         status.reason =
            "Tester time is outside the registered inclusive/exclusive interval";
         return;
        }

      status.execution_environment_eligible = true;
      status.safety_state = "PHASE 6 TEST EXECUTION ELIGIBLE";
      status.reason =
         "Explicit Phase 6 tester gates passed; trade permissions still apply";
      return;
     }

   if(status.detected_environment == SOLTRADE_ENV_DEMO)
     {
      if(!config.enable_demo_execution &&
         !config.enable_position_management)
        {
         status.safety_state = "DEMO AUTOMATION DISABLED";
         status.reason =
            "EnableDemoExecution and EnablePositionManagement are false";
         return;
        }

      if(config.approved_demo_account <= 0)
        {
         status.safety_state = "DEMO EXECUTION DISABLED";
         status.reason = "ApprovedDemoAccount is not configured";
         return;
        }

      if(config.approved_demo_account !=
         AccountInfoInteger(ACCOUNT_LOGIN))
        {
         status.safety_state = "DEMO ACCOUNT NOT APPROVED";
         status.reason =
            "Connected demo account does not match ApprovedDemoAccount";
         return;
        }

      status.demo_gates_passed = true;
      status.execution_environment_eligible = true;
      status.safety_state = "DEMO AUTOMATION ELIGIBLE";
      status.reason =
         "Approved demo automation is eligible; trade permissions still apply";
      return;
     }

   // Real-account execution remains intentionally impossible in Phase 6. This is
   // evaluated before terminal/Algo Trading permissions, so enabling the button
   // cannot bypass the phase boundary.
   status.safety_state = "REAL EXECUTION LOCKED";
   status.reason =
      "Phase 6 rejects every real-account order request";
  }

#endif // SOLTRADE_ACCOUNT_GUARD_MQH
