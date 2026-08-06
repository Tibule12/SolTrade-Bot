#property strict
#property version "1.001"
#property description "V28 tester-only continuous FXIFY addendum signal evaluator"

input datetime ResearchCutoff=D'2026.08.01 00:00:00';
input string OutputRoot="SolTrade\\Phase6\\V28Signals";
string SYMBOLS[7]={"EURUSD","GBPUSD","AUDUSD","NZDUSD","USDCAD","USDCHF","USDJPY"};int ORIENTATION[7]={1,1,1,1,-1,-1,-1};
int g_file=INVALID_HANDLE,g_cohorts=0,g_legs=0,g_buy=0,g_sell=0,g_skips=0,g_key=0;datetime g_max=0;bool g_seal=false,g_ok=false;
string TS(datetime x){return x>0?TimeToString(x,TIME_DATE|TIME_SECONDS):"NONE";}
int Key(datetime x){MqlDateTime d;TimeToStruct(x,d);return d.year*100+d.mon;}
datetime FirstMonday(int year,int month)
  {MqlDateTime d;ZeroMemory(d);d.year=year;d.mon=month;d.day=1;datetime x=StructToTime(d);TimeToStruct(x,d);int add=(8-d.day_of_week)%7;return x+add*24*3600;}
datetime PreviousFirstMonday(datetime current)
  {MqlDateTime d;TimeToStruct(current,d);int y=d.year,m=d.mon-1;if(m==0){m=12;y--;}return FirstMonday(y,m);}
datetime NextFirstMonday(datetime current)
  {MqlDateTime d;TimeToStruct(current,d);int y=d.year,m=d.mon+1;if(m==13){m=1;y++;}return FirstMonday(y,m);}
bool ExactClose(string symbol,datetime opening,double &value)
  {int shift=iBarShift(symbol,PERIOD_H1,opening,true);if(shift<0||iTime(symbol,PERIOD_H1,shift)!=opening)return false;value=iClose(symbol,PERIOD_H1,shift);return value>0;}
string Dataset(datetime target,datetime exit_time)
  {if(target>=D'2025.01.06 10:05:00'&&target<ResearchCutoff)return "V28_FXIFY_CONTINUOUS";return "NONE";}
void Evaluate(datetime monday)
  {
   datetime target=monday+10*3600+5*60,exit_time=NextFirstMonday(monday)+10*3600+5*60;string dataset=Dataset(target,exit_time);if(dataset=="NONE")return;
   datetime recent=monday+9*3600,anchor=PreviousFirstMonday(monday)+9*3600;double returns[7],rc[7],ac[7],factor=0;
   for(int i=0;i<7;i++){if(!ExactClose(SYMBOLS[i],recent,rc[i])||!ExactClose(SYMBOLS[i],anchor,ac[i])){g_skips++;return;}returns[i]=ORIENTATION[i]*MathLog(rc[i]/ac[i]);factor+=returns[i]/7.0;}
   if(factor==0){g_skips++;return;}bool foreign_buy=factor>0;
   for(int i=0;i<7;i++){string direction=(foreign_buy==(ORIENTATION[i]>0))?"BUY":"SELL";if(direction=="BUY")g_buy++;else g_sell++;g_legs++;FileWrite(g_file,"SOLTRADE_PHASE6_V28_SIGNAL_V1",dataset,TS(target),SYMBOLS[i],ORIENTATION[i],DoubleToString(factor,12),foreign_buy?"LONG_FOREIGN_FACTOR":"SHORT_FOREIGN_FACTOR",direction,TS(recent),DoubleToString(rc[i],10),TS(anchor),DoubleToString(ac[i],10),TS(exit_time));}
   g_cohorts++;
  }
int OnInit()
  {if(!MQLInfoInteger(MQL_TESTER)||MQLInfoInteger(MQL_OPTIMIZATION)||(int)TerminalInfoInteger(TERMINAL_BUILD)!=6090||AccountInfoString(ACCOUNT_SERVER)!="FPMarketsSC-Demo"||ResearchCutoff!=D'2026.08.01 00:00:00')return INIT_PARAMETERS_INCORRECT;for(int i=0;i<7;i++)if(!SymbolSelect(SYMBOLS[i],true))return INIT_FAILED;g_file=FileOpen(OutputRoot+"\\signal-schedule.csv",FILE_WRITE|FILE_CSV|FILE_ANSI|FILE_COMMON,',');if(g_file==INVALID_HANDLE)return INIT_FAILED;FileWrite(g_file,"schema","dataset","target","symbol","orientation","dollar_factor_return","factor_side","chart_direction","recent_h1","recent_close","anchor_h1","anchor_close","scheduled_exit");g_ok=true;return INIT_SUCCEEDED;}
void OnTick(){datetime now=TimeCurrent();if(now>=ResearchCutoff){g_seal=true;return;}g_max=now;MqlDateTime d;TimeToStruct(now,d);if(d.day_of_week!=1||d.day>7||d.hour!=10||d.min<5||d.min>=10)return;datetime monday=now-d.hour*3600-d.min*60-d.sec;int key=Key(monday);if(key==g_key)return;g_key=key;Evaluate(monday);}
bool Summary(){int h=FileOpen(OutputRoot+"\\signal-summary.csv",FILE_WRITE|FILE_CSV|FILE_ANSI|FILE_COMMON,',');if(h==INVALID_HANDLE)return false;FileWrite(h,"field","value");FileWrite(h,"schema","SOLTRADE_PHASE6_V28_SIGNAL_SUMMARY_V1");FileWrite(h,"cohorts",g_cohorts);FileWrite(h,"legs",g_legs);FileWrite(h,"buy",g_buy);FileWrite(h,"sell",g_sell);FileWrite(h,"skips",g_skips);FileWrite(h,"max_tick",TS(g_max));FileWrite(h,"seal_breach",g_seal?"YES":"NO");FileWrite(h,"orders_or_positions","ZERO");FileWrite(h,"pnl_calculated","NO");bool pass=g_ok&&!g_seal&&g_cohorts==19&&g_legs==133;FileWrite(h,"status",pass?"PASS":"FAIL");FileClose(h);return pass;}
double OnTester(){if(g_file!=INVALID_HANDLE)FileFlush(g_file);return Summary()?1:0;}
void OnDeinit(const int reason){if(g_file!=INVALID_HANDLE)FileClose(g_file);}
