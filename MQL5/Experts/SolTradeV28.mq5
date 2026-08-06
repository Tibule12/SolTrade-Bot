#property strict
#property version   "28.100"
#property description "Production adapter for frozen V28 monthly seven-pair USD-factor momentum"

#include <SolTrade/Config.mqh>
#include <SolTrade/AccountGuard.mqh>
#include <SolTrade/MarketData.mqh>
#include <SolTrade/RiskEngine.mqh>
#include <SolTrade/StrategyBreakout.mqh>
#include <SolTrade/ExecutionEngine.mqh>
#include <SolTrade/PositionManager.mqh>

input group "FXIFY deployment lock"
input long   ApprovedAccount=0;
input string ApprovedServer="FXIFY-Server";
input double ProductionBaselineEquity=10000.0;
input bool   DryRunMode=true;

input group "Broker symbol mapping"
input string SymbolSuffix=".r";
input string EURUSDSymbol="";
input string GBPUSDSymbol="";
input string AUDUSDSymbol="";
input string NZDUSDSymbol="";
input string USDCADSymbol="";
input string USDCHFSymbol="";
input string USDJPYSymbol="";

input group "Frozen V28 equivalence harness"
input bool     EquivalenceMode=false;
input datetime EligibleFrom=D'2025.01.06 00:00:00';
input datetime EligibleTo=D'2026.01.01 00:00:00';
input datetime ResearchCutoff=D'2026.08.01 00:00:00';
input string   DatasetId="V28_2025_DEVELOPMENT";
input string   ExecutionLayer="NATIVE_NORMAL_EXECUTION";
input int      ExpectedExecutionMode=0;
input int      ExpectedScheduleSignals=77;
input string   ExecutionInstanceId="SOLTRADEV28-EQUIVALENCE";
input string   OutputRoot="SolTrade\\V28Equivalence\\SOLTRADEV28-EQUIVALENCE";

#define V28_MAGIC_BASE                 2808202600
#define V28_LEGS                       7
#define V28_ALL_LEGS_MASK              127
#define V28_RISK_PER_LEG_PERCENT       0.5
#define V28_DAILY_LOSS_LIMIT_PERCENT   1.0
#define V28_WEEKLY_LOSS_LIMIT_PERCENT  2.5
#define V28_EMERGENCY_DRAWDOWN_PERCENT 5.0
#define V28_CONSECUTIVE_LOSS_LIMIT     3
#define V28_ATR_MULTIPLIER             3.0
#define V28_MAX_SPREAD_POINTS          30
#define V28_MAX_SLIPPAGE_POINTS        10
#define V28_STATE_SCHEMA               "SOLTRADE_V28_COHORT_STATE_V1"

string CANONICAL[V28_LEGS]={"EURUSD","GBPUSD","AUDUSD","NZDUSD","USDCAD","USDCHF","USDJPY"};
int ORIENTATION[V28_LEGS]={1,1,1,1,-1,-1,-1};
double FROZEN_SWAP_LONG[V28_LEGS]={-9.71,-2.63,-1.83,-2.76,3.49,5.97,9.54};
double FROZEN_SWAP_SHORT[V28_LEGS]={4.50,-1.53,-0.51,0.46,-9.10,-11.60,-18.97};
string g_symbols[V28_LEGS];

SolTradeConfig g_config[V28_LEGS];
SolTradeAccountStatus g_account[V28_LEGS];
SolTradeMarketSnapshot g_market[V28_LEGS];
SolTradeExecutionStatus g_execution[V28_LEGS];
SolTradePositionStatus g_position[V28_LEGS];
CSolTradeExecutionEngine g_exec[V28_LEGS];
CSolTradePositionManager g_pm[V28_LEGS];
CSolTradeRiskEngine g_risk_engine;
SolTradeRiskStatus g_risk;

int g_atr[V28_LEGS];
datetime g_exit_target[V28_LEGS];
datetime g_last_exit_submission_tick=0;
datetime g_max_tick=0;
int g_events=INVALID_HANDLE;
int g_transactions=INVALID_HANDLE;
int g_signals_file=INVALID_HANDLE;
int g_signal_count=0;
int g_processed=0;
int g_entry_attempts=0;
int g_entry_fills=0;
int g_exit_fills=0;
int g_missed=0;
int g_spread_blocks=0;
int g_risk_blocks=0;
int g_execution_blocks=0;
int g_month_key=0;
int g_live_state_month=0;
int g_live_state_mask=0;
string g_live_state_path="";
bool g_preflight=false;
bool g_seal_breach=false;
bool g_live_state_valid=false;

string TS(const datetime value)
  {
   return value>0?TimeToString(value,TIME_DATE|TIME_SECONDS):"NONE";
  }

int MonthKey(const datetime value)
  {
   MqlDateTime d;
   TimeToStruct(value,d);
   return d.year*100+d.mon;
  }

datetime FirstMonday(const int year,const int month)
  {
   MqlDateTime d;
   ZeroMemory(d);
   d.year=year;
   d.mon=month;
   d.day=1;
   datetime value=StructToTime(d);
   TimeToStruct(value,d);
   return value+((8-d.day_of_week)%7)*24*3600;
  }

datetime PreviousFirstMonday(const datetime current)
  {
   MqlDateTime d;
   TimeToStruct(current,d);
   int year=d.year;
   int month=d.mon-1;
   if(month==0)
     {
      month=12;
      year--;
     }
   return FirstMonday(year,month);
  }

datetime NextFirstMonday(const datetime current)
  {
   MqlDateTime d;
   TimeToStruct(current,d);
   int year=d.year;
   int month=d.mon+1;
   if(month==13)
     {
      month=1;
      year++;
     }
   return FirstMonday(year,month);
  }

string ResolveSymbol(const int index)
  {
   string explicit_symbols[V28_LEGS];
   explicit_symbols[0]=EURUSDSymbol;
   explicit_symbols[1]=GBPUSDSymbol;
   explicit_symbols[2]=AUDUSDSymbol;
   explicit_symbols[3]=NZDUSDSymbol;
   explicit_symbols[4]=USDCADSymbol;
   explicit_symbols[5]=USDCHFSymbol;
   explicit_symbols[6]=USDJPYSymbol;
   return StringLen(explicit_symbols[index])>0
          ?explicit_symbols[index]
          :CANONICAL[index]+SymbolSuffix;
  }

string StateChecksum(const string payload)
  {
   uint hash=2166136261;
   for(int i=0;i<StringLen(payload);i++)
     {
      hash^=(uint)StringGetCharacter(payload,i);
      hash=(uint)(hash*(uint)16777619);
     }
   return StringFormat("%08lX",hash);
  }

void Event(const string type,const string reason,const string detail="",const int index=-1)
  {
   string canonical=index>=0&&index<V28_LEGS?CANONICAL[index]:"";
   string resolved=index>=0&&index<V28_LEGS?g_symbols[index]:"";
   Print("SOLTRADE_V28 | ",type," | ",reason,
         StringLen(canonical)>0?" | "+canonical+"="+resolved:"",
         StringLen(detail)>0?" | "+detail:"");
   if(g_events!=INVALID_HANDLE)
     {
      FileWrite(g_events,"SOLTRADE_V28_EVENT_V1",TS(TimeCurrent()),DatasetId,
                ExecutionLayer,canonical,resolved,type,reason,detail,
                DryRunMode?"YES":"NO");
      FileFlush(g_events);
     }
  }

bool OpenOutputFiles(string &reason)
  {
   int flags=FILE_READ|FILE_WRITE|FILE_CSV|FILE_ANSI;
   if(EquivalenceMode)
      flags|=FILE_COMMON;
   g_events=FileOpen(OutputRoot+"\\events.csv",flags,',');
   g_transactions=FileOpen(OutputRoot+"\\transactions.csv",flags,',');
   g_signals_file=FileOpen(OutputRoot+"\\signals.csv",flags,',');
   if(g_events==INVALID_HANDLE||g_transactions==INVALID_HANDLE||g_signals_file==INVALID_HANDLE)
     {
      reason="OUTPUT_OPEN_FAILED_"+IntegerToString(GetLastError());
      return false;
     }
   if(FileSize(g_events)==0)
      FileWrite(g_events,"schema","time","dataset","execution_layer","canonical_symbol","resolved_symbol","event_type","reason_code","details","dry_run");
   else
      FileSeek(g_events,0,SEEK_END);
   if(FileSize(g_transactions)==0)
      FileWrite(g_transactions,"schema","time","dataset","execution_layer","canonical_symbol","resolved_symbol","record_type","signal_time","scheduled_exit","direction","requested_price","actual_price","spread_points","slippage_points","volume","initial_risk_amount","stop_loss","order_ticket","deal_ticket","broker_retcode","fill_confirmed","atr_or_exit_reason");
   else
      FileSeek(g_transactions,0,SEEK_END);
   if(FileSize(g_signals_file)==0)
      FileWrite(g_signals_file,"schema","dataset","target","canonical_symbol","resolved_symbol","orientation","dollar_factor_return","factor_side","direction","recent_h1","recent_close","anchor_h1","anchor_close","scheduled_exit");
   else
      FileSeek(g_signals_file,0,SEEK_END);
   return true;
  }

bool LoadLiveState(string &reason)
  {
   reason="";
   g_live_state_valid=false;
   g_live_state_month=0;
   g_live_state_mask=0;
   g_live_state_path="SolTradeV28\\state_"+
                     IntegerToString(AccountInfoInteger(ACCOUNT_LOGIN))+"_"+
                     StringFormat("%I64u",(ulong)V28_MAGIC_BASE)+".csv";
   if(!FileIsExist(g_live_state_path))
     {
      g_live_state_valid=true;
      return true;
     }
   int handle=FileOpen(g_live_state_path,FILE_READ|FILE_CSV|FILE_ANSI,',');
   if(handle==INVALID_HANDLE)
     {
      reason="COHORT_STATE_OPEN_FAILED";
      return false;
     }
   string schema=FileReadString(handle);
   string account=FileReadString(handle);
   string magic=FileReadString(handle);
   string month=FileReadString(handle);
   string mask=FileReadString(handle);
   string checksum=FileReadString(handle);
   FileClose(handle);
   string payload=schema+"|"+account+"|"+magic+"|"+month+"|"+mask;
   if(schema!=V28_STATE_SCHEMA||
      StringToInteger(account)!=AccountInfoInteger(ACCOUNT_LOGIN)||
      StringToInteger(magic)!=(long)V28_MAGIC_BASE||
      checksum!=StateChecksum(payload))
     {
      reason="COHORT_STATE_INVALID";
      return false;
     }
   g_live_state_month=(int)StringToInteger(month);
   g_live_state_mask=(int)StringToInteger(mask);
   if(g_live_state_month<0||g_live_state_mask<0||g_live_state_mask>V28_ALL_LEGS_MASK)
     {
      reason="COHORT_STATE_VALUES_INVALID";
      return false;
     }
   if(g_live_state_month>MonthKey(TimeCurrent()))
     {
      reason="COHORT_STATE_DATED_IN_FUTURE";
      return false;
     }
   g_live_state_valid=true;
   return true;
  }

bool SaveLiveState(const int month,const int mask,string &reason)
  {
   reason="";
   if(EquivalenceMode)
      return true;
   string temporary=g_live_state_path+".tmp";
   FileDelete(temporary);
   int handle=FileOpen(temporary,FILE_WRITE|FILE_CSV|FILE_ANSI,',');
   if(handle==INVALID_HANDLE)
     {
      reason="COHORT_STATE_TEMP_OPEN_FAILED";
      return false;
     }
   string account=IntegerToString(AccountInfoInteger(ACCOUNT_LOGIN));
   string magic=StringFormat("%I64u",(ulong)V28_MAGIC_BASE);
   string month_text=IntegerToString(month);
   string mask_text=IntegerToString(mask);
   string payload=V28_STATE_SCHEMA+"|"+account+"|"+magic+"|"+month_text+"|"+mask_text;
   uint written=FileWrite(handle,V28_STATE_SCHEMA,account,magic,month_text,mask_text,StateChecksum(payload));
   FileFlush(handle);
   FileClose(handle);
   if(written==0||!FileMove(temporary,0,g_live_state_path,FILE_REWRITE))
     {
      reason="COHORT_STATE_REPLACE_FAILED_"+IntegerToString(GetLastError());
      FileDelete(temporary);
      return false;
     }
   g_live_state_month=month;
   g_live_state_mask=mask;
   g_live_state_valid=true;
   return true;
  }

bool ClaimLiveLeg(const int month,const int index,string &reason)
  {
   if(EquivalenceMode)
      return true;
   if(!g_live_state_valid)
     {
      reason="COHORT_STATE_NOT_VALID";
      return false;
     }
   int mask=(g_live_state_month==month)?g_live_state_mask:0;
   int bit=1<<index;
   if((mask&bit)!=0)
     {
      reason="COHORT_LEG_ALREADY_CONSUMED";
      return false;
     }
   return SaveLiveState(month,mask|bit,reason);
  }

void LoadConfig(const int index)
  {
   SolTradeConfig c;
   c.strategy_version="FX_DOLLAR_FACTOR_MOMENTUM_1M_1M_1_0";
   c.approved_strategy_version=EquivalenceMode?"":"FX_DOLLAR_FACTOR_MOMENTUM_1M_1M_1_0";
   c.risk_profile="CONSERVATIVE_V1";
   c.approved_risk_profile=EquivalenceMode?"":"CONSERVATIVE_V1";
   c.magic_number=V28_MAGIC_BASE+index+1;
   c.symbol=g_symbols[index];
   c.timeframe=PERIOD_H1;
   c.minimum_history_bars=300;
   c.max_tick_age_seconds=120;
   c.max_spread_points=V28_MAX_SPREAD_POINTS;
   c.max_spread_atr_percent=99.0;
   c.max_slippage_points=V28_MAX_SLIPPAGE_POINTS;
   c.risk_per_trade_percent=V28_RISK_PER_LEG_PERCENT;
   c.daily_loss_limit_percent=V28_DAILY_LOSS_LIMIT_PERCENT;
   c.weekly_loss_limit_percent=V28_WEEKLY_LOSS_LIMIT_PERCENT;
   c.emergency_drawdown_percent=V28_EMERGENCY_DRAWDOWN_PERCENT;
   c.production_baseline_equity=EquivalenceMode?0.0:ProductionBaselineEquity;
   c.consecutive_loss_limit=V28_CONSECUTIVE_LOSS_LIMIT;
   c.reset_emergency_lock=false;
   c.expected_environment=EquivalenceMode?SOLTRADE_ENV_BACKTEST:SOLTRADE_ENV_DEMO;
   c.enable_demo_execution=!EquivalenceMode;
   c.enable_position_management=!EquivalenceMode;
   c.approved_demo_account=EquivalenceMode?0:ApprovedAccount;
   c.allow_live_trading=false;
   c.approved_live_account=0;
   c.emergency_stop=false;
   c.enable_backtest_research=EquivalenceMode;
   c.enable_backtest_execution=EquivalenceMode;
   c.enable_backtest_position_management=EquivalenceMode;
   c.research_manifest_id="PHASE6-V28-DOLLAR-FACTOR-MOMENTUM";
   c.execution_instance_id=ExecutionInstanceId+"-"+CANONICAL[index];
   c.research_dataset=SOLTRADE_DATASET_DEVELOPMENT;
   c.research_cost_profile=SOLTRADE_COST_NORMAL;
   c.research_start_inclusive=EligibleFrom;
   c.research_end_exclusive=EligibleTo;
   c.research_history_fingerprint="cc0a379aa8aa54dde6079c63d0d4eda97abcc929ed7a6bf0dec1404c64b4ea21";
   c.research_latency_fingerprint="e301e77895e8f095d485b00bd1b5da9f10f07d6c8b6ae9162048a7643ddf4dfe";
   c.research_latency_sample_count=30;
   c.research_frozen_delay_ms=200;
   c.research_source_commit="200db5a2c9200723ba01c43622dbb65a47b4c083";
   c.research_build_fingerprint="b046bb957b715b533cfa1f05d21a8191a814ecd774fbbbf4849a8048294b64f7";
   c.research_expected_terminal_build=6090;
   c.research_expected_broker_server="FPMarketsSC-Demo";
   c.research_expected_initial_deposit=10000;
   c.research_expected_deposit_currency="USD";
   c.research_expected_leverage=30;
   c.research_expected_trading_input_hash="b046bb957b715b533cfa1f05d21a8191a814ecd774fbbbf4849a8048294b64f7";
   string state_family=EquivalenceMode?"phase6-v28-live-equivalence":"production-v28";
   c.research_state_root="SolTradeBot\\"+state_family+"-state\\"+ExecutionInstanceId+"\\"+CANONICAL[index];
   c.research_artifact_root="SolTradeBot\\"+state_family+"-artifacts\\"+ExecutionInstanceId+"\\"+CANONICAL[index];
   c.enable_csv_journal=true;
   c.journal_directory="SolTradeBot\\"+state_family+"-journal\\"+ExecutionInstanceId+"\\"+CANONICAL[index];
   c.risk_state_directory="SolTradeBot\\"+state_family+"-risk\\"+ExecutionInstanceId;
   c.execution_state_directory=c.research_state_root;
   c.enable_dashboard=false;
   c.dashboard_refresh_seconds=1;
   g_config[index]=c;
  }

bool ValidateSymbolSpecification(const int index,string &reason)
  {
   string symbol=g_symbols[index];
   if(symbol==""||!SymbolSelect(symbol,true)||!(bool)SymbolInfoInteger(symbol,SYMBOL_EXIST))
     {
      reason="SYMBOL_UNAVAILABLE_"+CANONICAL[index]+"_"+symbol;
      return false;
     }
   double point=SymbolInfoDouble(symbol,SYMBOL_POINT);
   double tick_size=SymbolInfoDouble(symbol,SYMBOL_TRADE_TICK_SIZE);
   double tick_value_loss=SymbolInfoDouble(symbol,SYMBOL_TRADE_TICK_VALUE_LOSS);
   double volume_min=SymbolInfoDouble(symbol,SYMBOL_VOLUME_MIN);
   double volume_max=SymbolInfoDouble(symbol,SYMBOL_VOLUME_MAX);
   double volume_step=SymbolInfoDouble(symbol,SYMBOL_VOLUME_STEP);
   long order_mode=SymbolInfoInteger(symbol,SYMBOL_ORDER_MODE);
   long trade_mode=SymbolInfoInteger(symbol,SYMBOL_TRADE_MODE);
   if(point<=0||tick_size<=0||tick_value_loss<=0||volume_min<=0||
      volume_max<volume_min||volume_step<=0||
      trade_mode==SYMBOL_TRADE_MODE_DISABLED||
      (order_mode&SYMBOL_ORDER_MARKET)!=SYMBOL_ORDER_MARKET||
      (order_mode&SYMBOL_ORDER_SL)!=SYMBOL_ORDER_SL)
     {
      reason="SYMBOL_SPEC_INVALID_"+CANONICAL[index]+"_"+symbol;
      return false;
     }
   int volume_digits=MathMax(SolTradeVolumeDigits(volume_min),SolTradeVolumeDigits(volume_step));
   double grid=(volume_max-volume_min)/volume_step;
   if(MathAbs(grid-MathRound(grid))>1e-7||volume_digits>8)
     {
      reason="SYMBOL_VOLUME_GRID_INVALID_"+CANONICAL[index]+"_"+symbol;
      return false;
     }
   if(EquivalenceMode)
     {
      if(MathAbs(SymbolInfoDouble(symbol,SYMBOL_SWAP_LONG)-FROZEN_SWAP_LONG[index])>1e-8||
         MathAbs(SymbolInfoDouble(symbol,SYMBOL_SWAP_SHORT)-FROZEN_SWAP_SHORT[index])>1e-8||
         (int)SymbolInfoInteger(symbol,SYMBOL_SWAP_MODE)!=1||
         (int)SymbolInfoInteger(symbol,SYMBOL_SWAP_ROLLOVER3DAYS)!=3)
        {
         reason="FROZEN_SYMBOL_SPEC_DIFFERS_"+CANONICAL[index];
         return false;
        }
     }
   return true;
  }

bool Preflight(string &reason)
  {
   reason="";
   bool tester=(bool)MQLInfoInteger(MQL_TESTER);
   if((tester&&!EquivalenceMode)||(!tester&&EquivalenceMode)||(bool)MQLInfoInteger(MQL_OPTIMIZATION))
     {
      reason="MODE_OR_OPTIMIZATION_INVALID";
      return false;
     }
   for(int i=0;i<V28_LEGS;i++)
     {
      g_symbols[i]=ResolveSymbol(i);
      if(!ValidateSymbolSpecification(i,reason))
         return false;
      LoadConfig(i);
      string validator_symbol=g_config[i].symbol;
      if(i>0)
         g_config[i].symbol=g_symbols[0];
      bool config_ok=ValidateSolTradeConfig(g_config[i],reason);
      g_config[i].symbol=validator_symbol;
      if(!config_ok)
         return false;
     }
   if(_Symbol!=g_symbols[0]||_Period!=PERIOD_H1)
     {
      reason="ATTACHMENT_MUST_BE_"+g_symbols[0]+"_H1";
      return false;
     }
   if(AccountInfoString(ACCOUNT_CURRENCY)!="USD"||
      AccountInfoDouble(ACCOUNT_BALANCE)<=0||AccountInfoDouble(ACCOUNT_EQUITY)<=0||
      AccountInfoInteger(ACCOUNT_MARGIN_MODE)!=ACCOUNT_MARGIN_MODE_RETAIL_HEDGING)
     {
      reason="ACCOUNT_SPEC_INVALID";
      return false;
     }
   if(EquivalenceMode)
     {
      if(DryRunMode||AccountInfoString(ACCOUNT_SERVER)!="FPMarketsSC-Demo"||
         (int)TerminalInfoInteger(TERMINAL_BUILD)!=6090||
         (int)AccountInfoInteger(ACCOUNT_LEVERAGE)!=30||
         MathAbs(AccountInfoDouble(ACCOUNT_BALANCE)-10000)>0.01||
         EligibleFrom<=0||EligibleTo<=EligibleFrom||EligibleTo>ResearchCutoff||
         ResearchCutoff!=D'2026.08.01 00:00:00'||
         (ExpectedExecutionMode==0&&ExecutionLayer!="NATIVE_NORMAL_EXECUTION")||
         (ExpectedExecutionMode==200&&ExecutionLayer!="FIXED_DELAY_200_MS")||
         FileIsExist(OutputRoot+"\\run-summary.csv",FILE_COMMON))
        {
         reason="FROZEN_EQUIVALENCE_ENVIRONMENT_DIFFERS";
         return false;
        }
     }
   else
     {
      if(AccountInfoInteger(ACCOUNT_TRADE_MODE)!=ACCOUNT_TRADE_MODE_DEMO||
         AccountInfoInteger(ACCOUNT_LOGIN)!=ApprovedAccount||
         AccountInfoString(ACCOUNT_SERVER)!=ApprovedServer||
         ProductionBaselineEquity<=0||
         V28_RISK_PER_LEG_PERCENT*V28_LEGS>=4.0||
         V28_EMERGENCY_DRAWDOWN_PERCENT>=8.0)
        {
         reason="FXIFY_ACCOUNT_OR_RISK_GATE_FAILED";
         return false;
        }
      if(!LoadLiveState(reason))
         return false;
     }
   return true;
  }

bool ExactClose(const string symbol,const datetime opening,double &value)
  {
   int shift=iBarShift(symbol,PERIOD_H1,opening,true);
   if(shift<0||iTime(symbol,PERIOD_H1,shift)!=opening)
      return false;
   value=iClose(symbol,PERIOD_H1,shift);
   return value>0;
  }

bool ATR(const int index,double &value)
  {
   double values[1];
   if(CopyBuffer(g_atr[index],0,1,1,values)!=1||values[0]<=0)
      return false;
   value=values[0];
   return true;
  }

bool TesterCohortEligible(const datetime target,const datetime exit_time)
  {
   return target>=EligibleFrom&&target<EligibleTo&&exit_time<EligibleTo;
  }

int PortfolioPositions()
  {
   int count=0;
   for(int p=0;p<PositionsTotal();p++)
     {
      if(PositionGetTicket(p)==0)
         continue;
      long magic=PositionGetInteger(POSITION_MAGIC);
      if(magic>V28_MAGIC_BASE&&magic<=V28_MAGIC_BASE+V28_LEGS)
         count++;
     }
   return count;
  }

int PortfolioOrders()
  {
   int count=0;
   for(int p=0;p<OrdersTotal();p++)
     {
      if(OrderGetTicket(p)==0)
         continue;
      long magic=OrderGetInteger(ORDER_MAGIC);
      if(magic>V28_MAGIC_BASE&&magic<=V28_MAGIC_BASE+V28_LEGS)
         count++;
     }
   return count;
  }

void RefreshAll()
  {
   string reason="";
   g_risk_engine.Refresh(TimeCurrent(),AccountInfoDouble(ACCOUNT_EQUITY),reason);
   g_risk_engine.GetStatus(g_risk);
   for(int i=0;i<V28_LEGS;i++)
     {
      EvaluateSolTradeAccountSafety(g_config[i],g_account[i]);
      RefreshSolTradeMarketData(g_config[i],g_market[i]);
      g_exec[i].RefreshExposure();
      g_exec[i].GetStatus(g_execution[i]);
      g_pm[i].Refresh(reason);
      g_pm[i].GetStatus(g_position[i]);
     }
  }

void RecordEntry(const string record_type,const int index,const datetime target,
                 const datetime exit_time,SolTradeExecutionReport &report,const double atr)
  {
   if(g_transactions==INVALID_HANDLE)
      return;
   FileWrite(g_transactions,"SOLTRADE_V28_TRANSACTION_V1",TS(TimeCurrent()),DatasetId,
             ExecutionLayer,CANONICAL[index],g_symbols[index],record_type,TS(target),
             TS(exit_time),report.signal_result,DoubleToString(report.requested_entry,10),
             DoubleToString(report.actual_entry,10),report.spread_points,
             DoubleToString(report.slippage_points,4),DoubleToString(report.volume,8),
             DoubleToString(report.risk_amount,8),DoubleToString(report.stop_loss,10),
             StringFormat("%I64u",report.order_ticket),StringFormat("%I64u",report.deal_ticket),
             (int)report.broker_return_code,report.fill_confirmed?"YES":"NO",DoubleToString(atr,12));
   FileFlush(g_transactions);
  }

void RecordExit(const string record_type,const int index,SolTradePositionReport &report)
  {
   if(g_transactions==INVALID_HANDLE)
      return;
   FileWrite(g_transactions,"SOLTRADE_V28_TRANSACTION_V1",TS(TimeCurrent()),DatasetId,
             ExecutionLayer,CANONICAL[index],g_symbols[index],record_type,
             TS(report.signal_bar_time),TS(g_exit_target[index]),report.position_direction,
             DoubleToString(report.requested_close_price,10),DoubleToString(report.actual_close_price,10),
             0,DoubleToString(report.slippage_points,4),DoubleToString(report.volume,8),0,0,
             StringFormat("%I64u",report.order_ticket),StringFormat("%I64u",report.deal_ticket),
             (int)report.broker_return_code,report.fill_confirmed?"YES":"NO",report.exit_reason_code);
   FileFlush(g_transactions);
  }

void RecordSignal(const int index,const datetime target,const datetime exit_time,
                  const datetime recent,const datetime anchor,const double recent_close,
                  const double anchor_close,const double factor,const bool foreign_buy,
                  const string direction)
  {
   if(g_signals_file==INVALID_HANDLE)
      return;
   FileWrite(g_signals_file,"SOLTRADE_V28_SIGNAL_V1",DatasetId,TS(target),CANONICAL[index],
             g_symbols[index],ORIENTATION[index],DoubleToString(factor,12),
             foreign_buy?"LONG_FOREIGN_FACTOR":"SHORT_FOREIGN_FACTOR",direction,
             TS(recent),DoubleToString(recent_close,10),TS(anchor),
             DoubleToString(anchor_close,10),TS(exit_time));
   FileFlush(g_signals_file);
  }

bool DryRunSizing(const int index,const string direction,const datetime target,
                  const datetime exit_time,const double factor)
  {
   double atr=0;
   if(!ATR(index,atr))
     {
      Event("DRY_RUN_BLOCK","ATR_UNAVAILABLE","target="+TS(target),index);
      return false;
     }
   MqlTick tick;
   if(!SymbolInfoTick(g_symbols[index],tick)||tick.ask<=0||tick.bid<=0)
     {
      Event("DRY_RUN_BLOCK","QUOTE_UNAVAILABLE","target="+TS(target),index);
      return false;
     }
   ENUM_ORDER_TYPE type=direction=="BUY"?ORDER_TYPE_BUY:ORDER_TYPE_SELL;
   double entry=type==ORDER_TYPE_BUY?tick.ask:tick.bid;
   double tick_size=SymbolInfoDouble(g_symbols[index],SYMBOL_TRADE_TICK_SIZE);
   int digits=(int)SymbolInfoInteger(g_symbols[index],SYMBOL_DIGITS);
   double raw_stop=type==ORDER_TYPE_BUY?entry-V28_ATR_MULTIPLIER*atr:entry+V28_ATR_MULTIPLIER*atr;
   double stop=SolTradeNormaliseProtectiveStop(type,raw_stop,tick_size,digits);
   SolTradeRiskCalculation calculation;
   if(!SolTradeCalculatePositionSize(AccountInfoDouble(ACCOUNT_EQUITY),
                                     V28_RISK_PER_LEG_PERCENT,MathAbs(entry-stop),tick_size,
                                     SymbolInfoDouble(g_symbols[index],SYMBOL_TRADE_TICK_VALUE_LOSS),
                                     SymbolInfoDouble(g_symbols[index],SYMBOL_VOLUME_MIN),
                                     SymbolInfoDouble(g_symbols[index],SYMBOL_VOLUME_MAX),
                                     SymbolInfoDouble(g_symbols[index],SYMBOL_VOLUME_STEP),calculation))
     {
      Event("DRY_RUN_BLOCK","POSITION_SIZE_REJECTED",calculation.reason,index);
      return false;
     }
   Event("DRY_RUN_ENTRY_PLAN","NO_ORDER_SUBMISSION",
         "target="+TS(target)+";exit="+TS(exit_time)+";direction="+direction+
         ";factor="+DoubleToString(factor,12)+";atr="+DoubleToString(atr,12)+
         ";entry="+DoubleToString(entry,digits)+";stop="+DoubleToString(stop,digits)+
         ";volume="+DoubleToString(calculation.normalised_volume,SolTradeVolumeDigits(calculation.volume_step))+
         ";risk="+DoubleToString(calculation.expected_loss,2)+";tp=NONE",index);
   return true;
  }

void AttemptEntry(const int index,const string direction,const string factor_side,
                  const double factor,const datetime target,const datetime exit_time)
  {
   if(DryRunMode)
     {
      DryRunSizing(index,direction,target,exit_time,factor);
      g_processed++;
      return;
     }
   double atr=0;
   if(!ATR(index,atr))
     {
      g_execution_blocks++;
      g_processed++;
      Event("ENTRY_BLOCK","ATR_UNAVAILABLE",TS(target),index);
      return;
     }
   SolTradeStrategySignal signal;
   ResetSolTradeStrategySignal(signal);
   signal.evaluated=true;
   signal.valid=true;
   signal.entry_signal=direction=="BUY"?SOLTRADE_SIGNAL_BUY:SOLTRADE_SIGNAL_SELL;
   signal.signal_bar_time=target;
   signal.signal_close=direction=="BUY"?g_market[index].ask:g_market[index].bid;
   signal.signal_high=signal.signal_close;
   signal.signal_low=signal.signal_close;
   signal.signal_open=signal.signal_close;
   signal.atr_14=atr;
   signal.initial_stop_distance=V28_ATR_MULTIPLIER*atr;
   signal.entry_reason_code="DOLLAR_FACTOR_MOMENTUM";
   signal.entry_reason=factor_side+";factor_return="+DoubleToString(factor,12);
   SolTradeExecutionReport report;
   g_entry_attempts++;
   g_exec[index].ProcessSignal(signal,g_account[index],g_market[index],g_risk,false,report);
   if(report.evaluated)
     {
      if(report.broker_accepted&&report.deal_ticket!=0)
        {
         g_entry_fills++;
         g_exit_target[index]=exit_time;
        }
      else if(report.reason_code=="RISK_ENGINE_LOCKED")
         g_risk_blocks++;
      else if(report.reason_code=="SPREAD_REJECTED"||report.reason_code=="EXCESSIVE_SPREAD"||report.reason_code=="SPREAD_EXCEEDS_LIMIT")
         g_spread_blocks++;
      else
         g_execution_blocks++;
      Event(report.event_type,report.reason_code,report.reason,index);
      RecordEntry("ENTRY_ATTEMPT",index,target,exit_time,report,atr);
     }
   g_exec[index].GetStatus(g_execution[index]);
   g_processed++;
  }

bool EvaluateCohort(const datetime monday,const datetime now)
  {
   datetime target=monday+10*3600+5*60;
   datetime exit_time=NextFirstMonday(monday)+10*3600+5*60;
   if(EquivalenceMode&&!TesterCohortEligible(target,exit_time))
      return false;
   if(now<target)
      return false;
   if(now>=target+5*60)
     {
      if(EquivalenceMode)
        {
         g_signal_count+=V28_LEGS;
         g_processed+=V28_LEGS;
         g_missed+=V28_LEGS;
         return true;
        }
      string state_reason="";
      if(g_live_state_month!=MonthKey(monday)&&SaveLiveState(MonthKey(monday),V28_ALL_LEGS_MASK,state_reason))
         Event("ENTRY_GROUP_SKIP","ENTRY_WINDOW_MISSED",TS(target));
      return true;
     }
   if(g_last_exit_submission_tick==now)
      return false;
   double recent_close[V28_LEGS];
   double anchor_close[V28_LEGS];
   datetime recent=monday+9*3600;
   datetime anchor=PreviousFirstMonday(monday)+9*3600;
   double factor=0;
   for(int i=0;i<V28_LEGS;i++)
     {
      if(!ExactClose(g_symbols[i],recent,recent_close[i])||
         !ExactClose(g_symbols[i],anchor,anchor_close[i]))
        {
         Event("ENTRY_GROUP_SKIP","EXACT_H1_CLOSE_MISSING",
               CANONICAL[i]+";recent="+TS(recent)+";anchor="+TS(anchor));
         if(!EquivalenceMode)
           {
            string state_reason="";
            SaveLiveState(MonthKey(monday),V28_ALL_LEGS_MASK,state_reason);
           }
         return true;
        }
      factor+=ORIENTATION[i]*MathLog(recent_close[i]/anchor_close[i])/7.0;
     }
   if(factor==0)
     {
      Event("ENTRY_GROUP_SKIP","ZERO_FACTOR",TS(target));
      if(!EquivalenceMode)
        {
         string state_reason="";
         SaveLiveState(MonthKey(monday),V28_ALL_LEGS_MASK,state_reason);
        }
      return true;
     }
   bool foreign_buy=factor>0;
   string factor_side=foreign_buy?"LONG_FOREIGN_FACTOR":"SHORT_FOREIGN_FACTOR";
   if(EquivalenceMode)
      g_signal_count+=V28_LEGS;
   RefreshAll();
   int month=MonthKey(monday);
   for(int i=0;i<V28_LEGS;i++)
     {
      string direction=(foreign_buy==(ORIENTATION[i]>0))?"BUY":"SELL";
      RecordSignal(i,target,exit_time,recent,anchor,recent_close[i],anchor_close[i],factor,foreign_buy,direction);
      if(!EquivalenceMode)
        {
         string state_reason="";
         if(!ClaimLiveLeg(month,i,state_reason))
           {
            if(state_reason!="COHORT_LEG_ALREADY_CONSUMED")
               Event("ENTRY_BLOCK",state_reason,"state persistence failed",i);
            continue;
           }
        }
      AttemptEntry(i,direction,factor_side,factor,target,exit_time);
     }
   return true;
  }

void ProcessMonthlyEntry(const datetime now)
  {
   MqlDateTime d;
   TimeToStruct(now,d);
   if(d.day_of_week!=1||d.day>7||d.hour!=10||d.min<5||d.min>=10)
      return;
   datetime monday=now-d.hour*3600-d.min*60-d.sec;
   int key=MonthKey(monday);
   if(EquivalenceMode)
     {
      if(key==g_month_key)
         return;
      if(EvaluateCohort(monday,now))
         g_month_key=key;
      return;
     }
   else if(g_live_state_month==key&&g_live_state_mask==V28_ALL_LEGS_MASK)
      return;
   EvaluateCohort(monday,now);
  }

void ReconstructPositions()
  {
   string reason="";
   for(int i=0;i<V28_LEGS;i++)
     {
      g_pm[i].Refresh(reason);
      g_pm[i].GetStatus(g_position[i]);
      g_exit_target[i]=0;
      if(!g_position[i].position_present)
         continue;
      MqlDateTime opened;
      TimeToStruct(g_position[i].open_time,opened);
      datetime cohort=FirstMonday(opened.year,opened.mon);
      g_exit_target[i]=NextFirstMonday(cohort)+10*3600+5*60;
      Event("POSITION_RECONSTRUCTED","RESTART_SAFE",
            "ticket="+StringFormat("%I64u",g_position[i].position_ticket)+
            ";open="+TS(g_position[i].open_time)+";exit="+TS(g_exit_target[i])+
            ";stop="+DoubleToString(g_position[i].stop_loss,(int)SymbolInfoInteger(g_symbols[i],SYMBOL_DIGITS)),i);
     }
  }

bool ReconstructCohortState(string &reason)
  {
   reason="";
   if(EquivalenceMode)
      return true;
   int reconstructed_month=0;
   int reconstructed_mask=0;
   if(!HistorySelect(0,TimeCurrent()))
     {
      reason="ACCOUNT_HISTORY_SELECT_FAILED";
      return false;
     }
   for(int i=0;i<HistoryDealsTotal();i++)
     {
      ulong deal=HistoryDealGetTicket(i);
      if(deal==0||HistoryDealGetInteger(deal,DEAL_ENTRY)!=DEAL_ENTRY_IN)
         continue;
      long magic=HistoryDealGetInteger(deal,DEAL_MAGIC);
      if(magic<=V28_MAGIC_BASE||magic>V28_MAGIC_BASE+V28_LEGS)
         continue;
      int month=MonthKey((datetime)HistoryDealGetInteger(deal,DEAL_TIME));
      int index=(int)(magic-V28_MAGIC_BASE-1);
      if(month>reconstructed_month)
        {
         reconstructed_month=month;
         reconstructed_mask=0;
        }
      if(month==reconstructed_month)
         reconstructed_mask|=1<<index;
     }
   for(int i=0;i<V28_LEGS;i++)
     {
      g_exec[i].GetStatus(g_execution[i]);
      datetime consumed=g_execution[i].last_consumed_signal_bar;
      if(consumed<=0)
         continue;
      int month=MonthKey(consumed);
      if(month>reconstructed_month)
        {
         reconstructed_month=month;
         reconstructed_mask=0;
        }
      if(month==reconstructed_month)
         reconstructed_mask|=1<<i;
     }
   if(g_live_state_month>reconstructed_month)
     {
      reconstructed_month=g_live_state_month;
      reconstructed_mask=g_live_state_mask;
     }
   else if(g_live_state_month==reconstructed_month)
      reconstructed_mask|=g_live_state_mask;
   if(reconstructed_month>0&&
      (g_live_state_month!=reconstructed_month||g_live_state_mask!=reconstructed_mask))
     {
      if(!SaveLiveState(reconstructed_month,reconstructed_mask,reason))
         return false;
     }
   Event("COHORT_STATE_RECONSTRUCTED","RESTART_SAFE",
         "month="+IntegerToString(reconstructed_month)+
         ";processed_mask="+IntegerToString(reconstructed_mask)+
         ";sources=history_execution_state");
   return true;
  }

void ProcessExits(const datetime now)
  {
   bool due=false;
   for(int i=0;i<V28_LEGS;i++)
      if(g_exit_target[i]>0&&now>=g_exit_target[i])
        {
         due=true;
         break;
        }
   if(!due)
      return;
   RefreshAll();
   for(int i=0;i<V28_LEGS;i++)
     {
      if(g_exit_target[i]<=0||now<g_exit_target[i])
         continue;
      if(!g_position[i].position_present)
        {
         g_exit_target[i]=0;
         continue;
        }
      if(DryRunMode)
        {
         Event("DRY_RUN_EXIT_DUE","NO_ORDER_SUBMISSION","scheduled="+TS(g_exit_target[i]),i);
         continue;
        }
      SolTradeStrategySignal signal;
      ResetSolTradeStrategySignal(signal);
      signal.evaluated=true;
      signal.valid=true;
      signal.signal_bar_time=g_exit_target[i];
      signal.exit_signal=g_position[i].position_type==POSITION_TYPE_BUY?SOLTRADE_EXIT_LONG:SOLTRADE_EXIT_SHORT;
      signal.exit_reason_code="DOLLAR_FACTOR_REBALANCE";
      signal.exit_reason="Frozen next-month factor rebalance exit";
      SolTradePositionReport report;
      g_pm[i].ProcessClose(signal,SOLTRADE_CLOSE_STRATEGY,g_account[i],g_market[i],report);
      if(report.evaluated)
        {
         if(report.broker_accepted)
            g_last_exit_submission_tick=now;
         Event(report.event_type,report.reason_code,report.reason,i);
         RecordExit("EXIT_ATTEMPT",i,report);
        }
      g_pm[i].GetStatus(g_position[i]);
     }
  }

bool WriteDeals()
  {
   if(!EquivalenceMode)
      return true;
   HistorySelect(EligibleFrom-7*24*3600,TimeCurrent());
   int handle=FileOpen(OutputRoot+"\\deals.csv",FILE_WRITE|FILE_CSV|FILE_ANSI|FILE_COMMON,',');
   if(handle==INVALID_HANDLE)
      return false;
   FileWrite(handle,"deal_ticket","order_ticket","position_identifier","time","time_msc","entry","type","reason","volume","price","profit","commission","swap","fee","magic","canonical_symbol","resolved_symbol","comment","in_research_window");
   for(int i=0;i<HistoryDealsTotal();i++)
     {
      ulong deal=HistoryDealGetTicket(i);
      if(deal==0)
         continue;
      long magic=HistoryDealGetInteger(deal,DEAL_MAGIC);
      if(magic<=V28_MAGIC_BASE||magic>V28_MAGIC_BASE+V28_LEGS)
         continue;
      datetime time=(datetime)HistoryDealGetInteger(deal,DEAL_TIME);
      int index=(int)(magic-V28_MAGIC_BASE-1);
      FileWrite(handle,StringFormat("%I64u",deal),
                StringFormat("%I64u",(ulong)HistoryDealGetInteger(deal,DEAL_ORDER)),
                StringFormat("%I64u",(ulong)HistoryDealGetInteger(deal,DEAL_POSITION_ID)),
                TS(time),StringFormat("%I64d",HistoryDealGetInteger(deal,DEAL_TIME_MSC)),
                (int)HistoryDealGetInteger(deal,DEAL_ENTRY),(int)HistoryDealGetInteger(deal,DEAL_TYPE),
                (int)HistoryDealGetInteger(deal,DEAL_REASON),
                DoubleToString(HistoryDealGetDouble(deal,DEAL_VOLUME),8),
                DoubleToString(HistoryDealGetDouble(deal,DEAL_PRICE),10),
                DoubleToString(HistoryDealGetDouble(deal,DEAL_PROFIT),8),
                DoubleToString(HistoryDealGetDouble(deal,DEAL_COMMISSION),8),
                DoubleToString(HistoryDealGetDouble(deal,DEAL_SWAP),8),
                DoubleToString(HistoryDealGetDouble(deal,DEAL_FEE),8),magic,CANONICAL[index],
                HistoryDealGetString(deal,DEAL_SYMBOL),HistoryDealGetString(deal,DEAL_COMMENT),
                time>=EligibleFrom&&time<EligibleTo?"YES":"NO");
     }
   FileClose(handle);
   return true;
  }

bool WriteSummary()
  {
   if(!EquivalenceMode)
      return true;
   int open=PortfolioPositions();
   int handle=FileOpen(OutputRoot+"\\run-summary.csv",FILE_WRITE|FILE_CSV|FILE_ANSI|FILE_COMMON,',');
   if(handle==INVALID_HANDLE)
      return false;
   FileWrite(handle,"field","value");
   FileWrite(handle,"schema","SOLTRADE_V28_LIVE_EQUIVALENCE_SUMMARY_V1");
   FileWrite(handle,"execution_instance_id",ExecutionInstanceId);
   FileWrite(handle,"dataset",DatasetId);
   FileWrite(handle,"execution_layer",ExecutionLayer);
   FileWrite(handle,"schedule_signals",g_signal_count);
   FileWrite(handle,"processed_signals",g_processed);
   FileWrite(handle,"entry_attempts",g_entry_attempts);
   FileWrite(handle,"entry_fills",g_entry_fills);
   FileWrite(handle,"exit_fills",g_exit_fills);
   FileWrite(handle,"missed_signals",g_missed);
   FileWrite(handle,"spread_blocks",g_spread_blocks);
   FileWrite(handle,"risk_blocks",g_risk_blocks);
   FileWrite(handle,"execution_blocks",g_execution_blocks);
   FileWrite(handle,"open_positions_at_end",open);
   FileWrite(handle,"max_tick",TS(g_max_tick));
   FileWrite(handle,"seal_breach",g_seal_breach?"YES":"NO");
   bool valid=g_preflight&&!g_seal_breach&&g_signal_count==ExpectedScheduleSignals&&
              g_processed==g_signal_count&&open==0;
   FileWrite(handle,"run_evidence_status",valid?"PASS":"FAIL");
   FileClose(handle);
   return valid;
  }

void LogPreflightSpecifications()
  {
   for(int i=0;i<V28_LEGS;i++)
     {
      string symbol=g_symbols[i];
      Event("SYMBOL_PREFLIGHT","PASS",
            "tick_size="+DoubleToString(SymbolInfoDouble(symbol,SYMBOL_TRADE_TICK_SIZE),10)+
            ";tick_value_loss="+DoubleToString(SymbolInfoDouble(symbol,SYMBOL_TRADE_TICK_VALUE_LOSS),8)+
            ";volume_min="+DoubleToString(SymbolInfoDouble(symbol,SYMBOL_VOLUME_MIN),8)+
            ";volume_max="+DoubleToString(SymbolInfoDouble(symbol,SYMBOL_VOLUME_MAX),8)+
            ";volume_step="+DoubleToString(SymbolInfoDouble(symbol,SYMBOL_VOLUME_STEP),8)+
            ";stops_level="+IntegerToString(SymbolInfoInteger(symbol,SYMBOL_TRADE_STOPS_LEVEL))+
            ";filling="+IntegerToString(SymbolInfoInteger(symbol,SYMBOL_FILLING_MODE)),i);
     }
   Event("ACCOUNT_PREFLIGHT","PASS",
         "server="+AccountInfoString(ACCOUNT_SERVER)+
         ";balance="+DoubleToString(AccountInfoDouble(ACCOUNT_BALANCE),2)+
         ";equity="+DoubleToString(AccountInfoDouble(ACCOUNT_EQUITY),2)+
         ";leverage=1:"+IntegerToString(AccountInfoInteger(ACCOUNT_LEVERAGE))+
         ";hedge=YES;positions="+IntegerToString(PositionsTotal())+
         ";orders="+IntegerToString(OrdersTotal()));
   Event("RISK_PREFLIGHT","PASS",
         "risk_per_leg=0.5%;cohort_initial_risk=3.5%;daily_lock=1.0%;weekly_lock=2.5%;emergency_static_lock=5.0%;fxify_daily=4.0%;fxify_static=8.0%");
  }

int OnInit()
  {
   for(int i=0;i<V28_LEGS;i++)
     {
      g_atr[i]=INVALID_HANDLE;
      g_exit_target[i]=0;
      ResetSolTradeMarketSnapshot(g_market[i]);
      ResetSolTradeExecutionStatus(g_execution[i]);
      ResetSolTradePositionStatus(g_position[i]);
     }
   ResetSolTradeRiskStatus(g_risk);
   string reason="";
   if(!Preflight(reason))
     {
      Print("SOLTRADE_V28_PREFLIGHT_FAILED | ",reason);
      return INIT_PARAMETERS_INCORRECT;
     }
   if(!OpenOutputFiles(reason))
     {
      Print("SOLTRADE_V28_OUTPUT_FAILED | ",reason);
      return INIT_FAILED;
     }
   for(int i=0;i<V28_LEGS;i++)
     {
      EvaluateSolTradeAccountSafety(g_config[i],g_account[i]);
      datetime last=0;
      if(!InitialiseSolTradeMarketData(g_config[i],last,reason)||
         !g_exec[i].Initialise(g_config[i],g_account[i].account_identifier_hash,reason)||
         !g_pm[i].Initialise(g_config[i],g_account[i].account_identifier_hash,reason))
        {
         Event("ENGINE_INIT_FAILED",reason,"",i);
         return INIT_FAILED;
        }
      g_atr[i]=iATR(g_symbols[i],PERIOD_D1,14);
      if(g_atr[i]==INVALID_HANDLE)
        {
         Event("ATR_INIT_FAILED","INVALID_HANDLE","",i);
         return INIT_FAILED;
        }
     }
   if(!g_risk_engine.Initialise(g_config[0],g_account[0].account_identifier_hash,
                                TimeCurrent(),AccountInfoDouble(ACCOUNT_EQUITY),reason))
     {
      Event("RISK_INIT_FAILED",reason);
      return INIT_FAILED;
     }
   if(!ReconstructCohortState(reason))
     {
      Event("COHORT_STATE_RECONSTRUCTION_FAILED",reason);
      return INIT_FAILED;
     }
   ReconstructPositions();
   LogPreflightSpecifications();
   g_preflight=true;
   Event("PREFLIGHT_PASSED","NONE",
         "strategy=FX_DOLLAR_FACTOR_MOMENTUM_1M_1M_1_0;symbols=7;dry_run="+
         (DryRunMode?"YES":"NO")+";orders_submitted=NO");
   return INIT_SUCCEEDED;
  }

void OnTick()
  {
   datetime now=TimeCurrent();
   if(EquivalenceMode&&now>=ResearchCutoff)
     {
      g_seal_breach=true;
      return;
     }
   if(EquivalenceMode&&now>=EligibleTo)
      return;
   g_max_tick=now;
   ProcessExits(now);
   ProcessMonthlyEntry(now);
  }

void OnTradeTransaction(const MqlTradeTransaction &transaction,
                        const MqlTradeRequest &request,
                        const MqlTradeResult &result)
  {
   if(DryRunMode||(EquivalenceMode&&TimeCurrent()>=EligibleTo))
      return;
   for(int i=0;i<V28_LEGS;i++)
     {
      SolTradeExecutionReport entry;
      if(g_exec[i].HandleTradeTransaction(transaction,entry))
        {
         Event(entry.event_type,entry.reason_code,
               "deal="+StringFormat("%I64u",entry.deal_ticket),i);
         RecordEntry("ENTRY_TRANSACTION",i,0,g_exit_target[i],entry,0);
        }
      SolTradePositionReport exit;
      if(g_pm[i].HandleTradeTransaction(transaction,exit))
        {
         if(exit.fill_confirmed)
           {
            g_exit_fills++;
            g_exit_target[i]=0;
           }
         Event(exit.event_type,exit.reason_code,exit.exit_reason_code,i);
         RecordExit("EXIT_TRANSACTION",i,exit);
         string reason="";
         g_risk_engine.RecordClosedOutcome("V28_EXIT_"+StringFormat("%I64u",exit.deal_ticket),
                                           exit.final_profit_loss,TimeCurrent(),
                                           AccountInfoDouble(ACCOUNT_EQUITY),reason);
         g_risk_engine.GetStatus(g_risk);
        }
     }
  }

double OnTester()
  {
   bool ok=WriteDeals()&&WriteSummary();
   if(g_events!=INVALID_HANDLE)
      FileFlush(g_events);
   if(g_transactions!=INVALID_HANDLE)
      FileFlush(g_transactions);
   if(g_signals_file!=INVALID_HANDLE)
      FileFlush(g_signals_file);
   Print("SOLTRADE_V28_EQUIVALENCE_RUN | status=",ok?"PASS":"FAIL",
         " | dataset=",DatasetId," | layer=",ExecutionLayer,
         " | entries=",g_entry_fills," | exits=",g_exit_fills,
         " | open=",PortfolioPositions());
   return ok?1.0:0.0;
  }

void OnDeinit(const int reason)
  {
   for(int i=0;i<V28_LEGS;i++)
      if(g_atr[i]!=INVALID_HANDLE)
         IndicatorRelease(g_atr[i]);
   if(g_events!=INVALID_HANDLE)
      FileClose(g_events);
   if(g_transactions!=INVALID_HANDLE)
      FileClose(g_transactions);
   if(g_signals_file!=INVALID_HANDLE)
      FileClose(g_signals_file);
  }
