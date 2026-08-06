#property strict
#property version "1.000"
#property description "V30C tester-only exact-window real-tick qualification; no trading or P&L"

input string OutputRoot="SolTrade\\Phase6\\V30CQualification\\EURUSD";

#define V30C_START_MSC ((long)D'2022.11.14 00:05:00'*1000+354)
#define V30C_END_MSC ((long)D'2024.01.01 00:00:00'*1000)

long g_ticks=0,g_zero_spread=0,g_m1=0,g_h1=0,g_m1_mismatch=0,g_h1_mismatch=0,g_2022=0,g_2023=0;
long g_first=0,g_last=0;datetime g_prev=0,g_minute=0,g_hour=0;
double g_m1_o=0,g_m1_h=0,g_m1_l=0,g_m1_c=0,g_h1_o=0,g_h1_h=0,g_h1_l=0,g_h1_c=0,g_spread_sum=0,g_spread_max=0;
int g_gaps=INVALID_HANDLE;bool g_ok=false;

string TSms(long x){return x>0?TimeToString((datetime)(x/1000),TIME_DATE|TIME_SECONDS)+StringFormat(".%03d",(int)(x%1000)):"NONE";}
bool Same(double a,double b){return MathAbs(a-b)<=SymbolInfoDouble(_Symbol,SYMBOL_POINT)/2.0;}
void Compare(ENUM_TIMEFRAMES tf,datetime opening,double o,double h,double l,double c,long &bad)
  {int shift=iBarShift(_Symbol,tf,opening,true);if(shift<0||iTime(_Symbol,tf,shift)!=opening||!Same(iOpen(_Symbol,tf,shift),o)||!Same(iHigh(_Symbol,tf,shift),h)||!Same(iLow(_Symbol,tf,shift),l)||!Same(iClose(_Symbol,tf,shift),c))bad++;}
void CloseM1(){if(g_minute>0){Compare(PERIOD_M1,g_minute,g_m1_o,g_m1_h,g_m1_l,g_m1_c,g_m1_mismatch);g_m1++;}}
void CloseH1(){if(g_hour>0){Compare(PERIOD_H1,g_hour,g_h1_o,g_h1_h,g_h1_l,g_h1_c,g_h1_mismatch);g_h1++;}}
void StartM1(datetime t,double p){g_minute=t;g_m1_o=p;g_m1_h=p;g_m1_l=p;g_m1_c=p;}
void StartH1(datetime t,double p){g_hour=t;g_h1_o=p;g_h1_h=p;g_h1_l=p;g_h1_c=p;}

int OnInit()
  {
   bool safe=(bool)MQLInfoInteger(MQL_TESTER)&&!(bool)MQLInfoInteger(MQL_OPTIMIZATION)&&(int)TerminalInfoInteger(TERMINAL_BUILD)==6090&&AccountInfoString(ACCOUNT_SERVER)=="FPMarketsSC-Demo";
   if(!safe)return INIT_PARAMETERS_INCORRECT;
   g_gaps=FileOpen(OutputRoot+"\\tick-gaps.csv",FILE_WRITE|FILE_CSV|FILE_ANSI|FILE_COMMON,',');if(g_gaps==INVALID_HANDLE)return INIT_FAILED;
   FileWrite(g_gaps,"schema","symbol","previous_tick","current_tick","gap_seconds");g_ok=true;return INIT_SUCCEEDED;
  }
void OnTick()
  {
   MqlTick tick;if(!SymbolInfoTick(_Symbol,tick))return;long now=tick.time_msc;if(now<V30C_START_MSC||now>=V30C_END_MSC)return;
   datetime sec=(datetime)(now/1000);if(g_prev>0&&sec-g_prev>3600)FileWrite(g_gaps,"SOLTRADE_PHASE6_V30C_GAP_V1",_Symbol,TimeToString(g_prev,TIME_DATE|TIME_SECONDS),TimeToString(sec,TIME_DATE|TIME_SECONDS),(long)(sec-g_prev));g_prev=sec;
   if(g_first==0)g_first=now;g_last=now;g_ticks++;MqlDateTime d;TimeToStruct(sec,d);if(d.year==2022)g_2022++;else if(d.year==2023)g_2023++;
   double point=SymbolInfoDouble(_Symbol,SYMBOL_POINT),spread=point>0?(tick.ask-tick.bid)/point:0;g_spread_sum+=spread;if(spread>g_spread_max)g_spread_max=spread;if(spread<=0)g_zero_spread++;
   datetime minute=sec-sec%60,hour=sec-sec%3600;
   if(g_minute==0)StartM1(minute,tick.bid);else if(minute!=g_minute){CloseM1();StartM1(minute,tick.bid);}else{g_m1_h=MathMax(g_m1_h,tick.bid);g_m1_l=MathMin(g_m1_l,tick.bid);g_m1_c=tick.bid;}
   if(g_hour==0)StartH1(hour,tick.bid);else if(hour!=g_hour){CloseH1();StartH1(hour,tick.bid);}else{g_h1_h=MathMax(g_h1_h,tick.bid);g_h1_l=MathMin(g_h1_l,tick.bid);g_h1_c=tick.bid;}
  }
bool Summary()
  {
   CloseM1();CloseH1();int h=FileOpen(OutputRoot+"\\qualification-summary.csv",FILE_WRITE|FILE_CSV|FILE_ANSI|FILE_COMMON,',');if(h==INVALID_HANDLE)return false;
   FileWrite(h,"field","value");FileWrite(h,"schema","SOLTRADE_PHASE6_V30C_QUALIFICATION_V1");FileWrite(h,"symbol",_Symbol);FileWrite(h,"model","EVERY_TICK_BASED_ON_REAL_TICKS");FileWrite(h,"bound_start_inclusive",TSms(V30C_START_MSC));FileWrite(h,"bound_end_exclusive",TSms(V30C_END_MSC));FileWrite(h,"first_processed_tick",TSms(g_first));FileWrite(h,"final_processed_tick",TSms(g_last));FileWrite(h,"processed_tick_count",g_ticks);FileWrite(h,"processed_ticks_2022",g_2022);FileWrite(h,"processed_ticks_2023",g_2023);FileWrite(h,"m1_count",g_m1);FileWrite(h,"h1_count",g_h1);FileWrite(h,"m1_mismatches",g_m1_mismatch);FileWrite(h,"h1_mismatches",g_h1_mismatch);FileWrite(h,"spread_samples",g_ticks);FileWrite(h,"zero_or_negative_spread_samples",g_zero_spread);FileWrite(h,"mean_spread_points",g_ticks>0?g_spread_sum/g_ticks:0);FileWrite(h,"maximum_spread_points",g_spread_max);FileWrite(h,"digits",(int)SymbolInfoInteger(_Symbol,SYMBOL_DIGITS));FileWrite(h,"point",DoubleToString(SymbolInfoDouble(_Symbol,SYMBOL_POINT),10));FileWrite(h,"contract_size",DoubleToString(SymbolInfoDouble(_Symbol,SYMBOL_TRADE_CONTRACT_SIZE),2));FileWrite(h,"swap_mode",(int)SymbolInfoInteger(_Symbol,SYMBOL_SWAP_MODE));FileWrite(h,"swap_rollover3day",(int)SymbolInfoInteger(_Symbol,SYMBOL_SWAP_ROLLOVER3DAYS));FileWrite(h,"swap_long",DoubleToString(SymbolInfoDouble(_Symbol,SYMBOL_SWAP_LONG),8));FileWrite(h,"swap_short",DoubleToString(SymbolInfoDouble(_Symbol,SYMBOL_SWAP_SHORT),8));FileWrite(h,"orders_or_positions","ZERO");FileWrite(h,"pnl_calculated","NO");
   bool pass=g_ok&&g_first>=V30C_START_MSC&&g_first<V30C_START_MSC+60000&&g_last>=(long)D'2023.12.29 23:57:52'*1000+904&&g_ticks>0&&g_2022>0&&g_2023>0&&g_m1_mismatch==0&&g_h1_mismatch==0;FileWrite(h,"local_status",pass?"PASS":"FAIL");FileClose(h);return pass;
  }
double OnTester(){if(g_gaps!=INVALID_HANDLE)FileFlush(g_gaps);return Summary()?1:0;}
void OnDeinit(const int reason){if(g_gaps!=INVALID_HANDLE)FileClose(g_gaps);}
