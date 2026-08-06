#property strict
#property version "1.000"
#property description "V31A connected trade-disabled application and audit of FP Markets pre-start rates"

string CANONICAL[7]={"EURUSD","GBPUSD","AUDUSD","NZDUSD","USDCAD","USDCHF","USDJPY"};
string RESEARCH[7]={"EURUSD.V31","GBPUSD.V31","AUDUSD.V31","NZDUSD.V31","USDCAD.V31","USDCHF.V31","USDJPY.V31"};
datetime FROM=D'2024.11.01 00:00:00';
datetime TO_EXCLUSIVE=D'2025.01.02 00:00:00';
string INPUT_ROOT="SolTrade\\Phase6\\V31AWarmup";
string OUTPUT_ROOT="SolTrade\\Phase6\\V31AWarmupApply";

bool SameRate(const MqlRates &a,const MqlRates &b)
  {return a.time==b.time&&a.open==b.open&&a.high==b.high&&a.low==b.low&&a.close==b.close&&a.tick_volume==b.tick_volume&&a.spread==b.spread&&a.real_volume==b.real_volume;}

int LoadRates(const string symbol,MqlRates &rates[])
  {
   int h=FileOpen(INPUT_ROOT+"\\"+symbol+".csv",FILE_READ|FILE_CSV|FILE_ANSI|FILE_COMMON,',');if(h==INVALID_HANDLE)return -1;
   for(int i=0;i<9;i++)FileReadString(h);
   while(!FileIsEnding(h))
     {
      string schema=FileReadString(h);if(schema=="")break;int n=ArraySize(rates);ArrayResize(rates,n+1,4096);
      rates[n].time=StringToTime(FileReadString(h));rates[n].open=StringToDouble(FileReadString(h));rates[n].high=StringToDouble(FileReadString(h));rates[n].low=StringToDouble(FileReadString(h));rates[n].close=StringToDouble(FileReadString(h));rates[n].tick_volume=(long)StringToInteger(FileReadString(h));rates[n].spread=(int)StringToInteger(FileReadString(h));rates[n].real_volume=(long)StringToInteger(FileReadString(h));
     }
   FileClose(h);return ArraySize(rates);
  }

int OnInit()
  {
   bool safe=!(bool)MQLInfoInteger(MQL_TESTER)&&AccountInfoString(ACCOUNT_SERVER)=="FPMarketsSC-Demo"&&(ENUM_ACCOUNT_TRADE_MODE)AccountInfoInteger(ACCOUNT_TRADE_MODE)==ACCOUNT_TRADE_MODE_DEMO&&!(bool)TerminalInfoInteger(TERMINAL_TRADE_ALLOWED)&&!(bool)MQLInfoInteger(MQL_TRADE_ALLOWED)&&OrdersTotal()==0&&PositionsTotal()==0;
   if(!safe)return INIT_FAILED;
   int h=FileOpen(OUTPUT_ROOT+"\\summary.csv",FILE_WRITE|FILE_CSV|FILE_ANSI|FILE_COMMON,',');if(h==INVALID_HANDLE)return INIT_FAILED;
   FileWrite(h,"schema","canonical_symbol","research_symbol","source_rates","replaced_rates","reloaded_rates","exact_rate_mismatches","first","last","tick_operations","orders","positions","trade_api_calls","pnl_calculated","status");
   for(int i=0;i<7;i++)
     {
      bool custom=false;if(!SymbolExist(RESEARCH[i],custom)||!custom){FileClose(h);return INIT_FAILED;}
      MqlRates source[];int count=LoadRates(CANONICAL[i],source);if(count<=0){FileClose(h);return INIT_FAILED;}
      ResetLastError();int replaced=CustomRatesReplace(RESEARCH[i],FROM,TO_EXCLUSIVE-1,source,count);int replace_error=GetLastError();
      MqlRates reloaded[];int got=CopyRates(RESEARCH[i],PERIOD_M1,FROM,TO_EXCLUSIVE-1,reloaded);long mismatches=MathAbs(count-got);for(int j=0;j<MathMin(count,got);j++)if(!SameRate(source[j],reloaded[j]))mismatches++;
      string status=(replaced==count&&got==count&&mismatches==0)?"PASS":"FAIL";
      FileWrite(h,"SOLTRADE_PHASE6_V31A_WARMUP_APPLY_V1",CANONICAL[i],RESEARCH[i],count,replaced,got,mismatches,TimeToString(source[0].time,TIME_DATE|TIME_SECONDS),TimeToString(source[count-1].time,TIME_DATE|TIME_SECONDS),"NONE",OrdersTotal(),PositionsTotal(),"NONE","NO",status);FileFlush(h);
      if(status!="PASS"){Print("SOLTRADE_V31A_WARMUP_APPLY_FAILED | ",RESEARCH[i]," | error=",replace_error," | mismatches=",mismatches);FileClose(h);return INIT_FAILED;}
     }
   FileClose(h);Print("SOLTRADE_V31A_WARMUP_APPLY_COMPLETE | symbols=7 | tick_operations=NONE | trade_api_calls=NONE | pnl=NO");TerminalClose(0);return INIT_SUCCEEDED;
  }
void OnTick(){}
