#property strict
#property version "1.000"
#property description "V30 tester-only broker real-tick history qualification; no trading and no P&L"

input datetime WarmupFrom=D'2017.11.01 00:00:00';
input datetime BoundFrom=D'2018.01.01 00:00:00';
input datetime BoundTo=D'2025.01.01 00:00:00';
input string OutputRoot="SolTrade\\Phase6\\V30Qualification\\EURUSD";

long g_ticks=0,g_warmup_ticks=0,g_zero_spread=0,g_m1=0,g_h1=0,g_m1_mismatch=0,g_h1_mismatch=0,g_spread_samples=0;
long g_year_ticks[7],g_year_m1[7],g_year_h1[7];
datetime g_first=0,g_last=0,g_warmup_first=0,g_warmup_last=0,g_prev_tick=0,g_minute=0,g_hour=0;
double g_m1_o=0,g_m1_h=0,g_m1_l=0,g_m1_c=0,g_h1_o=0,g_h1_h=0,g_h1_l=0,g_h1_c=0,g_spread_sum=0,g_spread_max=0;
int g_gaps=INVALID_HANDLE;bool g_ok=false,g_outside=false;

string TS(datetime x){return x>0?TimeToString(x,TIME_DATE|TIME_SECONDS):"NONE";}
int YearIndex(datetime x){MqlDateTime d;TimeToStruct(x,d);return d.year>=2018&&d.year<=2024?d.year-2018:-1;}
datetime FloorMinute(datetime x){return x-x%60;}
datetime FloorHour(datetime x){return x-x%3600;}
bool Same(double a,double b){return MathAbs(a-b)<=SymbolInfoDouble(_Symbol,SYMBOL_POINT)/2.0;}
void CompareBar(ENUM_TIMEFRAMES tf,datetime opening,double o,double h,double l,double c,long &mismatches)
  {
   int shift=iBarShift(_Symbol,tf,opening,true);
   if(shift<0||iTime(_Symbol,tf,shift)!=opening||!Same(iOpen(_Symbol,tf,shift),o)||!Same(iHigh(_Symbol,tf,shift),h)||!Same(iLow(_Symbol,tf,shift),l)||!Same(iClose(_Symbol,tf,shift),c))mismatches++;
  }
void CloseMinute(){if(g_minute<=0)return;CompareBar(PERIOD_M1,g_minute,g_m1_o,g_m1_h,g_m1_l,g_m1_c,g_m1_mismatch);int y=YearIndex(g_minute);if(y>=0)g_year_m1[y]++;g_m1++;}
void CloseHour(){if(g_hour<=0)return;CompareBar(PERIOD_H1,g_hour,g_h1_o,g_h1_h,g_h1_l,g_h1_c,g_h1_mismatch);int y=YearIndex(g_hour);if(y>=0)g_year_h1[y]++;g_h1++;}
void StartMinute(datetime m,double bid){g_minute=m;g_m1_o=bid;g_m1_h=bid;g_m1_l=bid;g_m1_c=bid;}
void StartHour(datetime h,double bid){g_hour=h;g_h1_o=bid;g_h1_h=bid;g_h1_l=bid;g_h1_c=bid;}

int OnInit()
  {
   if(!MQLInfoInteger(MQL_TESTER)||MQLInfoInteger(MQL_OPTIMIZATION)||(int)TerminalInfoInteger(TERMINAL_BUILD)!=6090||AccountInfoString(ACCOUNT_SERVER)!="FPMarketsSC-Demo"||WarmupFrom!=D'2017.11.01 00:00:00'||BoundFrom!=D'2018.01.01 00:00:00'||BoundTo!=D'2025.01.01 00:00:00')return INIT_PARAMETERS_INCORRECT;
   g_gaps=FileOpen(OutputRoot+"\\tick-gaps.csv",FILE_WRITE|FILE_CSV|FILE_ANSI|FILE_COMMON,',');if(g_gaps==INVALID_HANDLE)return INIT_FAILED;
   FileWrite(g_gaps,"schema","symbol","previous_tick","current_tick","gap_seconds");g_ok=true;return INIT_SUCCEEDED;
  }
void OnTick()
  {
   MqlTick tick;if(!SymbolInfoTick(_Symbol,tick)||tick.time<WarmupFrom)return;
   datetime now=tick.time;if(now>=BoundTo){g_outside=true;return;}
   if(g_prev_tick>0&&now-g_prev_tick>3600)FileWrite(g_gaps,"SOLTRADE_PHASE6_V30_TICK_GAP_V1",_Symbol,TS(g_prev_tick),TS(now),(long)(now-g_prev_tick));
   g_prev_tick=now;
   if(now<BoundFrom){g_warmup_ticks++;if(g_warmup_first==0)g_warmup_first=now;g_warmup_last=now;return;}
   if(g_first==0)g_first=now;g_last=now;g_ticks++;int y=YearIndex(now);if(y>=0)g_year_ticks[y]++;
   double point=SymbolInfoDouble(_Symbol,SYMBOL_POINT);double spread=point>0?(tick.ask-tick.bid)/point:0;g_spread_samples++;g_spread_sum+=spread;if(spread>g_spread_max)g_spread_max=spread;if(spread<=0)g_zero_spread++;
   datetime minute=FloorMinute(now),hour=FloorHour(now);
   if(g_minute==0)StartMinute(minute,tick.bid);else if(minute!=g_minute){CloseMinute();StartMinute(minute,tick.bid);}else{g_m1_h=MathMax(g_m1_h,tick.bid);g_m1_l=MathMin(g_m1_l,tick.bid);g_m1_c=tick.bid;}
   if(g_hour==0)StartHour(hour,tick.bid);else if(hour!=g_hour){CloseHour();StartHour(hour,tick.bid);}else{g_h1_h=MathMax(g_h1_h,tick.bid);g_h1_l=MathMin(g_h1_l,tick.bid);g_h1_c=tick.bid;}
  }
bool WriteSummary()
  {
   CloseMinute();CloseHour();
   int h=FileOpen(OutputRoot+"\\qualification-summary.csv",FILE_WRITE|FILE_CSV|FILE_ANSI|FILE_COMMON,',');if(h==INVALID_HANDLE)return false;
   FileWrite(h,"field","value");FileWrite(h,"schema","SOLTRADE_PHASE6_V30_REAL_TICK_QUALIFICATION_V1");FileWrite(h,"symbol",_Symbol);FileWrite(h,"model","EVERY_TICK_BASED_ON_REAL_TICKS");FileWrite(h,"warmup_from",TS(WarmupFrom));FileWrite(h,"bound_from",TS(BoundFrom));FileWrite(h,"bound_to_exclusive",TS(BoundTo));FileWrite(h,"warmup_first_tick",TS(g_warmup_first));FileWrite(h,"warmup_last_tick",TS(g_warmup_last));FileWrite(h,"warmup_tick_count",g_warmup_ticks);FileWrite(h,"first_tick",TS(g_first));FileWrite(h,"final_tick",TS(g_last));FileWrite(h,"tick_count",g_ticks);FileWrite(h,"m1_count",g_m1);FileWrite(h,"h1_count",g_h1);FileWrite(h,"m1_mismatches",g_m1_mismatch);FileWrite(h,"h1_mismatches",g_h1_mismatch);FileWrite(h,"spread_samples",g_spread_samples);FileWrite(h,"zero_or_negative_spread_samples",g_zero_spread);FileWrite(h,"mean_spread_points",g_spread_samples>0?g_spread_sum/g_spread_samples:0);FileWrite(h,"maximum_spread_points",g_spread_max);FileWrite(h,"digits",(int)SymbolInfoInteger(_Symbol,SYMBOL_DIGITS));FileWrite(h,"point",DoubleToString(SymbolInfoDouble(_Symbol,SYMBOL_POINT),10));FileWrite(h,"contract_size",DoubleToString(SymbolInfoDouble(_Symbol,SYMBOL_TRADE_CONTRACT_SIZE),2));FileWrite(h,"swap_mode",(int)SymbolInfoInteger(_Symbol,SYMBOL_SWAP_MODE));FileWrite(h,"swap_rollover3day",(int)SymbolInfoInteger(_Symbol,SYMBOL_SWAP_ROLLOVER3DAYS));FileWrite(h,"swap_long",DoubleToString(SymbolInfoDouble(_Symbol,SYMBOL_SWAP_LONG),8));FileWrite(h,"swap_short",DoubleToString(SymbolInfoDouble(_Symbol,SYMBOL_SWAP_SHORT),8));
   for(int i=0;i<7;i++){string year=IntegerToString(2018+i);FileWrite(h,"ticks_"+year,g_year_ticks[i]);FileWrite(h,"m1_"+year,g_year_m1[i]);FileWrite(h,"h1_"+year,g_year_h1[i]);}
   FileWrite(h,"orders_or_positions","ZERO");FileWrite(h,"pnl_calculated","NO");
   bool pass=g_ok&&g_ticks>0&&g_warmup_ticks>0&&g_first>0&&g_last>0&&g_m1_mismatch==0&&g_h1_mismatch==0&&g_spread_samples==g_ticks;
   for(int i=0;i<7;i++)pass=pass&&g_year_ticks[i]>0&&g_year_m1[i]>0&&g_year_h1[i]>0;
   FileWrite(h,"status",pass?"PASS":"FAIL");FileClose(h);return pass;
  }
double OnTester(){if(g_gaps!=INVALID_HANDLE)FileFlush(g_gaps);return WriteSummary()?1:0;}
void OnDeinit(const int reason){if(g_gaps!=INVALID_HANDLE)FileClose(g_gaps);}
