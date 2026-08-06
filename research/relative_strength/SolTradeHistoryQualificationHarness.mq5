#property strict
#property version "1.000"
#property description "Tester-only timestamp availability qualification; no prices or trading"

input datetime BoundFrom=D'2024.12.01 00:00:00';
input datetime BoundTo=D'2026.08.01 00:00:00';
input string OutputRoot="SolTrade\\Phase6\\V26Qualification\\EURUSD";

bool g_ok=false;
int g_times=INVALID_HANDLE;
int g_count=0;
datetime g_first=0,g_last=0,g_seen=0;

string TS(datetime value){return value>0?TimeToString(value,TIME_DATE|TIME_SECONDS):"NONE";}

bool WriteSummary()
  {
   int s=FileOpen(OutputRoot+"\\qualification-summary.csv",FILE_WRITE|FILE_CSV|FILE_ANSI|FILE_COMMON,',');
   if(s==INVALID_HANDLE)return false;
   FileWrite(s,"field","value");
   FileWrite(s,"schema","SOLTRADE_PHASE6_V26_HISTORY_QUALIFICATION_V1");
   FileWrite(s,"symbol",_Symbol);
   FileWrite(s,"bound_from",TS(BoundFrom));
   FileWrite(s,"bound_to_exclusive",TS(BoundTo));
   FileWrite(s,"h1_timestamp_count",g_count);
   FileWrite(s,"first_h1",TS(g_first));
   FileWrite(s,"last_h1",TS(g_last));
   FileWrite(s,"price_fields_written","NO");
   FileWrite(s,"returns_or_rankings_calculated","NO");
   FileWrite(s,"orders_or_positions","ZERO");
   FileWrite(s,"post_seal_access","NO");
   FileWrite(s,"status",(g_ok&&g_count>0&&g_last<BoundTo)?"PASS":"FAIL");
   FileClose(s);
   return g_ok&&g_count>0&&g_last<BoundTo;
  }

int OnInit()
  {
   if(!MQLInfoInteger(MQL_TESTER)||MQLInfoInteger(MQL_OPTIMIZATION)||BoundFrom<=0||BoundTo<=BoundFrom||BoundTo>D'2026.08.01 00:00:00')
      return INIT_PARAMETERS_INCORRECT;
   if((int)TerminalInfoInteger(TERMINAL_BUILD)!=6090||AccountInfoString(ACCOUNT_SERVER)!="FPMarketsSC-Demo")
      return INIT_PARAMETERS_INCORRECT;
   g_times=FileOpen(OutputRoot+"\\h1-timestamps.csv",FILE_WRITE|FILE_CSV|FILE_ANSI|FILE_COMMON,',');
   if(g_times==INVALID_HANDLE)return INIT_FAILED;
   FileWrite(g_times,"schema","symbol","time");
   g_ok=true;
   return INIT_SUCCEEDED;
  }

void OnTick()
  {
   datetime current=iTime(_Symbol,PERIOD_H1,0);
   if(current<BoundFrom||current>=BoundTo||current==g_seen)return;
   g_seen=current;
   if(g_first==0)g_first=current;
   g_last=current;
   g_count++;
   FileWrite(g_times,"SOLTRADE_PHASE6_V26_H1_TIMESTAMP_V1",_Symbol,TS(current));
  }
double OnTester(){if(g_times!=INVALID_HANDLE)FileFlush(g_times);return WriteSummary()?1.0:0.0;}
void OnDeinit(const int reason){if(g_times!=INVALID_HANDLE)FileClose(g_times);}
