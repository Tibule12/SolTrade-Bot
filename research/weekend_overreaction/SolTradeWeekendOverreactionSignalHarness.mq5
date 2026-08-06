#property strict
#property version "1.000"
#property description "V27 frozen weekend-overreaction signal-only evaluator"

input datetime ResearchCutoff=D'2026.08.01 00:00:00';
input string OutputRoot="SolTrade\\Phase6\\V27Signals";

string SYMBOLS[7]={"EURUSD","GBPUSD","AUDUSD","NZDUSD","USDCAD","USDCHF","USDJPY"};
int ORIENTATION[7]={1,1,1,1,-1,-1,-1};
int g_ledger=INVALID_HANDLE,g_weeks=0,g_evaluations=0,g_signals=0,g_buy=0,g_sell=0,g_current_missing=0,g_history_unavailable=0,g_week_key=0;
int g_symbol_signals[7];
datetime g_max_tick=0;
bool g_ok=false,g_seal_breach=false;

string TS(datetime value){return value>0?TimeToString(value,TIME_DATE|TIME_SECONDS):"NONE";}
int WeekKey(datetime value){MqlDateTime d;TimeToStruct(value,d);return d.year*1000+d.day_of_year;}
string Dataset(datetime monday)
  {
   datetime exit_time=monday+4*24*3600+23*3600+55*60;
   if(monday>=D'2025.01.06 00:00:00'&&exit_time<D'2026.01.01 00:00:00')return "V27_2025_DEVELOPMENT";
   if(monday>=D'2026.01.05 00:00:00'&&exit_time<D'2026.08.01 00:00:00')return "V27_2026_PRESEAL_DEVELOPMENT";
   return "NONE";
  }

bool ExactBar(string symbol,datetime opening,double &open,double &close)
  {
   int shift=iBarShift(symbol,PERIOD_H1,opening,true);if(shift<0)return false;
   if(iTime(symbol,PERIOD_H1,shift)!=opening)return false;
   open=iOpen(symbol,PERIOD_H1,shift);close=iClose(symbol,PERIOD_H1,shift);
   return open>0&&close>0;
  }

bool Gap(string symbol,int orientation,datetime monday,double &gap,double &monday_open,double &friday_close)
  {
   double unused=0;
   if(!ExactBar(symbol,monday,monday_open,unused))return false;
   if(!ExactBar(symbol,monday-49*3600,unused,friday_close))return false;
   gap=orientation*MathLog(monday_open/friday_close);
   return MathIsValidNumber(gap);
  }

bool Thresholds(int index,datetime monday,double &lower,double &upper,datetime &oldest)
  {
   double history[260];int found=0;oldest=0;
   for(int week=1;week<=520&&found<260;week++)
     {
      datetime prior=monday-week*7*24*3600;double gap=0,mo=0,fc=0;
      if(!Gap(SYMBOLS[index],ORIENTATION[index],prior,gap,mo,fc))continue;
      history[found++]=gap;oldest=prior;
     }
   if(found!=260)return false;
   ArraySort(history);
   lower=history[12];upper=history[246];
   return true;
  }

void Evaluate(datetime monday)
  {
   string dataset=Dataset(monday);if(dataset=="NONE")return;
   g_weeks++;
   for(int i=0;i<7;i++)
     {
      double gap=0,mo=0,fc=0,lower=0,upper=0;datetime oldest=0;
      if(!Gap(SYMBOLS[i],ORIENTATION[i],monday,gap,mo,fc))
        {g_current_missing++;FileWrite(g_ledger,"SOLTRADE_PHASE6_V27_SIGNAL_V1",dataset,TS(monday),SYMBOLS[i],ORIENTATION[i],"CURRENT_REFERENCE_MISSING","NONE",0,0,0,0,0,"NONE",TS(monday+2*3600+5*60),TS(monday+4*24*3600+23*3600+55*60));continue;}
      if(!Thresholds(i,monday,lower,upper,oldest))
        {g_history_unavailable++;FileWrite(g_ledger,"SOLTRADE_PHASE6_V27_SIGNAL_V1",dataset,TS(monday),SYMBOLS[i],ORIENTATION[i],"THRESHOLD_HISTORY_UNAVAILABLE","NONE",DoubleToString(gap,12),DoubleToString(lower,12),DoubleToString(upper,12),DoubleToString(mo,10),DoubleToString(fc,10),TS(oldest),TS(monday+2*3600+5*60),TS(monday+4*24*3600+23*3600+55*60));continue;}
      string tail="NONE",direction="NONE";
      if(gap>upper){tail="UPPER";direction=(ORIENTATION[i]>0)?"SELL":"BUY";}
      else if(gap<lower){tail="LOWER";direction=(ORIENTATION[i]>0)?"BUY":"SELL";}
      g_evaluations++;
      if(direction!="NONE"){g_signals++;g_symbol_signals[i]++;if(direction=="BUY")g_buy++;else g_sell++;}
      FileWrite(g_ledger,"SOLTRADE_PHASE6_V27_SIGNAL_V1",dataset,TS(monday),SYMBOLS[i],ORIENTATION[i],"EVALUATED",tail,DoubleToString(gap,12),DoubleToString(lower,12),DoubleToString(upper,12),DoubleToString(mo,10),DoubleToString(fc,10),TS(oldest),TS(monday+2*3600+5*60),TS(monday+4*24*3600+23*3600+55*60));
     }
  }

int OnInit()
  {
   if(!MQLInfoInteger(MQL_TESTER)||MQLInfoInteger(MQL_OPTIMIZATION)||(int)TerminalInfoInteger(TERMINAL_BUILD)!=6090||AccountInfoString(ACCOUNT_SERVER)!="FPMarketsSC-Demo"||ResearchCutoff!=D'2026.08.01 00:00:00')return INIT_PARAMETERS_INCORRECT;
   for(int i=0;i<7;i++){g_symbol_signals[i]=0;if(!SymbolSelect(SYMBOLS[i],true))return INIT_FAILED;}
   g_ledger=FileOpen(OutputRoot+"\\signal-ledger.csv",FILE_WRITE|FILE_CSV|FILE_ANSI|FILE_COMMON,',');if(g_ledger==INVALID_HANDLE)return INIT_FAILED;
   FileWrite(g_ledger,"schema","dataset","monday","symbol","orientation","evaluation_status","tail","foreign_gap_log_return","lower_5pct_threshold","upper_95pct_threshold","monday_00_h1_open","friday_23_h1_close","oldest_threshold_observation","entry_target","scheduled_exit");
   g_ok=true;return INIT_SUCCEEDED;
  }

void OnTick()
  {
   datetime now=TimeCurrent();if(now>=ResearchCutoff){g_seal_breach=true;return;}g_max_tick=now;
   MqlDateTime d;TimeToStruct(now,d);if(d.day_of_week!=1||d.hour!=2)return;
   datetime monday=now-d.hour*3600-d.min*60-d.sec;int key=WeekKey(monday);if(key==g_week_key)return;g_week_key=key;Evaluate(monday);
  }

bool WriteSummary()
  {
   int h=FileOpen(OutputRoot+"\\signal-summary.csv",FILE_WRITE|FILE_CSV|FILE_ANSI|FILE_COMMON,',');if(h==INVALID_HANDLE)return false;
   FileWrite(h,"field","value");FileWrite(h,"schema","SOLTRADE_PHASE6_V27_SIGNAL_SUMMARY_V1");FileWrite(h,"weeks",g_weeks);FileWrite(h,"evaluations",g_evaluations);FileWrite(h,"signals",g_signals);FileWrite(h,"buy_signals",g_buy);FileWrite(h,"sell_signals",g_sell);FileWrite(h,"current_reference_missing",g_current_missing);FileWrite(h,"threshold_history_unavailable",g_history_unavailable);
   for(int i=0;i<7;i++)FileWrite(h,"signals_"+SYMBOLS[i],g_symbol_signals[i]);
   FileWrite(h,"max_tick",TS(g_max_tick));FileWrite(h,"seal_breach",g_seal_breach?"YES":"NO");FileWrite(h,"orders_or_positions","ZERO");FileWrite(h,"pnl_calculated","NO");bool pass=g_ok&&!g_seal_breach&&g_weeks>0&&g_evaluations>0&&g_history_unavailable==0;FileWrite(h,"status",pass?"PASS":"FAIL");FileClose(h);return pass;
  }

double OnTester(){if(g_ledger!=INVALID_HANDLE)FileFlush(g_ledger);return WriteSummary()?1.0:0.0;}
void OnDeinit(const int reason){if(g_ledger!=INVALID_HANDLE)FileClose(g_ledger);}
