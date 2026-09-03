#property strict
#property version "1.000"
#property description "Read-only FP cached-tick to M1 research exporter; contains no trading operations"

input string OutputTag="v202-20260831-20260903";
input bool ConnectedHistoricalReadOnly=false;
input bool CloseIsolatedTerminalWhenDone=false;

struct ResearchCase
  {
   string name;
   string symbol;
   string direction;
   string admission_broker_time;
  };

bool g_ran=false;

void WriteBar(const int handle,const ResearchCase &probe,const datetime minute,
              const double bid_open,const double bid_high,const double bid_low,const double bid_close,
              const double ask_open,const double ask_high,const double ask_low,const double ask_close,
              const double spread_min,const double spread_max,const double spread_sum,const long ticks)
  {
   datetime entry=StringToTime(probe.admission_broker_time);
   FileWrite(handle,"SOLTRADE_FP_M1_TICK_BACKFILL_V1",probe.name,probe.symbol,probe.direction,
             probe.admission_broker_time,TimeToString(minute,TIME_DATE|TIME_MINUTES),(long)(minute-entry)/60,
             DoubleToString(bid_open,10),DoubleToString(bid_high,10),DoubleToString(bid_low,10),DoubleToString(bid_close,10),
             DoubleToString(ask_open,10),DoubleToString(ask_high,10),DoubleToString(ask_low,10),DoubleToString(ask_close,10),
             DoubleToString(spread_min,10),DoubleToString(spread_max,10),DoubleToString(ticks>0?spread_sum/ticks:0,10),ticks);
  }

void RunCase(const ResearchCase &probe,const int bar_handle,const int summary_handle)
  {
   ResetLastError();
   if(!SymbolSelect(probe.symbol,true))
     {
      FileWrite(summary_handle,"SOLTRADE_FP_M1_TICK_BACKFILL_SUMMARY_V1",probe.name,probe.symbol,
                probe.direction,probe.admission_broker_time,0,0,"SYMBOL_SELECT_FAILED",GetLastError());
      return;
     }

   datetime entry=StringToTime(probe.admission_broker_time);
   // Three hours supplies the 30 completed M1 bars and 20 completed M5 bars
   // required by the production feature definitions without look-ahead.
   ulong from_msc=(ulong)((long)entry-10800)*1000;
   ulong to_msc=(ulong)((long)entry+1800)*1000+999;
   MqlTick source[];
   int copied=CopyTicksRange(probe.symbol,source,COPY_TICKS_ALL,from_msc,to_msc);
   for(int attempt=1;copied<=0 && attempt<=3;attempt++)
     {
      Sleep(2000);
      ResetLastError();
      copied=CopyTicksRange(probe.symbol,source,COPY_TICKS_ALL,from_msc,to_msc);
     }
   if(copied<=0)
     {
      FileWrite(summary_handle,"SOLTRADE_FP_M1_TICK_BACKFILL_SUMMARY_V1",probe.name,probe.symbol,
                probe.direction,probe.admission_broker_time,copied,0,"COPY_TICKS_FAILED",GetLastError());
      return;
     }

   datetime minute=0;
   double bid_open=0,bid_high=0,bid_low=0,bid_close=0;
   double ask_open=0,ask_high=0,ask_low=0,ask_close=0;
   double spread_min=DBL_MAX,spread_max=0,spread_sum=0;
   long minute_ticks=0,total_bars=0;
   for(int i=0;i<copied;i++)
     {
      if(source[i].bid<=0 || source[i].ask<=0) continue;
      datetime tick_minute=(datetime)(((long)source[i].time/60)*60);
      if(minute!=0 && tick_minute!=minute)
        {
         WriteBar(bar_handle,probe,minute,bid_open,bid_high,bid_low,bid_close,
                  ask_open,ask_high,ask_low,ask_close,spread_min,spread_max,spread_sum,minute_ticks);
         total_bars++;
         minute=0;
        }
      const double spread=source[i].ask-source[i].bid;
      if(minute==0)
        {
         minute=tick_minute;
         bid_open=bid_high=bid_low=bid_close=source[i].bid;
         ask_open=ask_high=ask_low=ask_close=source[i].ask;
         spread_min=spread_max=spread;
         spread_sum=spread;
         minute_ticks=1;
        }
      else
        {
         bid_high=MathMax(bid_high,source[i].bid);
         bid_low=MathMin(bid_low,source[i].bid);
         bid_close=source[i].bid;
         ask_high=MathMax(ask_high,source[i].ask);
         ask_low=MathMin(ask_low,source[i].ask);
         ask_close=source[i].ask;
         spread_min=MathMin(spread_min,spread);
         spread_max=MathMax(spread_max,spread);
         spread_sum+=spread;
         minute_ticks++;
        }
     }
   if(minute!=0)
     {
      WriteBar(bar_handle,probe,minute,bid_open,bid_high,bid_low,bid_close,
               ask_open,ask_high,ask_low,ask_close,spread_min,spread_max,spread_sum,minute_ticks);
      total_bars++;
     }
   FileWrite(summary_handle,"SOLTRADE_FP_M1_TICK_BACKFILL_SUMMARY_V1",probe.name,probe.symbol,
             probe.direction,probe.admission_broker_time,copied,total_bars,"PASS",0);
  }

int OnInit()
  {
   if((bool)MQLInfoInteger(MQL_OPTIMIZATION) || (bool)MQLInfoInteger(MQL_TESTER)) return INIT_FAILED;
   if(!ConnectedHistoricalReadOnly) return INIT_FAILED;
   // This executable has no trade API imports or calls. The harness also runs
   // with AllowLiveTrading=0 and in a network namespace with no interfaces.
   EventSetTimer(1);
   return INIT_SUCCEEDED;
  }

void OnDeinit(const int reason) { EventKillTimer(); }

void RunOnce()
  {
   if(g_ran) return;
   g_ran=true;
   string bars_path="SolTradeV202M1Backfill\\"+OutputTag+"-bars.csv";
   string summary_path="SolTradeV202M1Backfill\\"+OutputTag+"-summary.csv";
   int bars=FileOpen(bars_path,FILE_WRITE|FILE_CSV|FILE_ANSI|FILE_COMMON,',');
   int summary=FileOpen(summary_path,FILE_WRITE|FILE_CSV|FILE_ANSI|FILE_COMMON,',');
   if(bars==INVALID_HANDLE || summary==INVALID_HANDLE) return;
   FileWrite(bars,"schema","case","symbol","direction","admission_broker_time","bar_broker_time","relative_minute",
             "bid_open","bid_high","bid_low","bid_close","ask_open","ask_high","ask_low","ask_close",
             "spread_min","spread_max","spread_mean","tick_count");
   FileWrite(summary,"schema","case","symbol","direction","admission_broker_time","ticks_copied","bars_written","status","error");

   ResearchCase probes[16];
   probes[0].name="20260831_US100_SELL"; probes[0].symbol="US100"; probes[0].direction="SELL"; probes[0].admission_broker_time="2026.08.31 03:13:40";
   probes[1].name="20260831_XAUUSD_SELL"; probes[1].symbol="XAUUSD.r"; probes[1].direction="SELL"; probes[1].admission_broker_time="2026.08.31 05:54:30";
   probes[2].name="20260831_GER40_BUY"; probes[2].symbol="GER40"; probes[2].direction="BUY"; probes[2].admission_broker_time="2026.08.31 09:02:20";
   probes[3].name="20260831_EURUSD_BUY"; probes[3].symbol="EURUSD.r"; probes[3].direction="BUY"; probes[3].admission_broker_time="2026.08.31 11:17:10";
   probes[4].name="20260831_GER40_SELL_1"; probes[4].symbol="GER40"; probes[4].direction="SELL"; probes[4].admission_broker_time="2026.08.31 18:06:30";
   probes[5].name="20260831_GER40_SELL_2"; probes[5].symbol="GER40"; probes[5].direction="SELL"; probes[5].admission_broker_time="2026.08.31 20:49:10";
   probes[6].name="20260901_XAUUSD_SELL_1"; probes[6].symbol="XAUUSD.r"; probes[6].direction="SELL"; probes[6].admission_broker_time="2026.09.01 13:20:40";
   probes[7].name="20260901_GER40_SELL_1"; probes[7].symbol="GER40"; probes[7].direction="SELL"; probes[7].admission_broker_time="2026.09.01 13:21:30";
   probes[8].name="20260901_US100_SELL"; probes[8].symbol="US100"; probes[8].direction="SELL"; probes[8].admission_broker_time="2026.09.01 13:22:10";
   probes[9].name="20260901_XAUUSD_SELL_2"; probes[9].symbol="XAUUSD.r"; probes[9].direction="SELL"; probes[9].admission_broker_time="2026.09.01 16:35:50";
   probes[10].name="20260901_XAUUSD_SELL_3"; probes[10].symbol="XAUUSD.r"; probes[10].direction="SELL"; probes[10].admission_broker_time="2026.09.01 21:25:40";
   probes[11].name="20260901_GER40_SELL_2"; probes[11].symbol="GER40"; probes[11].direction="SELL"; probes[11].admission_broker_time="2026.09.01 22:04:10";
   probes[12].name="20260902_GBPJPY_SELL"; probes[12].symbol="GBPJPY.r"; probes[12].direction="SELL"; probes[12].admission_broker_time="2026.09.02 10:13:30";
   probes[13].name="20260902_EURJPY_SELL"; probes[13].symbol="EURJPY.r"; probes[13].direction="SELL"; probes[13].admission_broker_time="2026.09.02 10:16:50";
   probes[14].name="20260902_US500_BUY_REFERENCE"; probes[14].symbol="US500"; probes[14].direction="BUY"; probes[14].admission_broker_time="2026.09.02 18:00:42";
   probes[15].name="20260903_USDJPY_SELL"; probes[15].symbol="USDJPY.r"; probes[15].direction="SELL"; probes[15].admission_broker_time="2026.09.03 04:58:20";

   for(int i=0;i<ArraySize(probes);i++) RunCase(probes[i],bars,summary);
   FileFlush(bars); FileFlush(summary); FileClose(bars); FileClose(summary);
   Print("SOLTRADE_FP_M1_BACKFILL_COMPLETE bars=",bars_path," summary=",summary_path," orders_sent=0");
   if(CloseIsolatedTerminalWhenDone) TerminalClose(0);
  }

void OnTick() { RunOnce(); }
void OnTimer() { RunOnce(); }
