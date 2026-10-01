#property strict
#property version "1.000"
#property description "Read-only historical completed bars for native opposite-stop reconstruction"

input bool ReadOnlyAuditConfirmed=false;
input bool CloseIsolatedTerminalWhenDone=true;
input string RequestFilename="native-stop-requests.csv";
input string ExportSuffix="";

string ROOT="SolTradeFPAllSymbolAudit20260908\\";
bool g_ran=false;
int g_attempts=0;

void Finish(const string result)
  {
   int h=FileOpen(ROOT+"native-stop-status"+ExportSuffix+".csv",FILE_WRITE|FILE_CSV|FILE_ANSI|FILE_COMMON,',');
   if(h!=INVALID_HANDLE)
     {
      FileWrite(h,"status","account","server","server_time","utc_time","order_capability");
      FileWrite(h,result,AccountInfoInteger(ACCOUNT_LOGIN),AccountInfoString(ACCOUNT_SERVER),
                TimeToString(TimeCurrent(),TIME_DATE|TIME_SECONDS),TimeToString(TimeGMT(),TIME_DATE|TIME_SECONDS),"false");
      FileClose(h);
     }
   if(CloseIsolatedTerminalWhenDone) TerminalClose(0);
  }

int OnInit()
  {
   if(!ReadOnlyAuditConfirmed || MQLInfoInteger(MQL_TESTER) || MQLInfoInteger(MQL_OPTIMIZATION))
      return INIT_FAILED;
   string path=TerminalInfoString(TERMINAL_PATH);
   StringToLower(path);
   if(StringFind(path,"v202-validation-terminal")<0) return INIT_FAILED;
   EventSetTimer(2);
   return INIT_SUCCEEDED;
  }

void OnDeinit(const int reason)
  {
   EventKillTimer();
  }

void ExportFrame(const string id,const string symbol,const datetime entry_server,
                 const ENUM_TIMEFRAMES timeframe,const int minutes,const int h,const int coverage)
  {
   ResetLastError();
   int containing_shift=iBarShift(symbol,timeframe,entry_server,false);
   int shift_error=GetLastError();
   MqlRates bars[];
   ArraySetAsSeries(bars,true);
   int n=-1;
   if(containing_shift>=0)
     {
      for(int attempt=0;attempt<8;attempt++)
        {
         ResetLastError();
         n=CopyRates(symbol,timeframe,containing_shift+1,20,bars);
         if(n>=18) break;
         Sleep(500);
        }
     }
   long latest=n>0?(long)bars[0].time:0;
   bool causal=n>=18 && latest+(long)minutes*60<=entry_server;
   FileWrite(coverage,id,symbol,minutes,TimeToString(entry_server,TIME_DATE|TIME_SECONDS),
             containing_shift,n,latest,causal?"true":"false",shift_error,GetLastError());
   if(!causal) return;
   for(int j=0;j<n;j++)
      FileWrite(h,id,symbol,minutes,j+1,(long)bars[j].time,
                DoubleToString(bars[j].open,10),DoubleToString(bars[j].high,10),
                DoubleToString(bars[j].low,10),DoubleToString(bars[j].close,10),
                bars[j].tick_volume,bars[j].spread,bars[j].real_volume);
  }

void ExportBars()
  {
   int requests=FileOpen(ROOT+RequestFilename,FILE_READ|FILE_CSV|FILE_ANSI|FILE_COMMON,',');
   if(requests==INVALID_HANDLE){Finish("REQUESTS_MISSING");return;}
   int bars=FileOpen(ROOT+"native-stop-bars"+ExportSuffix+".csv",FILE_WRITE|FILE_CSV|FILE_ANSI|FILE_COMMON,',');
   int coverage=FileOpen(ROOT+"native-stop-coverage"+ExportSuffix+".csv",FILE_WRITE|FILE_CSV|FILE_ANSI|FILE_COMMON,',');
   int specs=FileOpen(ROOT+"native-stop-specifications"+ExportSuffix+".csv",FILE_WRITE|FILE_CSV|FILE_ANSI|FILE_COMMON,',');
   if(bars==INVALID_HANDLE || coverage==INVALID_HANDLE || specs==INVALID_HANDLE)
     {
      if(bars!=INVALID_HANDLE)FileClose(bars);
      if(coverage!=INVALID_HANDLE)FileClose(coverage);
      if(specs!=INVALID_HANDLE)FileClose(specs);
      FileClose(requests);Finish("FILE_ERROR");return;
     }
   FileWrite(bars,"case_id","symbol","timeframe_minutes","completed_shift","bar_open_server_epoch",
             "open","high","low","close","tick_volume","spread_points","real_volume");
   FileWrite(coverage,"case_id","symbol","timeframe_minutes","entry_server","containing_shift",
             "copied_bars","latest_completed_open_server_epoch","completed_before_entry","shift_error","copy_error");
   FileWrite(specs,"case_id","symbol","point","digits","tick_size","stops_level_points",
             "freeze_level_points","captured_server","historical_broker_floor_available");
   for(int i=0;i<4;i++)FileReadString(requests);
   while(!FileIsEnding(requests))
     {
      string id=FileReadString(requests),symbol=FileReadString(requests),when=FileReadString(requests);
      string ignored=FileReadString(requests);
      if(id=="" || symbol=="") continue;
      if(StringFind(id,"..")>=0 || StringFind(id,"/")>=0 || StringFind(id,"\\")>=0)
        {FileClose(requests);FileClose(bars);FileClose(coverage);FileClose(specs);Finish("INVALID_CASE_ID");return;}
      datetime entry=StringToTime(when);
      SymbolSelect(symbol,true);
      FileWrite(specs,id,symbol,SymbolInfoDouble(symbol,SYMBOL_POINT),
                SymbolInfoInteger(symbol,SYMBOL_DIGITS),SymbolInfoDouble(symbol,SYMBOL_TRADE_TICK_SIZE),
                SymbolInfoInteger(symbol,SYMBOL_TRADE_STOPS_LEVEL),
                SymbolInfoInteger(symbol,SYMBOL_TRADE_FREEZE_LEVEL),
                TimeToString(TimeCurrent(),TIME_DATE|TIME_SECONDS),"false");
      ExportFrame(id,symbol,entry,PERIOD_M5,5,bars,coverage);
      ExportFrame(id,symbol,entry,PERIOD_M15,15,bars,coverage);
      FileFlush(bars);FileFlush(coverage);FileFlush(specs);
     }
   FileClose(requests);FileClose(bars);FileClose(coverage);FileClose(specs);
   Finish("COMPLETE");
  }

void OnTimer()
  {
   if(g_ran)return;
   if(!TerminalInfoInteger(TERMINAL_CONNECTED) || AccountInfoInteger(ACCOUNT_LOGIN)!=7404213 ||
      AccountInfoString(ACCOUNT_SERVER)!="FPMarketsSC-Demo")
     {if(++g_attempts>=60){g_ran=true;Finish("ACCOUNT_CONNECTION_UNAVAILABLE");}return;}
   g_ran=true;
   ExportBars();
  }
