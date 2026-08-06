#property strict
#property version "1.000"
#property description "V26 tester-only multi-currency cross-sectional momentum performance harness"

#include <SolTrade/Config.mqh>
#include <SolTrade/AccountGuard.mqh>
#include <SolTrade/MarketData.mqh>
#include <SolTrade/RiskEngine.mqh>
#include <SolTrade/StrategyBreakout.mqh>
#include <SolTrade/ExecutionEngine.mqh>
#include <SolTrade/PositionManager.mqh>

input datetime EligibleFrom=D'2025.01.06 10:05:00';
input datetime EligibleTo=D'2026.01.01 00:00:00';
input datetime ResearchCutoff=D'2026.08.01 00:00:00';
input string DatasetId="V26_2025_DEVELOPMENT";
input string ExecutionLayer="NATIVE_NORMAL_EXECUTION";
input int ExpectedExecutionMode=0;
input int ExpectedScheduleLegs=204;
input string ScheduleFile="SolTrade\\Phase6\\V26Signals\\V26_2025_DEVELOPMENT\\signal-schedule.csv";
input string ExecutionInstanceId="V26-2025-NATIVE";
input string OutputRoot="SolTrade\\Phase6\\V26Performance\\V26-2025-NATIVE";

#define V26_MAGIC_BASE 2608202600

string SYMBOLS[7]={"EURUSD","GBPUSD","AUDUSD","NZDUSD","USDCAD","USDCHF","USDJPY"};
double SWAP_LONG[7]={-9.71,-2.63,-1.83,-2.76,3.49,5.97,9.54};
double SWAP_SHORT[7]={4.50,-1.53,-0.51,0.46,-9.10,-11.60,-18.97};

struct V26Leg {datetime target;datetime exit_time;int symbol_index;string direction;string portfolio_side;};
V26Leg g_legs[];
int g_leg_count=0,g_next=0,g_rebalances=0,g_entry_attempts=0,g_entry_fills=0,g_exit_fills=0,g_missed=0,g_spread_blocks=0,g_risk_blocks=0,g_execution_blocks=0;
datetime g_max_tick=0,g_close_target=0;
bool g_preflight=false,g_seal_breach=false;
int g_events=INVALID_HANDLE,g_transactions=INVALID_HANDLE;

SolTradeConfig g_config[7];
SolTradeAccountStatus g_account[7];
SolTradeMarketSnapshot g_market[7];
SolTradeExecutionStatus g_execution[7];
SolTradePositionStatus g_position[7];
CSolTradeExecutionEngine g_exec[7];
CSolTradePositionManager g_pm[7];
CSolTradeRiskEngine g_risk_engine;
SolTradeRiskStatus g_risk;
int g_atr[7];

string TS(datetime value){return value>0?TimeToString(value,TIME_DATE|TIME_SECONDS):"NONE";}
int SymbolIndex(string symbol){for(int i=0;i<7;i++)if(SYMBOLS[i]==symbol)return i;return -1;}
void Event(string type,string reason,string detail=""){if(g_events!=INVALID_HANDLE)FileWrite(g_events,"SOLTRADE_PHASE6_V26_EVENT_V1",TS(TimeCurrent()),DatasetId,ExecutionLayer,type,reason,detail);}

void LoadConfig(int i)
  {
   g_config[i].strategy_version="FX_CROSS_SECTIONAL_MOMENTUM_3W_1W_TOP2_BOTTOM2_1_0";g_config[i].approved_strategy_version="";g_config[i].risk_profile="CONSERVATIVE_V1";g_config[i].approved_risk_profile="";g_config[i].magic_number=V26_MAGIC_BASE+i+1;g_config[i].symbol=SYMBOLS[i];g_config[i].timeframe=PERIOD_H1;g_config[i].minimum_history_bars=300;g_config[i].max_tick_age_seconds=120;g_config[i].max_spread_points=30;g_config[i].max_spread_atr_percent=99.0;g_config[i].max_slippage_points=10;g_config[i].risk_per_trade_percent=.05;g_config[i].daily_loss_limit_percent=1.0;g_config[i].weekly_loss_limit_percent=2.5;g_config[i].emergency_drawdown_percent=5.0;g_config[i].production_baseline_equity=0;g_config[i].consecutive_loss_limit=3;g_config[i].reset_emergency_lock=false;g_config[i].expected_environment=SOLTRADE_ENV_BACKTEST;g_config[i].enable_demo_execution=false;g_config[i].enable_position_management=false;g_config[i].approved_demo_account=0;g_config[i].allow_live_trading=false;g_config[i].approved_live_account=0;g_config[i].emergency_stop=false;g_config[i].enable_backtest_research=true;g_config[i].enable_backtest_execution=true;g_config[i].enable_backtest_position_management=true;g_config[i].research_manifest_id="PHASE6-V26-CROSS-SECTIONAL-MOMENTUM";g_config[i].execution_instance_id=ExecutionInstanceId+"-"+SYMBOLS[i];g_config[i].research_dataset=SOLTRADE_DATASET_DEVELOPMENT;g_config[i].research_cost_profile=SOLTRADE_COST_NORMAL;g_config[i].research_start_inclusive=EligibleFrom;g_config[i].research_end_exclusive=EligibleTo;g_config[i].research_history_fingerprint="b212f8986bb69ffd2bdfdbf8e98f270d75cf6672bc51d4e601c311064c418bad";g_config[i].research_latency_fingerprint="e301e77895e8f095d485b00bd1b5da9f10f07d6c8b6ae9162048a7643ddf4dfe";g_config[i].research_latency_sample_count=30;g_config[i].research_frozen_delay_ms=200;g_config[i].research_source_commit="5ef675ae6be908ae228f7825e7b910472eeab206";g_config[i].research_build_fingerprint="dba62ffabb987248971934ba37b3d91244809b1b9eaacdc42811360289b7bf87";g_config[i].research_expected_terminal_build=6090;g_config[i].research_expected_broker_server="FPMarketsSC-Demo";g_config[i].research_expected_initial_deposit=10000;g_config[i].research_expected_deposit_currency="USD";g_config[i].research_expected_leverage=30;g_config[i].research_expected_trading_input_hash="dba62ffabb987248971934ba37b3d91244809b1b9eaacdc42811360289b7bf87";g_config[i].research_state_root="SolTradeBot\\phase6-v26-state\\"+ExecutionInstanceId+"\\"+SYMBOLS[i];g_config[i].research_artifact_root="SolTradeBot\\phase6-v26-artifacts\\"+ExecutionInstanceId+"\\"+SYMBOLS[i];g_config[i].enable_csv_journal=true;g_config[i].journal_directory="SolTradeBot\\phase6-v26-journal\\"+ExecutionInstanceId+"\\"+SYMBOLS[i];g_config[i].risk_state_directory="SolTradeBot\\phase6-v26-risk\\"+ExecutionInstanceId;g_config[i].execution_state_directory=g_config[i].research_state_root;g_config[i].enable_dashboard=false;g_config[i].dashboard_refresh_seconds=1;
  }

bool LoadSchedule(string &reason)
  {
   int h=FileOpen(ScheduleFile,FILE_READ|FILE_CSV|FILE_ANSI|FILE_COMMON,',');if(h==INVALID_HANDLE){reason="SCHEDULE_OPEN_FAILED";return false;}
   for(int i=0;i<15;i++)FileReadString(h);
   while(!FileIsEnding(h))
     {
      string schema=FileReadString(h);if(schema=="")break;
      string dataset=FileReadString(h),target=FileReadString(h),currency=FileReadString(h),symbol=FileReadString(h);FileReadString(h);FileReadString(h);FileReadString(h);string side=FileReadString(h),direction=FileReadString(h);FileReadString(h);FileReadString(h);FileReadString(h);FileReadString(h);string exit_time=FileReadString(h);
      if(dataset!=DatasetId||direction=="NONE")continue;
      int index=SymbolIndex(symbol);if(index<0){FileClose(h);reason="UNKNOWN_SCHEDULE_SYMBOL";return false;}
      int n=ArraySize(g_legs);ArrayResize(g_legs,n+1,512);g_legs[n].target=StringToTime(target);g_legs[n].exit_time=StringToTime(exit_time);g_legs[n].symbol_index=index;g_legs[n].direction=direction;g_legs[n].portfolio_side=side;
     }
   FileClose(h);g_leg_count=ArraySize(g_legs);
   if(g_leg_count!=ExpectedScheduleLegs||g_leg_count%4!=0){reason="SCHEDULE_COUNT_MISMATCH";return false;}
   for(int i=0;i<g_leg_count;i+=4)for(int j=1;j<4;j++)if(g_legs[i+j].target!=g_legs[i].target){reason="SCHEDULE_GROUP_INVALID";return false;}
   return true;
  }

bool Preflight(string &reason)
  {
   reason="";if(!MQLInfoInteger(MQL_TESTER)||MQLInfoInteger(MQL_OPTIMIZATION)){reason="TESTER_ONLY_OPTIMIZATION_PROHIBITED";return false;}
   if(_Symbol!="EURUSD"||_Period!=PERIOD_H1||AccountInfoString(ACCOUNT_SERVER)!="FPMarketsSC-Demo"||(int)TerminalInfoInteger(TERMINAL_BUILD)!=6090||AccountInfoString(ACCOUNT_CURRENCY)!="USD"||(int)AccountInfoInteger(ACCOUNT_LEVERAGE)!=30||MathAbs(AccountInfoDouble(ACCOUNT_BALANCE)-10000)>0.01){reason="FROZEN_ENVIRONMENT_DIFFERS";return false;}
   if(EligibleFrom<=0||EligibleTo<=EligibleFrom||EligibleTo>ResearchCutoff||ResearchCutoff!=D'2026.08.01 00:00:00'||(ExpectedExecutionMode==0&&ExecutionLayer!="NATIVE_NORMAL_EXECUTION")||(ExpectedExecutionMode==200&&ExecutionLayer!="FIXED_DELAY_200_MS")){reason="FROZEN_BOUNDARY_OR_AXIS_INVALID";return false;}
   if(FileIsExist(OutputRoot+"\\run-summary.csv",FILE_COMMON)){reason="OUTPUT_COLLISION";return false;}
   for(int i=0;i<7;i++)
     {
      if(!SymbolSelect(SYMBOLS[i],true)){reason="SYMBOL_SELECT_FAILED";return false;}
      if(MathAbs(SymbolInfoDouble(SYMBOLS[i],SYMBOL_SWAP_LONG)-SWAP_LONG[i])>1e-8||MathAbs(SymbolInfoDouble(SYMBOLS[i],SYMBOL_SWAP_SHORT)-SWAP_SHORT[i])>1e-8||(int)SymbolInfoInteger(SYMBOLS[i],SYMBOL_SWAP_MODE)!=1||(int)SymbolInfoInteger(SYMBOLS[i],SYMBOL_SWAP_ROLLOVER3DAYS)!=3){reason="FROZEN_SYMBOL_SPEC_DIFFERS_"+SYMBOLS[i];return false;}
      LoadConfig(i);
      string actual_symbol=g_config[i].symbol;
      if(i>0)g_config[i].symbol="EURUSD";
      bool config_valid=ValidateSolTradeConfig(g_config[i],reason);
      g_config[i].symbol=actual_symbol;
      if(!config_valid)return false;
     }
   return LoadSchedule(reason);
  }

int PortfolioPositions()
  {int count=0;for(int p=0;p<PositionsTotal();p++){ulong ticket=PositionGetTicket(p);if(ticket==0)continue;long magic=PositionGetInteger(POSITION_MAGIC);if(magic>V26_MAGIC_BASE&&magic<=V26_MAGIC_BASE+7)count++;}return count;}

void RefreshAll()
  {
   string reason="";g_risk_engine.Refresh(TimeCurrent(),AccountInfoDouble(ACCOUNT_EQUITY),reason);g_risk_engine.GetStatus(g_risk);
   for(int i=0;i<7;i++){EvaluateSolTradeAccountSafety(g_config[i],g_account[i]);RefreshSolTradeMarketData(g_config[i],g_market[i]);g_exec[i].RefreshExposure();g_exec[i].GetStatus(g_execution[i]);g_pm[i].Refresh(reason);g_pm[i].GetStatus(g_position[i]);}
  }

bool ATR(int index,double &value)
  {double values[1];if(CopyBuffer(g_atr[index],0,1,1,values)!=1||values[0]<=0)return false;value=values[0];return true;}

void RecordEntry(string record_type,int index,datetime target,SolTradeExecutionReport &r,double atr)
  {if(g_transactions==INVALID_HANDLE)return;FileWrite(g_transactions,"SOLTRADE_PHASE6_V26_TRANSACTION_V1",TS(TimeCurrent()),DatasetId,ExecutionLayer,SYMBOLS[index],record_type,TS(target),r.signal_result,DoubleToString(r.requested_entry,10),DoubleToString(r.actual_entry,10),r.spread_points,DoubleToString(r.slippage_points,4),DoubleToString(r.volume,8),DoubleToString(r.risk_amount,8),DoubleToString(r.stop_loss,10),StringFormat("%I64u",r.order_ticket),StringFormat("%I64u",r.deal_ticket),(int)r.broker_return_code,r.fill_confirmed?"YES":"NO",DoubleToString(atr,12));}
void RecordExit(string record_type,int index,SolTradePositionReport &r)
  {if(g_transactions==INVALID_HANDLE)return;FileWrite(g_transactions,"SOLTRADE_PHASE6_V26_TRANSACTION_V1",TS(TimeCurrent()),DatasetId,ExecutionLayer,SYMBOLS[index],record_type,TS(r.signal_bar_time),r.position_direction,DoubleToString(r.requested_close_price,10),DoubleToString(r.actual_close_price,10),0,DoubleToString(r.slippage_points,4),DoubleToString(r.volume,8),0,0,StringFormat("%I64u",r.order_ticket),StringFormat("%I64u",r.deal_ticket),(int)r.broker_return_code,r.fill_confirmed?"YES":"NO",r.exit_reason_code);}

void AttemptEntry(V26Leg &leg)
  {
   int i=leg.symbol_index;double atr=0;if(!ATR(i,atr)){g_execution_blocks++;Event("ENTRY_BLOCK","ATR_UNAVAILABLE",SYMBOLS[i]);return;}
   SolTradeStrategySignal signal;ResetSolTradeStrategySignal(signal);signal.evaluated=true;signal.valid=true;signal.entry_signal=(leg.direction=="BUY")?SOLTRADE_SIGNAL_BUY:SOLTRADE_SIGNAL_SELL;signal.signal_bar_time=leg.target;signal.signal_close=(leg.direction=="BUY")?g_market[i].ask:g_market[i].bid;signal.signal_high=signal.signal_close;signal.signal_low=signal.signal_close;signal.signal_open=signal.signal_close;signal.atr_14=atr;signal.initial_stop_distance=3.0*atr;signal.entry_reason_code="CROSS_SECTIONAL_MOMENTUM_WEEKLY";signal.entry_reason=leg.portfolio_side+" currency relative-strength portfolio";
   SolTradeExecutionReport report;g_entry_attempts++;g_exec[i].ProcessSignal(signal,g_account[i],g_market[i],g_risk,false,report);if(report.evaluated){if(report.broker_accepted&&report.deal_ticket!=0)g_entry_fills++;else if(report.reason_code=="RISK_ENGINE_LOCKED")g_risk_blocks++;else if(report.reason_code=="SPREAD_REJECTED"||report.reason_code=="EXCESSIVE_SPREAD"||report.reason_code=="SPREAD_EXCEEDS_LIMIT")g_spread_blocks++;else g_execution_blocks++;Event(report.event_type,report.reason_code,SYMBOLS[i]+";"+report.reason);RecordEntry("ENTRY_ATTEMPT",i,leg.target,report,atr);}g_exec[i].GetStatus(g_execution[i]);
  }

void ClosePortfolio(datetime target)
  {
   for(int i=0;i<7;i++)
     {
      string reason="";g_pm[i].Refresh(reason);g_pm[i].GetStatus(g_position[i]);if(!g_position[i].position_present)continue;
      SolTradeStrategySignal signal;ResetSolTradeStrategySignal(signal);signal.evaluated=true;signal.valid=true;signal.signal_bar_time=target;signal.exit_signal=(g_position[i].position_type==POSITION_TYPE_BUY)?SOLTRADE_EXIT_LONG:SOLTRADE_EXIT_SHORT;signal.exit_reason_code="CROSS_SECTIONAL_WEEKLY_REBALANCE";signal.exit_reason="Frozen one-week holding period complete";
      SolTradePositionReport report;g_pm[i].ProcessClose(signal,SOLTRADE_CLOSE_STRATEGY,g_account[i],g_market[i],report);if(report.evaluated){Event(report.event_type,report.reason_code,SYMBOLS[i]+";"+report.reason);RecordExit("EXIT_ATTEMPT",i,report);}g_pm[i].GetStatus(g_position[i]);
     }
  }

void ProcessSchedule(datetime now)
  {
   if(g_next>=g_leg_count)return;datetime target=g_legs[g_next].target;if(now<target)return;
   if(now>=target+5*60){g_missed+=4;g_next+=4;g_close_target=0;Event("REBALANCE_SKIP","ENTRY_WINDOW_MISSED",TS(target));return;}
   if(PortfolioPositions()>0&&g_close_target!=target){g_close_target=target;ClosePortfolio(target);}
   if(PortfolioPositions()>0)return;
   RefreshAll();
   for(int j=0;j<4;j++)AttemptEntry(g_legs[g_next+j]);
   g_next+=4;g_rebalances++;g_close_target=0;
  }

bool WriteDeals()
  {
   HistorySelect(EligibleFrom-7*24*3600,TimeCurrent());int h=FileOpen(OutputRoot+"\\deals.csv",FILE_WRITE|FILE_CSV|FILE_ANSI|FILE_COMMON,',');if(h==INVALID_HANDLE)return false;FileWrite(h,"deal_ticket","order_ticket","position_identifier","time","time_msc","entry","type","reason","volume","price","profit","commission","swap","fee","magic","symbol","comment","in_research_window");
   for(int i=0;i<HistoryDealsTotal();i++){ulong deal=HistoryDealGetTicket(i);if(deal==0)continue;long magic=HistoryDealGetInteger(deal,DEAL_MAGIC);if(magic<=V26_MAGIC_BASE||magic>V26_MAGIC_BASE+7)continue;datetime time=(datetime)HistoryDealGetInteger(deal,DEAL_TIME);FileWrite(h,StringFormat("%I64u",deal),StringFormat("%I64u",(ulong)HistoryDealGetInteger(deal,DEAL_ORDER)),StringFormat("%I64u",(ulong)HistoryDealGetInteger(deal,DEAL_POSITION_ID)),TS(time),StringFormat("%I64d",HistoryDealGetInteger(deal,DEAL_TIME_MSC)),(int)HistoryDealGetInteger(deal,DEAL_ENTRY),(int)HistoryDealGetInteger(deal,DEAL_TYPE),(int)HistoryDealGetInteger(deal,DEAL_REASON),DoubleToString(HistoryDealGetDouble(deal,DEAL_VOLUME),8),DoubleToString(HistoryDealGetDouble(deal,DEAL_PRICE),10),DoubleToString(HistoryDealGetDouble(deal,DEAL_PROFIT),8),DoubleToString(HistoryDealGetDouble(deal,DEAL_COMMISSION),8),DoubleToString(HistoryDealGetDouble(deal,DEAL_SWAP),8),DoubleToString(HistoryDealGetDouble(deal,DEAL_FEE),8),magic,HistoryDealGetString(deal,DEAL_SYMBOL),HistoryDealGetString(deal,DEAL_COMMENT),(time>=EligibleFrom&&time<EligibleTo)?"YES":"NO");}FileClose(h);return true;
  }

bool WriteSummary()
  {
   int open=PortfolioPositions();int h=FileOpen(OutputRoot+"\\run-summary.csv",FILE_WRITE|FILE_CSV|FILE_ANSI|FILE_COMMON,',');if(h==INVALID_HANDLE)return false;FileWrite(h,"field","value");FileWrite(h,"schema","SOLTRADE_PHASE6_V26_RUN_SUMMARY_V1");FileWrite(h,"execution_instance_id",ExecutionInstanceId);FileWrite(h,"dataset",DatasetId);FileWrite(h,"execution_layer",ExecutionLayer);FileWrite(h,"schedule_legs",g_leg_count);FileWrite(h,"processed_rebalances",g_rebalances);FileWrite(h,"entry_attempts",g_entry_attempts);FileWrite(h,"entry_fills",g_entry_fills);FileWrite(h,"exit_fills",g_exit_fills);FileWrite(h,"missed_legs",g_missed);FileWrite(h,"spread_blocks",g_spread_blocks);FileWrite(h,"risk_blocks",g_risk_blocks);FileWrite(h,"execution_blocks",g_execution_blocks);FileWrite(h,"open_positions_at_end",open);FileWrite(h,"max_tick",TS(g_max_tick));FileWrite(h,"seal_breach",g_seal_breach?"YES":"NO");bool valid=g_preflight&&!g_seal_breach&&g_leg_count==ExpectedScheduleLegs&&g_next==g_leg_count&&open==0;FileWrite(h,"run_evidence_status",valid?"PASS":"FAIL");FileClose(h);return valid;
  }

int OnInit()
  {
   ArrayResize(g_legs,0);string reason="";if(!Preflight(reason)){Print("SOLTRADE_V26_PREFLIGHT_FAILED | ",reason);return INIT_PARAMETERS_INCORRECT;}
   g_events=FileOpen(OutputRoot+"\\events.csv",FILE_WRITE|FILE_CSV|FILE_ANSI|FILE_COMMON,',');g_transactions=FileOpen(OutputRoot+"\\transactions.csv",FILE_WRITE|FILE_CSV|FILE_ANSI|FILE_COMMON,',');if(g_events==INVALID_HANDLE||g_transactions==INVALID_HANDLE)return INIT_FAILED;FileWrite(g_events,"schema","time","dataset","execution_layer","event_type","reason_code","details");FileWrite(g_transactions,"schema","time","dataset","execution_layer","symbol","record_type","signal_time","direction","requested_price","actual_price","spread_points","slippage_points","volume","initial_risk_amount","stop_loss","order_ticket","deal_ticket","broker_retcode","fill_confirmed","atr_or_exit_reason");
   for(int i=0;i<7;i++){ResetSolTradeMarketSnapshot(g_market[i]);ResetSolTradeExecutionStatus(g_execution[i]);ResetSolTradePositionStatus(g_position[i]);EvaluateSolTradeAccountSafety(g_config[i],g_account[i]);datetime last=0;if(!InitialiseSolTradeMarketData(g_config[i],last,reason)||!g_exec[i].Initialise(g_config[i],g_account[i].account_identifier_hash,reason)||!g_pm[i].Initialise(g_config[i],g_account[i].account_identifier_hash,reason)){Print("SOLTRADE_V26_ENGINE_INIT_FAILED | ",SYMBOLS[i]," | ",reason);return INIT_FAILED;}g_atr[i]=iATR(SYMBOLS[i],PERIOD_D1,14);if(g_atr[i]==INVALID_HANDLE)return INIT_FAILED;}
   if(!g_risk_engine.Initialise(g_config[0],g_account[0].account_identifier_hash,TimeCurrent(),AccountInfoDouble(ACCOUNT_EQUITY),reason)){Print("SOLTRADE_V26_RISK_INIT_FAILED | ",reason);return INIT_FAILED;}ResetSolTradeRiskStatus(g_risk);g_preflight=true;Event("PREFLIGHT_PASSED","NONE","tester_only=YES;optimization=NO;symbols=7");return INIT_SUCCEEDED;
  }

void OnTick(){datetime now=TimeCurrent();if(now>=ResearchCutoff){g_seal_breach=true;return;}if(now>=EligibleTo)return;g_max_tick=now;RefreshAll();ProcessSchedule(now);}
void OnTradeTransaction(const MqlTradeTransaction &t,const MqlTradeRequest &q,const MqlTradeResult &z)
  {
   if(TimeCurrent()>=EligibleTo)return;
   for(int i=0;i<7;i++)
     {
      SolTradeExecutionReport entry;if(g_exec[i].HandleTradeTransaction(t,entry)){Event(entry.event_type,entry.reason_code,SYMBOLS[i]+";deal="+StringFormat("%I64u",entry.deal_ticket));RecordEntry("ENTRY_TRANSACTION",i,0,entry,0);}
      SolTradePositionReport exit;if(g_pm[i].HandleTradeTransaction(t,exit)){if(exit.fill_confirmed)g_exit_fills++;Event(exit.event_type,exit.reason_code,SYMBOLS[i]+";"+exit.exit_reason_code);RecordExit("EXIT_TRANSACTION",i,exit);string reason="";g_risk_engine.RecordClosedOutcome("V26_EXIT_"+StringFormat("%I64u",exit.deal_ticket),exit.final_profit_loss,TimeCurrent(),AccountInfoDouble(ACCOUNT_EQUITY),reason);g_risk_engine.GetStatus(g_risk);}
     }
  }
double OnTester(){bool ok=WriteDeals()&&WriteSummary();if(g_events!=INVALID_HANDLE)FileFlush(g_events);if(g_transactions!=INVALID_HANDLE)FileFlush(g_transactions);Print("SOLTRADE_V26_RUN_RESULT | status=",ok?"PASS":"FAIL"," | dataset=",DatasetId," | layer=",ExecutionLayer," | entries=",g_entry_fills," | exits=",g_exit_fills," | open=",PortfolioPositions());return ok?1.0:0.0;}
void OnDeinit(const int reason){for(int i=0;i<7;i++)if(g_atr[i]!=INVALID_HANDLE)IndicatorRelease(g_atr[i]);if(g_events!=INVALID_HANDLE)FileClose(g_events);if(g_transactions!=INVALID_HANDLE)FileClose(g_transactions);}
