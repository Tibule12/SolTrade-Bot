#property strict
#property version "1.100"
#property description "V31A research-only symbol compatibility adapter for frozen V28"

#include <SolTrade/Config.mqh>
#include <SolTrade/AccountGuard.mqh>
#include <SolTrade/MarketData.mqh>
#include <SolTrade/RiskEngine.mqh>
#include <SolTrade/StrategyBreakout.mqh>
#include <SolTrade/ExecutionEngine.mqh>
#include <SolTrade/PositionManager.mqh>

input datetime EligibleFrom=D'2025.01.06 00:00:00';
input datetime EligibleTo=D'2026.01.01 00:00:00';
input datetime ResearchCutoff=D'2026.08.01 00:00:00';
input string DatasetId="V28_2025_DEVELOPMENT";
input string ExecutionLayer="NATIVE_NORMAL_EXECUTION";
input int ExpectedExecutionMode=0;
input int ExpectedScheduleSignals=77;
input string ScheduleFile="SolTrade\\Phase6\\V28Signals\\signal-schedule.csv";
input string ExecutionInstanceId="V31A-2025-NATIVE";
input string OutputRoot="SolTrade\\Phase6\\V31AAdapter\\V31A-2025-NATIVE";

#define V28_MAGIC_BASE 2808202600

string CANONICAL_SYMBOLS[7]={"EURUSD","GBPUSD","AUDUSD","NZDUSD","USDCAD","USDCHF","USDJPY"};
double SWAP_LONG[7]={-9.71,-2.63,-1.83,-2.76,3.49,5.97,9.54};
double SWAP_SHORT[7]={4.50,-1.53,-0.51,0.46,-9.10,-11.60,-18.97};

string ResearchSymbol(const string canonical_symbol)
  {
   if(canonical_symbol=="EURUSD")return "EURUSD.V31";
   if(canonical_symbol=="GBPUSD")return "GBPUSD.V31";
   if(canonical_symbol=="AUDUSD")return "AUDUSD.V31";
   if(canonical_symbol=="NZDUSD")return "NZDUSD.V31";
   if(canonical_symbol=="USDCAD")return "USDCAD.V31";
   if(canonical_symbol=="USDCHF")return "USDCHF.V31";
   if(canonical_symbol=="USDJPY")return "USDJPY.V31";
   return "";
  }

struct V28Signal {datetime target;datetime exit_time;int symbol_index;string direction;string tail;double gap;};
V28Signal g_signals[];
int g_signal_count=0,g_next=0,g_processed=0,g_entry_attempts=0,g_entry_fills=0,g_exit_fills=0,g_missed=0,g_spread_blocks=0,g_risk_blocks=0,g_execution_blocks=0;
datetime g_exit_target[7],g_max_tick=0,g_last_exit_submission_tick=0;
bool g_preflight=false,g_seal_breach=false;
int g_events=INVALID_HANDLE,g_transactions=INVALID_HANDLE,g_atr[7];

SolTradeConfig g_config[7];SolTradeAccountStatus g_account[7];SolTradeMarketSnapshot g_market[7];SolTradeExecutionStatus g_execution[7];SolTradePositionStatus g_position[7];
CSolTradeExecutionEngine g_exec[7];CSolTradePositionManager g_pm[7];CSolTradeRiskEngine g_risk_engine;SolTradeRiskStatus g_risk;

string TS(datetime value){return value>0?TimeToString(value,TIME_DATE|TIME_SECONDS):"NONE";}
int SymbolIndex(string symbol){for(int i=0;i<7;i++)if(CANONICAL_SYMBOLS[i]==symbol)return i;return -1;}
void Event(string type,string reason,string detail="",string canonical="",string resolved=""){if(g_events!=INVALID_HANDLE)FileWrite(g_events,"SOLTRADE_PHASE6_V31A_EVENT_V1",TS(TimeCurrent()),DatasetId,ExecutionLayer,canonical,resolved,type,reason,detail);}

void LoadConfig(int i)
  {
   string resolved=ResearchSymbol(CANONICAL_SYMBOLS[i]);
   g_config[i].strategy_version="FX_DOLLAR_FACTOR_MOMENTUM_1M_1M_1_0";g_config[i].approved_strategy_version="";g_config[i].risk_profile="CONSERVATIVE_V1";g_config[i].approved_risk_profile="";g_config[i].magic_number=V28_MAGIC_BASE+i+1;g_config[i].symbol=resolved;g_config[i].timeframe=PERIOD_H1;g_config[i].minimum_history_bars=300;g_config[i].max_tick_age_seconds=120;g_config[i].max_spread_points=30;g_config[i].max_spread_atr_percent=99.0;g_config[i].max_slippage_points=10;g_config[i].risk_per_trade_percent=.5;g_config[i].daily_loss_limit_percent=1.0;g_config[i].weekly_loss_limit_percent=2.5;g_config[i].emergency_drawdown_percent=5.0;g_config[i].production_baseline_equity=0;g_config[i].consecutive_loss_limit=3;g_config[i].reset_emergency_lock=false;g_config[i].expected_environment=SOLTRADE_ENV_BACKTEST;g_config[i].enable_demo_execution=false;g_config[i].enable_position_management=false;g_config[i].approved_demo_account=0;g_config[i].allow_live_trading=false;g_config[i].approved_live_account=0;g_config[i].emergency_stop=false;g_config[i].enable_backtest_research=true;g_config[i].enable_backtest_execution=true;g_config[i].enable_backtest_position_management=true;g_config[i].research_manifest_id="PHASE6-V28-DOLLAR-FACTOR-MOMENTUM";g_config[i].execution_instance_id=ExecutionInstanceId+"-"+CANONICAL_SYMBOLS[i];g_config[i].research_dataset=SOLTRADE_DATASET_DEVELOPMENT;g_config[i].research_cost_profile=SOLTRADE_COST_NORMAL;g_config[i].research_start_inclusive=EligibleFrom;g_config[i].research_end_exclusive=EligibleTo;g_config[i].research_history_fingerprint="cc0a379aa8aa54dde6079c63d0d4eda97abcc929ed7a6bf0dec1404c64b4ea21";g_config[i].research_latency_fingerprint="e301e77895e8f095d485b00bd1b5da9f10f07d6c8b6ae9162048a7643ddf4dfe";g_config[i].research_latency_sample_count=30;g_config[i].research_frozen_delay_ms=200;g_config[i].research_source_commit="200db5a2c9200723ba01c43622dbb65a47b4c083";g_config[i].research_build_fingerprint="b046bb957b715b533cfa1f05d21a8191a814ecd774fbbbf4849a8048294b64f7";g_config[i].research_expected_terminal_build=6090;g_config[i].research_expected_broker_server="FPMarketsSC-Demo";g_config[i].research_expected_initial_deposit=10000;g_config[i].research_expected_deposit_currency="USD";g_config[i].research_expected_leverage=30;g_config[i].research_expected_trading_input_hash="b046bb957b715b533cfa1f05d21a8191a814ecd774fbbbf4849a8048294b64f7";g_config[i].research_state_root="SolTradeBot\\phase6-v31a-state\\"+ExecutionInstanceId+"\\"+CANONICAL_SYMBOLS[i];g_config[i].research_artifact_root="SolTradeBot\\phase6-v31a-artifacts\\"+ExecutionInstanceId+"\\"+CANONICAL_SYMBOLS[i];g_config[i].enable_csv_journal=true;g_config[i].journal_directory="SolTradeBot\\phase6-v31a-journal\\"+ExecutionInstanceId+"\\"+CANONICAL_SYMBOLS[i];g_config[i].risk_state_directory="SolTradeBot\\phase6-v31a-risk\\"+ExecutionInstanceId;g_config[i].execution_state_directory=g_config[i].research_state_root;g_config[i].enable_dashboard=false;g_config[i].dashboard_refresh_seconds=1;
  }

bool LoadSchedule(string &reason)
  {
   int h=FileOpen(ScheduleFile,FILE_READ|FILE_CSV|FILE_ANSI|FILE_COMMON,',');if(h==INVALID_HANDLE){reason="SCHEDULE_OPEN_FAILED";return false;}
   for(int i=0;i<13;i++)FileReadString(h);
   while(!FileIsEnding(h))
     {
      string schema=FileReadString(h);if(schema=="")break;string dataset=FileReadString(h);datetime target=StringToTime(FileReadString(h));string symbol=FileReadString(h);FileReadString(h);double factor=StringToDouble(FileReadString(h));string side=FileReadString(h),direction=FileReadString(h);FileReadString(h);FileReadString(h);FileReadString(h);FileReadString(h);datetime exit_time=StringToTime(FileReadString(h));
      if(dataset!=DatasetId||(direction!="BUY"&&direction!="SELL"))continue;int index=SymbolIndex(symbol);if(index<0){FileClose(h);reason="UNKNOWN_SCHEDULE_SYMBOL";return false;}int n=ArraySize(g_signals);ArrayResize(g_signals,n+1,128);g_signals[n].target=target;g_signals[n].exit_time=exit_time;g_signals[n].symbol_index=index;g_signals[n].tail=side;g_signals[n].gap=factor;g_signals[n].direction=direction;
     }
   FileClose(h);g_signal_count=ArraySize(g_signals);if(g_signal_count!=ExpectedScheduleSignals){reason="SCHEDULE_COUNT_MISMATCH";return false;}return true;
  }

bool Preflight(string &reason)
  {
   reason="";if(!MQLInfoInteger(MQL_TESTER)||MQLInfoInteger(MQL_OPTIMIZATION)){reason="TESTER_ONLY_OPTIMIZATION_PROHIBITED";return false;}
   if(_Symbol!=ResearchSymbol("EURUSD")||_Period!=PERIOD_H1||AccountInfoString(ACCOUNT_SERVER)!="FPMarketsSC-Demo"||(int)TerminalInfoInteger(TERMINAL_BUILD)!=6090||AccountInfoString(ACCOUNT_CURRENCY)!="USD"||(int)AccountInfoInteger(ACCOUNT_LEVERAGE)!=30||MathAbs(AccountInfoDouble(ACCOUNT_BALANCE)-10000)>0.01){reason="FROZEN_ENVIRONMENT_DIFFERS";return false;}
   if(EligibleFrom<=0||EligibleTo<=EligibleFrom||EligibleTo>ResearchCutoff||ResearchCutoff!=D'2026.08.01 00:00:00'||(ExpectedExecutionMode==0&&ExecutionLayer!="NATIVE_NORMAL_EXECUTION")||(ExpectedExecutionMode==200&&ExecutionLayer!="FIXED_DELAY_200_MS")){reason="FROZEN_BOUNDARY_OR_AXIS_INVALID";return false;}
   if(FileIsExist(OutputRoot+"\\run-summary.csv",FILE_COMMON)){reason="OUTPUT_COLLISION";return false;}
   for(int i=0;i<7;i++)
     {
      string resolved=ResearchSymbol(CANONICAL_SYMBOLS[i]);if(resolved==""||!SymbolSelect(resolved,true)){reason="SYMBOL_SELECT_FAILED";return false;}
      if(MathAbs(SymbolInfoDouble(resolved,SYMBOL_SWAP_LONG)-SWAP_LONG[i])>1e-8||MathAbs(SymbolInfoDouble(resolved,SYMBOL_SWAP_SHORT)-SWAP_SHORT[i])>1e-8||(int)SymbolInfoInteger(resolved,SYMBOL_SWAP_MODE)!=1||(int)SymbolInfoInteger(resolved,SYMBOL_SWAP_ROLLOVER3DAYS)!=3){reason="FROZEN_SYMBOL_SPEC_DIFFERS_"+CANONICAL_SYMBOLS[i];return false;}
      LoadConfig(i);string actual=g_config[i].symbol;if(i>0)g_config[i].symbol=ResearchSymbol("EURUSD");bool valid=ValidateSolTradeConfig(g_config[i],reason);g_config[i].symbol=actual;if(!valid)return false;
     }
   return LoadSchedule(reason);
  }

int PortfolioPositions(){int count=0;for(int p=0;p<PositionsTotal();p++){ulong ticket=PositionGetTicket(p);if(ticket==0)continue;long magic=PositionGetInteger(POSITION_MAGIC);if(magic>V28_MAGIC_BASE&&magic<=V28_MAGIC_BASE+7)count++;}return count;}
void RefreshAll(){string reason="";g_risk_engine.Refresh(TimeCurrent(),AccountInfoDouble(ACCOUNT_EQUITY),reason);g_risk_engine.GetStatus(g_risk);for(int i=0;i<7;i++){EvaluateSolTradeAccountSafety(g_config[i],g_account[i]);RefreshSolTradeMarketData(g_config[i],g_market[i]);g_exec[i].RefreshExposure();g_exec[i].GetStatus(g_execution[i]);g_pm[i].Refresh(reason);g_pm[i].GetStatus(g_position[i]);}}
bool ATR(int i,double &value){double values[1];if(CopyBuffer(g_atr[i],0,1,1,values)!=1||values[0]<=0)return false;value=values[0];return true;}

void RecordEntry(string record_type,int i,datetime target,datetime exit_time,SolTradeExecutionReport &r,double atr)
  {if(g_transactions!=INVALID_HANDLE)FileWrite(g_transactions,"SOLTRADE_PHASE6_V31A_TRANSACTION_V1",TS(TimeCurrent()),DatasetId,ExecutionLayer,CANONICAL_SYMBOLS[i],ResearchSymbol(CANONICAL_SYMBOLS[i]),record_type,TS(target),TS(exit_time),r.signal_result,DoubleToString(r.requested_entry,10),DoubleToString(r.actual_entry,10),r.spread_points,DoubleToString(r.slippage_points,4),DoubleToString(r.volume,8),DoubleToString(r.risk_amount,8),DoubleToString(r.stop_loss,10),StringFormat("%I64u",r.order_ticket),StringFormat("%I64u",r.deal_ticket),(int)r.broker_return_code,r.fill_confirmed?"YES":"NO",DoubleToString(atr,12));}
void RecordExit(string record_type,int i,SolTradePositionReport &r)
  {if(g_transactions!=INVALID_HANDLE)FileWrite(g_transactions,"SOLTRADE_PHASE6_V31A_TRANSACTION_V1",TS(TimeCurrent()),DatasetId,ExecutionLayer,CANONICAL_SYMBOLS[i],ResearchSymbol(CANONICAL_SYMBOLS[i]),record_type,TS(r.signal_bar_time),TS(g_exit_target[i]),r.position_direction,DoubleToString(r.requested_close_price,10),DoubleToString(r.actual_close_price,10),0,DoubleToString(r.slippage_points,4),DoubleToString(r.volume,8),0,0,StringFormat("%I64u",r.order_ticket),StringFormat("%I64u",r.deal_ticket),(int)r.broker_return_code,r.fill_confirmed?"YES":"NO",r.exit_reason_code);}

void AttemptEntry(V28Signal &item)
  {
   int i=item.symbol_index;double atr=0;if(!ATR(i,atr)){g_execution_blocks++;Event("ENTRY_BLOCK","ATR_UNAVAILABLE","",CANONICAL_SYMBOLS[i],ResearchSymbol(CANONICAL_SYMBOLS[i]));return;}
   SolTradeStrategySignal signal;ResetSolTradeStrategySignal(signal);signal.evaluated=true;signal.valid=true;signal.entry_signal=(item.direction=="BUY")?SOLTRADE_SIGNAL_BUY:SOLTRADE_SIGNAL_SELL;signal.signal_bar_time=item.target;signal.signal_close=(item.direction=="BUY")?g_market[i].ask:g_market[i].bid;signal.signal_high=signal.signal_close;signal.signal_low=signal.signal_close;signal.signal_open=signal.signal_close;signal.atr_14=atr;signal.initial_stop_distance=3.0*atr;signal.entry_reason_code="DOLLAR_FACTOR_MOMENTUM";signal.entry_reason=item.tail+";factor_return="+DoubleToString(item.gap,12);
   SolTradeExecutionReport report;g_entry_attempts++;g_exec[i].ProcessSignal(signal,g_account[i],g_market[i],g_risk,false,report);if(report.evaluated){if(report.broker_accepted&&report.deal_ticket!=0){g_entry_fills++;g_exit_target[i]=item.exit_time;}else if(report.reason_code=="RISK_ENGINE_LOCKED")g_risk_blocks++;else if(report.reason_code=="SPREAD_REJECTED"||report.reason_code=="EXCESSIVE_SPREAD"||report.reason_code=="SPREAD_EXCEEDS_LIMIT")g_spread_blocks++;else g_execution_blocks++;Event(report.event_type,report.reason_code,report.reason,CANONICAL_SYMBOLS[i],ResearchSymbol(CANONICAL_SYMBOLS[i]));RecordEntry("ENTRY_ATTEMPT",i,item.target,item.exit_time,report,atr);}g_exec[i].GetStatus(g_execution[i]);
  }

void ProcessEntries(datetime now)
  {
   if(g_next>=g_signal_count)return;datetime target=g_signals[g_next].target;if(now<target)return;int end=g_next+1;while(end<g_signal_count&&g_signals[end].target==target)end++;
   if(g_last_exit_submission_tick==now)return;
   if(now>=target+5*60){g_missed+=end-g_next;g_processed+=end-g_next;g_next=end;Event("ENTRY_GROUP_SKIP","ENTRY_WINDOW_MISSED",TS(target));return;}
   RefreshAll();for(int i=g_next;i<end;i++){AttemptEntry(g_signals[i]);g_processed++;}g_next=end;
  }

void ProcessExits(datetime now)
  {
   bool due=false;for(int i=0;i<7;i++)if(g_exit_target[i]>0&&now>=g_exit_target[i]){due=true;break;}if(!due)return;RefreshAll();
   for(int i=0;i<7;i++)
     {
      if(g_exit_target[i]<=0||now<g_exit_target[i])continue;if(!g_position[i].position_present){g_exit_target[i]=0;continue;}
      SolTradeStrategySignal signal;ResetSolTradeStrategySignal(signal);signal.evaluated=true;signal.valid=true;signal.signal_bar_time=g_exit_target[i];signal.exit_signal=(g_position[i].position_type==POSITION_TYPE_BUY)?SOLTRADE_EXIT_LONG:SOLTRADE_EXIT_SHORT;signal.exit_reason_code="DOLLAR_FACTOR_REBALANCE";signal.exit_reason="Frozen next-month factor rebalance exit";
      SolTradePositionReport report;g_pm[i].ProcessClose(signal,SOLTRADE_CLOSE_STRATEGY,g_account[i],g_market[i],report);if(report.evaluated){if(report.broker_accepted)g_last_exit_submission_tick=now;Event(report.event_type,report.reason_code,report.reason,CANONICAL_SYMBOLS[i],ResearchSymbol(CANONICAL_SYMBOLS[i]));RecordExit("EXIT_ATTEMPT",i,report);}g_pm[i].GetStatus(g_position[i]);
     }
  }

bool WriteDeals()
  {
   HistorySelect(EligibleFrom-7*24*3600,TimeCurrent());int h=FileOpen(OutputRoot+"\\deals.csv",FILE_WRITE|FILE_CSV|FILE_ANSI|FILE_COMMON,',');if(h==INVALID_HANDLE)return false;FileWrite(h,"deal_ticket","order_ticket","position_identifier","time","time_msc","entry","type","reason","volume","price","profit","commission","swap","fee","magic","canonical_symbol","research_symbol","comment","in_research_window");
   for(int i=0;i<HistoryDealsTotal();i++){ulong deal=HistoryDealGetTicket(i);if(deal==0)continue;long magic=HistoryDealGetInteger(deal,DEAL_MAGIC);if(magic<=V28_MAGIC_BASE||magic>V28_MAGIC_BASE+7)continue;datetime time=(datetime)HistoryDealGetInteger(deal,DEAL_TIME);string resolved=HistoryDealGetString(deal,DEAL_SYMBOL);int index=(int)(magic-V28_MAGIC_BASE-1);string canonical=(index>=0&&index<7)?CANONICAL_SYMBOLS[index]:"UNKNOWN";FileWrite(h,StringFormat("%I64u",deal),StringFormat("%I64u",(ulong)HistoryDealGetInteger(deal,DEAL_ORDER)),StringFormat("%I64u",(ulong)HistoryDealGetInteger(deal,DEAL_POSITION_ID)),TS(time),StringFormat("%I64d",HistoryDealGetInteger(deal,DEAL_TIME_MSC)),(int)HistoryDealGetInteger(deal,DEAL_ENTRY),(int)HistoryDealGetInteger(deal,DEAL_TYPE),(int)HistoryDealGetInteger(deal,DEAL_REASON),DoubleToString(HistoryDealGetDouble(deal,DEAL_VOLUME),8),DoubleToString(HistoryDealGetDouble(deal,DEAL_PRICE),10),DoubleToString(HistoryDealGetDouble(deal,DEAL_PROFIT),8),DoubleToString(HistoryDealGetDouble(deal,DEAL_COMMISSION),8),DoubleToString(HistoryDealGetDouble(deal,DEAL_SWAP),8),DoubleToString(HistoryDealGetDouble(deal,DEAL_FEE),8),magic,canonical,resolved,HistoryDealGetString(deal,DEAL_COMMENT),(time>=EligibleFrom&&time<EligibleTo)?"YES":"NO");}FileClose(h);return true;
  }

bool WriteSummary()
  {
   int open=PortfolioPositions();int h=FileOpen(OutputRoot+"\\run-summary.csv",FILE_WRITE|FILE_CSV|FILE_ANSI|FILE_COMMON,',');if(h==INVALID_HANDLE)return false;FileWrite(h,"field","value");FileWrite(h,"schema","SOLTRADE_PHASE6_V31A_RUN_SUMMARY_V1");FileWrite(h,"execution_instance_id",ExecutionInstanceId);FileWrite(h,"dataset",DatasetId);FileWrite(h,"execution_layer",ExecutionLayer);for(int i=0;i<7;i++)FileWrite(h,"symbol_mapping_"+CANONICAL_SYMBOLS[i],ResearchSymbol(CANONICAL_SYMBOLS[i]));FileWrite(h,"schedule_signals",g_signal_count);FileWrite(h,"processed_signals",g_processed);FileWrite(h,"entry_attempts",g_entry_attempts);FileWrite(h,"entry_fills",g_entry_fills);FileWrite(h,"exit_fills",g_exit_fills);FileWrite(h,"missed_signals",g_missed);FileWrite(h,"spread_blocks",g_spread_blocks);FileWrite(h,"risk_blocks",g_risk_blocks);FileWrite(h,"execution_blocks",g_execution_blocks);FileWrite(h,"open_positions_at_end",open);FileWrite(h,"max_tick",TS(g_max_tick));FileWrite(h,"seal_breach",g_seal_breach?"YES":"NO");bool valid=g_preflight&&!g_seal_breach&&g_signal_count==ExpectedScheduleSignals&&g_processed==g_signal_count&&open==0;FileWrite(h,"run_evidence_status",valid?"PASS":"FAIL");FileClose(h);return valid;
  }

int OnInit()
  {
   ArrayResize(g_signals,0);string reason="";if(!Preflight(reason)){Print("SOLTRADE_V31A_PREFLIGHT_FAILED | ",reason);return INIT_PARAMETERS_INCORRECT;}
   g_events=FileOpen(OutputRoot+"\\events.csv",FILE_WRITE|FILE_CSV|FILE_ANSI|FILE_COMMON,',');g_transactions=FileOpen(OutputRoot+"\\transactions.csv",FILE_WRITE|FILE_CSV|FILE_ANSI|FILE_COMMON,',');if(g_events==INVALID_HANDLE||g_transactions==INVALID_HANDLE)return INIT_FAILED;FileWrite(g_events,"schema","time","dataset","execution_layer","canonical_symbol","research_symbol","event_type","reason_code","details");FileWrite(g_transactions,"schema","time","dataset","execution_layer","canonical_symbol","research_symbol","record_type","signal_time","scheduled_exit","direction","requested_price","actual_price","spread_points","slippage_points","volume","initial_risk_amount","stop_loss","order_ticket","deal_ticket","broker_retcode","fill_confirmed","atr_or_exit_reason");
   for(int i=0;i<7;i++){g_exit_target[i]=0;g_atr[i]=INVALID_HANDLE;ResetSolTradeMarketSnapshot(g_market[i]);ResetSolTradeExecutionStatus(g_execution[i]);ResetSolTradePositionStatus(g_position[i]);EvaluateSolTradeAccountSafety(g_config[i],g_account[i]);datetime last=0;if(!InitialiseSolTradeMarketData(g_config[i],last,reason)||!g_exec[i].Initialise(g_config[i],g_account[i].account_identifier_hash,reason)||!g_pm[i].Initialise(g_config[i],g_account[i].account_identifier_hash,reason)){Print("SOLTRADE_V31A_ENGINE_INIT_FAILED | ",CANONICAL_SYMBOLS[i]," | ",ResearchSymbol(CANONICAL_SYMBOLS[i])," | ",reason);return INIT_FAILED;}g_atr[i]=iATR(ResearchSymbol(CANONICAL_SYMBOLS[i]),PERIOD_D1,14);if(g_atr[i]==INVALID_HANDLE)return INIT_FAILED;}
   if(!g_risk_engine.Initialise(g_config[0],g_account[0].account_identifier_hash,TimeCurrent(),AccountInfoDouble(ACCOUNT_EQUITY),reason)){Print("SOLTRADE_V31A_RISK_INIT_FAILED | ",reason);return INIT_FAILED;}ResetSolTradeRiskStatus(g_risk);g_preflight=true;Event("PREFLIGHT_PASSED","NONE","tester_only=YES;optimization=NO;symbols=7");return INIT_SUCCEEDED;
  }

void OnTick(){datetime now=TimeCurrent();if(now>=ResearchCutoff){g_seal_breach=true;return;}if(now>=EligibleTo)return;g_max_tick=now;ProcessExits(now);ProcessEntries(now);}
void OnTradeTransaction(const MqlTradeTransaction &t,const MqlTradeRequest &q,const MqlTradeResult &z)
  {
   if(TimeCurrent()>=EligibleTo)return;for(int i=0;i<7;i++)
     {
      SolTradeExecutionReport entry;if(g_exec[i].HandleTradeTransaction(t,entry)){Event(entry.event_type,entry.reason_code,"deal="+StringFormat("%I64u",entry.deal_ticket),CANONICAL_SYMBOLS[i],ResearchSymbol(CANONICAL_SYMBOLS[i]));RecordEntry("ENTRY_TRANSACTION",i,0,g_exit_target[i],entry,0);}
      SolTradePositionReport exit;if(g_pm[i].HandleTradeTransaction(t,exit)){if(exit.fill_confirmed){g_exit_fills++;g_exit_target[i]=0;}Event(exit.event_type,exit.reason_code,exit.exit_reason_code,CANONICAL_SYMBOLS[i],ResearchSymbol(CANONICAL_SYMBOLS[i]));RecordExit("EXIT_TRANSACTION",i,exit);string reason="";g_risk_engine.RecordClosedOutcome("V28_EXIT_"+StringFormat("%I64u",exit.deal_ticket),exit.final_profit_loss,TimeCurrent(),AccountInfoDouble(ACCOUNT_EQUITY),reason);g_risk_engine.GetStatus(g_risk);}
     }
  }
double OnTester(){bool ok=WriteDeals()&&WriteSummary();if(g_events!=INVALID_HANDLE)FileFlush(g_events);if(g_transactions!=INVALID_HANDLE)FileFlush(g_transactions);Print("SOLTRADE_V31A_RUN_RESULT | status=",ok?"PASS":"FAIL"," | dataset=",DatasetId," | layer=",ExecutionLayer," | entries=",g_entry_fills," | exits=",g_exit_fills," | open=",PortfolioPositions());return ok?1.0:0.0;}
void OnDeinit(const int reason){for(int i=0;i<7;i++)if(g_atr[i]!=INVALID_HANDLE)IndicatorRelease(g_atr[i]);if(g_events!=INVALID_HANDLE)FileClose(g_events);if(g_transactions!=INVALID_HANDLE)FileClose(g_transactions);}
