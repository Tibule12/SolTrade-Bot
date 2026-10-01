#property strict
#property version "1.000"
#property description "Read-only FP account history and historical tick export; no order operations"
input bool ReadOnlyAuditConfirmed=false;
input bool ExportPaths=false;
input bool CloseIsolatedTerminalWhenDone=true;
input string RequestFilename="path-requests.csv";
input string ExportSuffix="";
string ROOT="SolTradeFPAllSymbolAudit20260908\\";
bool ran=false;
int attempts=0;

int OnInit()
  {
   if(!ReadOnlyAuditConfirmed || MQLInfoInteger(MQL_TESTER) || MQLInfoInteger(MQL_OPTIMIZATION)) return INIT_FAILED;
   string path=TerminalInfoString(TERMINAL_PATH); StringToLower(path);
   if(StringFind(path,"v202-validation-terminal")<0) return INIT_FAILED;
   EventSetTimer(2); return INIT_SUCCEEDED;
  }
void OnDeinit(const int reason){EventKillTimer();}
void Done(const string status)
  {
   int h=FileOpen(ROOT+(ExportPaths?"paths-status"+ExportSuffix+".csv":"history-status.csv"),FILE_WRITE|FILE_CSV|FILE_ANSI|FILE_COMMON,',');
   if(h!=INVALID_HANDLE){FileWrite(h,"status","account","server","server_time","utc_time");FileWrite(h,status,AccountInfoInteger(ACCOUNT_LOGIN),AccountInfoString(ACCOUNT_SERVER),TimeToString(TimeCurrent(),TIME_DATE|TIME_SECONDS),TimeToString(TimeGMT(),TIME_DATE|TIME_SECONDS));FileClose(h);}
   if(CloseIsolatedTerminalWhenDone) TerminalClose(0);
  }
void History()
  {
   if(!HistorySelect(0,TimeCurrent())){Done("HISTORY_SELECT_FAILED");return;}
   int d=FileOpen(ROOT+"deals.csv",FILE_WRITE|FILE_CSV|FILE_ANSI|FILE_COMMON,',');
   int o=FileOpen(ROOT+"orders.csv",FILE_WRITE|FILE_CSV|FILE_ANSI|FILE_COMMON,',');
   if(d==INVALID_HANDLE || o==INVALID_HANDLE){if(d!=INVALID_HANDLE)FileClose(d);if(o!=INVALID_HANDLE)FileClose(o);Done("FILE_ERROR");return;}
   FileWrite(d,"ticket","position_id","order","time_server","time_msc","symbol","magic","type","entry","reason","volume","price","profit","commission","swap","fee","sl","tp","comment");
   for(int i=0;i<HistoryDealsTotal();i++)
     {
      ulong t=HistoryDealGetTicket(i);
      FileWrite(d,t,HistoryDealGetInteger(t,DEAL_POSITION_ID),HistoryDealGetInteger(t,DEAL_ORDER),TimeToString((datetime)HistoryDealGetInteger(t,DEAL_TIME),TIME_DATE|TIME_SECONDS),HistoryDealGetInteger(t,DEAL_TIME_MSC),HistoryDealGetString(t,DEAL_SYMBOL),HistoryDealGetInteger(t,DEAL_MAGIC),HistoryDealGetInteger(t,DEAL_TYPE),HistoryDealGetInteger(t,DEAL_ENTRY),HistoryDealGetInteger(t,DEAL_REASON),DoubleToString(HistoryDealGetDouble(t,DEAL_VOLUME),8),DoubleToString(HistoryDealGetDouble(t,DEAL_PRICE),10),DoubleToString(HistoryDealGetDouble(t,DEAL_PROFIT),8),DoubleToString(HistoryDealGetDouble(t,DEAL_COMMISSION),8),DoubleToString(HistoryDealGetDouble(t,DEAL_SWAP),8),DoubleToString(HistoryDealGetDouble(t,DEAL_FEE),8),DoubleToString(HistoryDealGetDouble(t,DEAL_SL),10),DoubleToString(HistoryDealGetDouble(t,DEAL_TP),10),HistoryDealGetString(t,DEAL_COMMENT));
     }
   FileWrite(o,"ticket","position_id","time_setup","time_done","symbol","magic","type","state","volume_initial","volume_current","price_open","sl","tp","comment");
   for(int i=0;i<HistoryOrdersTotal();i++)
     {
      ulong t=HistoryOrderGetTicket(i);
      FileWrite(o,t,HistoryOrderGetInteger(t,ORDER_POSITION_ID),TimeToString((datetime)HistoryOrderGetInteger(t,ORDER_TIME_SETUP),TIME_DATE|TIME_SECONDS),TimeToString((datetime)HistoryOrderGetInteger(t,ORDER_TIME_DONE),TIME_DATE|TIME_SECONDS),HistoryOrderGetString(t,ORDER_SYMBOL),HistoryOrderGetInteger(t,ORDER_MAGIC),HistoryOrderGetInteger(t,ORDER_TYPE),HistoryOrderGetInteger(t,ORDER_STATE),DoubleToString(HistoryOrderGetDouble(t,ORDER_VOLUME_INITIAL),8),DoubleToString(HistoryOrderGetDouble(t,ORDER_VOLUME_CURRENT),8),DoubleToString(HistoryOrderGetDouble(t,ORDER_PRICE_OPEN),10),DoubleToString(HistoryOrderGetDouble(t,ORDER_SL),10),DoubleToString(HistoryOrderGetDouble(t,ORDER_TP),10),HistoryOrderGetString(t,ORDER_COMMENT));
     }
   FileClose(d);FileClose(o);Done("COMPLETE");
  }
void Paths()
  {
   int requests=FileOpen(ROOT+RequestFilename,FILE_READ|FILE_CSV|FILE_ANSI|FILE_COMMON,',');
   if(requests==INVALID_HANDLE){Done("REQUESTS_MISSING");return;}
   int summary=FileOpen(ROOT+"path-coverage"+ExportSuffix+".csv",FILE_WRITE|FILE_CSV|FILE_ANSI|FILE_COMMON,',');
   if(summary==INVALID_HANDLE){FileClose(requests);Done("FILE_ERROR");return;}
   FileWrite(summary,"case_id","symbol","requested_from","requested_to","ticks","first_msc","last_msc","error");
   int specs=FileOpen(ROOT+"symbol-specifications"+ExportSuffix+".csv",FILE_WRITE|FILE_CSV|FILE_ANSI|FILE_COMMON,',');
   int chunks=FileOpen(ROOT+"path-chunks"+ExportSuffix+".csv",FILE_WRITE|FILE_CSV|FILE_ANSI|FILE_COMMON,',');
   if(specs==INVALID_HANDLE || chunks==INVALID_HANDLE){FileClose(requests);FileClose(summary);if(specs!=INVALID_HANDLE)FileClose(specs);if(chunks!=INVALID_HANDLE)FileClose(chunks);Done("FILE_ERROR");return;}
   FileWrite(specs,"symbol","volume_min","volume_max","volume_step","point","tick_size","contract_size","profit_currency","base_currency","stop_level_points","captured_server");
   FileWrite(chunks,"case_id","from_msc","to_msc","copied","error");
   for(int i=0;i<4;i++)FileReadString(requests);
   while(!FileIsEnding(requests))
     {
      string id=FileReadString(requests),symbol=FileReadString(requests),from=FileReadString(requests),to=FileReadString(requests);
      if(id=="" || symbol=="")continue;
      if(StringFind(id,"..")>=0 || StringFind(id,"/")>=0 || StringFind(id,"\\")>=0){FileClose(requests);FileClose(summary);Done("INVALID_CASE_ID");return;}
      int out=FileOpen(ROOT+"ticks-"+id+".csv",FILE_WRITE|FILE_CSV|FILE_ANSI|FILE_COMMON,',');
      if(out==INVALID_HANDLE)continue;
      SymbolSelect(symbol,true);
      FileWrite(specs,symbol,SymbolInfoDouble(symbol,SYMBOL_VOLUME_MIN),SymbolInfoDouble(symbol,SYMBOL_VOLUME_MAX),SymbolInfoDouble(symbol,SYMBOL_VOLUME_STEP),SymbolInfoDouble(symbol,SYMBOL_POINT),SymbolInfoDouble(symbol,SYMBOL_TRADE_TICK_SIZE),SymbolInfoDouble(symbol,SYMBOL_TRADE_CONTRACT_SIZE),SymbolInfoString(symbol,SYMBOL_CURRENCY_PROFIT),SymbolInfoString(symbol,SYMBOL_CURRENCY_BASE),SymbolInfoInteger(symbol,SYMBOL_TRADE_STOPS_LEVEL),TimeToString(TimeCurrent(),TIME_DATE|TIME_SECONDS));FileFlush(specs);
      FileWrite(out,"time_msc","bid","ask");
      ulong begin=(ulong)StringToTime(from)*1000,end=(ulong)StringToTime(to)*1000+999;
      ulong now=(ulong)TimeCurrent()*1000;end=end<now?end:now;
      long total=0,first=0,last=0;int err=0;
      if(SymbolSelect(symbol,true)) for(ulong start=begin;start<=end;)
        {
         ulong candidate_stop=start+900000-1;ulong stop=end<candidate_stop?end:candidate_stop;MqlTick ticks[];ResetLastError();
         int n=CopyTicksRange(symbol,ticks,COPY_TICKS_ALL,start,stop);err=GetLastError();
         if(n<0){Sleep(1000);ResetLastError();n=CopyTicksRange(symbol,ticks,COPY_TICKS_ALL,start,stop);err=GetLastError();}
         FileWrite(chunks,id,start,stop,n,err);FileFlush(chunks);
         for(int j=0;j<n;j++)if(ticks[j].bid>0 && ticks[j].ask>=ticks[j].bid)
           {
            FileWrite(out,ticks[j].time_msc,DoubleToString(ticks[j].bid,10),DoubleToString(ticks[j].ask,10));
            if(total==0)first=ticks[j].time_msc;last=ticks[j].time_msc;total++;
           }
         start=stop+1;
        }
      FileClose(out);FileWrite(summary,id,symbol,from,to,total,first,last,err);FileFlush(summary);
     }
   FileClose(requests);FileClose(summary);FileClose(specs);FileClose(chunks);Done("COMPLETE");
  }
void OnTimer()
  {
   if(ran)return;
   if(!TerminalInfoInteger(TERMINAL_CONNECTED) || AccountInfoInteger(ACCOUNT_LOGIN)!=7404213 || AccountInfoString(ACCOUNT_SERVER)!="FPMarketsSC-Demo")
     {if(++attempts>=60){ran=true;Done("ACCOUNT_CONNECTION_UNAVAILABLE");}return;}
   ran=true;if(ExportPaths)Paths();else History();
  }
