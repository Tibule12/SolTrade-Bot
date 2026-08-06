#property strict
#property version "1.000"
#property description "V26 frozen cross-sectional currency momentum signal-only harness"

input datetime EligibleFrom=D'2025.01.06 10:05:00';
input datetime EligibleTo=D'2026.01.01 00:00:00';
input datetime ResearchCutoff=D'2026.08.01 00:00:00';
input string DatasetId="V26_2025_DEVELOPMENT";
input string OutputRoot="SolTrade\\Phase6\\V26Signals\\V26_2025_DEVELOPMENT";

string CURRENCIES[7]={"EUR","GBP","AUD","NZD","CAD","CHF","JPY"};
string SYMBOLS[7]={"EURUSD","GBPUSD","AUDUSD","NZDUSD","USDCAD","USDCHF","USDJPY"};
int ORIENTATION[7]={1,1,1,1,-1,-1,-1};
int g_schedule=INVALID_HANDLE,g_rebalances=0,g_legs=0,g_skips=0,g_week_key=0;
datetime g_max_tick=0;
bool g_ok=false,g_seal_breach=false;

string TS(datetime value){return value>0?TimeToString(value,TIME_DATE|TIME_SECONDS):"NONE";}
int WeekKey(datetime value){MqlDateTime d;TimeToStruct(value,d);return d.year*10000+d.day_of_year;}

bool ExactClose(string symbol,datetime opening,double &value)
  {
   int shift=iBarShift(symbol,PERIOD_H1,opening,true);
   if(shift<0)return false;
   datetime actual=iTime(symbol,PERIOD_H1,shift);
   value=iClose(symbol,PERIOD_H1,shift);
   return actual==opening&&value>0;
  }

void Evaluate(datetime target)
  {
   datetime recent_time=target-65*60;
   datetime anchor_time=recent_time-21*24*3600;
   double returns[7],recent[7],anchor[7];
   for(int i=0;i<7;i++)
     {
      if(!ExactClose(SYMBOLS[i],recent_time,recent[i])||!ExactClose(SYMBOLS[i],anchor_time,anchor[i]))
        {g_skips++;return;}
      returns[i]=(ORIENTATION[i]>0)?recent[i]/anchor[i]-1.0:anchor[i]/recent[i]-1.0;
     }
   int order[7];for(int i=0;i<7;i++)order[i]=i;
   for(int i=0;i<6;i++)for(int j=i+1;j<7;j++)
     {
      int a=order[i],b=order[j];
      if(returns[b]>returns[a]||(returns[b]==returns[a]&&StringCompare(CURRENCIES[b],CURRENCIES[a])<0))
        {int temp=order[i];order[i]=order[j];order[j]=temp;}
     }
   int ranks[7];for(int i=0;i<7;i++)ranks[order[i]]=i+1;
   for(int i=0;i<7;i++)
     {
      string portfolio=(ranks[i]<=2)?"LONG":((ranks[i]>=6)?"SHORT":"NONE");
      string direction="NONE";
      if(portfolio=="LONG")direction=(ORIENTATION[i]>0)?"BUY":"SELL";
      if(portfolio=="SHORT")direction=(ORIENTATION[i]>0)?"SELL":"BUY";
      if(direction!="NONE")g_legs++;
      FileWrite(g_schedule,"SOLTRADE_PHASE6_V26_SIGNAL_V1",DatasetId,TS(target),CURRENCIES[i],SYMBOLS[i],ORIENTATION[i],ranks[i],DoubleToString(returns[i],12),portfolio,direction,TS(recent_time),DoubleToString(recent[i],10),TS(anchor_time),DoubleToString(anchor[i],10),TS(target+7*24*3600));
     }
   g_rebalances++;
  }

int OnInit()
  {
   if(!MQLInfoInteger(MQL_TESTER)||MQLInfoInteger(MQL_OPTIMIZATION)||(int)TerminalInfoInteger(TERMINAL_BUILD)!=6090||AccountInfoString(ACCOUNT_SERVER)!="FPMarketsSC-Demo"||EligibleFrom<=0||EligibleTo<=EligibleFrom||EligibleTo>ResearchCutoff||ResearchCutoff!=D'2026.08.01 00:00:00')
      return INIT_PARAMETERS_INCORRECT;
   for(int i=0;i<7;i++)if(!SymbolSelect(SYMBOLS[i],true))return INIT_FAILED;
   g_schedule=FileOpen(OutputRoot+"\\signal-schedule.csv",FILE_WRITE|FILE_CSV|FILE_ANSI|FILE_COMMON,',');
   if(g_schedule==INVALID_HANDLE)return INIT_FAILED;
   FileWrite(g_schedule,"schema","dataset","target","currency","symbol","orientation","rank","formation_return","portfolio_side","chart_direction","recent_h1","recent_close","anchor_h1","anchor_close","scheduled_exit");
   g_ok=true;
   return INIT_SUCCEEDED;
  }

void OnTick()
  {
   datetime now=TimeCurrent();
   if(now>=ResearchCutoff){g_seal_breach=true;return;}
   if(now<EligibleFrom||now>=EligibleTo){return;}
   g_max_tick=now;
   MqlDateTime d;TimeToStruct(now,d);
   if(d.day_of_week!=1||d.hour!=10||d.min<5||d.min>=10)return;
   datetime target=now-d.sec-(d.min-5)*60;
   if(target+7*24*3600>=EligibleTo)return;
   int key=WeekKey(target);if(key==g_week_key)return;g_week_key=key;
   Evaluate(target);
  }

bool WriteSummary()
  {
   int h=FileOpen(OutputRoot+"\\signal-summary.csv",FILE_WRITE|FILE_CSV|FILE_ANSI|FILE_COMMON,',');if(h==INVALID_HANDLE)return false;
   FileWrite(h,"field","value");FileWrite(h,"schema","SOLTRADE_PHASE6_V26_SIGNAL_SUMMARY_V1");FileWrite(h,"dataset",DatasetId);FileWrite(h,"eligible_from",TS(EligibleFrom));FileWrite(h,"eligible_to_exclusive",TS(EligibleTo));FileWrite(h,"rebalances",g_rebalances);FileWrite(h,"selected_legs",g_legs);FileWrite(h,"skipped_rebalances",g_skips);FileWrite(h,"max_tick",TS(g_max_tick));FileWrite(h,"seal_breach",g_seal_breach?"YES":"NO");FileWrite(h,"orders_or_positions","ZERO");FileWrite(h,"pnl_calculated","NO");FileWrite(h,"status",(g_ok&&!g_seal_breach&&g_rebalances>0&&g_legs==g_rebalances*4)?"PASS":"FAIL");FileClose(h);return g_ok&&!g_seal_breach&&g_rebalances>0&&g_legs==g_rebalances*4;
  }
double OnTester(){if(g_schedule!=INVALID_HANDLE)FileFlush(g_schedule);return WriteSummary()?1.0:0.0;}
void OnDeinit(const int reason){if(g_schedule!=INVALID_HANDLE)FileClose(g_schedule);}
