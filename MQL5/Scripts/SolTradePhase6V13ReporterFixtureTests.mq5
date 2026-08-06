#property copyright "SolTrade Bot"
#property link      ""
#property version   "1.000"
#property strict
#property script_show_inputs
#property description "Deterministic Phase 6 V13 boundary/censoring fixtures"
#property description "No strategy, orders, positions, or profitability calculations."

#include <SolTradeResearch/V13ResearchHarness.mqh>

int g_passed = 0;
int g_failed = 0;

void V13Check(const bool condition, const string label)
  {
   if(condition)
     {
      g_passed++;
      Print("PASS | ", label);
     }
   else
     {
      g_failed++;
      Print("FAIL | ", label);
     }
  }

void OnStart()
  {
   const datetime reset_at = D'2025.02.05 01:00:00';
   const datetime eligible_from = D'2025.02.18 05:00:00';
   const datetime eligible_to = D'2025.03.07 23:00:00';
   const datetime cutoff = D'2025.12.24 00:00:00';

   V13Check(SolTradeV13ValidBoundaries(reset_at,
                                       eligible_from,
                                       eligible_to,
                                       cutoff),
            "BOUNDARY valid ordering accepted");
   V13Check(!SolTradeV13ValidBoundaries(reset_at,
                                        eligible_from,
                                        eligible_from,
                                        cutoff),
            "BOUNDARY empty interval rejected");
   V13Check(!SolTradeV13BarIsLocal(reset_at - 3600,
                                   reset_at,
                                   eligible_to),
            "RESET pre-reset bar excluded");
   V13Check(SolTradeV13BarIsLocal(reset_at,
                                  reset_at,
                                  eligible_to),
            "RESET first local bar included");
   V13Check(SolTradeV13BarIsEligible(eligible_from,
                                     eligible_from,
                                     eligible_to,
                                     cutoff),
            "ELIGIBLE inclusive start accepted");
   V13Check(!SolTradeV13BarIsEligible(eligible_to,
                                      eligible_from,
                                      eligible_to,
                                      cutoff),
            "ELIGIBLE exclusive end rejected");
   V13Check(SolTradeV13CutoffClassification(true) ==
               "RIGHT_CENSORED_OPEN_POSITION",
            "CENSOR open position classified");
   V13Check(SolTradeV13CutoffClassification(false) ==
               "NO_OPEN_POSITION_AT_CUTOFF",
            "CENSOR flat state classified");
   V13Check(SolTradeV13ExitClassification(eligible_to - 1,
                                          eligible_to,
                                          false) ==
               "NATURALLY_CLOSED_IN_WINDOW",
            "EXIT in-window natural close retained");
   V13Check(SolTradeV13ExitClassification(eligible_to,
                                          eligible_to,
                                          true) ==
               "POST_CUTOFF_EXCLUDED",
            "EXIT boundary deal excluded");
   V13Check(SolTradeV13ExitClassification(eligible_to + 3600,
                                          eligible_to,
                                          false) ==
               "POST_CUTOFF_EXCLUDED",
            "EXIT later deal excluded");

   SolTradeV13ReporterTransactionFixture natural_close;
   natural_close.deal_time = eligible_to - 1;
   natural_close.order_ticket = 13001;
   natural_close.deal_ticket = 13002;
   natural_close.tester_forced = false;
   V13Check(SolTradeV13FixtureTransactionClassification(
               natural_close, eligible_to) ==
               "NATURALLY_CLOSED_IN_WINDOW",
            "TRANSACTION natural in-window fixture retained");
   V13Check(natural_close.order_ticket == 13001 &&
            natural_close.deal_ticket == 13002,
            "TRANSACTION fixture identifiers retained");

   SolTradeV13ReporterTransactionFixture forced_boundary;
   forced_boundary.deal_time = eligible_to;
   forced_boundary.order_ticket = 13003;
   forced_boundary.deal_ticket = 13004;
   forced_boundary.tester_forced = true;
   V13Check(SolTradeV13FixtureTransactionClassification(
               forced_boundary, eligible_to) ==
               "POST_CUTOFF_EXCLUDED",
            "TRANSACTION tester-forced boundary fixture excluded");
   V13Check(MathAbs(SolTradeV13FrozenExternalCommission(1.0, 1) -
                    3.0) < 1e-12,
            "COMMISSION one-lot one-side is USD 3");
   V13Check(MathAbs(SolTradeV13FrozenExternalCommission(1.0, 2) -
                    6.0) < 1e-12,
            "COMMISSION one-lot round trip is USD 6");
   V13Check(MathAbs(SolTradeV13FrozenExternalCommission(0.01, 2) -
                    0.06) < 1e-12,
            "COMMISSION pro-rata 0.01-lot round trip is USD 0.06");
   V13Check(SolTradeV13FrozenExternalCommission(-0.01, 2) < 0.0,
            "COMMISSION negative volume rejected");
   V13Check(OrdersTotal() == 0,
            "SAFETY no orders created");
   V13Check(PositionsTotal() == 0,
            "SAFETY no positions created");

   Print("SOLTRADE_V13_REPORTER_FIXTURES | passed=", g_passed,
         " | failed=", g_failed,
         " | strategy=NOT_LOADED | pnl=NOT_CALCULATED | trades=0");
  }
