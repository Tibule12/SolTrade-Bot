#property strict
#property version "1.000"
#property description "V31A tester-only export of already-consumed FP Markets M1 warm-up bars"

string SYMBOLS[7]={"EURUSD","GBPUSD","AUDUSD","NZDUSD","USDCAD","USDCHF","USDJPY"};
datetime FROM=D'2024.11.01 00:00:00';
datetime TO_EXCLUSIVE=D'2025.01.02 00:00:00';
string ROOT="SolTrade\\Phase6\\V31AWarmup";
datetime g_last_sync=0;

bool ExportAll()
  {
   int summary=FileOpen(ROOT+"\\summary.csv",FILE_WRITE|FILE_CSV|FILE_ANSI|FILE_COMMON,',');
   if(summary==INVALID_HANDLE)return false;
   FileWrite(summary,"schema","symbol","rates","first","last","status","orders","positions","trade_api_calls","pnl_calculated");
   for(int i=0;i<7;i++)
     {
      MqlRates rates[];int count=CopyRates(SYMBOLS[i],PERIOD_M1,FROM,TO_EXCLUSIVE-1,rates);
      if(count<=0){Print("SOLTRADE_V31A_WARMUP_EXPORT_COPY_FAILED | ",SYMBOLS[i]," | error=",GetLastError());FileClose(summary);return false;}
      int h=FileOpen(ROOT+"\\"+SYMBOLS[i]+".csv",FILE_WRITE|FILE_CSV|FILE_ANSI|FILE_COMMON,',');
      if(h==INVALID_HANDLE){FileClose(summary);return false;}
      FileWrite(h,"schema","time","open","high","low","close","tick_volume","spread","real_volume");
      for(int j=0;j<count;j++)FileWrite(h,"SOLTRADE_PHASE6_V31A_WARMUP_RATE_V1",TimeToString(rates[j].time,TIME_DATE|TIME_SECONDS),DoubleToString(rates[j].open,10),DoubleToString(rates[j].high,10),DoubleToString(rates[j].low,10),DoubleToString(rates[j].close,10),StringFormat("%I64d",rates[j].tick_volume),rates[j].spread,StringFormat("%I64d",rates[j].real_volume));
      FileClose(h);
      FileWrite(summary,"SOLTRADE_PHASE6_V31A_WARMUP_SUMMARY_V1",SYMBOLS[i],count,TimeToString(rates[0].time,TIME_DATE|TIME_SECONDS),TimeToString(rates[count-1].time,TIME_DATE|TIME_SECONDS),"PASS",OrdersTotal(),PositionsTotal(),"NONE","NO");
     }
   FileClose(summary);
   Print("SOLTRADE_V31A_WARMUP_EXPORT_COMPLETE | symbols=7 | trade_api_calls=NONE | orders=0 | positions=0 | pnl=NO");
   return true;
  }

int OnInit()
  {
   if(!MQLInfoInteger(MQL_TESTER)||MQLInfoInteger(MQL_OPTIMIZATION)||AccountInfoString(ACCOUNT_SERVER)!="FPMarketsSC-Demo"||OrdersTotal()!=0||PositionsTotal()!=0)
     {
      Print("SOLTRADE_V31A_WARMUP_EXPORT_REJECTED");
      return INIT_FAILED;
     }
   for(int i=0;i<7;i++)if(!SymbolSelect(SYMBOLS[i],true))return INIT_FAILED;
   return INIT_SUCCEEDED;
  }

double OnTester(){return ExportAll()?1.0:0.0;}
void OnTick()
  {
   datetime now=TimeCurrent();
   if(g_last_sync>0&&now<g_last_sync+3600)return;
   g_last_sync=now;
   for(int i=0;i<7;i++)
     {
      MqlRates recent[];
      datetime start=now-2*3600;if(start<FROM)start=FROM;
      CopyRates(SYMBOLS[i],PERIOD_M1,start,now,recent);
     }
  }
