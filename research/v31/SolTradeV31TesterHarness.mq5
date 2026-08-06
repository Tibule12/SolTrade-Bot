#property strict
#property version "1.100"
#property description "V3.1 tester-only structural state harness; no trade API calls"

input datetime ResetAt=D'2026.01.02 00:00:00';
input datetime EligibleFrom=D'2026.01.16 00:00:00';
input datetime EligibleTo=D'2026.04.09 00:00:00';
input datetime ResearchCutoff=D'2026.08.01 00:00:00';
input string SegmentId="V22";
input string OutputFile="SolTradeV31TesterLedger.csv";
input bool RestoreState=false;
input string StateFile="SolTradeV31State";

struct Bar { datetime t; double o,h,l,c,ema,atr,mean; };
Bar bars[];
int n=0,fh=INVALID_HANDLE,retest=0;
datetime last_hour=0,setup_t=0,entry_t=0,last_processed=0;
int setup_dir=0,pos_dir=0;
double boundary=0,stop_level=0;
long seq=0,transactions=0,orders_before=0,positions_before=0,deals_before=0;
bool invalid=false;
datetime max_tick=0,max_bar=0;
datetime current_tick_time=0;
ulong current_tick_msc=0;
datetime confirmation_t=0;
double setup_close=0,setup_ema=0,setup_atr=0;
int spread_decision=0;
string final_status="INITIAL";

void Persist()
  {
   int h=FileOpen(StateFile+"-"+SegmentId+".csv",FILE_WRITE|FILE_CSV|FILE_COMMON,',');if(h==INVALID_HANDLE){invalid=true;return;}
   FileWrite(h,"TREND_BREAKOUT_V3_RETEST_HOLD_1_1",SegmentId,setup_dir,DoubleToString(boundary,12),setup_t,DoubleToString(setup_close,12),DoubleToString(setup_ema,12),DoubleToString(setup_atr,12),retest,last_processed,confirmation_t,spread_decision,pos_dir,entry_t,DoubleToString(stop_level,12),final_status);
   FileFlush(h);FileClose(h);
  }
bool Restore()
  {
   int h=FileOpen(StateFile+"-"+SegmentId+".csv",FILE_READ|FILE_CSV|FILE_COMMON,',');if(h==INVALID_HANDLE)return false;
   string version=FileReadString(h),segment=FileReadString(h);if(version!="TREND_BREAKOUT_V3_RETEST_HOLD_1_1" || segment!=SegmentId){FileClose(h);return false;}
   setup_dir=(int)FileReadNumber(h);boundary=FileReadNumber(h);setup_t=(datetime)FileReadNumber(h);setup_close=FileReadNumber(h);setup_ema=FileReadNumber(h);setup_atr=FileReadNumber(h);retest=(int)FileReadNumber(h);last_processed=(datetime)FileReadNumber(h);confirmation_t=(datetime)FileReadNumber(h);spread_decision=(int)FileReadNumber(h);pos_dir=(int)FileReadNumber(h);entry_t=(datetime)FileReadNumber(h);stop_level=FileReadNumber(h);final_status=FileReadString(h);FileClose(h);return true;
  }

string T(datetime x){string base=TimeToString(x,TIME_DATE|TIME_SECONDS);if(x==current_tick_time && current_tick_msc>0)return base+"."+StringFormat("%03u",(uint)(current_tick_msc%1000));return base+".000";}
void Event(string ev,datetime when,int dir=0,string cancel="",int rn=0,datetime confirm=0,datetime entry=0,double stop=0,string exit_type="",double bid=0,double ask=0,double atr=0,double limit=0)
  {
   seq++;
   FileWrite(fh,seq,ev,T(when),SegmentId,dir>0?"BUY":dir<0?"SELL":"",setup_t>0?T(setup_t):"",DoubleToString(boundary,10),rn,confirm>0?T(confirm):"",entry>0?T(entry):"",DoubleToString(stop,10),exit_type,cancel,DoubleToString(bid,10),DoubleToString(ask,10),DoubleToString(NormalizeDouble((ask-bid)/_Point,8),8),DoubleToString(atr,12),DoubleToString(limit,12));
  }
bool Regime(Bar &b){return b.atr>0 && b.mean>0 && b.atr/b.mean>=0.5 && b.atr/b.mean<=2.0;}
bool Compute(Bar &b)
  {
   if(n<1)return false;
   if(n==200){double e=0;for(int i=0;i<200;i++)e+=bars[i].c;b.ema=e/200.0;}
   else if(n>200)b.ema=b.c*(2.0/201.0)+bars[n-2].ema*(199.0/201.0);
   if(n==14){double av=0;for(int i=0;i<14;i++){double tr=bars[i].h-bars[i].l;if(i>0)tr=MathMax(tr,MathMax(MathAbs(bars[i].h-bars[i-1].c),MathAbs(bars[i].l-bars[i-1].c)));av+=tr;}b.atr=av/14.0;}
   else if(n>14){double tr=MathMax(b.h-b.l,MathMax(MathAbs(b.h-bars[n-2].c),MathAbs(b.l-bars[n-2].c)));b.atr=(bars[n-2].atr*13.0+tr)/14.0;}
   if(n>=114)
     {
      double sum=0;for(int i=n-101;i<=n-2;i++)sum+=bars[i].atr;b.mean=sum/100.0;
     }
   return true;
  }
int Setup(Bar &b,double &bound)
  {
   if(n<300 || !Regime(b))return 0;double hi=-DBL_MAX,lo=DBL_MAX;
   for(int i=n-21;i<=n-2;i++){hi=MathMax(hi,bars[i].h);lo=MathMin(lo,bars[i].l);}
   if(b.c>hi && b.c>b.ema){bound=hi;return 1;}if(b.c<lo && b.c<b.ema){bound=lo;return -1;}return 0;
  }
void CreateSetup(Bar &b,int d,double bound)
  {setup_dir=d;setup_t=b.t;boundary=bound;setup_close=b.c;setup_ema=b.ema;setup_atr=b.atr;retest=0;spread_decision=0;final_status="ACTIVE_SETUP";Event("SETUP",b.t,d);Persist();}
void Complete(Bar &b,datetime tick_t,double bid,double ask)
  {
   if(b.t<EligibleFrom || b.t>=EligibleTo)return;
   last_processed=b.t;double cand_bound=0;int cand=Setup(b,cand_bound);
   if(pos_dir!=0 && n>=11)
     {
      double hi=-DBL_MAX,lo=DBL_MAX;for(int i=n-11;i<=n-2;i++){hi=MathMax(hi,bars[i].h);lo=MathMin(lo,bars[i].l);}
      bool out=pos_dir>0?b.c<lo:b.c>hi;
      if(out){Event("EXIT",tick_t,pos_dir,"",0,0,entry_t,stop_level,"DONCHIAN_10");pos_dir=0;entry_t=0;stop_level=0;final_status="CYCLE_COMPLETE_DONCHIAN_10";Persist();}
     }
   if(setup_dir!=0)
     {
      retest++;bool touch=setup_dir>0?b.l<=boundary:b.h>=boundary;bool hold=setup_dir>0?b.c>boundary:b.c<boundary;bool emaok=setup_dir>0?b.c>b.ema:b.c<b.ema;
      if(touch && hold && emaok && Regime(b))
        {
         double lim=MathMin(30.0,0.20*b.atr/_Point);confirmation_t=b.t;Event("CONFIRMATION",tick_t,setup_dir,"",retest,b.t,0,0,"",bid,ask,b.atr,lim);
         if(pos_dir!=0){spread_decision=0;final_status="BLOCK_POSITION_ALREADY_OPEN";Event("ENTRY_BLOCK",tick_t,setup_dir,"POSITION_ALREADY_OPEN",retest,b.t,0,0,"",bid,ask,b.atr,lim);}
         else if(bid<=0 || ask<=0){spread_decision=0;final_status="BLOCK_NO_TRADABLE_TICK";Event("ENTRY_BLOCK",tick_t,setup_dir,"NO_TRADABLE_TICK",retest,b.t,0,0,"",bid,ask,b.atr,lim);}
         else if((ask-bid)/_Point>lim){spread_decision=2;final_status="BLOCK_SPREAD";Event("ENTRY_BLOCK",tick_t,setup_dir,"SPREAD",retest,b.t,0,0,"",bid,ask,b.atr,lim);}
         else {spread_decision=1;final_status="THEORETICAL_POSITION_OPEN";pos_dir=setup_dir;entry_t=tick_t;double price=pos_dir>0?ask:bid;stop_level=pos_dir>0?price-2*b.atr:price+2*b.atr;Event("ENTRY",tick_t,pos_dir,"",retest,b.t,entry_t,stop_level,"",bid,ask,b.atr,lim);}
         setup_dir=0;setup_t=0;boundary=0;setup_close=0;setup_ema=0;setup_atr=0;retest=0;Persist();return;
        }
      bool wrong=!emaok;bool opp=cand!=0 && cand!=setup_dir;string reason="";
      if(wrong)reason="WRONG_EMA_SIDE";else if(opp)reason="OPPOSITE_BREAKOUT";else if(retest>=6)reason="EXPIRED_SIX_CANDLES";
      if(reason!=""){int old=setup_dir;Event("CANCEL",tick_t,old,reason,retest);final_status="CANCEL_"+reason;setup_dir=0;setup_t=0;boundary=0;setup_close=0;setup_ema=0;setup_atr=0;retest=0;Persist();if(reason=="OPPOSITE_BREAKOUT"){CreateSetup(b,cand,cand_bound);return;}}
     }
   if(pos_dir==0 && setup_dir==0 && cand!=0)CreateSetup(b,cand,cand_bound);
  }
int OnInit()
  {
   orders_before=OrdersTotal();positions_before=PositionsTotal();HistorySelect(ResetAt,EligibleTo);deals_before=HistoryDealsTotal();
   bool safe=(bool)MQLInfoInteger(MQL_TESTER)&&_Symbol=="EURUSD"&&_Period==PERIOD_H1&&EligibleTo<=ResearchCutoff&&orders_before==0&&positions_before==0;
   if(!safe)return INIT_FAILED;
   fh=FileOpen(OutputFile,FILE_WRITE|FILE_CSV|FILE_COMMON,',');if(fh==INVALID_HANDLE)return INIT_FAILED;
   FileWrite(fh,"sequence","event","timestamp","segment","direction","setup_timestamp","frozen_boundary","retest_candle_number","confirmation_timestamp","entry_timestamp","stop_level","exit_type","cancellation_reason","bid","ask","spread_points","confirmation_atr","effective_spread_limit_points");
   if(RestoreState && !Restore())return INIT_FAILED;if(!RestoreState)Persist();
   return INIT_SUCCEEDED;
  }
void OnTick()
  {
   MqlTick tick;if(!SymbolInfoTick(_Symbol,tick))return;if(tick.time>=ResearchCutoff){invalid=true;return;}
   if(tick.time>=EligibleTo)return;
   max_tick=tick.time;current_tick_time=tick.time;current_tick_msc=tick.time_msc;
   datetime hour=(datetime)(tick.time/3600)*3600;
   if(hour!=last_hour)
     {
      MqlRates rr[];if(CopyRates(_Symbol,PERIOD_H1,1,1,rr)==1 && rr[0].time>=ResetAt && rr[0].time<EligibleTo && rr[0].time!=max_bar)
        {int z=ArraySize(bars);ArrayResize(bars,z+1);bars[z].t=rr[0].time;bars[z].o=rr[0].open;bars[z].h=rr[0].high;bars[z].l=rr[0].low;bars[z].c=rr[0].close;bars[z].ema=0;bars[z].atr=0;bars[z].mean=0;n=z+1;Compute(bars[z]);max_bar=rr[0].time;Complete(bars[z],tick.time,tick.bid,tick.ask);}
      last_hour=hour;
     }
   if(pos_dir!=0){bool hit=pos_dir>0?tick.bid<=stop_level:tick.ask>=stop_level;if(hit){Event("EXIT",tick.time,pos_dir,"",0,0,entry_t,stop_level,"INITIAL_STOP");pos_dir=0;entry_t=0;stop_level=0;final_status="CYCLE_COMPLETE_INITIAL_STOP";Persist();}}
  }
void OnDeinit(const int reason)
  {
   if(pos_dir!=0)Event("OPEN_AT_BOUNDARY",EligibleTo,pos_dir,"",0,0,entry_t,stop_level);
   if(setup_dir!=0)Event("RESET",EligibleTo,setup_dir,"PERIOD_BOUNDARY",retest);
   final_status="SEGMENT_RESET";Persist();
   if(fh!=INVALID_HANDLE){FileFlush(fh);FileClose(fh);}
   HistorySelect(ResetAt,EligibleTo);
   PrintFormat("SOLTRADE_V31_RESULT | segment=%s | events=%I64d | max_tick=%s | max_bar=%s | invalid=%s | orders=%d | positions=%d | deals=%d | transactions=%I64d",SegmentId,seq,T(max_tick),T(max_bar),invalid?"YES":"NO",OrdersTotal(),PositionsTotal(),HistoryDealsTotal(),transactions);
  }
void OnTradeTransaction(const MqlTradeTransaction &t,const MqlTradeRequest &q,const MqlTradeResult &r){transactions++;}
