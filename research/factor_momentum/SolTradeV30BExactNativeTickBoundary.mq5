#property strict
#property version "1.001"
#property description "V30B connected read-only exact native tick boundary audit"

string SYMBOLS[7]={"EURUSD","GBPUSD","AUDUSD","NZDUSD","USDCAD","USDCHF","USDJPY"};
datetime REPORTED_STARTS[7]={D'2022.11.11 00:00:00',D'2022.11.11 00:00:00',D'2022.11.11 00:00:00',D'2022.11.14 00:00:00',D'2022.11.11 00:00:00',D'2022.11.11 00:00:00',D'2022.11.11 00:00:00'};
string OUTPUT="SolTrade\\Phase6\\V30BQualification\\exact-native-boundaries-v2.csv";

string TSms(long value)
  {
   if(value<=0)return "NONE";
   return TimeToString((datetime)(value/1000),TIME_DATE|TIME_SECONDS)+StringFormat(".%03d",(int)(value%1000));
  }

int CopyRange(string symbol,datetime from,datetime to,MqlTick &ticks[])
  {
   ArrayFree(ticks);ResetLastError();
   return CopyTicksRange(symbol,ticks,COPY_TICKS_ALL,(ulong)from*1000,(ulong)to*1000-1);
  }

int OnInit()
  {
   bool safe=!(bool)MQLInfoInteger(MQL_TESTER)&&AccountInfoString(ACCOUNT_SERVER)=="FPMarketsSC-Demo"&&(ENUM_ACCOUNT_TRADE_MODE)AccountInfoInteger(ACCOUNT_TRADE_MODE)==ACCOUNT_TRADE_MODE_DEMO&&!(bool)TerminalInfoInteger(TERMINAL_TRADE_ALLOWED)&&!(bool)MQLInfoInteger(MQL_TRADE_ALLOWED)&&OrdersTotal()==0&&PositionsTotal()==0;
   if(!safe){Print("SOLTRADE_V30B_NATIVE_BOUNDARY_REJECTED | reason=CONNECTED_SAFETY_PREFLIGHT");return INIT_FAILED;}
   int h=FileOpen(OUTPUT,FILE_WRITE|FILE_CSV|FILE_ANSI|FILE_COMMON,',');if(h==INVALID_HANDLE)return INIT_FAILED;
   FileWrite(h,"schema","symbol","reported_start","ticks_before_reported_start","before_error","first_day_count","first_day_error","exact_first_native_tick","exact_last_tick_first_day","december_2023_count","december_2023_error","exact_last_native_tick_2023","january_2024_count","january_2024_error","june_2024_count","june_2024_error","december_2024_count","december_2024_error","full_2024_count","full_2024_error","orders","positions","trade_api_calls");
   for(int i=0;i<7;i++)
     {
      if(!SymbolSelect(SYMBOLS[i],true)){FileClose(h);return INIT_FAILED;}
      MqlTick ticks[];
      int before=CopyRange(SYMBOLS[i],D'2022.11.01 00:00:00',REPORTED_STARTS[i],ticks),before_error=GetLastError();
      int day=CopyRange(SYMBOLS[i],REPORTED_STARTS[i],REPORTED_STARTS[i]+24*3600,ticks),day_error=GetLastError();long first=day>0?ticks[0].time_msc:0,last_day=day>0?ticks[day-1].time_msc:0;
      int dec23=CopyRange(SYMBOLS[i],D'2023.12.01 00:00:00',D'2024.01.01 00:00:00',ticks),dec23_error=GetLastError();long last23=dec23>0?ticks[dec23-1].time_msc:0;
      int jan24=CopyRange(SYMBOLS[i],D'2024.01.01 00:00:00',D'2024.02.01 00:00:00',ticks),jan24_error=GetLastError();
      int jun24=CopyRange(SYMBOLS[i],D'2024.06.01 00:00:00',D'2024.07.01 00:00:00',ticks),jun24_error=GetLastError();
      int dec24=CopyRange(SYMBOLS[i],D'2024.12.01 00:00:00',D'2025.01.01 00:00:00',ticks),dec24_error=GetLastError();
      int full24=CopyRange(SYMBOLS[i],D'2024.01.01 00:00:00',D'2025.01.01 00:00:00',ticks),full24_error=GetLastError();
      FileWrite(h,"SOLTRADE_PHASE6_V30B_NATIVE_BOUNDARY_V2",SYMBOLS[i],TimeToString(REPORTED_STARTS[i],TIME_DATE|TIME_SECONDS),before,before_error,day,day_error,TSms(first),TSms(last_day),dec23,dec23_error,TSms(last23),jan24,jan24_error,jun24,jun24_error,dec24,dec24_error,full24,full24_error,OrdersTotal(),PositionsTotal(),"NONE");
     }
   FileClose(h);
   Print("SOLTRADE_V30B_NATIVE_BOUNDARY_COMPLETE | symbols=7 | trade_api_calls=NONE | orders=0 | positions=0 | pnl=NO");
   TerminalClose(0);return INIT_SUCCEEDED;
  }
void OnTick(){}
