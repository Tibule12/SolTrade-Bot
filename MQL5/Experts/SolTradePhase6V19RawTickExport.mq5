#property strict
#property version "1.000"
#property description "Inert V19 qualified real-tick exporter; no strategy or trade calls"

const string SERVER="FPMarketsSC-Demo";
const datetime START=D'2026.01.02 00:00:00';
const datetime END=D'2026.08.01 00:00:00';
const string FILE_NAME="SolTradePhase6V19RawTicks.csv";
long g_transactions=0;

string TS(const ulong msc)
  {
   return TimeToString((datetime)(msc/1000),TIME_DATE|TIME_SECONDS)+"."+StringFormat("%03u",(uint)(msc%1000));
  }

int OnInit()
  {
   bool safe=!(bool)MQLInfoInteger(MQL_TESTER) &&
             AccountInfoInteger(ACCOUNT_TRADE_MODE)==ACCOUNT_TRADE_MODE_DEMO &&
             AccountInfoString(ACCOUNT_SERVER)==SERVER && _Symbol=="EURUSD" &&
             !(bool)TerminalInfoInteger(TERMINAL_TRADE_ALLOWED) &&
             !(bool)MQLInfoInteger(MQL_TRADE_ALLOWED) &&
             OrdersTotal()==0 && PositionsTotal()==0 && !FileIsExist(FILE_NAME);
   PrintFormat("SOLTRADE_V19_EXPORT_PREFLIGHT | valid=%s | trade_attempted=NO",safe?"YES":"NO");
   if(!safe) return INIT_FAILED;
   int f=FileOpen(FILE_NAME,FILE_WRITE|FILE_TXT|FILE_ANSI);
   if(f==INVALID_HANDLE) return INIT_FAILED;
   FileWriteString(f,"timestamp,bid,ask\n");
   ulong cursor=(ulong)START*1000, finish=(ulong)END*1000, count=0, first=0, last=0;
   long failures=0;
   while(cursor<finish)
     {
      ulong next=((cursor/86400000)+1)*86400000;
      if(next>finish) next=finish;
      MqlTick ticks[];
      ResetLastError();
      int copied=CopyTicksRange("EURUSD",ticks,COPY_TICKS_ALL,cursor,next-1);
      if(copied<0) { failures++; break; }
      for(int i=0;i<copied;i++)
        {
         if(count==0) first=ticks[i].time_msc;
         last=ticks[i].time_msc;
         FileWriteString(f,StringFormat("%s,%.10f,%.10f\n",TS(ticks[i].time_msc),ticks[i].bid,ticks[i].ask));
         count++;
        }
      ArrayFree(ticks);
      cursor=next;
     }
   FileFlush(f); FileClose(f);
   bool pass=count==9259175 && first==(ulong)D'2026.01.02 00:00:00'*1000+1129 && last==(ulong)D'2026.07.31 23:59:59'*1000+143 && failures==0;
   PrintFormat("SOLTRADE_V19_EXPORT_RESULT | status=%s | ticks=%I64u | first=%s | final=%s | failures=%I64d | transactions=%I64d | trade_attempted=NO",pass?"PASS":"FAIL",count,TS(first),TS(last),failures,g_transactions);
   ExpertRemove();
   return pass?INIT_SUCCEEDED:INIT_FAILED;
  }
void OnTick() {}
void OnTradeTransaction(const MqlTradeTransaction &t,const MqlTradeRequest &q,const MqlTradeResult &r) { g_transactions++; }
