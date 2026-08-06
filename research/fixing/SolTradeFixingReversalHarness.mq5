#property strict
#property version "1.000"
#property description "Tester-only London-fix USD inventory-reversal development harness"

#include <SolTrade/Config.mqh>
#include <SolTrade/AccountGuard.mqh>
#include <SolTrade/MarketData.mqh>
#include <SolTrade/RiskEngine.mqh>
#include <SolTrade/StrategyBreakout.mqh>
#include <SolTrade/ExecutionEngine.mqh>
#include <SolTrade/PositionManager.mqh>

input datetime ResetAt=D'2025.01.02 00:00:00';
input datetime EligibleFrom=D'2025.01.16 00:00:00';
input datetime EligibleTo=D'2025.02.05 00:00:00';
input datetime ResearchCutoff=D'2026.08.01 00:00:00';
input string SegmentId="2025_S1";
input ENUM_SOLTRADE_BACKTEST_DATASET Dataset=SOLTRADE_DATASET_DEVELOPMENT;
input ENUM_SOLTRADE_COST_PROFILE CostProfile=SOLTRADE_COST_NORMAL;
input string ExecutionLayer="NATIVE_NORMAL_EXECUTION";
input int ExpectedExecutionMode=0;
input string ExecutionInstanceId="V25-001";
input int ExpectedEvaluationCount=277;
input datetime ExpectedFirstEvaluation=D'2025.01.20 11:00:00';
input string OutputRoot="SolTrade\\Phase6\\V25\\V25-001";

#define V25_MAGIC 2508202601

struct FixBar { datetime t; double o,h,l,c,atr; };
FixBar g_bars[];
int g_n=0,g_evaluations=0,g_entry_opportunities=0,g_entry_attempts=0,g_entries=0,g_exits=0;
int g_spread_blocks=0,g_execution_blocks=0,g_risk_blocks=0,g_daily_pauses=0,g_weekly_pauses=0,g_emergency_stops=0,g_consecutive_pauses=0,g_stop_exits=0,g_time_exits=0,g_missed_windows=0,g_insufficient_history=0;
datetime g_last_hour=0,g_first_eval=0,g_final_eval=0,g_max_tick=0,g_max_bar=0,g_scheduled_exit=0;
int g_day_key=0;bool g_day_consumed=false,g_exit_attempted=false,g_preflight=false,g_cutoff=false,g_seal_breach=false;
bool g_tracked_open=false;ulong g_track_ticket=0,g_track_identifier=0;long g_track_type=-1;double g_track_volume=0,g_track_entry=0,g_track_stop=0,g_track_unrealized=0;datetime g_track_observation=0;
int g_events=INVALID_HANDLE,g_transactions=INVALID_HANDLE;

SolTradeConfig g_config;SolTradeAccountStatus g_account;SolTradeMarketSnapshot g_market;SolTradeRiskStatus g_risk;SolTradeExecutionStatus g_execution;SolTradePositionStatus g_position;
CSolTradeRiskEngine g_risk_engine;CSolTradeExecutionEngine g_execution_engine;CSolTradePositionManager g_position_manager;

string TS(datetime t){return t>0?TimeToString(t,TIME_DATE|TIME_SECONDS):"NONE";}
void Event(string type,string reason,string detail="")
  {if(g_events!=INVALID_HANDLE)FileWrite(g_events,"SOLTRADE_PHASE6_V25_EVENT_V1",TS(TimeCurrent()),SegmentId,SolTradeBacktestDatasetName(Dataset),SolTradeCostProfileName(CostProfile),ExecutionLayer,type,reason,detail);}

void RecordEntry(string type,SolTradeExecutionReport &r,datetime target,double atr)
  {
   if(g_transactions==INVALID_HANDLE)return;
   ulong pid=r.deal_ticket?((ulong)HistoryDealGetInteger(r.deal_ticket,DEAL_POSITION_ID)):0;
   FileWrite(g_transactions,"SOLTRADE_PHASE6_V25_TRANSACTION_V1",TS(TimeCurrent()),SegmentId,type,TS(r.signal_bar_time),StringFormat("%I64u",pid),r.signal_result,DoubleToString(r.requested_entry,10),DoubleToString(r.actual_entry,10),IntegerToString(r.spread_points),DoubleToString(r.slippage_points,4),DoubleToString(r.volume,8),DoubleToString(r.risk_amount,8),DoubleToString(r.stop_loss,10),StringFormat("%I64u",r.order_ticket),StringFormat("%I64u",r.deal_ticket),IntegerToString((int)r.broker_return_code),"NONE",r.fill_confirmed?"YES":"NO",TS(target),DoubleToString(atr,12));
  }
void RecordExit(string type,SolTradePositionReport &r)
  {
   if(g_transactions==INVALID_HANDLE)return;
   FileWrite(g_transactions,"SOLTRADE_PHASE6_V25_TRANSACTION_V1",TS(TimeCurrent()),SegmentId,type,TS(r.signal_bar_time),StringFormat("%I64u",r.position_identifier),r.position_direction,DoubleToString(r.requested_close_price,10),DoubleToString(r.actual_close_price,10),"0",DoubleToString(r.slippage_points,4),DoubleToString(r.volume,8),"0","0",StringFormat("%I64u",r.order_ticket),StringFormat("%I64u",r.deal_ticket),IntegerToString((int)r.broker_return_code),r.exit_reason_code,r.fill_confirmed?"YES":"NO","NONE","0");
  }

void LoadConfig()
  {
   g_config.strategy_version="LONDON_FIX_USD_INVENTORY_REVERSAL_1_0";g_config.approved_strategy_version="";g_config.risk_profile="CONSERVATIVE_V1";g_config.approved_risk_profile="";g_config.magic_number=V25_MAGIC;g_config.symbol="EURUSD";g_config.timeframe=PERIOD_H1;g_config.minimum_history_bars=300;g_config.max_tick_age_seconds=120;g_config.max_spread_points=30;g_config.max_spread_atr_percent=99.0;g_config.max_slippage_points=10;g_config.risk_per_trade_percent=.25;g_config.daily_loss_limit_percent=1.0;g_config.weekly_loss_limit_percent=2.5;g_config.emergency_drawdown_percent=5.0;g_config.production_baseline_equity=0;g_config.consecutive_loss_limit=3;g_config.reset_emergency_lock=false;g_config.expected_environment=SOLTRADE_ENV_BACKTEST;g_config.enable_demo_execution=false;g_config.enable_position_management=false;g_config.approved_demo_account=0;g_config.allow_live_trading=false;g_config.approved_live_account=0;g_config.emergency_stop=false;g_config.enable_backtest_research=true;g_config.enable_backtest_execution=true;g_config.enable_backtest_position_management=true;g_config.research_manifest_id="PHASE6-V25-FIXING-REVERSAL-DEVELOPMENT";g_config.execution_instance_id=ExecutionInstanceId;g_config.research_dataset=Dataset;g_config.research_cost_profile=CostProfile;g_config.research_start_inclusive=EligibleFrom;g_config.research_end_exclusive=EligibleTo;g_config.research_history_fingerprint="b212f8986bb69ffd2bdfdbf8e98f270d75cf6672bc51d4e601c311064c418bad";g_config.research_latency_fingerprint="e301e77895e8f095d485b00bd1b5da9f10f07d6c8b6ae9162048a7643ddf4dfe";g_config.research_latency_sample_count=30;g_config.research_frozen_delay_ms=200;g_config.research_source_commit="8dc381a5aae2bfe7442eb8036b94cc89a00153e2";g_config.research_build_fingerprint="398f16e38e2eba5d450eaa4a8821488a7834384b9a5de7725165a4439793c283";g_config.research_expected_terminal_build=6090;g_config.research_expected_broker_server="FPMarketsSC-Demo";g_config.research_expected_initial_deposit=10000;g_config.research_expected_deposit_currency="USD";g_config.research_expected_leverage=30;g_config.research_expected_trading_input_hash="398f16e38e2eba5d450eaa4a8821488a7834384b9a5de7725165a4439793c283";g_config.research_state_root="SolTradeBot\\phase6-v25-state\\"+ExecutionInstanceId;g_config.research_artifact_root="SolTradeBot\\phase6-v25-artifacts\\"+ExecutionInstanceId;g_config.enable_csv_journal=true;g_config.journal_directory="SolTradeBot\\phase6-v25-journal\\"+ExecutionInstanceId;g_config.risk_state_directory=g_config.research_state_root;g_config.execution_state_directory=g_config.research_state_root;g_config.enable_dashboard=false;g_config.dashboard_refresh_seconds=1;
  }

bool Preflight(string &reason)
  {
   reason="";
   if(!MQLInfoInteger(MQL_TESTER)||MQLInfoInteger(MQL_OPTIMIZATION)){reason="TESTER_ONLY_OPTIMIZATION_PROHIBITED";return false;}
   if(_Symbol!="EURUSD"||_Period!=PERIOD_H1||AccountInfoString(ACCOUNT_SERVER)!="FPMarketsSC-Demo"||(int)TerminalInfoInteger(TERMINAL_BUILD)!=6090||AccountInfoString(ACCOUNT_CURRENCY)!="USD"||(int)AccountInfoInteger(ACCOUNT_LEVERAGE)!=30||MathAbs(AccountInfoDouble(ACCOUNT_BALANCE)-10000)>0.01){reason="FROZEN_TESTER_ENVIRONMENT_DIFFERS";return false;}
   if(ResetAt<=0||EligibleFrom<ResetAt||EligibleTo<=EligibleFrom||EligibleTo>ResearchCutoff||ResearchCutoff!=D'2026.08.01 00:00:00'||ExpectedEvaluationCount<=0||ExpectedFirstEvaluation<EligibleFrom||ExpectedFirstEvaluation>=EligibleTo){reason="FROZEN_BOUNDARY_INVALID";return false;}
   if((ExpectedExecutionMode==0&&ExecutionLayer!="NATIVE_NORMAL_EXECUTION")||(ExpectedExecutionMode==200&&ExecutionLayer!="FIXED_DELAY_200_MS")||(ExpectedExecutionMode!=0&&ExpectedExecutionMode!=200)){reason="EXECUTION_AXIS_INVALID";return false;}
   if(MathAbs(SymbolInfoDouble(_Symbol,SYMBOL_SWAP_LONG)-(-9.71))>1e-8||MathAbs(SymbolInfoDouble(_Symbol,SYMBOL_SWAP_SHORT)-4.50)>1e-8||(int)SymbolInfoInteger(_Symbol,SYMBOL_SWAP_MODE)!=1||(int)SymbolInfoInteger(_Symbol,SYMBOL_SWAP_ROLLOVER3DAYS)!=3){reason="FROZEN_SWAP_DIFFERS";return false;}
   if(FileIsExist(OutputRoot+"\\run-summary.csv",FILE_COMMON)){reason="OUTPUT_COLLISION";return false;}
   return ValidateSolTradeConfig(g_config,reason);
  }

int DayKey(datetime t){MqlDateTime d;TimeToStruct(t,d);return d.year*10000+d.mon*100+d.day;}
datetime MakeDate(int y,int m,int day,int hour,int minute){MqlDateTime d;ZeroMemory(d);d.year=y;d.mon=m;d.day=day;d.hour=hour;d.min=minute;return StructToTime(d);}
int Weekday(int y,int m,int day){MqlDateTime d;TimeToStruct(MakeDate(y,m,day,0,0),d);return d.day_of_week;}
int FirstSunday(int y,int m){int w=Weekday(y,m,1);return 1+((7-w)%7);}
int LastSunday(int y,int m,int days){int w=Weekday(y,m,days);return days-w;}
bool DstMismatch(datetime now)
  {
   MqlDateTime d;TimeToStruct(now,d);datetime day=MakeDate(d.year,d.mon,d.day,0,0);
   datetime us_start=MakeDate(d.year,3,FirstSunday(d.year,3)+7,0,0),uk_start=MakeDate(d.year,3,LastSunday(d.year,3,31),0,0),uk_end=MakeDate(d.year,10,LastSunday(d.year,10,31),0,0),us_end=MakeDate(d.year,11,FirstSunday(d.year,11),0,0);
   return (day>=us_start&&day<uk_start)||(day>=uk_end&&day<us_end);
  }
datetime EntryTarget(datetime now){MqlDateTime d;TimeToStruct(now,d);return MakeDate(d.year,d.mon,d.day,DstMismatch(now)?19:18,5);}

void RefreshFoundation()
  {EvaluateSolTradeAccountSafety(g_config,g_account);RefreshSolTradeMarketData(g_config,g_market);string reason="";g_risk_engine.Refresh(TimeCurrent(),AccountInfoDouble(ACCOUNT_EQUITY),reason);g_risk_engine.GetStatus(g_risk);g_execution_engine.RefreshExposure();g_execution_engine.GetStatus(g_execution);g_position_manager.Refresh(reason);g_position_manager.GetStatus(g_position);}
void TrackPosition()
  {g_track_observation=TimeCurrent();g_tracked_open=false;for(int i=0;i<PositionsTotal();i++){ulong t=PositionGetTicket(i);if(t==0||(ulong)PositionGetInteger(POSITION_MAGIC)!=V25_MAGIC||PositionGetString(POSITION_SYMBOL)!="EURUSD")continue;g_tracked_open=true;g_track_ticket=t;g_track_identifier=(ulong)PositionGetInteger(POSITION_IDENTIFIER);g_track_type=PositionGetInteger(POSITION_TYPE);g_track_volume=PositionGetDouble(POSITION_VOLUME);g_track_entry=PositionGetDouble(POSITION_PRICE_OPEN);g_track_stop=PositionGetDouble(POSITION_SL);g_track_unrealized=PositionGetDouble(POSITION_PROFIT)+PositionGetDouble(POSITION_SWAP);break;}}

void AddCompletedBar()
  {
   datetime hour=iTime(_Symbol,PERIOD_H1,0);if(hour<=0||hour==g_last_hour)return;g_last_hour=hour;MqlRates rr[1];if(CopyRates(_Symbol,PERIOD_H1,1,1,rr)!=1||rr[0].time<ResetAt||rr[0].time>=EligibleTo||rr[0].time==g_max_bar)return;
   int z=ArraySize(g_bars);ArrayResize(g_bars,z+1,512);g_bars[z].t=rr[0].time;g_bars[z].o=rr[0].open;g_bars[z].h=rr[0].high;g_bars[z].l=rr[0].low;g_bars[z].c=rr[0].close;g_bars[z].atr=0;g_n=z+1;
   if(g_n==14){double x=0;for(int i=0;i<14;i++){double tr=g_bars[i].h-g_bars[i].l;if(i>0)tr=MathMax(tr,MathMax(MathAbs(g_bars[i].h-g_bars[i-1].c),MathAbs(g_bars[i].l-g_bars[i-1].c)));x+=tr;}g_bars[z].atr=x/14.0;}else if(g_n>14){double tr=MathMax(g_bars[z].h-g_bars[z].l,MathMax(MathAbs(g_bars[z].h-g_bars[z-1].c),MathAbs(g_bars[z].l-g_bars[z-1].c)));g_bars[z].atr=(g_bars[z-1].atr*13.0+tr)/14.0;}
   g_max_bar=rr[0].time;if(g_n>=300&&rr[0].time>=EligibleFrom){if(g_first_eval==0)g_first_eval=rr[0].time;g_final_eval=rr[0].time;g_evaluations++;}
  }

void AttemptEntry(datetime target)
  {
   g_day_consumed=true;g_entry_opportunities++;
   if(g_n<300||g_bars[g_n-1].atr<=0){g_insufficient_history++;Event("ENTRY_SKIP","INSUFFICIENT_CLEAN_HISTORY","target="+TS(target));return;}
   if(g_position.position_present){Event("ENTRY_SKIP","POSITION_ALREADY_OPEN","target="+TS(target));return;}
   double spread=(g_market.ask-g_market.bid)/g_market.point;if(spread>30.0){g_spread_blocks++;Event("ENTRY_BLOCK","SPREAD_ABOVE_30_POINTS","spread="+DoubleToString(spread,4));return;}
   if(g_risk.daily_locked){g_daily_pauses++;g_risk_blocks++;return;}if(g_risk.weekly_locked){g_weekly_pauses++;g_risk_blocks++;return;}if(g_risk.emergency_locked){g_emergency_stops++;g_risk_blocks++;return;}if(g_risk.consecutive_locked){g_consecutive_pauses++;g_risk_blocks++;return;}
   FixBar b=g_bars[g_n-1];SolTradeStrategySignal s;ResetSolTradeStrategySignal(s);s.evaluated=true;s.valid=true;s.entry_signal=SOLTRADE_SIGNAL_BUY;s.signal_bar_time=b.t;s.signal_open=b.o;s.signal_high=b.h;s.signal_low=b.l;s.signal_close=b.c;s.atr_14=b.atr;s.initial_stop_distance=2.0*b.atr;s.entry_reason_code="LONDON_FIX_POSTFIX_BUY";s.entry_reason="Post-London-fix USD inventory-reversal entry";
   SolTradeExecutionReport r;g_entry_attempts++;g_execution_engine.ProcessSignal(s,g_account,g_market,g_risk,false,r);if(r.evaluated){if(r.broker_accepted&&r.deal_ticket!=0){g_entries++;g_scheduled_exit=target+4*3600;g_exit_attempted=false;}else if(r.reason_code=="SPREAD_REJECTED"||r.reason_code=="EXCESSIVE_SPREAD"||r.reason_code=="SPREAD_EXCEEDS_LIMIT")g_spread_blocks++;else if(r.reason_code!="RISK_ENGINE_LOCKED")g_execution_blocks++;Event(r.event_type,r.reason_code,r.reason);RecordEntry("ENTRY_ATTEMPT",r,target,b.atr);}g_execution_engine.GetStatus(g_execution);
  }

void AttemptTimeExit()
  {
   if(g_exit_attempted||!g_position.position_present)return;g_exit_attempted=true;SolTradeStrategySignal s;ResetSolTradeStrategySignal(s);s.evaluated=true;s.valid=true;s.signal_bar_time=g_bars[g_n-1].t;s.exit_signal=SOLTRADE_EXIT_LONG;s.exit_reason_code="FIXING_REVERSAL_TIME_EXIT";s.exit_reason="Frozen four-hour post-fix holding period complete";SolTradePositionReport r;g_position_manager.ProcessClose(s,SOLTRADE_CLOSE_STRATEGY,g_account,g_market,r);if(r.evaluated){Event(r.event_type,r.reason_code,r.reason);RecordExit("EXIT_ATTEMPT",r);}g_position_manager.GetStatus(g_position);
  }

void ProcessClock(datetime now)
  {
   int key=DayKey(now);if(key!=g_day_key){g_day_key=key;g_day_consumed=false;}
   MqlDateTime d;TimeToStruct(now,d);if(d.day_of_week==0||d.day_of_week==6)return;
   datetime target=EntryTarget(now),scheduled=target+4*3600;if(!g_day_consumed&&target>=EligibleFrom&&scheduled<EligibleTo){if(now>=target&&now<target+5*60)AttemptEntry(target);else if(now>=target+5*60){g_day_consumed=true;g_missed_windows++;Event("ENTRY_SKIP","NO_TRADABLE_TICK_IN_ENTRY_WINDOW","target="+TS(target));}}
   if(g_position.position_present&&g_scheduled_exit>0&&now>=g_scheduled_exit)AttemptTimeExit();
  }

void FreezeCutoff(){if(g_cutoff)return;g_cutoff=true;TrackPosition();Event("CUTOFF_FROZEN",g_tracked_open?"RIGHT_CENSORED_OPEN_POSITION":"NO_OPEN_POSITION_AT_CUTOFF","eligible_to="+TS(EligibleTo));}
bool WriteCutoff()
  {int h=FileOpen(OutputRoot+"\\cutoff.csv",FILE_WRITE|FILE_CSV|FILE_ANSI|FILE_COMMON,',');if(h==INVALID_HANDLE)return false;FileWrite(h,"field","value");FileWrite(h,"classification",g_tracked_open?"RIGHT_CENSORED_OPEN_POSITION":"NO_OPEN_POSITION_AT_CUTOFF");FileWrite(h,"eligible_to",TS(EligibleTo));FileWrite(h,"observation_time",TS(g_track_observation));FileWrite(h,"position_open",g_tracked_open?"YES":"NO");FileWrite(h,"position_ticket",StringFormat("%I64u",g_track_ticket));FileWrite(h,"position_identifier",StringFormat("%I64u",g_track_identifier));FileWrite(h,"position_type",IntegerToString(g_track_type));FileWrite(h,"volume",DoubleToString(g_track_volume,8));FileWrite(h,"entry_price",DoubleToString(g_track_entry,10));FileWrite(h,"stop_loss",DoubleToString(g_track_stop,10));FileWrite(h,"unrealized_result_reporting_only",DoubleToString(g_track_unrealized,8));FileWrite(h,"formal_pnl_included","NO");FileWrite(h,"naturally_closed_trade_included","NO");FileClose(h);return true;}
bool WriteDeals()
  {HistorySelect(ResetAt,TimeCurrent());int h=FileOpen(OutputRoot+"\\deals.csv",FILE_WRITE|FILE_CSV|FILE_ANSI|FILE_COMMON,',');if(h==INVALID_HANDLE)return false;FileWrite(h,"deal_ticket","order_ticket","position_identifier","time","time_msc","entry","type","reason","volume","price","profit","commission","swap","fee","magic","symbol","comment","in_research_window");for(int i=0;i<HistoryDealsTotal();i++){ulong d=HistoryDealGetTicket(i);if(d==0||(ulong)HistoryDealGetInteger(d,DEAL_MAGIC)!=V25_MAGIC||HistoryDealGetString(d,DEAL_SYMBOL)!="EURUSD")continue;datetime t=(datetime)HistoryDealGetInteger(d,DEAL_TIME);FileWrite(h,StringFormat("%I64u",d),StringFormat("%I64u",(ulong)HistoryDealGetInteger(d,DEAL_ORDER)),StringFormat("%I64u",(ulong)HistoryDealGetInteger(d,DEAL_POSITION_ID)),TS(t),StringFormat("%I64d",HistoryDealGetInteger(d,DEAL_TIME_MSC)),IntegerToString((int)HistoryDealGetInteger(d,DEAL_ENTRY)),IntegerToString((int)HistoryDealGetInteger(d,DEAL_TYPE)),IntegerToString((int)HistoryDealGetInteger(d,DEAL_REASON)),DoubleToString(HistoryDealGetDouble(d,DEAL_VOLUME),8),DoubleToString(HistoryDealGetDouble(d,DEAL_PRICE),10),DoubleToString(HistoryDealGetDouble(d,DEAL_PROFIT),8),DoubleToString(HistoryDealGetDouble(d,DEAL_COMMISSION),8),DoubleToString(HistoryDealGetDouble(d,DEAL_SWAP),8),DoubleToString(HistoryDealGetDouble(d,DEAL_FEE),8),StringFormat("%I64d",HistoryDealGetInteger(d,DEAL_MAGIC)),HistoryDealGetString(d,DEAL_SYMBOL),HistoryDealGetString(d,DEAL_COMMENT),(t>=EligibleFrom&&t<EligibleTo)?"YES":"NO");}FileClose(h);return true;}
bool WriteSummary()
  {int h=FileOpen(OutputRoot+"\\run-summary.csv",FILE_WRITE|FILE_CSV|FILE_ANSI|FILE_COMMON,',');if(h==INVALID_HANDLE)return false;FileWrite(h,"field","value");FileWrite(h,"schema","SOLTRADE_PHASE6_V25_RUN_SUMMARY_V1");FileWrite(h,"execution_instance_id",ExecutionInstanceId);FileWrite(h,"segment_id",SegmentId);FileWrite(h,"dataset",SolTradeBacktestDatasetName(Dataset));FileWrite(h,"cost_profile",SolTradeCostProfileName(CostProfile));FileWrite(h,"execution_layer",ExecutionLayer);FileWrite(h,"expected_execution_mode",ExpectedExecutionMode);FileWrite(h,"reset_at",TS(ResetAt));FileWrite(h,"eligible_from",TS(EligibleFrom));FileWrite(h,"eligible_to",TS(EligibleTo));FileWrite(h,"first_evaluation",TS(g_first_eval));FileWrite(h,"final_evaluation",TS(g_final_eval));FileWrite(h,"expected_processable_completed_h1",ExpectedEvaluationCount-1);FileWrite(h,"evaluations",g_evaluations);FileWrite(h,"entry_opportunities",g_entry_opportunities);FileWrite(h,"entry_attempts",g_entry_attempts);FileWrite(h,"entry_fills",g_entries);FileWrite(h,"exit_fills",g_exits);FileWrite(h,"missed_entry_windows",g_missed_windows);FileWrite(h,"insufficient_history_skips",g_insufficient_history);FileWrite(h,"spread_blocks",g_spread_blocks);FileWrite(h,"execution_blocks",g_execution_blocks);FileWrite(h,"risk_engine_blocks",g_risk_blocks);FileWrite(h,"daily_limit_pauses",g_daily_pauses);FileWrite(h,"weekly_limit_pauses",g_weekly_pauses);FileWrite(h,"emergency_stops",g_emergency_stops);FileWrite(h,"consecutive_loss_pauses",g_consecutive_pauses);FileWrite(h,"stop_loss_exits",g_stop_exits);FileWrite(h,"time_exits",g_time_exits);FileWrite(h,"censored_position",g_tracked_open?"YES":"NO");FileWrite(h,"max_tick",TS(g_max_tick));FileWrite(h,"max_completed_h1",TS(g_max_bar));FileWrite(h,"seal_breach",g_seal_breach?"YES":"NO");FileWrite(h,"native_tester_commission_inspection","DEALS_LEDGER_REQUIRED");bool valid=g_preflight&&g_cutoff&&!g_seal_breach&&g_evaluations==ExpectedEvaluationCount-1&&g_first_eval==ExpectedFirstEvaluation;FileWrite(h,"run_evidence_status",valid?"PASS":"FAIL");FileClose(h);return valid;}

int OnInit()
  {ArrayResize(g_bars,0);LoadConfig();string reason="";if(!Preflight(reason)){Print("SOLTRADE_V25_PREFLIGHT_FAILED | ",reason);return INIT_PARAMETERS_INCORRECT;}g_events=FileOpen(OutputRoot+"\\events.csv",FILE_WRITE|FILE_CSV|FILE_ANSI|FILE_COMMON,',');g_transactions=FileOpen(OutputRoot+"\\transactions.csv",FILE_WRITE|FILE_CSV|FILE_ANSI|FILE_COMMON,',');if(g_events==INVALID_HANDLE||g_transactions==INVALID_HANDLE)return INIT_FAILED;FileWrite(g_events,"schema","time","segment_id","dataset","cost_profile","execution_layer","event_type","reason_code","details");FileWrite(g_transactions,"schema","time","segment_id","record_type","signal_bar_time","position_identifier","direction","requested_price","actual_price","spread_points","slippage_points","volume","initial_risk_amount","stop_loss","order_ticket","deal_ticket","broker_retcode","exit_reason","fill_confirmed","scheduled_entry_target","entry_atr");ResetSolTradeMarketSnapshot(g_market);ResetSolTradeRiskStatus(g_risk);ResetSolTradeExecutionStatus(g_execution);ResetSolTradePositionStatus(g_position);EvaluateSolTradeAccountSafety(g_config,g_account);if(!InitialiseSolTradeMarketData(g_config,g_last_hour,reason)||!g_risk_engine.Initialise(g_config,g_account.account_identifier_hash,TimeCurrent(),AccountInfoDouble(ACCOUNT_EQUITY),reason)||!g_execution_engine.Initialise(g_config,g_account.account_identifier_hash,reason)||!g_position_manager.Initialise(g_config,g_account.account_identifier_hash,reason)){Print("SOLTRADE_V25_ENGINE_INIT_FAILED | ",reason);return INIT_FAILED;}g_preflight=true;Event("PREFLIGHT_PASSED","NONE","tester_only=YES;optimization=NO");return INIT_SUCCEEDED;}
void OnTick()
  {datetime now=TimeCurrent();if(now>=ResearchCutoff){g_seal_breach=true;return;}if(now>=EligibleTo){FreezeCutoff();return;}g_max_tick=now;RefreshFoundation();TrackPosition();AddCompletedBar();ProcessClock(now);}
void OnTradeTransaction(const MqlTradeTransaction &t,const MqlTradeRequest &q,const MqlTradeResult &z)
  {if(TimeCurrent()>=EligibleTo)return;SolTradeExecutionReport e;if(g_execution_engine.HandleTradeTransaction(t,e)){Event(e.event_type,e.reason_code,"deal="+StringFormat("%I64u",e.deal_ticket));RecordEntry("ENTRY_TRANSACTION",e,0,0);}SolTradePositionReport x;if(g_position_manager.HandleTradeTransaction(t,x)){if(x.fill_confirmed){g_exits++;if(x.exit_reason_code=="FIXING_REVERSAL_TIME_EXIT")g_time_exits++;else g_stop_exits++;}Event(x.event_type,x.reason_code,x.exit_reason_code);RecordExit("EXIT_TRANSACTION",x);string reason="";g_risk_engine.RecordClosedOutcome("V25_EXIT_"+StringFormat("%I64u",x.deal_ticket),x.final_profit_loss,TimeCurrent(),AccountInfoDouble(ACCOUNT_EQUITY),reason);g_risk_engine.GetStatus(g_risk);g_scheduled_exit=0;g_exit_attempted=false;}TrackPosition();}
double OnTester()
  {FreezeCutoff();bool ok=WriteCutoff()&&WriteDeals()&&WriteSummary();if(g_events!=INVALID_HANDLE)FileFlush(g_events);if(g_transactions!=INVALID_HANDLE)FileFlush(g_transactions);Print("SOLTRADE_V25_RUN_RESULT | status=",ok?"PASS":"FAIL"," | instance=",ExecutionInstanceId," | evaluations=",g_evaluations," | entries=",g_entries," | exits=",g_exits," | censored=",g_tracked_open?"YES":"NO"," | seal_breach=",g_seal_breach?"YES":"NO");return ok?1:0;}
void OnDeinit(const int reason){if(g_events!=INVALID_HANDLE)FileClose(g_events);if(g_transactions!=INVALID_HANDLE)FileClose(g_transactions);}
