#property strict
#property version "1.000"
#property description "No-order V2.202 real-tick scratch boundary probe"

input string OutputTag="v202-20260831";
input bool ConnectedHistoricalReadOnly=false;
input bool CloseIsolatedTerminalWhenDone=false;

struct ProbeCase
  {
   string name;
   string symbol;
   int direction;
   string admission_time;
   double expected_fill;
   double volume;
   double initial_risk;
   double commission_per_lot;
   double point_size;
   double tick_value_loss;
  };

bool g_ran=false;

string BoolText(const bool value) { return value?"true":"false"; }

void WriteSummaryHeader(const int handle)
  {
   FileWrite(handle,"schema","runtime_mode","account","server","case","symbol","direction","requested_admission_broker_time","fill_time_msc","fill_time_broker",
             "fill_price","fill_bid","fill_ask","fill_spread","reference_close","spread_false_trigger",
             "first_adverse_time_msc","first_adverse_time","first_adverse_bid","first_adverse_ask",
             "executable_exit","scratch_exit_time_msc","response_delay_msc","modeled_slippage","commission",
             "gross_pl","net_pl","realized_r","ticks_observed","copy_result","error",
             "raw_fill_reclaim_time_msc","raw_fill_reclaim_time_broker",
             "net_profitable_recovery_time_msc","net_profitable_recovery_time_broker","recovered_net_within_30m");
  }

void WriteTickHeader(const int handle)
  {
   FileWrite(handle,"schema","case","symbol","time_msc","time","bid","ask","spread","reference_close",
             "executable_close","adverse_cross","relative_msc");
  }

void RunCase(const ProbeCase &probe,const int summary_handle,const int tick_handle)
  {
   string runtime_mode=(bool)MQLInfoInteger(MQL_TESTER)?"STRATEGY_TESTER_REAL_TICKS":"CONNECTED_HISTORY_READ_ONLY";
   long account=(long)AccountInfoInteger(ACCOUNT_LOGIN);
   string server=AccountInfoString(ACCOUNT_SERVER);
   if(!SymbolSelect(probe.symbol,true))
     {
      FileWrite(summary_handle,"SOLTRADE_V202_REAL_TICK_SCRATCH_V1",runtime_mode,account,server,probe.name,probe.symbol,
                probe.direction>0?"BUY":"SELL",probe.admission_time,0,"",0,0,0,0,0,"",0,"",0,0,0,0,0,0,0,0,0,0,0,
                "SYMBOL_SELECT_FAILED",GetLastError());
      return;
     }
   datetime requested=StringToTime(probe.admission_time);
   ulong from_msc=(ulong)MathMax(0,(long)requested-5)*1000;
   ulong to_msc=(ulong)((long)requested+1800)*1000+999;
   MqlTick ticks[];
   int copied=CopyTicksRange(probe.symbol,ticks,COPY_TICKS_ALL,from_msc,to_msc);
   double point=SymbolInfoDouble(probe.symbol,SYMBOL_POINT);
   if(copied<=0 || point<=0)
     {
      FileWrite(summary_handle,"SOLTRADE_V202_REAL_TICK_SCRATCH_V1",runtime_mode,account,server,probe.name,probe.symbol,
                probe.direction>0?"BUY":"SELL",probe.admission_time,0,"",0,0,0,0,0,"",0,"",0,0,0,0,0,0,0,0,0,0,0,
                "COPY_TICKS_FAILED",GetLastError());
      return;
     }

   int fill_index=-1;
   long requested_msc=(long)requested*1000;
   long best_distance=LONG_MAX;
   for(int i=0;i<copied;i++)
     {
      if(ticks[i].bid<=0 || ticks[i].ask<=0) continue;
      double executable_fill=probe.direction>0?ticks[i].ask:ticks[i].bid;
      if(MathAbs(executable_fill-probe.expected_fill)>0.5*point+1e-12) continue;
      long distance=(long)MathAbs((double)((long)ticks[i].time_msc-requested_msc));
      if(distance<best_distance) { best_distance=distance; fill_index=i; }
     }
   if(fill_index<0)
     {
      FileWrite(summary_handle,"SOLTRADE_V202_REAL_TICK_SCRATCH_V1",runtime_mode,account,server,probe.name,probe.symbol,
                probe.direction>0?"BUY":"SELL",probe.admission_time,0,"",0,0,0,0,0,"",0,"",0,0,0,0,0,0,0,0,0,0,0,copied,
                "EXPECTED_EXECUTABLE_FILL_TICK_NOT_FOUND",GetLastError());
      return;
     }

   MqlTick fill_tick=ticks[fill_index];
   double fill=probe.direction>0?fill_tick.ask:fill_tick.bid;
   double reference_close=probe.direction>0?fill_tick.bid:fill_tick.ask;
   double fill_spread=fill_tick.ask-fill_tick.bid;
   double fill_executable_close=probe.direction>0?fill_tick.bid:fill_tick.ask;
   bool false_trigger=probe.direction>0?fill_executable_close<reference_close:fill_executable_close>reference_close;
   int observed=0,trigger_index=-1;
   for(int i=fill_index;i<copied;i++)
     {
      double executable_close=probe.direction>0?ticks[i].bid:ticks[i].ask;
      bool adverse=probe.direction>0?executable_close<reference_close:executable_close>reference_close;
      FileWrite(tick_handle,"SOLTRADE_V202_REAL_TICK_SCRATCH_TICK_V1",probe.name,probe.symbol,
                ticks[i].time_msc,TimeToString(ticks[i].time,TIME_DATE|TIME_SECONDS),
                DoubleToString(ticks[i].bid,(int)SymbolInfoInteger(probe.symbol,SYMBOL_DIGITS)),
                DoubleToString(ticks[i].ask,(int)SymbolInfoInteger(probe.symbol,SYMBOL_DIGITS)),
                DoubleToString(ticks[i].ask-ticks[i].bid,10),DoubleToString(reference_close,10),
                DoubleToString(executable_close,10),BoolText(adverse),(long)ticks[i].time_msc-(long)fill_tick.time_msc);
      observed++;
      if(i>fill_index && adverse) { trigger_index=i; break; }
     }

   if(trigger_index<0)
     {
      FileWrite(summary_handle,"SOLTRADE_V202_REAL_TICK_SCRATCH_V1",runtime_mode,account,server,probe.name,probe.symbol,
                probe.direction>0?"BUY":"SELL",probe.admission_time,fill_tick.time_msc,
                TimeToString(fill_tick.time,TIME_DATE|TIME_SECONDS),DoubleToString(fill,10),
                DoubleToString(fill_tick.bid,10),DoubleToString(fill_tick.ask,10),DoubleToString(fill_spread,10),
                DoubleToString(reference_close,10),BoolText(false_trigger),0,"",0,0,0,0,0,0,0,0,0,0,observed,
                "NO_ADVERSE_CROSS_IN_30_MINUTES",0);
      return;
     }

   MqlTick trigger=ticks[trigger_index];
   double exit_price=probe.direction>0?trigger.bid:trigger.ask;
   bool profit_ok=probe.point_size>0 && probe.tick_value_loss>0;
   double gross=profit_ok?probe.direction*(exit_price-fill)/probe.point_size*probe.volume*probe.tick_value_loss:0;
   double commission=probe.commission_per_lot*probe.volume;
   double net=profit_ok?gross-commission:0;
   double realized_r=profit_ok && probe.initial_risk>0?net/probe.initial_risk:0;
   ulong raw_reclaim_msc=0,net_recovery_msc=0;
   for(int i=trigger_index+1;i<copied;i++)
     {
      double future_exit=probe.direction>0?ticks[i].bid:ticks[i].ask;
      double future_gross=probe.direction*(future_exit-fill)/probe.point_size*probe.volume*probe.tick_value_loss;
      if(raw_reclaim_msc==0 && probe.direction*(future_exit-fill)>0) raw_reclaim_msc=ticks[i].time_msc;
      if(net_recovery_msc==0 && future_gross-commission>0) net_recovery_msc=ticks[i].time_msc;
      if(raw_reclaim_msc>0 && net_recovery_msc>0) break;
     }
   FileWrite(summary_handle,"SOLTRADE_V202_REAL_TICK_SCRATCH_V1",runtime_mode,account,server,probe.name,probe.symbol,
             probe.direction>0?"BUY":"SELL",probe.admission_time,fill_tick.time_msc,
             TimeToString(fill_tick.time,TIME_DATE|TIME_SECONDS),DoubleToString(fill,10),
             DoubleToString(fill_tick.bid,10),DoubleToString(fill_tick.ask,10),DoubleToString(fill_spread,10),
             DoubleToString(reference_close,10),BoolText(false_trigger),trigger.time_msc,
             TimeToString(trigger.time,TIME_DATE|TIME_SECONDS),DoubleToString(trigger.bid,10),DoubleToString(trigger.ask,10),
             DoubleToString(exit_price,10),trigger.time_msc,0,0.0,DoubleToString(commission,2),
             DoubleToString(gross,2),DoubleToString(net,2),DoubleToString(realized_r,8),observed,
             profit_ok?"REAL_TICKS_FP_SYMBOL_SPEC_MODEL":"FP_SYMBOL_SPEC_MODEL_FAILED",profit_ok?0:GetLastError(),
             raw_reclaim_msc,raw_reclaim_msc>0?TimeToString((datetime)(raw_reclaim_msc/1000),TIME_DATE|TIME_SECONDS):"",
             net_recovery_msc,net_recovery_msc>0?TimeToString((datetime)(net_recovery_msc/1000),TIME_DATE|TIME_SECONDS):"",
             BoolText(net_recovery_msc>0));
  }

int OnInit()
  {
   if((bool)MQLInfoInteger(MQL_OPTIMIZATION)) return INIT_FAILED;
   if(!(bool)MQLInfoInteger(MQL_TESTER))
     {
      if(!ConnectedHistoricalReadOnly) return INIT_FAILED;
      if((long)AccountInfoInteger(ACCOUNT_LOGIN)!=7404213) return INIT_FAILED;
      if(AccountInfoString(ACCOUNT_SERVER)!="FPMarketsSC-Demo") return INIT_FAILED;
      EventSetTimer(1);
     }
   return INIT_SUCCEEDED;
  }

void OnDeinit(const int reason) { EventKillTimer(); }

void RunOnce()
  {
   if(g_ran) return;
   if((bool)MQLInfoInteger(MQL_TESTER) && TimeCurrent()<StringToTime("2026.08.31 10:47:10")) return;
   g_ran=true;
   string summary_path="SolTradeV202RealTick\\"+OutputTag+"-summary.csv";
   string ticks_path="SolTradeV202RealTick\\"+OutputTag+"-ticks.csv";
   int summary=FileOpen(summary_path,FILE_WRITE|FILE_CSV|FILE_ANSI|FILE_COMMON,',');
   int tick_log=FileOpen(ticks_path,FILE_WRITE|FILE_CSV|FILE_ANSI|FILE_COMMON,',');
   if(summary==INVALID_HANDLE || tick_log==INVALID_HANDLE) { TesterStop(); return; }
   WriteSummaryHeader(summary); WriteTickHeader(tick_log);
   ProbeCase probes[2];
   probes[0].name="XAUUSD_DELAYED_SELL"; probes[0].symbol="XAUUSD.r"; probes[0].direction=-1;
   // FP's cache is UTC+3 broker time; the audit's SAST stamps are broker time minus one hour.
   probes[0].admission_time="2026.08.31 05:55:30"; probes[0].expected_fill=4417.32;
   probes[0].volume=0.19; probes[0].initial_risk=242.40; probes[0].commission_per_lot=6.0;
   probes[0].point_size=0.01; probes[0].tick_value_loss=1.0;
   probes[1].name="EURUSD_BUY"; probes[1].symbol="EURUSD.r"; probes[1].direction=1;
   probes[1].admission_time="2026.08.31 11:17:10"; probes[1].expected_fill=1.15984;
   probes[1].volume=5.31; probes[1].initial_risk=245.11; probes[1].commission_per_lot=6.0;
   probes[1].point_size=0.00001; probes[1].tick_value_loss=1.0;
   for(int i=0;i<2;i++) RunCase(probes[i],summary,tick_log);
   FileFlush(summary); FileFlush(tick_log); FileClose(summary); FileClose(tick_log);
   Print("SOLTRADE_V202_REAL_TICK_PROBE_COMPLETE summary=",summary_path," ticks=",ticks_path," orders_sent=0");
   if((bool)MQLInfoInteger(MQL_TESTER)) TesterStop();
   else if(CloseIsolatedTerminalWhenDone) TerminalClose(0);
  }

void OnTick() { RunOnce(); }
void OnTimer() { RunOnce(); }
