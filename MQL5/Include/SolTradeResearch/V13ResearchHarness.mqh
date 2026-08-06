#ifndef SOLTRADE_V13_RESEARCH_HARNESS_MQH
#define SOLTRADE_V13_RESEARCH_HARNESS_MQH

#define SOLTRADE_V13_HARNESS_SCHEMA "SOLTRADE_PHASE6_V13_HARNESS_V1"
#define SOLTRADE_V13_MAGIC_NUMBER    2607202601

enum ENUM_SOLTRADE_V13_SIGNAL_STATE
  {
   SOLTRADE_V13_STATE_FLAT  = 0,
   SOLTRADE_V13_STATE_LONG  = 1,
   SOLTRADE_V13_STATE_SHORT = 2
  };

struct SolTradeV13CutoffSnapshot
  {
   bool       captured;
   datetime   cutoff_time;
   datetime   observation_time;
   bool       position_open;
   ulong      position_ticket;
   long       position_type;
   double     volume;
   double     entry_price;
   double     stop_loss;
   double     unrealized_result;
   ENUM_SOLTRADE_V13_SIGNAL_STATE strategy_state;
  };

struct SolTradeV13ReporterTransactionFixture
  {
   datetime deal_time;
   ulong    order_ticket;
   ulong    deal_ticket;
   bool     tester_forced;
  };

void ResetSolTradeV13CutoffSnapshot(
   SolTradeV13CutoffSnapshot &snapshot)
  {
   snapshot.captured          = false;
   snapshot.cutoff_time       = 0;
   snapshot.observation_time  = 0;
   snapshot.position_open     = false;
   snapshot.position_ticket   = 0;
   snapshot.position_type     = -1;
   snapshot.volume            = 0.0;
   snapshot.entry_price       = 0.0;
   snapshot.stop_loss         = 0.0;
   snapshot.unrealized_result = 0.0;
   snapshot.strategy_state    = SOLTRADE_V13_STATE_FLAT;
  }

bool SolTradeV13ValidBoundaries(const datetime reset_at,
                                const datetime eligible_from,
                                const datetime eligible_to,
                                const datetime research_cutoff)
  {
   return reset_at > 0 &&
          eligible_from >= reset_at &&
          eligible_to > eligible_from &&
          research_cutoff >= eligible_to;
  }

bool SolTradeV13BarIsLocal(const datetime bar_time,
                           const datetime reset_at,
                           const datetime eligible_to)
  {
   return bar_time >= reset_at && bar_time < eligible_to;
  }

bool SolTradeV13BarIsEligible(const datetime bar_time,
                              const datetime eligible_from,
                              const datetime eligible_to,
                              const datetime research_cutoff)
  {
   return bar_time >= eligible_from &&
          bar_time < eligible_to &&
          bar_time < research_cutoff;
  }

string SolTradeV13SignalStateName(
   const ENUM_SOLTRADE_V13_SIGNAL_STATE state)
  {
   if(state == SOLTRADE_V13_STATE_LONG)
      return "LONG";
   if(state == SOLTRADE_V13_STATE_SHORT)
      return "SHORT";
   return "FLAT";
  }

string SolTradeV13CutoffClassification(const bool open_at_cutoff)
  {
   return open_at_cutoff
      ? "RIGHT_CENSORED_OPEN_POSITION"
      : "NO_OPEN_POSITION_AT_CUTOFF";
  }

string SolTradeV13ExitClassification(const datetime exit_time,
                                     const datetime eligible_to,
                                     const bool open_at_cutoff)
  {
   if(exit_time >= eligible_to || open_at_cutoff)
      return "POST_CUTOFF_EXCLUDED";
   return "NATURALLY_CLOSED_IN_WINDOW";
  }

string SolTradeV13FixtureTransactionClassification(
   const SolTradeV13ReporterTransactionFixture &transaction,
   const datetime eligible_to)
  {
   if(transaction.deal_time >= eligible_to)
      return "POST_CUTOFF_EXCLUDED";
   if(transaction.tester_forced)
      return "TESTER_FORCED_CLOSE_INVALID_IN_WINDOW";
   return "NATURALLY_CLOSED_IN_WINDOW";
  }

double SolTradeV13FrozenExternalCommission(
   const double executed_volume,
   const int charged_sides)
  {
   if(!MathIsValidNumber(executed_volume) ||
      executed_volume < 0.0 ||
      charged_sides < 0)
      return -1.0;
   return executed_volume * 3.0 * (double)charged_sides;
  }

#endif
