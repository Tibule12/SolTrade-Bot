#property copyright "SolTrade Bot"
#property link      ""
#property version   "1.000"
#property strict
#property script_show_inputs
#property description "Isolated V2 one-shot connected-demo entry-and-close verification"
#property description "Both confirmations required; V1 markers preserved; no retry."

#define SOLTRADE_CLOSE_VERIFIER_V2_CONFIGURATION
#define SOLTRADE_CLOSE_VERIFIER_REQUIRE_BOTH_CONFIRMATIONS
#define SOLTRADE_V2_RISK_DIRECTORY \
   "SolTradeBot\\one-shot-close-risk-v2"
#define SOLTRADE_V2_STATE_DIRECTORY \
   "SolTradeBot\\one-shot-close-state-v2"
#define SOLTRADE_V2_FIXTURE_MARKER_FILENAME_PREFIX \
   "one_shot_close_fixture_entry_v2_"
#define SOLTRADE_V2_CLOSE_MARKER_FILENAME_PREFIX \
   "one_shot_position_close_v2_"
#define SOLTRADE_V2_FIXTURE_MARKER_SCHEMA \
   "SOLTRADE_CLOSE_FIXTURE_ENTRY_V2"
#define SOLTRADE_V2_CLOSE_MARKER_SCHEMA \
   "SOLTRADE_ONE_SHOT_POSITION_CLOSE_V2"
#define SOLTRADE_V2_PREFLIGHT_STARTED_EVENT \
   "SOLTRADE_CLOSE_V2_PREFLIGHT_STARTED"
#define SOLTRADE_V2_NOT_ARMED_EVENT \
   "SOLTRADE_CLOSE_V2_NOT_ARMED"

#include "SolTradeOneShotPositionCloseVerification.mq5"
