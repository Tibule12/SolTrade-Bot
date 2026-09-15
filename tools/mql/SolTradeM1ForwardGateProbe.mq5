#property strict
#property version "1.000"
#property description "Read-only completed-M1 exporter for the locked forward timing gate; no trading operations"

input string OutputTag="fp-forward-gate-20260908-20260915";
input bool ConnectedHistoricalReadOnly=false;
input bool CloseIsolatedTerminalWhenDone=true;

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
   FileWrite(handle,"SOLTRADE_FP_M1_FORWARD_GATE_V1",probe.name,probe.symbol,probe.direction,
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
      FileWrite(summary_handle,"SOLTRADE_FP_M1_FORWARD_GATE_SUMMARY_V1",probe.name,probe.symbol,
                probe.direction,probe.admission_broker_time,0,0,"SYMBOL_SELECT_FAILED",GetLastError());
      return;
     }

   datetime entry=StringToTime(probe.admission_broker_time);
   // Eight hours supplies enough completed M1 bars to reconstruct the locked
   // M1 rule and the production M5/M15 setup family without look-ahead.
   ulong from_msc=(ulong)((long)entry-28800)*1000;
   ulong to_msc=(ulong)((long)entry+1800)*1000+999;
   MqlTick source[];
   ResetLastError();
   int copied=CopyTicksRange(probe.symbol,source,COPY_TICKS_ALL,from_msc,to_msc);
   if(copied<=0)
     {
      FileWrite(summary_handle,"SOLTRADE_FP_M1_FORWARD_GATE_SUMMARY_V1",probe.name,probe.symbol,
                probe.direction,probe.admission_broker_time,copied,0,"COPY_TICKS_FAILED",GetLastError());
      return;
     }

   datetime minute=0;
   double bid_open=0,bid_high=0,bid_low=0,bid_close=0;
   double ask_open=0,ask_high=0,ask_low=0,ask_close=0;
   double spread_min=0,spread_max=0,spread_sum=0;
   long minute_ticks=0,total_bars=0;
   for(int i=0;i<copied;i++)
     {
      if(source[i].bid<=0 || source[i].ask<=source[i].bid) continue;
      datetime tick_minute=(datetime)((long)(source[i].time/60)*60);
      double spread=source[i].ask-source[i].bid;
      if(minute!=tick_minute)
        {
         if(minute!=0)
           {
            WriteBar(bar_handle,probe,minute,bid_open,bid_high,bid_low,bid_close,
                     ask_open,ask_high,ask_low,ask_close,spread_min,spread_max,spread_sum,minute_ticks);
            total_bars++;
           }
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
   FileWrite(summary_handle,"SOLTRADE_FP_M1_FORWARD_GATE_SUMMARY_V1",probe.name,probe.symbol,
             probe.direction,probe.admission_broker_time,copied,total_bars,"PASS",0);
  }

int OnInit()
  {
   if((bool)MQLInfoInteger(MQL_OPTIMIZATION) || (bool)MQLInfoInteger(MQL_TESTER)) return INIT_FAILED;
   if(!ConnectedHistoricalReadOnly) return INIT_FAILED;
   EventSetTimer(1);
   return INIT_SUCCEEDED;
  }

void OnDeinit(const int reason) { EventKillTimer(); }

void RunOnce()
  {
   if(g_ran) return;
   g_ran=true;
   string bars_path="SolTradeM1ForwardGate\\"+OutputTag+"-bars.csv";
   string summary_path="SolTradeM1ForwardGate\\"+OutputTag+"-summary.csv";
   int bars=FileOpen(bars_path,FILE_WRITE|FILE_CSV|FILE_ANSI|FILE_COMMON,',');
   int summary=FileOpen(summary_path,FILE_WRITE|FILE_CSV|FILE_ANSI|FILE_COMMON,',');
   if(bars==INVALID_HANDLE || summary==INVALID_HANDLE) return;
   FileWrite(bars,"schema","case","symbol","direction","admission_broker_time","bar_broker_time","relative_minute",
             "bid_open","bid_high","bid_low","bid_close","ask_open","ask_high","ask_low","ask_close",
             "spread_min","spread_max","spread_mean","tick_count");
   FileWrite(summary,"schema","case","symbol","direction","admission_broker_time","ticks_copied","bars_written","status","error");

   ResearchCase probes[10];
   probes[0].name="20260908_AUDJPY_SELL"; probes[0].symbol="AUDJPY.r"; probes[0].direction="SELL"; probes[0].admission_broker_time="2026.09.08 05:53:40";
   probes[1].name="20260908_NZDUSD_SELL"; probes[1].symbol="NZDUSD.r"; probes[1].direction="SELL"; probes[1].admission_broker_time="2026.09.08 11:19:20";
   probes[2].name="20260908_GER40_SELL"; probes[2].symbol="GER40"; probes[2].direction="SELL"; probes[2].admission_broker_time="2026.09.08 11:50:30";
   probes[3].name="20260909_USDJPY_SELL"; probes[3].symbol="USDJPY.r"; probes[3].direction="SELL"; probes[3].admission_broker_time="2026.09.09 03:32:30";
   probes[4].name="20260909_XAUUSD_BUY"; probes[4].symbol="XAUUSD.r"; probes[4].direction="BUY"; probes[4].admission_broker_time="2026.09.09 09:28:41";
   probes[5].name="20260909_GER40_SELL"; probes[5].symbol="GER40"; probes[5].direction="SELL"; probes[5].admission_broker_time="2026.09.09 14:07:20";
   probes[6].name="20260914_XAUUSD_SELL"; probes[6].symbol="XAUUSD.r"; probes[6].direction="SELL"; probes[6].admission_broker_time="2026.09.14 16:38:51";
   probes[7].name="20260914_USDJPY_SELL"; probes[7].symbol="USDJPY.r"; probes[7].direction="SELL"; probes[7].admission_broker_time="2026.09.14 22:20:30";
   probes[8].name="20260915_US100_SELL"; probes[8].symbol="US100"; probes[8].direction="SELL"; probes[8].admission_broker_time="2026.09.15 08:40:40";
   probes[9].name="20260915_GER40_SELL"; probes[9].symbol="GER40"; probes[9].direction="SELL"; probes[9].admission_broker_time="2026.09.15 11:21:00";

   for(int i=0;i<ArraySize(probes);i++) RunCase(probes[i],bars,summary);
   FileFlush(bars); FileFlush(summary); FileClose(bars); FileClose(summary);
   Print("SOLTRADE_FP_M1_FORWARD_GATE_COMPLETE bars=",bars_path," summary=",summary_path," orders_sent=0");
   if(CloseIsolatedTerminalWhenDone) TerminalClose(0);
  }

void OnTick() { RunOnce(); }
void OnTimer() { RunOnce(); }
