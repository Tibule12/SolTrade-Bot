#property strict
#property version "1.000"
#property description "Read-only FP gold M1 history for weekend close/reopen research"

input bool ReadOnlyResearchConfirmed=false;
input bool CloseWhenDone=true;
input string OutputSuffix="20261003";

string ROOT="SolTradeGoldWeekendReadOnly\\";
bool ran=false;
int attempts=0;

void Finish(const string result,const long rows,const int errors)
  {
   int h=FileOpen(ROOT+"status-"+OutputSuffix+".csv",FILE_WRITE|FILE_CSV|FILE_ANSI|FILE_COMMON,',');
   if(h!=INVALID_HANDLE)
     {
      FileWrite(h,"result","login","server","symbol","rows","errors","order_capability","mql_trade_allowed","terminal_trade_allowed","server_now");
      FileWrite(h,result,AccountInfoInteger(ACCOUNT_LOGIN),AccountInfoString(ACCOUNT_SERVER),"XAUUSD.r",rows,errors,
                "false",MQLInfoInteger(MQL_TRADE_ALLOWED),TerminalInfoInteger(TERMINAL_TRADE_ALLOWED),
                TimeToString(TimeCurrent(),TIME_DATE|TIME_SECONDS));
      FileClose(h);
     }
   if(CloseWhenDone) TerminalClose(0);
  }

int OnInit()
  {
   if(!ReadOnlyResearchConfirmed || MQLInfoInteger(MQL_TESTER) || MQLInfoInteger(MQL_OPTIMIZATION)) return INIT_FAILED;
   string path=TerminalInfoString(TERMINAL_PATH);StringToLower(path);
   if(StringFind(path,"v202-validation-terminal")<0) return INIT_FAILED;
   EventSetTimer(2);
   return INIT_SUCCEEDED;
  }

void OnDeinit(const int reason){EventKillTimer();}

void ExportBars()
  {
   const string symbol="XAUUSD.r";
   if(!SymbolSelect(symbol,true)){Finish("SYMBOL_UNAVAILABLE",0,1);return;}
   int h=FileOpen(ROOT+"m1-"+OutputSuffix+".csv",FILE_WRITE|FILE_CSV|FILE_ANSI|FILE_COMMON,',');
   if(h==INVALID_HANDLE){Finish("FILE_ERROR",0,1);return;}
   FileWrite(h,"server_epoch","bid_open","bid_high","bid_low","bid_close","spread_points","point","tick_volume");
   datetime start=StringToTime("2026.04.01 00:00:00");
   datetime finish=StringToTime("2026.10.04 00:00:00");
   long rows=0;int errors=0;
   for(datetime from=start;from<finish;from+=7*86400)
     {
      datetime to=from+7*86400-1;if(to>=finish)to=finish-1;
      MqlRates rates[];ResetLastError();
      int n=CopyRates(symbol,PERIOD_M1,from,to,rates);
      if(n<0){errors++;continue;}
      for(int i=0;i<n;i++)
        {
         FileWrite(h,(long)rates[i].time,DoubleToString(rates[i].open,3),DoubleToString(rates[i].high,3),
                   DoubleToString(rates[i].low,3),DoubleToString(rates[i].close,3),rates[i].spread,
                   DoubleToString(SymbolInfoDouble(symbol,SYMBOL_POINT),5),rates[i].tick_volume);
         rows++;
        }
      FileFlush(h);
     }
   FileClose(h);Finish(errors==0?"COMPLETE":"COPY_ERRORS",rows,errors);
  }

void OnTimer()
  {
   if(ran)return;
   if(!TerminalInfoInteger(TERMINAL_CONNECTED) || AccountInfoInteger(ACCOUNT_LOGIN)!=7404213 ||
      AccountInfoString(ACCOUNT_SERVER)!="FPMarketsSC-Demo")
     {if(++attempts>=60){ran=true;Finish("ACCOUNT_CONNECTION_UNAVAILABLE",0,0);}return;}
   ran=true;ExportBars();
  }
