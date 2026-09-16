#property strict
#property version   "1.000"
#property description "SOLTRADE_BRAIN_COLLECTOR_V1: causal market telemetry only; no order capability"

input bool ObserverConfirmed=false;
input int  TimerMilliseconds=200;
input int  FeatureIntervalSeconds=5;
input int  FlushIntervalSeconds=5;

#define COLLECTOR_SCHEMA "SOLTRADE_BRAIN_TICK_V1"
#define FEATURE_SCHEMA   "SOLTRADE_BRAIN_FEATURE_V1"
#define COLLECTOR_VERSION "1.0.0"
#define SYMBOL_COUNT 19
#define RING_SIZE 2048
const bool ORDER_CAPABILITY=false;

string Root="SolTradeBrainCollectorV1\\";
string Symbols[SYMBOL_COUNT]={"EURUSD.r","GBPUSD.r","USDJPY.r","USDCHF.r","USDCAD.r","AUDUSD.r","NZDUSD.r","EURJPY.r","GBPJPY.r","AUDJPY.r","EURGBP.r","AUDNZD.r","XAUUSD.r","XAGUSD.r","GER40","US100","US500","UK100","EURO50"};
int Groups[SYMBOL_COUNT]={1,1,1,1,1,1,1,1,1,1,1,1,2,2,3,3,3,3,3};
string Currencies[8]={"USD","EUR","GBP","JPY","CHF","CAD","AUD","NZD"};

long LastTickMsc[SYMBOL_COUNT];
ulong Sequences[SYMBOL_COUNT];
double LastBid[SYMBOL_COUNT],LastAsk[SYMBOL_COUNT],LastMid[SYMBOL_COUNT];
double DayOpen[SYMBOL_COUNT],SessionOpen[SYMBOL_COUNT];
int DayKey[SYMBOL_COUNT],SessionKey[SYMBOL_COUNT];
long RingTime[SYMBOL_COUNT][RING_SIZE];
double RingMid[SYMBOL_COUNT][RING_SIZE],RingSpread[SYMBOL_COUNT][RING_SIZE];
int RingDirection[SYMBOL_COUNT][RING_SIZE],RingTradeDirection[SYMBOL_COUNT][RING_SIZE];
int RingHead[SYMBOL_COUNT],RingCount[SYMBOL_COUNT];
int TickHandles[SYMBOL_COUNT];
string TickHour[SYMBOL_COUNT];
long TotalTicks=0,TotalFeatures=0,CopyErrors=0;
int RestartCount=0;
datetime StartedUtc=0,LastFeatureUtc=0,LastFlushUtc=0,LastStateUtc=0,LastCalendarUtc=0;
long ServerOffsetSeconds=0;

bool CalendarAvailable[8];
bool CalendarHasEvent[8];
long CalendarEventUtc[8];
int CalendarImportance[8],CalendarError[8];
string CalendarEventName[8];

struct BarState
  {
   bool ready;
   long end_utc;
   double open,high,low,close,atr,vol_ratio,ret;
   long tick_volume;
   int trend,structure;
  };
BarState M1[SYMBOL_COUNT],M5[SYMBOL_COUNT],M15[SYMBOL_COUNT],H1[SYMBOL_COUNT];

string BoolText(const bool value){return value?"true":"false";}
long UtcNow(){return (long)TimeGMT();}
long OffsetNow()
  {
   long raw=(long)TimeTradeServer()-(long)TimeGMT();
   return (long)MathRound((double)raw/60.0)*60;
  }
string Two(const int value){return StringFormat("%02d",value);}
string DateKey(const datetime utc)
  {
   MqlDateTime d;TimeToStruct(utc,d);
   return StringFormat("%04d%02d%02d",d.year,d.mon,d.day);
  }
string HourKey(const datetime utc)
  {
   MqlDateTime d;TimeToStruct(utc,d);
   return StringFormat("%04d%02d%02d-%02d",d.year,d.mon,d.day,d.hour);
  }
int NumericDayKey(const datetime utc)
  {
   MqlDateTime d;TimeToStruct(utc,d);return d.year*10000+d.mon*100+d.day;
  }
int SessionId(const datetime utc)
  {
   MqlDateTime d;TimeToStruct(utc,d);
   int minute=d.hour*60+d.min;
   if(minute>=420 && minute<720)return 1;       // London
   if(minute>=720 && minute<960)return 2;       // London/New York overlap
   if(minute>=960 && minute<1260)return 3;      // New York
   if(minute<420 || minute>=1320)return 4;      // Asia / rollover span
   return 0;
  }
string SessionName(const int id)
  {
   if(id==1)return "LONDON";if(id==2)return "LONDON_NEWYORK_OVERLAP";
   if(id==3)return "NEW_YORK";if(id==4)return "ASIA";return "OFF_SESSION";
  }
int CurrentSessionKey(const datetime utc){return NumericDayKey(utc)*10+SessionId(utc);}

bool EnsureFolders(const datetime utc)
  {
   string date=DateKey(utc);
   FolderCreate(Root);
   FolderCreate(Root+"raw_ticks");
   FolderCreate(Root+"raw_ticks\\"+date);
   FolderCreate(Root+"features");
   FolderCreate(Root+"features\\"+date);
   FolderCreate(Root+"status");
   return true;
  }

void CloseTickHandle(const int index)
  {
   if(TickHandles[index]!=INVALID_HANDLE){FileFlush(TickHandles[index]);FileClose(TickHandles[index]);}
   TickHandles[index]=INVALID_HANDLE;TickHour[index]="";
  }

int OpenTickHandle(const int index,const datetime utc)
  {
   string hour=HourKey(utc);
   if(TickHandles[index]!=INVALID_HANDLE && TickHour[index]==hour)return TickHandles[index];
   CloseTickHandle(index);EnsureFolders(utc);
   string path=Root+"raw_ticks\\"+DateKey(utc)+"\\"+hour+"-"+Symbols[index]+".csv";
   bool exists=FileIsExist(path);
   int h=FileOpen(path,FILE_READ|FILE_WRITE|FILE_CSV|FILE_ANSI|FILE_SHARE_READ|FILE_SHARE_WRITE,',');
   if(h==INVALID_HANDLE)return INVALID_HANDLE;
   if(!exists || FileSize(h)==0)
      FileWrite(h,"schema","collector_version","account","server","symbol","sequence","tick_time_server_msc","tick_time_utc_msc","captured_utc","server_offset_seconds","bid","ask","last","spread_price","spread_points","mid","quote_direction","bid_direction","ask_direction","trade_direction","tick_flags","tick_volume","tick_volume_real","interarrival_ms","source");
   FileSeek(h,0,SEEK_END);TickHandles[index]=h;TickHour[index]=hour;return h;
  }

void AddRing(const int s,const long at,const double mid,const double spread,const int qdir,const int tdir)
  {
   int p=RingHead[s];RingTime[s][p]=at;RingMid[s][p]=mid;RingSpread[s][p]=spread;
   RingDirection[s][p]=qdir;RingTradeDirection[s][p]=tdir;
   RingHead[s]=(p+1)%RING_SIZE;if(RingCount[s]<RING_SIZE)RingCount[s]++;
  }

void WindowStats(const int s,const long now_msc,const int seconds,int &count,double &rate,int &quote_pressure,int &trade_pressure,double &spread_mean,double &mid_change,double &arrival_mean)
  {
   count=0;quote_pressure=0;trade_pressure=0;spread_mean=0;mid_change=0;arrival_mean=0;
   long cutoff=now_msc-(long)seconds*1000,previous=0;double oldest=0,newest=0;int gaps=0;
   for(int k=0;k<RingCount[s];k++)
     {
      int p=(RingHead[s]-1-k+RING_SIZE)%RING_SIZE;long at=RingTime[s][p];if(at<cutoff)break;
      if(count==0)newest=RingMid[s][p];oldest=RingMid[s][p];
      spread_mean+=RingSpread[s][p];quote_pressure+=RingDirection[s][p];trade_pressure+=RingTradeDirection[s][p];
      if(previous>0){arrival_mean+=(double)(previous-at);gaps++;}previous=at;count++;
     }
   rate=(double)count/MathMax(1,seconds);
   if(count>0)spread_mean/=count;
   if(gaps>0)arrival_mean/=gaps;
   mid_change=newest-oldest;
  }

void ProcessTick(const int s,const MqlTick &tick,const int batch_size)
  {
   if(tick.time_msc<=LastTickMsc[s])return;
   double bid=tick.bid,ask=tick.ask;if(bid<=0 || ask<bid)return;
   double mid=(bid+ask)*0.5,spread=ask-bid,point=SymbolInfoDouble(Symbols[s],SYMBOL_POINT);
   int qdir=0,bdir=0,adir=0,tdir=0;
   if(LastMid[s]>0){if(mid>LastMid[s])qdir=1;else if(mid<LastMid[s])qdir=-1;}
   if(LastBid[s]>0){if(bid>LastBid[s])bdir=1;else if(bid<LastBid[s])bdir=-1;}
   if(LastAsk[s]>0){if(ask>LastAsk[s])adir=1;else if(ask<LastAsk[s])adir=-1;}
   if((tick.flags&TICK_FLAG_BUY)!=0)tdir=1;else if((tick.flags&TICK_FLAG_SELL)!=0)tdir=-1;
   long gap=LastTickMsc[s]>0?tick.time_msc-LastTickMsc[s]:0;
   ServerOffsetSeconds=OffsetNow();long utc_msc=tick.time_msc-ServerOffsetSeconds*1000;
   datetime utc=(datetime)(utc_msc/1000);EnsureFolders(utc);
   int h=OpenTickHandle(s,utc);
   Sequences[s]++;
   if(h!=INVALID_HANDLE)
      FileWrite(h,COLLECTOR_SCHEMA,COLLECTOR_VERSION,AccountInfoInteger(ACCOUNT_LOGIN),AccountInfoString(ACCOUNT_SERVER),Symbols[s],Sequences[s],tick.time_msc,utc_msc,UtcNow(),ServerOffsetSeconds,DoubleToString(bid,10),DoubleToString(ask,10),DoubleToString(tick.last,10),DoubleToString(spread,10),DoubleToString(point>0?spread/point:0,3),DoubleToString(mid,10),qdir,bdir,adir,tdir,(long)tick.flags,(long)tick.volume,DoubleToString(tick.volume_real,4),gap,"BROKER_COPY_TICKS_ALL");
   AddRing(s,utc_msc,mid,spread,qdir,tdir);
   int day=NumericDayKey(utc),session=CurrentSessionKey(utc);
   if(DayKey[s]!=day){DayKey[s]=day;DayOpen[s]=mid;}
   if(SessionKey[s]!=session){SessionKey[s]=session;SessionOpen[s]=mid;}
   LastTickMsc[s]=tick.time_msc;LastBid[s]=bid;LastAsk[s]=ask;LastMid[s]=mid;TotalTicks++;
  }

void CollectSymbol(const int s)
  {
   if(!SymbolSelect(Symbols[s],true))return;
   MqlTick latest;if(!SymbolInfoTick(Symbols[s],latest))return;
   ulong from=LastTickMsc[s]>0?(ulong)(LastTickMsc[s]+1):(ulong)MathMax(0,latest.time_msc-2000);
   MqlTick ticks[];ResetLastError();int n=CopyTicks(Symbols[s],ticks,COPY_TICKS_ALL,from,2000);
   if(n<0){CopyErrors++;return;}
   for(int i=0;i<n;i++)ProcessTick(s,ticks[i],n);
  }

bool LoadBarState(const string symbol,const ENUM_TIMEFRAMES tf,const int seconds,BarState &out)
  {
   MqlRates r[];ArraySetAsSeries(r,true);int n=CopyRates(symbol,tf,1,16,r);
   if(n<15){out.ready=false;return false;}
   out.ready=true;out.end_utc=(long)r[0].time+seconds-ServerOffsetSeconds;
   out.open=r[0].open;out.high=r[0].high;out.low=r[0].low;out.close=r[0].close;out.tick_volume=(long)r[0].tick_volume;
   double trsum=0,prior=0;
   for(int i=0;i<14;i++)
     {
      double tr=MathMax(r[i].high-r[i].low,MathMax(MathAbs(r[i].high-r[i+1].close),MathAbs(r[i].low-r[i+1].close)));
      trsum+=tr;if(i>0)prior+=tr;
     }
   out.atr=trsum/14.0;double current=MathMax(r[0].high-r[0].low,MathMax(MathAbs(r[0].high-r[1].close),MathAbs(r[0].low-r[1].close)));
   out.vol_ratio=prior>0?current/(prior/13.0):0;
   out.ret=r[3].close!=0?r[0].close/r[3].close-1.0:0;
   out.trend=out.ret>0?1:(out.ret<0?-1:0);
   if(r[0].high>r[1].high && r[0].low>r[1].low)out.structure=1;
   else if(r[0].high<r[1].high && r[0].low<r[1].low)out.structure=-1;
   else out.structure=0;
   return true;
  }

void RefreshBars()
  {
   for(int s=0;s<SYMBOL_COUNT;s++)
     {
      LoadBarState(Symbols[s],PERIOD_M1,60,M1[s]);LoadBarState(Symbols[s],PERIOD_M5,300,M5[s]);
      LoadBarState(Symbols[s],PERIOD_M15,900,M15[s]);LoadBarState(Symbols[s],PERIOD_H1,3600,H1[s]);
     }
  }

int CurrencyIndex(const string currency){for(int i=0;i<8;i++)if(Currencies[i]==currency)return i;return -1;}
void RefreshCalendar()
  {
   datetime now=TimeTradeServer();
   for(int c=0;c<8;c++)
     {
      CalendarAvailable[c]=false;CalendarHasEvent[c]=false;CalendarEventUtc[c]=0;CalendarImportance[c]=0;CalendarEventName[c]="";CalendarError[c]=0;
      MqlCalendarValue values[];ResetLastError();int n=CalendarValueHistory(values,now,now+86400,NULL,Currencies[c]);
      CalendarError[c]=GetLastError();if(n<0)continue;CalendarAvailable[c]=true;
      long best=0;MqlCalendarEvent ev;
      for(int i=0;i<n;i++)if(values[i].time>=now && (best==0 || (long)values[i].time<best))
        {
         if(CalendarEventById(values[i].event_id,ev))
           {best=(long)values[i].time;CalendarHasEvent[c]=true;CalendarEventUtc[c]=best-ServerOffsetSeconds;CalendarImportance[c]=(int)ev.importance;CalendarEventName[c]=ev.name;}
        }
     }
   LastCalendarUtc=(datetime)UtcNow();
  }

void EventContext(const int s,bool &available,bool &has_event,long &event_utc,int &importance,string &currency,string &name,int &error)
  {
   string base=SymbolInfoString(Symbols[s],SYMBOL_CURRENCY_BASE),profit=SymbolInfoString(Symbols[s],SYMBOL_CURRENCY_PROFIT);
   int a=CurrencyIndex(base),b=CurrencyIndex(profit);available=false;has_event=false;event_utc=0;importance=0;currency="";name="";error=0;
   int ids[2]={a,b};for(int k=0;k<2;k++){int c=ids[k];if(c<0)continue;if(CalendarAvailable[c])available=true;else if(error==0)error=CalendarError[c];if(CalendarHasEvent[c] && (event_utc==0 || CalendarEventUtc[c]<event_utc)){has_event=true;event_utc=CalendarEventUtc[c];importance=CalendarImportance[c];currency=Currencies[c];name=CalendarEventName[c];}}
  }

string BarText(const BarState &b)
  {
   if(!b.ready)return "available=false";
   return StringFormat("available=true;end_utc=%I64d;open=%s;high=%s;low=%s;close=%s;tick_volume=%I64d;atr14=%s;vol_ratio=%s;return_3bar=%s;trend=%d;structure=%d",b.end_utc,DoubleToString(b.open,10),DoubleToString(b.high,10),DoubleToString(b.low,10),DoubleToString(b.close,10),b.tick_volume,DoubleToString(b.atr,10),DoubleToString(b.vol_ratio,6),DoubleToString(b.ret,8),b.trend,b.structure);
  }

void WriteFeatures()
  {
   datetime utc=(datetime)UtcNow();EnsureFolders(utc);RefreshBars();if(LastCalendarUtc==0 || utc-LastCalendarUtc>=60)RefreshCalendar();
   string path=Root+"features\\"+DateKey(utc)+"\\"+HourKey(utc)+"-features.csv";bool exists=FileIsExist(path);
   int h=FileOpen(path,FILE_READ|FILE_WRITE|FILE_CSV|FILE_ANSI|FILE_SHARE_READ|FILE_SHARE_WRITE,',');if(h==INVALID_HANDLE)return;
   if(!exists || FileSize(h)==0)
     {
      FileWrite(h,"schema","collector_version","observation_utc","account","server","symbol","latest_tick_utc_msc","symbol_sync_lag_ms","bid","ask","mid","spread_price","spread_points","rate_1s","rate_5s","rate_30s","quote_pressure_1s","quote_pressure_5s","quote_pressure_30s","trade_pressure_1s","trade_pressure_5s","trade_pressure_30s","quote_acceleration","mid_change_1s","mid_change_5s","mid_change_30s","spread_mean_1s","spread_mean_5s","spread_mean_30s","arrival_mean_ms_5s","tick_window_truncated","day_open_observed","session","session_open_observed","distance_from_day_open","distance_from_session_open","correlated_count","correlated_return_mean","correlated_alignment_fraction","correlated_max_bar_lag_seconds","event_context_available","scheduled_event_present","next_event_utc","minutes_to_event","event_currency","event_importance","event_name","event_api_error","tick_size","tick_value_loss","spread_cash_per_lot_estimate","commission_available","commission_cash_per_lot","swap_long","swap_short","cost_source","m1_completed_state","m5_completed_state","m15_completed_state","h1_completed_state","completed_bars_only","order_capability");
     }
   FileSeek(h,0,SEEK_END);
   long now_msc=(long)utc*1000;
   for(int s=0;s<SYMBOL_COUNT;s++)
     {
      if(LastTickMsc[s]<=0)continue;
      int c1,c5,c30,qp1,qp5,qp30,tp1,tp5,tp30;double r1,r5,r30,sp1,sp5,sp30,mc1,mc5,mc30,ia1,ia5,ia30;
      long tick_utc_msc=LastTickMsc[s]-ServerOffsetSeconds*1000;
      WindowStats(s,tick_utc_msc,1,c1,r1,qp1,tp1,sp1,mc1,ia1);WindowStats(s,tick_utc_msc,5,c5,r5,qp5,tp5,sp5,mc5,ia5);WindowStats(s,tick_utc_msc,30,c30,r30,qp30,tp30,sp30,mc30,ia30);
      int corr=0,aligned=0;double corr_ret=0;long maxlag=0;
      for(int j=0;j<SYMBOL_COUNT;j++)if(j!=s && Groups[j]==Groups[s] && M1[j].ready)
        {corr++;corr_ret+=M1[j].ret;if(M1[s].trend!=0 && M1[j].trend==M1[s].trend)aligned++;long lag=MathAbs(M1[s].end_utc-M1[j].end_utc);if(lag>maxlag)maxlag=lag;}
      if(corr>0)corr_ret/=corr;double align=corr>0?(double)aligned/corr:0;
      bool ev_avail,ev_has;long ev_utc;int ev_imp,ev_err;string ev_ccy,ev_name;EventContext(s,ev_avail,ev_has,ev_utc,ev_imp,ev_ccy,ev_name,ev_err);
      double point=SymbolInfoDouble(Symbols[s],SYMBOL_POINT),tick_size=SymbolInfoDouble(Symbols[s],SYMBOL_TRADE_TICK_SIZE),tick_value=SymbolInfoDouble(Symbols[s],SYMBOL_TRADE_TICK_VALUE_LOSS),spread=LastAsk[s]-LastBid[s];
      double spread_cash=(tick_size>0 && tick_value>0)?spread/tick_size*tick_value:0;
      FileWrite(h,FEATURE_SCHEMA,COLLECTOR_VERSION,(long)utc,AccountInfoInteger(ACCOUNT_LOGIN),AccountInfoString(ACCOUNT_SERVER),Symbols[s],tick_utc_msc,MathMax(0,now_msc-tick_utc_msc),DoubleToString(LastBid[s],10),DoubleToString(LastAsk[s],10),DoubleToString(LastMid[s],10),DoubleToString(spread,10),DoubleToString(point>0?spread/point:0,3),DoubleToString(r1,3),DoubleToString(r5,3),DoubleToString(r30,3),qp1,qp5,qp30,tp1,tp5,tp30,DoubleToString(r1-(r5*5-r1)/4.0,3),DoubleToString(mc1,10),DoubleToString(mc5,10),DoubleToString(mc30,10),DoubleToString(sp1,10),DoubleToString(sp5,10),DoubleToString(sp30,10),DoubleToString(ia5,3),BoolText(c30>=RING_SIZE),DoubleToString(DayOpen[s],10),SessionName(SessionId(utc)),DoubleToString(SessionOpen[s],10),DoubleToString(LastMid[s]-DayOpen[s],10),DoubleToString(LastMid[s]-SessionOpen[s],10),corr,DoubleToString(corr_ret,8),DoubleToString(align,6),maxlag,BoolText(ev_avail),BoolText(ev_has),ev_utc,ev_has?DoubleToString((double)(ev_utc-(long)utc)/60.0,2):"",ev_ccy,ev_imp,ev_name,ev_err,DoubleToString(tick_size,10),DoubleToString(tick_value,6),DoubleToString(spread_cash,6),"false","",DoubleToString(SymbolInfoDouble(Symbols[s],SYMBOL_SWAP_LONG),6),DoubleToString(SymbolInfoDouble(Symbols[s],SYMBOL_SWAP_SHORT),6),"LIVE_SPREAD_AND_SYMBOL_PROPERTIES",BarText(M1[s]),BarText(M5[s]),BarText(M15[s]),BarText(H1[s]),"true","false");TotalFeatures++;
     }
   FileFlush(h);FileClose(h);LastFeatureUtc=utc;
  }

void SaveState()
  {
   string tmp=Root+"status\\state.tmp",path=Root+"status\\state.csv";int h=FileOpen(tmp,FILE_WRITE|FILE_CSV|FILE_ANSI,',');if(h==INVALID_HANDLE)return;
   FileWrite(h,"symbol","last_tick_server_msc","sequence","last_bid","last_ask","last_mid","day_key","day_open","session_key","session_open");
   for(int s=0;s<SYMBOL_COUNT;s++)FileWrite(h,Symbols[s],LastTickMsc[s],Sequences[s],DoubleToString(LastBid[s],10),DoubleToString(LastAsk[s],10),DoubleToString(LastMid[s],10),DayKey[s],DoubleToString(DayOpen[s],10),SessionKey[s],DoubleToString(SessionOpen[s],10));
   FileClose(h);FileMove(tmp,0,path,FILE_REWRITE);LastStateUtc=(datetime)UtcNow();
  }

void LoadState()
  {
   string path=Root+"status\\state.csv";if(!FileIsExist(path))return;int h=FileOpen(path,FILE_READ|FILE_CSV|FILE_ANSI,',');if(h==INVALID_HANDLE)return;
   for(int k=0;k<10;k++)FileReadString(h);
   while(!FileIsEnding(h))
     {
      string sym=FileReadString(h);if(sym=="")break;int s=-1;for(int i=0;i<SYMBOL_COUNT;i++)if(Symbols[i]==sym){s=i;break;}
      long msc=StringToInteger(FileReadString(h));ulong seq=(ulong)StringToInteger(FileReadString(h));double bid=StringToDouble(FileReadString(h)),ask=StringToDouble(FileReadString(h)),mid=StringToDouble(FileReadString(h));int day=(int)StringToInteger(FileReadString(h));double dayopen=StringToDouble(FileReadString(h));int session=(int)StringToInteger(FileReadString(h));double sessionopen=StringToDouble(FileReadString(h));
      if(s>=0){LastTickMsc[s]=msc;Sequences[s]=seq;LastBid[s]=bid;LastAsk[s]=ask;LastMid[s]=mid;DayKey[s]=day;DayOpen[s]=dayopen;SessionKey[s]=session;SessionOpen[s]=sessionopen;}
     }
   FileClose(h);
  }

// Reconcile the durable checkpoint with the append-only tick shards. A forced
// stop can follow a CSV append but precede the periodic state write. Reading
// both possible active-hour tails prevents sequence regression and duplicate
// backfill after restart without discarding a captured tick.
void ReconcileTickFile(const int s,const datetime utc)
  {
   string path=Root+"raw_ticks\\"+DateKey(utc)+"\\"+HourKey(utc)+"-"+Symbols[s]+".csv";
   if(!FileIsExist(path))return;
   int h=FileOpen(path,FILE_READ|FILE_CSV|FILE_ANSI|FILE_SHARE_READ|FILE_SHARE_WRITE,',');
   if(h==INVALID_HANDLE)return;
   for(int i=0;i<25 && !FileIsEnding(h);i++)FileReadString(h);
   ulong max_sequence=Sequences[s];long newest_msc=LastTickMsc[s];
   double newest_bid=LastBid[s],newest_ask=LastAsk[s],newest_mid=LastMid[s];
   while(!FileIsEnding(h))
     {
      string values[25];
      for(int c=0;c<25;c++)values[c]=FileReadString(h);
      if(values[0]=="")break;
      ulong sequence=(ulong)StringToInteger(values[5]);
      long tick_msc=StringToInteger(values[6]);
      if(sequence>max_sequence)max_sequence=sequence;
      if(tick_msc>newest_msc)
        {
         newest_msc=tick_msc;newest_bid=StringToDouble(values[10]);
         newest_ask=StringToDouble(values[11]);newest_mid=StringToDouble(values[15]);
        }
     }
   FileClose(h);Sequences[s]=max_sequence;LastTickMsc[s]=newest_msc;
   LastBid[s]=newest_bid;LastAsk[s]=newest_ask;LastMid[s]=newest_mid;
  }

void ReconcileTickTails()
  {
   datetime now=(datetime)UtcNow();
   for(int s=0;s<SYMBOL_COUNT;s++)
     {
      ReconcileTickFile(s,now-3600);
      ReconcileTickFile(s,now);
     }
  }

void WriteHeartbeat()
  {
   string tmp=Root+"status\\heartbeat.tmp",path=Root+"status\\heartbeat.csv";int h=FileOpen(tmp,FILE_WRITE|FILE_CSV|FILE_ANSI,',');if(h==INVALID_HANDLE)return;
   FileWrite(h,"schema","collector_version","status","utc","started_utc","restart_count","account","server","connected","terminal_trade_allowed","mql_trade_allowed","order_capability","total_ticks","total_features","copy_errors","symbols_configured","timer_milliseconds","feature_interval_seconds","server_offset_seconds","storage_root","latest_state_utc","build");
   FileWrite(h,"SOLTRADE_BRAIN_HEARTBEAT_V1",COLLECTOR_VERSION,"COLLECTING",UtcNow(),StartedUtc,RestartCount,AccountInfoInteger(ACCOUNT_LOGIN),AccountInfoString(ACCOUNT_SERVER),BoolText(TerminalInfoInteger(TERMINAL_CONNECTED)),BoolText(TerminalInfoInteger(TERMINAL_TRADE_ALLOWED)),BoolText(MQLInfoInteger(MQL_TRADE_ALLOWED)),"false",TotalTicks,TotalFeatures,CopyErrors,SYMBOL_COUNT,TimerMilliseconds,FeatureIntervalSeconds,ServerOffsetSeconds,TerminalInfoString(TERMINAL_DATA_PATH)+"\\MQL5\\Files\\"+Root,LastStateUtc,MQLInfoInteger(MQL_PROGRAM_TYPE));
   FileClose(h);FileMove(tmp,0,path,FILE_REWRITE);
  }

void WriteManifest()
  {
   string path=Root+"manifest.csv";int h=FileOpen(path,FILE_WRITE|FILE_CSV|FILE_ANSI,',');if(h==INVALID_HANDLE)return;
   FileWrite(h,"schema","collector_version","created_utc","account","server","terminal_path","data_path","order_capability","trade_api_linked","future_data_in_features","forming_bar_data_in_features","raw_tick_source","feature_interval_seconds","raw_rotation","retention_policy");
   FileWrite(h,"SOLTRADE_BRAIN_MANIFEST_V1",COLLECTOR_VERSION,UtcNow(),AccountInfoInteger(ACCOUNT_LOGIN),AccountInfoString(ACCOUNT_SERVER),TerminalInfoString(TERMINAL_PATH),TerminalInfoString(TERMINAL_DATA_PATH),"false","false","false","false","CopyTicks(COPY_TICKS_ALL)",FeatureIntervalSeconds,"hourly","external-maintenance-30-days-or-20GB");FileClose(h);
  }

int OnInit()
  {
   string path=TerminalInfoString(TERMINAL_PATH);StringToLower(path);
   if(!ObserverConfirmed || StringFind(path,"soltrade-brain-collector-v1")<0 || MQLInfoInteger(MQL_TESTER))return INIT_FAILED;
   if(AccountInfoInteger(ACCOUNT_LOGIN)!=7404213 || AccountInfoString(ACCOUNT_SERVER)!="FPMarketsSC-Demo")return INIT_FAILED;
   if(MQLInfoInteger(MQL_TRADE_ALLOWED) || TerminalInfoInteger(TERMINAL_TRADE_ALLOWED))return INIT_FAILED;
   StartedUtc=(datetime)UtcNow();ServerOffsetSeconds=OffsetNow();for(int s=0;s<SYMBOL_COUNT;s++)TickHandles[s]=INVALID_HANDLE;
   EnsureFolders(StartedUtc);LoadState();ReconcileTickTails();
   string restartPath=Root+"status\\restart-count.txt";if(FileIsExist(restartPath)){int f=FileOpen(restartPath,FILE_READ|FILE_TXT|FILE_ANSI);if(f!=INVALID_HANDLE){RestartCount=(int)StringToInteger(FileReadString(f));FileClose(f);}}
   RestartCount++;int rf=FileOpen(restartPath,FILE_WRITE|FILE_TXT|FILE_ANSI);if(rf!=INVALID_HANDLE){FileWriteString(rf,IntegerToString(RestartCount));FileClose(rf);}
   WriteManifest();SaveState();WriteHeartbeat();
   if(!EventSetMillisecondTimer(MathMax(100,TimerMilliseconds)))return INIT_FAILED;return INIT_SUCCEEDED;
  }

void OnDeinit(const int reason)
  {
   EventKillTimer();SaveState();WriteHeartbeat();for(int s=0;s<SYMBOL_COUNT;s++)CloseTickHandle(s);
  }

void OnTimer()
  {
   if(AccountInfoInteger(ACCOUNT_LOGIN)!=7404213 || AccountInfoString(ACCOUNT_SERVER)!="FPMarketsSC-Demo")return;
   if(MQLInfoInteger(MQL_TRADE_ALLOWED) || TerminalInfoInteger(TERMINAL_TRADE_ALLOWED)){ExpertRemove();return;}
   if(!TerminalInfoInteger(TERMINAL_CONNECTED)){WriteHeartbeat();return;}
   ServerOffsetSeconds=OffsetNow();for(int s=0;s<SYMBOL_COUNT;s++)CollectSymbol(s);
   datetime utc=(datetime)UtcNow();if(LastFeatureUtc==0 || utc-LastFeatureUtc>=FeatureIntervalSeconds)WriteFeatures();
   if(LastStateUtc==0 || utc-LastStateUtc>=10)SaveState();
   if(LastFlushUtc==0 || utc-LastFlushUtc>=FlushIntervalSeconds){for(int s=0;s<SYMBOL_COUNT;s++)if(TickHandles[s]!=INVALID_HANDLE)FileFlush(TickHandles[s]);WriteHeartbeat();LastFlushUtc=utc;}
  }
