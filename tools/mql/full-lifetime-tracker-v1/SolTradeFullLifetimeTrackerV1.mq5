#property strict
#property version   "1.100"
#property description "ORDERLESS V3 full-lifetime hypothetical tracker; no trade capability"

#include "SolTradeV3TrackingModel.mqh"

input bool ObserverConfirmed=false;
input int TimerMilliseconds=200;
input int ObservationIntervalSeconds=5;
input int FlushIntervalSeconds=5;
// Disabled by default. A positive value creates a research censoring boundary,
// never a trade exit or performance result.
input int ResearchSafetyHorizonDays=0;

#define SYMBOL_COUNT 19
#define RING_SIZE 4096
#define CANDIDATE_COUNT 4
#define WAIT_SECONDS 900
#define EPISODE_INDEPENDENCE_SECONDS 14400
#define TRACKER_VERSION "1.1.0"
#define OBS_SCHEMA "SOLTRADE_V3_LIFETIME_OBSERVATION_V2"
#define EVENT_SCHEMA "SOLTRADE_V3_LIFETIME_EVENT_V2"
#define OUTCOME_SCHEMA "SOLTRADE_V3_LIFETIME_OUTCOME_V2"
const bool ORDER_CAPABILITY=false;

string Root="SolTradeFullLifetimeTrackerV1\\";
string Symbols[SYMBOL_COUNT]={"EURUSD.r","GBPUSD.r","USDJPY.r","USDCHF.r","USDCAD.r","AUDUSD.r","NZDUSD.r","EURJPY.r","GBPJPY.r","AUDJPY.r","EURGBP.r","AUDNZD.r","XAUUSD.r","XAGUSD.r","GER40","US100","US500","UK100","EURO50"};
int Groups[SYMBOL_COUNT]={1,1,1,1,1,1,1,1,1,1,1,1,2,2,3,3,3,3,3};
string CandidateId[CANDIDATE_COUNT]={"FROZEN_V3_DIAGNOSTIC","STRICT_PRESSURE_RESUMPTION","STRUCTURAL_REVERSAL_CONFIRMATION","EXPANDING_PULLBACK_FAILURE"};
double CandidateAdverse[CANDIDATE_COUNT]={-0.40,-0.50,-0.40,-0.35};
double CandidateTransition[CANDIDATE_COUNT]={-0.25,-0.35,-0.25,-0.30};

struct BarState
  {
   bool ready;
   long end_utc;
   double open,high,low,close,atr,vol_ratio,ret;
   long tick_volume;
   int trend,structure;
  };

long LastTickMsc[SYMBOL_COUNT];
double LastBid[SYMBOL_COUNT],LastAsk[SYMBOL_COUNT],LastMid[SYMBOL_COUNT];
double DayOpen[SYMBOL_COUNT],SessionOpen[SYMBOL_COUNT];
int DayKeyValue[SYMBOL_COUNT],SessionKeyValue[SYMBOL_COUNT];
long RingTime[SYMBOL_COUNT][RING_SIZE];
double RingMid[SYMBOL_COUNT][RING_SIZE],RingSpread[SYMBOL_COUNT][RING_SIZE];
int RingDirection[SYMBOL_COUNT][RING_SIZE],RingTradeDirection[SYMBOL_COUNT][RING_SIZE];
int RingHead[SYMBOL_COUNT],RingCount[SYMBOL_COUNT];
BarState M1[SYMBOL_COUNT],M5[SYMBOL_COUNT],M15[SYMBOL_COUNT],H1[SYMBOL_COUNT];
int TrendValue[SYMBOL_COUNT][4];
long TrendStarted[SYMBOL_COUNT][4];

bool OpportunityActive[SYMBOL_COUNT];
string OpportunityId[SYMBOL_COUNT],OpportunityFamily[SYMBOL_COUNT];
long OpportunityDetected[SYMBOL_COUNT],OpportunityExpiry[SYMBOL_COUNT],OpportunityLastObserved[SYMBOL_COUNT],BlockedUntil[SYMBOL_COUNT];
int OpportunityCounter[SYMBOL_COUNT],OpportunityHypothesis[SYMBOL_COUNT];
double FirstPressure5[SYMBOL_COUNT],FirstRate5[SYMBOL_COUNT],FirstSpreadPoints[SYMBOL_COUNT],FirstMid30[SYMBOL_COUNT];
double FirstBid[SYMBOL_COUNT],FirstAsk[SYMBOL_COUNT],FirstEntryLong[SYMBOL_COUNT],FirstEntryShort[SYMBOL_COUNT];
double FirstRiskLong[SYMBOL_COUNT],FirstRiskShort[SYMBOL_COUNT];

bool PositionActive[SYMBOL_COUNT];
int PositionDirection[SYMBOL_COUNT];
long EntryUtc[SYMBOL_COUNT],BankUtc[SYMBOL_COUNT],StructuralStopUtc[SYMBOL_COUNT],RunnerStopUtc[SYMBOL_COUNT];
double EntryPrice[SYMBOL_COUNT],InitialStop[SYMBOL_COUNT],InitialRisk[SYMBOL_COUNT],RunnerStop[SYMBOL_COUNT],MfeR[SYMBOL_COUNT],MaeR[SYMBOL_COUNT];
bool Bank1Reached[SYMBOL_COUNT],StructuralStopReached[SYMBOL_COUNT],BaselineTerminal[SYMBOL_COUNT];
int RunnerTrailUpdates[SYMBOL_COUNT];
double LastCurrentR[SYMBOL_COUNT],BaselineExitR[SYMBOL_COUNT];
string BaselineTerminalReason[SYMBOL_COUNT];

bool Invalidated[SYMBOL_COUNT][CANDIDATE_COUNT];
long InvalidationUtc[SYMBOL_COUNT][CANDIDATE_COUNT];
double InvalidationR[SYMBOL_COUNT][CANDIDATE_COUNT],InvalidationTransition[SYMBOL_COUNT][CANDIDATE_COUNT];
bool AfterMinus1[SYMBOL_COUNT][CANDIDATE_COUNT],AfterBreakeven[SYMBOL_COUNT][CANDIDATE_COUNT],AfterBank1[SYMBOL_COUNT][CANDIDATE_COUNT];
bool AfterPlus2[SYMBOL_COUNT][CANDIDATE_COUNT],AfterPlus3[SYMBOL_COUNT][CANDIDATE_COUNT],AfterPlus5[SYMBOL_COUNT][CANDIDATE_COUNT];

long TotalTicks=0,TotalObservations=0,TotalOpportunities=0,TotalTriggered=0,TotalOutcomes=0,TotalRightCensored=0,CopyErrors=0;
int RestartCount=0;
long ServerOffsetSeconds=0;
datetime StartedUtc=0,LastObservationUtc=0,LastFlushUtc=0,LastStateUtc=0;
int ObsHandle=INVALID_HANDLE,EventHandle=INVALID_HANDLE,OutcomeHandle=INVALID_HANDLE;
string ObsHour="",EventHour="",OutcomeDate="";

string BoolText(const bool value){return value?"true":"false";}
long UtcNow(){return (long)TimeGMT();}
long OffsetNow(){long raw=(long)TimeTradeServer()-(long)TimeGMT();return (long)MathRound((double)raw/60.0)*60;}
string DateKey(const datetime utc){MqlDateTime d;TimeToStruct(utc,d);return StringFormat("%04d%02d%02d",d.year,d.mon,d.day);}
string HourKey(const datetime utc){MqlDateTime d;TimeToStruct(utc,d);return StringFormat("%04d%02d%02d-%02d",d.year,d.mon,d.day,d.hour);}
int NumericDayKey(const datetime utc){MqlDateTime d;TimeToStruct(utc,d);return d.year*10000+d.mon*100+d.day;}
int SessionId(const datetime utc){MqlDateTime d;TimeToStruct(utc,d);int minute=d.hour*60+d.min;if(minute>=420&&minute<720)return 1;if(minute>=720&&minute<960)return 2;if(minute>=960&&minute<1260)return 3;if(minute<420||minute>=1320)return 4;return 0;}
string SessionName(const int id){if(id==1)return "LONDON";if(id==2)return "LONDON_NEWYORK_OVERLAP";if(id==3)return "NEW_YORK";if(id==4)return "ASIA";return "OFF_SESSION";}
int CurrentSessionKey(const datetime utc){return NumericDayKey(utc)*10+SessionId(utc);}

bool EnsureFolders(const datetime utc)
  {
   string date=DateKey(utc);FolderCreate(Root);FolderCreate(Root+"lifetime_observations");FolderCreate(Root+"lifetime_observations\\"+date);
   FolderCreate(Root+"events");FolderCreate(Root+"events\\"+date);FolderCreate(Root+"outcomes");FolderCreate(Root+"outcomes\\"+date);FolderCreate(Root+"status");return true;
  }

void CloseHandle(int &handle){if(handle!=INVALID_HANDLE){FileFlush(handle);FileClose(handle);handle=INVALID_HANDLE;}}

int OpenObservation(const datetime utc)
  {
   string hour=HourKey(utc);if(ObsHandle!=INVALID_HANDLE&&ObsHour==hour)return ObsHandle;CloseHandle(ObsHandle);EnsureFolders(utc);
   string path=Root+"lifetime_observations\\"+DateKey(utc)+"\\"+hour+"-lifetime.csv";bool exists=FileIsExist(path);
   ObsHandle=FileOpen(path,FILE_READ|FILE_WRITE|FILE_CSV|FILE_ANSI|FILE_SHARE_READ|FILE_SHARE_WRITE,',');if(ObsHandle==INVALID_HANDLE)return INVALID_HANDLE;
   if(!exists||FileSize(ObsHandle)==0)FileWriteString(ObsHandle,"schema,tracker_version,model_id,observation_utc_msc,opportunity_id,symbol,direction,entry_utc,lifetime_seconds,entry_price,initial_structural_stop,initial_r_distance,active_structural_stop,runner_stop_utc,runner_trail_updates,current_exit_price,current_r,mfe_r,mae_r,bid,ask,bid_move_r,ask_move_r,rate_1s,rate_5s,rate_30s,rate_burst_5v30,quote_pressure_1s,quote_pressure_5s,quote_pressure_30s,pressure_reversal,quote_acceleration,mid_change_1s,mid_change_5s,mid_change_30s,spread_price,spread_points,spread_5v30,arrival_mean_ms_5s,pullback_expanding,resumption_evidence,transition_score,m1_state,m5_state,m15_state,h1_state,correlated_count,correlated_return,correlated_alignment,correlated_max_lag_seconds,m1_vol_ratio,m5_vol_ratio,m15_vol_ratio,spread_cash_per_lot,cost_r,bank1_reached,bank1_utc,banked_fraction,runner_active,structural_stop_reached,structural_stop_utc,baseline_active,diagnostic_invalidated,diagnostic_exit_utc,diagnostic_exit_r,strict_invalidated,strict_exit_r,structural_invalidated,structural_exit_r,pullback_invalidated,pullback_exit_r,completed_bars_only,feature_window_ready,order_capability\r\n");
   FileSeek(ObsHandle,0,SEEK_END);ObsHour=hour;return ObsHandle;
  }

int OpenEvent(const datetime utc)
  {
   string hour=HourKey(utc);if(EventHandle!=INVALID_HANDLE&&EventHour==hour)return EventHandle;CloseHandle(EventHandle);EnsureFolders(utc);
   string path=Root+"events\\"+DateKey(utc)+"\\"+hour+"-events.csv";bool exists=FileIsExist(path);
   EventHandle=FileOpen(path,FILE_READ|FILE_WRITE|FILE_CSV|FILE_ANSI|FILE_SHARE_READ|FILE_SHARE_WRITE,',');if(EventHandle==INVALID_HANDLE)return INVALID_HANDLE;
   if(!exists||FileSize(EventHandle)==0)FileWrite(EventHandle,"schema","tracker_version","model_id","utc_msc","opportunity_id","symbol","direction","event","candidate_id","current_r","transition_score","price","detail","order_capability");
   FileSeek(EventHandle,0,SEEK_END);EventHour=hour;return EventHandle;
  }

int OpenOutcome(const datetime utc)
  {
   string date=DateKey(utc);if(OutcomeHandle!=INVALID_HANDLE&&OutcomeDate==date)return OutcomeHandle;CloseHandle(OutcomeHandle);EnsureFolders(utc);
   string path=Root+"outcomes\\"+date+"\\"+date+"-outcomes.csv";bool exists=FileIsExist(path);
   OutcomeHandle=FileOpen(path,FILE_READ|FILE_WRITE|FILE_CSV|FILE_ANSI|FILE_SHARE_READ|FILE_SHARE_WRITE,',');if(OutcomeHandle==INVALID_HANDLE)return INVALID_HANDLE;
   if(!exists||FileSize(OutcomeHandle)==0)FileWrite(OutcomeHandle,"schema","tracker_version","model_id","opportunity_id","symbol","session","direction","entry_utc","terminal_utc","lifetime_seconds","outcome_status","terminal_reason","baseline_final_r_known","aftermath_complete","entry_price","initial_stop","initial_risk","final_runner_stop","runner_trail_updates","mfe_r","mae_r","bank1_reached","bank1_utc","structural_stop_reached","baseline_final_r","candidate_id","causal_exit_triggered","causal_exit_utc","causal_exit_r","causal_final_r_known","causal_final_r","continued_to_minus_1","recovered_to_breakeven","reached_bank1_after_exit","reached_plus_2_after_exit","reached_plus_3_after_exit","reached_plus_5_after_exit","profitable_path_interrupted","plus_1_path_interrupted","plus_2_path_interrupted","plus_3_path_interrupted","plus_5_path_interrupted","completed_bars_only","order_capability");
   FileSeek(OutcomeHandle,0,SEEK_END);OutcomeDate=date;return OutcomeHandle;
  }

void WriteEvent(const int s,const string event,const string candidate,const double r,const double transition,const double price,const string detail,const long at_msc=0)
  {
   datetime utc=(datetime)(at_msc>0?at_msc/1000:UtcNow());int h=OpenEvent(utc);if(h==INVALID_HANDLE)return;
   FileWrite(h,EVENT_SCHEMA,TRACKER_VERSION,V3_TRACKING_MODEL_ID,at_msc>0?at_msc:(long)utc*1000,OpportunityId[s],Symbols[s],PositionDirection[s]>0?"LONG":"SHORT",event,candidate,DoubleToString(r,8),DoubleToString(transition,8),DoubleToString(price,10),detail,"false");
  }

void AppendCsv(string &line,const string value){if(line!="")line+=",";line+=value;}

void AddRing(const int s,const long at,const double mid,const double spread,const int qdir,const int tdir)
  {int p=RingHead[s];RingTime[s][p]=at;RingMid[s][p]=mid;RingSpread[s][p]=spread;RingDirection[s][p]=qdir;RingTradeDirection[s][p]=tdir;RingHead[s]=(p+1)%RING_SIZE;if(RingCount[s]<RING_SIZE)RingCount[s]++;}

void WindowStats(const int s,const long now_msc,const int seconds,int &count,double &rate,int &quote_pressure,int &trade_pressure,double &spread_mean,double &mid_change,double &arrival_mean)
  {
   count=0;quote_pressure=0;trade_pressure=0;spread_mean=0;mid_change=0;arrival_mean=0;long cutoff=now_msc-(long)seconds*1000,previous=0;double oldest=0,newest=0;int gaps=0;
   for(int k=0;k<RingCount[s];k++){int p=(RingHead[s]-1-k+RING_SIZE)%RING_SIZE;long at=RingTime[s][p];if(at<cutoff)break;if(count==0)newest=RingMid[s][p];oldest=RingMid[s][p];spread_mean+=RingSpread[s][p];quote_pressure+=RingDirection[s][p];trade_pressure+=RingTradeDirection[s][p];if(previous>0){arrival_mean+=(double)(previous-at);gaps++;}previous=at;count++;}
   rate=(double)count/MathMax(1,seconds);if(count>0)spread_mean/=count;if(gaps>0)arrival_mean/=gaps;mid_change=newest-oldest;
  }

double CurrentR(const int s,const double bid,const double ask){if(!PositionActive[s]||InitialRisk[s]<=0)return 0;double exit=PositionDirection[s]>0?bid:ask;return (exit-EntryPrice[s])*PositionDirection[s]/InitialRisk[s];}

bool FeatureWindowReady(const int s)
  {
   if(RingCount[s]<2)return false;
   int newest=(RingHead[s]-1+RING_SIZE)%RING_SIZE;long newestAt=RingTime[s][newest],newerAt=newestAt,cutoff=newestAt-30000;
   for(int k=1;k<RingCount[s];k++)
     {
      int p=(RingHead[s]-1-k+RING_SIZE)%RING_SIZE;long at=RingTime[s][p];
      if(newerAt-at>10000)return false; // restart, overnight or market-close gap: rebuild the causal window
      if(at<=cutoff)return true;
      newerAt=at;
     }
   return false;
  }

double AverageCompletedRange(MqlRates &rates[],const int start,const int count)
  {double total=0;int used=0;for(int i=start;i<ArraySize(rates)&&used<count;i++,used++)total+=rates[i].high-rates[i].low;return used>0?total/used:0;}
double LowestCompletedLow(MqlRates &rates[],const int start,const int count)
  {double value=DBL_MAX;for(int i=start;i<ArraySize(rates)&&i<start+count;i++)value=MathMin(value,rates[i].low);return value;}
double HighestCompletedHigh(MqlRates &rates[],const int start,const int count)
  {double value=-DBL_MAX;for(int i=start;i<ArraySize(rates)&&i<start+count;i++)value=MathMax(value,rates[i].high);return value;}
double NormalizeSymbolPrice(const string symbol,const double value)
  {return NormalizeDouble(value,(int)SymbolInfoInteger(symbol,SYMBOL_DIGITS));}

void UpdateRunnerStructuralStop(const int s,const long now)
  {
   if(!PositionActive[s]||BaselineTerminal[s]||!Bank1Reached[s])return;
   MqlRates m5[],m15[];ArraySetAsSeries(m5,true);ArraySetAsSeries(m15,true);
   if(CopyRates(Symbols[s],PERIOD_M5,0,18,m5)<16||CopyRates(Symbols[s],PERIOD_M15,0,12,m15)<10)return;
   double a5=AverageCompletedRange(m5,1,14),a15=AverageCompletedRange(m15,1,8);
   double anchor=PositionDirection[s]>0?MathMin(LowestCompletedLow(m5,1,8),LowestCompletedLow(m15,1,6)):MathMax(HighestCompletedHigh(m5,1,8),HighestCompletedHigh(m15,1,6));
   double breathing=MathMax(MathMax(0.25*a5,0.12*a15),2.5*(LastAsk[s]-LastBid[s]));
   double desired=NormalizeSymbolPrice(Symbols[s],anchor-PositionDirection[s]*breathing);
   double point=SymbolInfoDouble(Symbols[s],SYMBOL_POINT),minDistance=MathMax((double)SymbolInfoInteger(Symbols[s],SYMBOL_TRADE_STOPS_LEVEL),(double)SymbolInfoInteger(Symbols[s],SYMBOL_TRADE_FREEZE_LEVEL))*point;
   bool tighter=PositionDirection[s]>0?desired>RunnerStop[s]:desired<RunnerStop[s];
   bool profitable=PositionDirection[s]*(desired-EntryPrice[s])>0;
   bool correctSide=PositionDirection[s]>0?desired<LastBid[s]-minDistance:desired>LastAsk[s]+minDistance;
   if(tighter&&profitable&&correctSide){double prior=RunnerStop[s];RunnerStop[s]=desired;RunnerStopUtc[s]=now;RunnerTrailUpdates[s]++;WriteEvent(s,"RUNNER_STRUCTURE_ADVANCED","",CurrentR(s,LastBid[s],LastAsk[s]),0,desired,StringFormat("prior_stop=%.10f;new_stop=%.10f;completed_m5_m15=true;monotonic=true",prior,desired),(long)now*1000);}
  }

void UpdateAftermath(const int s,const double r)
  {
   for(int c=0;c<CANDIDATE_COUNT;c++)if(Invalidated[s][c]){if(r<=-1)AfterMinus1[s][c]=true;if(r>=0)AfterBreakeven[s][c]=true;if(r>=1)AfterBank1[s][c]=true;if(r>=2)AfterPlus2[s][c]=true;if(r>=3)AfterPlus3[s][c]=true;if(r>=5)AfterPlus5[s][c]=true;}
  }

void ProcessPositionTick(const int s,const long utc_msc,const double bid,const double ask)
  {
   if(!PositionActive[s]||BaselineTerminal[s])return;double r=CurrentR(s,bid,ask);LastCurrentR[s]=r;MfeR[s]=MathMax(MfeR[s],r);MaeR[s]=MathMin(MaeR[s],r);UpdateAftermath(s,r);
   if(!Bank1Reached[s]&&r>=1.0){Bank1Reached[s]=true;BankUtc[s]=utc_msc/1000;WriteEvent(s,"BANK1R","",r,0,PositionDirection[s]>0?bid:ask,"bank_fraction=0.50;repeated_banking=false",utc_msc);}
   double activeStop=Bank1Reached[s]?RunnerStop[s]:InitialStop[s];bool hit=PositionDirection[s]>0?bid<=activeStop:ask>=activeStop;
   if(hit){StructuralStopReached[s]=true;StructuralStopUtc[s]=utc_msc/1000;BaselineTerminal[s]=true;BaselineExitR[s]=r;BaselineTerminalReason[s]=Bank1Reached[s]?"RUNNER_STRUCTURAL_STOP":"INITIAL_STRUCTURAL_STOP";WriteEvent(s,"STRUCTURAL_STOP","",r,0,PositionDirection[s]>0?bid:ask,"baseline_path_exit;terminal_reason="+BaselineTerminalReason[s],utc_msc);}
  }

void CollectSymbol(const int s)
  {
   if(!SymbolSelect(Symbols[s],true))return;MqlTick latest;if(!SymbolInfoTick(Symbols[s],latest))return;ulong from=LastTickMsc[s]>0?(ulong)(LastTickMsc[s]+1):(ulong)MathMax(0,latest.time_msc-2000);
   MqlTick ticks[];ResetLastError();int n=CopyTicks(Symbols[s],ticks,COPY_TICKS_ALL,from,2000);if(n<0){CopyErrors++;return;}
   for(int i=0;i<n;i++)
     {
      MqlTick tick=ticks[i];if(tick.time_msc<=LastTickMsc[s]||tick.bid<=0||tick.ask<tick.bid)continue;double bid=tick.bid,ask=tick.ask,mid=(bid+ask)*.5,spread=ask-bid;int qdir=0,tdir=0;if(LastMid[s]>0){if(mid>LastMid[s])qdir=1;else if(mid<LastMid[s])qdir=-1;}if((tick.flags&TICK_FLAG_BUY)!=0)tdir=1;else if((tick.flags&TICK_FLAG_SELL)!=0)tdir=-1;
      ServerOffsetSeconds=OffsetNow();long utc_msc=tick.time_msc-ServerOffsetSeconds*1000;AddRing(s,utc_msc,mid,spread,qdir,tdir);LastTickMsc[s]=tick.time_msc;LastBid[s]=bid;LastAsk[s]=ask;LastMid[s]=mid;datetime utc=(datetime)(utc_msc/1000);int day=NumericDayKey(utc),session=CurrentSessionKey(utc);if(DayKeyValue[s]!=day){DayKeyValue[s]=day;DayOpen[s]=mid;}if(SessionKeyValue[s]!=session){SessionKeyValue[s]=session;SessionOpen[s]=mid;}ProcessPositionTick(s,utc_msc,bid,ask);TotalTicks++;
     }
  }

bool LoadBarState(const string symbol,const ENUM_TIMEFRAMES tf,const int seconds,BarState &out)
  {
   MqlRates r[];ArraySetAsSeries(r,true);int n=CopyRates(symbol,tf,1,16,r);if(n<15){out.ready=false;return false;}out.ready=true;out.end_utc=(long)r[0].time+seconds-ServerOffsetSeconds;out.open=r[0].open;out.high=r[0].high;out.low=r[0].low;out.close=r[0].close;out.tick_volume=(long)r[0].tick_volume;double trsum=0,prior=0;
   for(int i=0;i<14;i++){double tr=MathMax(r[i].high-r[i].low,MathMax(MathAbs(r[i].high-r[i+1].close),MathAbs(r[i].low-r[i+1].close)));trsum+=tr;if(i>0)prior+=tr;}out.atr=trsum/14.0;double current=MathMax(r[0].high-r[0].low,MathMax(MathAbs(r[0].high-r[1].close),MathAbs(r[0].low-r[1].close)));out.vol_ratio=prior>0?current/(prior/13.0):0;out.ret=r[3].close!=0?r[0].close/r[3].close-1.0:0;out.trend=out.ret>0?1:(out.ret<0?-1:0);if(r[0].high>r[1].high&&r[0].low>r[1].low)out.structure=1;else if(r[0].high<r[1].high&&r[0].low<r[1].low)out.structure=-1;else out.structure=0;return true;
  }

void RefreshBars(const long now)
  {
   for(int s=0;s<SYMBOL_COUNT;s++)
     {
      LoadBarState(Symbols[s],PERIOD_M1,60,M1[s]);LoadBarState(Symbols[s],PERIOD_M5,300,M5[s]);LoadBarState(Symbols[s],PERIOD_M15,900,M15[s]);LoadBarState(Symbols[s],PERIOD_H1,3600,H1[s]);
      int values[4]={M1[s].trend,M5[s].trend,M15[s].trend,H1[s].trend};for(int tf=0;tf<4;tf++)if(TrendStarted[s][tf]==0||TrendValue[s][tf]!=values[tf]){TrendValue[s][tf]=values[tf];TrendStarted[s][tf]=now;}
     }
  }

void Geometry(const int s,const int direction,double &entry,double &stop,double &risk,double &stop1,double &stop5)
  {
   entry=direction>0?LastAsk[s]:LastBid[s];double atr1=MathMax(M1[s].atr,MathMax(SymbolInfoDouble(Symbols[s],SYMBOL_TRADE_TICK_SIZE),1e-12)),atr5=MathMax(M5[s].atr,atr1),atr15=MathMax(M15[s].atr,atr5);double structural=direction>0?MathMin(M5[s].low,M15[s].low):MathMax(M5[s].high,M15[s].high);double floor=MathMax(1.15*atr5,.55*atr15);stop=direction>0?MathMin(structural-.15*atr5,entry-floor):MathMax(structural+.15*atr5,entry+floor);risk=MathAbs(entry-stop);stop1=risk/atr1;stop5=risk/atr5;
  }

double Pressure(const int raw,const double rate,const int seconds){return (double)raw/MathMax(1.0,rate*seconds);}
bool SymbolFresh(const int s,const long now){if(LastTickMsc[s]<=0)return false;long tickUtc=LastTickMsc[s]/1000-ServerOffsetSeconds;long lag=now-tickUtc;return lag>=0&&lag<=10;}
string BarText(const BarState &b){if(!b.ready)return "available=false";return StringFormat("available=true;end_utc=%I64d;open=%s;high=%s;low=%s;close=%s;tick_volume=%I64d;atr14=%s;vol_ratio=%s;return_3bar=%s;trend=%d;structure=%d",b.end_utc,DoubleToString(b.open,10),DoubleToString(b.high,10),DoubleToString(b.low,10),DoubleToString(b.close,10),b.tick_volume,DoubleToString(b.atr,10),DoubleToString(b.vol_ratio,6),DoubleToString(b.ret,8),b.trend,b.structure);}

void Correlation(const int s,int &count,double &ret,double &alignment,long &maxlag)
  {count=0;int aligned=0;ret=0;maxlag=0;for(int j=0;j<SYMBOL_COUNT;j++)if(j!=s&&Groups[j]==Groups[s]&&M1[j].ready){count++;ret+=M1[j].ret;if(M1[s].trend!=0&&M1[j].trend==M1[s].trend)aligned++;long lag=MathAbs(M1[s].end_utc-M1[j].end_utc);if(lag>maxlag)maxlag=lag;}if(count>0)ret/=count;alignment=count>0?(double)aligned/count:0;}

void FillModelFeatures(const int s,const int direction,const long now,const int wait,double &x[],double &transition,bool &pullback,bool &resume,
                       double &r1,double &r5,double &r30,double &p1,double &p5,double &p30,double &sp5,double &sp30,double &mc1,double &mc5,double &mc30,double &arrival,
                       int &corr,double &corrret,double &corralign,long &corrlag)
  {
   ArrayResize(x,V3_MODEL_FEATURE_COUNT);ArrayInitialize(x,0);int c1,c5,c30,qp1,qp5,qp30,tp1,tp5,tp30;double sm1,ia1,ia30;long tick_utc=LastTickMsc[s]-ServerOffsetSeconds*1000;
   WindowStats(s,tick_utc,1,c1,r1,qp1,tp1,sm1,mc1,ia1);WindowStats(s,tick_utc,5,c5,r5,qp5,tp5,sp5,mc5,arrival);WindowStats(s,tick_utc,30,c30,r30,qp30,tp30,sp30,mc30,ia30);
   p1=Pressure(qp1,r1,1);p5=Pressure(qp5,r5,5);p30=Pressure(qp30,r30,30);Correlation(s,corr,corrret,corralign,corrlag);
   double entry,stop,risk,stop1,stop5;Geometry(s,direction,entry,stop,risk,stop1,stop5);double atr1=MathMax(M1[s].atr,MathMax(SymbolInfoDouble(Symbols[s],SYMBOL_TRADE_TICK_SIZE),1e-12));
   double alignedP1=p1*direction,alignedP5=p5*direction,alignedP30=p30*direction;double accel=r1-(r5*5-r1)/4.0;double m1body=(M1[s].close-M1[s].open)/atr1*direction;double m5body=(M5[s].close-M5[s].open)/MathMax(M5[s].atr,atr1)*direction;
   pullback=(mc30*direction<0&&(mc30-FirstMid30[s])*direction<0);resume=(alignedP5>.15&&mc5*direction>0&&m1body>0);transition=alignedP5+.5*accel*direction+.5*(resume?1.0:0.0)-.5*(pullback?1.0:0.0);
   double detectEntry=direction>0?FirstEntryLong[s]:FirstEntryShort[s],detectRisk=direction>0?FirstRiskLong[s]:FirstRiskShort[s];double currentExit=direction>0?LastBid[s]:LastAsk[s];
   x[0]=wait;x[1]=r1;x[2]=r5;x[3]=r30;x[4]=r5/MathMax(r30,.05);x[5]=alignedP1;x[6]=alignedP5;x[7]=alignedP30;x[8]=alignedP5;x[9]=(double)tp5/MathMax(1.0,r5*5)*direction;x[10]=accel*direction;x[11]=mc1*direction;x[12]=mc5*direction;x[13]=mc30*direction;
   double point=SymbolInfoDouble(Symbols[s],SYMBOL_POINT),spread=LastAsk[s]-LastBid[s],spreadPoints=point>0?spread/point:0;x[14]=spreadPoints;x[15]=sp5/MathMax(sp30,1e-12);x[16]=arrival;x[17]=(LastMid[s]-DayOpen[s])*direction;x[18]=(LastMid[s]-SessionOpen[s])*direction;x[19]=corrret*direction;x[20]=corralign;x[21]=corr;x[22]=0;x[23]=1440;x[24]=0;
   double tickSize=SymbolInfoDouble(Symbols[s],SYMBOL_TRADE_TICK_SIZE),tickValue=SymbolInfoDouble(Symbols[s],SYMBOL_TRADE_TICK_VALUE_LOSS),spreadCash=(tickSize>0&&tickValue>0)?spread/tickSize*tickValue:0;x[25]=tickSize;x[26]=spreadCash;
   BarState bars[4];bars[0]=M1[s];bars[1]=M5[s];bars[2]=M15[s];bars[3]=H1[s];for(int tf=0;tf<4;tf++){x[27+tf]=bars[tf].trend*direction;x[31+tf]=bars[tf].structure*direction;x[35+tf]=bars[tf].ret*direction;}x[39]=M1[s].vol_ratio;x[40]=M5[s].vol_ratio;x[41]=M15[s].vol_ratio;x[42]=(double)M1[s].tick_volume;x[43]=(double)M5[s].tick_volume;x[44]=(double)M15[s].tick_volume;x[45]=m1body;x[46]=m5body;x[47]=stop1;x[48]=stop5;x[49]=risk>0?spread/risk:99;
   x[50]=(p5-FirstPressure5[s])*direction;x[51]=r5-FirstRate5[s];x[52]=spreadPoints-FirstSpreadPoints[s];x[53]=(mc30-FirstMid30[s])*direction;x[54]=pullback?1:0;x[55]=resume?1:0;x[56]=transition;x[57]=(currentExit-detectEntry)*direction/MathMax(detectRisk,1e-12);x[58]=(LastBid[s]-FirstBid[s])*direction/atr1;x[59]=(LastAsk[s]-FirstAsk[s])*direction/atr1;
   for(int tf=0;tf<4;tf++)x[60+tf]=(double)(now-TrendStarted[s][tf]);x[64]=M1[s].ret*M1[s].close*direction/atr1;x[65]=M5[s].ret*M5[s].close*direction/MathMax(M5[s].atr,atr1);x[66]=M15[s].ret*M15[s].close*direction/MathMax(M15[s].atr,atr1);x[67]=MathMax(0.0,-mc30*direction/atr1);
   x[68]=(direction>0?M5[s].high-entry:entry-M5[s].low)/MathMax(detectRisk,1e-12);x[69]=(direction>0?M15[s].high-entry:entry-M15[s].low)/MathMax(detectRisk,1e-12);x[70]=(direction>0?entry-M5[s].low:M5[s].high-entry)/MathMax(detectRisk,1e-12);x[71]=(direction>0?entry-M15[s].low:M15[s].high-entry)/MathMax(detectRisk,1e-12);
   x[72]=x[6]*x[4];x[73]=x[6]*x[55];x[74]=x[56]*x[54];x[75]=x[56]*x[19];x[76]=x[4]*x[15];x[77]=x[56]*x[57];x[78]=x[27]*x[28];x[79]=x[28]*x[29];
  }

double Term(const int model,const int i,const double value)
  {
   if(model==0)return (value-V3_MEAN_0[i])/V3_SCALE_0[i]*V3_COEF_0[i];if(model==1)return (value-V3_MEAN_1[i])/V3_SCALE_1[i]*V3_COEF_1[i];if(model==2)return (value-V3_MEAN_2[i])/V3_SCALE_2[i]*V3_COEF_2[i];if(model==3)return (value-V3_MEAN_3[i])/V3_SCALE_3[i]*V3_COEF_3[i];if(model==4)return (value-V3_MEAN_4[i])/V3_SCALE_4[i]*V3_COEF_4[i];return (value-V3_MEAN_5[i])/V3_SCALE_5[i]*V3_COEF_5[i];
  }
double Intercept(const int model){if(model==0)return V3_INTERCEPT_0;if(model==1)return V3_INTERCEPT_1;if(model==2)return V3_INTERCEPT_2;if(model==3)return V3_INTERCEPT_3;if(model==4)return V3_INTERCEPT_4;return V3_INTERCEPT_5;}
double Score(const int model,const double &x[]){double value=Intercept(model);for(int i=0;i<V3_MODEL_FEATURE_COUNT;i++)value+=Term(model,i,x[i]);if(model<5)return 1.0/(1.0+MathExp(-MathMax(-35.0,MathMin(35.0,value))));return value;}

bool DetectOpportunity(const int s,int &hypothesis,string &family)
  {
   int c1,c5,c30,qp1,qp5,qp30,tp1,tp5,tp30;double r1,r5,r30,sp1,sp5,sp30,mc1,mc5,mc30,ia1,ia5,ia30;long tickUtc=LastTickMsc[s]-ServerOffsetSeconds*1000;WindowStats(s,tickUtc,1,c1,r1,qp1,tp1,sp1,mc1,ia1);WindowStats(s,tickUtc,5,c5,r5,qp5,tp5,sp5,mc5,ia5);WindowStats(s,tickUtc,30,c30,r30,qp30,tp30,sp30,mc30,ia30);double atr=MathMax(M1[s].atr,1e-12),move=mc30/atr,pressure=Pressure(qp5,r5,5),burst=r5/MathMax(r30,.05),raw=move+.35*pressure+.20*M1[s].trend+.10*M5[s].trend;hypothesis=raw>0?1:(raw<0?-1:0);bool active=MathAbs(move)>=.12||MathAbs(pressure)>=.30||burst>=1.8||MathAbs(M1[s].structure)>0;if(!active||hypothesis==0)return false;family=MathAbs(pressure)>=.30?"PRESSURE_BURST":(burst>=1.8?"RATE_BURST":"STRUCTURE_TRANSITION");return true;
  }

void StartOpportunity(const int s,const long now,const int hypothesis,const string family)
  {
   OpportunityCounter[s]++;OpportunityId[s]=Symbols[s]+"-"+IntegerToString(now)+"-"+StringFormat("%04d",OpportunityCounter[s]);OpportunityActive[s]=true;OpportunityDetected[s]=now;OpportunityExpiry[s]=now+WAIT_SECONDS;OpportunityLastObserved[s]=0;BlockedUntil[s]=now+EPISODE_INDEPENDENCE_SECONDS;OpportunityHypothesis[s]=hypothesis;OpportunityFamily[s]=family;
   int c1,c5,c30,qp1,qp5,qp30,tp1,tp5,tp30;double r1,r5,r30,sp1,sp5,sp30,mc1,mc5,mc30,ia1,ia5,ia30;long tickUtc=LastTickMsc[s]-ServerOffsetSeconds*1000;WindowStats(s,tickUtc,1,c1,r1,qp1,tp1,sp1,mc1,ia1);WindowStats(s,tickUtc,5,c5,r5,qp5,tp5,sp5,mc5,ia5);WindowStats(s,tickUtc,30,c30,r30,qp30,tp30,sp30,mc30,ia30);FirstPressure5[s]=Pressure(qp5,r5,5);FirstRate5[s]=r5;double point=SymbolInfoDouble(Symbols[s],SYMBOL_POINT);FirstSpreadPoints[s]=point>0?(LastAsk[s]-LastBid[s])/point:0;FirstMid30[s]=mc30;FirstBid[s]=LastBid[s];FirstAsk[s]=LastAsk[s];double stop,stop1,stop5;Geometry(s,1,FirstEntryLong[s],stop,FirstRiskLong[s],stop1,stop5);Geometry(s,-1,FirstEntryShort[s],stop,FirstRiskShort[s],stop1,stop5);TotalOpportunities++;WriteEvent(s,"OPPORTUNITY_DETECTED","",0,0,LastMid[s],family,(long)now*1000);
  }

void TriggerPosition(const int s,const int direction,const long now,const double ev,const double loss,const double bank,const double other)
  {
   double stop1,stop5;Geometry(s,direction,EntryPrice[s],InitialStop[s],InitialRisk[s],stop1,stop5);PositionActive[s]=true;PositionDirection[s]=direction;EntryUtc[s]=now;RunnerStop[s]=InitialStop[s];RunnerStopUtc[s]=now;RunnerTrailUpdates[s]=0;MfeR[s]=0;MaeR[s]=0;Bank1Reached[s]=false;BankUtc[s]=0;StructuralStopReached[s]=false;StructuralStopUtc[s]=0;BaselineTerminal[s]=false;BaselineExitR[s]=0;BaselineTerminalReason[s]="";LastCurrentR[s]=0;for(int c=0;c<CANDIDATE_COUNT;c++){Invalidated[s][c]=false;InvalidationUtc[s][c]=0;InvalidationR[s][c]=0;InvalidationTransition[s][c]=0;AfterMinus1[s][c]=false;AfterBreakeven[s][c]=false;AfterBank1[s][c]=false;AfterPlus2[s][c]=false;AfterPlus3[s][c]=false;AfterPlus5[s][c]=false;}OpportunityActive[s]=false;TotalTriggered++;WriteEvent(s,"ENTRY_TRIGGERED","",0,0,EntryPrice[s],StringFormat("expected_net_r=%.8f;full_loss_probability=%.8f;bank1_probability=%.8f;opposite_expected_net_r=%.8f;position_time_limit=false",ev,loss,bank,other),(long)now*1000);
  }

bool CandidateCondition(const int c,const double r,const double transition,const bool pullback,const bool resume,const double m1m5)
  {if(r>CandidateAdverse[c]||transition>CandidateTransition[c])return false;if(c==1)return !resume;if(c==2)return m1m5<=-1.0;if(c==3)return pullback&&!resume;return true;}

void FinalizePosition(const int s,const long terminalUtc,const bool rightCensored,const string terminalReason)
  {
   bool baselineKnown=!rightCensored&&BaselineTerminal[s];double baseline=baselineKnown?(Bank1Reached[s]?.5+.5*BaselineExitR[s]:BaselineExitR[s]):0;string baselineText=baselineKnown?DoubleToString(baseline,8):"";int h=OpenOutcome((datetime)terminalUtc);if(h!=INVALID_HANDLE)
     {
      for(int c=0;c<CANDIDATE_COUNT;c++)
        {
         bool causalKnown=Invalidated[s][c]||baselineKnown;bool bankedBeforeExit=Invalidated[s][c]&&BankUtc[s]>0&&BankUtc[s]<=InvalidationUtc[s][c];double causal=Invalidated[s][c]?(bankedBeforeExit?.5+.5*InvalidationR[s][c]:InvalidationR[s][c]):baseline;string causalText=causalKnown?DoubleToString(causal,8):"";string interrupted=baselineKnown?BoolText(Invalidated[s][c]&&baseline>0):"";
         FileWrite(h,OUTCOME_SCHEMA,TRACKER_VERSION,V3_TRACKING_MODEL_ID,OpportunityId[s],Symbols[s],SessionName(SessionId((datetime)EntryUtc[s])),PositionDirection[s]>0?"LONG":"SHORT",EntryUtc[s],terminalUtc,terminalUtc-EntryUtc[s],rightCensored?"RIGHT_CENSORED":"TERMINAL",terminalReason,BoolText(baselineKnown),BoolText(!rightCensored),DoubleToString(EntryPrice[s],10),DoubleToString(InitialStop[s],10),DoubleToString(InitialRisk[s],10),DoubleToString(RunnerStop[s],10),RunnerTrailUpdates[s],DoubleToString(MfeR[s],8),DoubleToString(MaeR[s],8),BoolText(Bank1Reached[s]),BankUtc[s],BoolText(StructuralStopReached[s]),baselineText,CandidateId[c],BoolText(Invalidated[s][c]),InvalidationUtc[s][c],Invalidated[s][c]?DoubleToString(InvalidationR[s][c],8):"",BoolText(causalKnown),causalText,BoolText(AfterMinus1[s][c]),BoolText(AfterBreakeven[s][c]),BoolText(AfterBank1[s][c]),BoolText(AfterPlus2[s][c]),BoolText(AfterPlus3[s][c]),BoolText(AfterPlus5[s][c]),interrupted,BoolText(Invalidated[s][c]&&MfeR[s]>=1),BoolText(Invalidated[s][c]&&MfeR[s]>=2),BoolText(Invalidated[s][c]&&MfeR[s]>=3),BoolText(Invalidated[s][c]&&MfeR[s]>=5),"true","false");
        }
     }
   WriteEvent(s,rightCensored?"RIGHT_CENSORED":"POSITION_LIFETIME_COMPLETE","",LastCurrentR[s],0,PositionDirection[s]>0?LastBid[s]:LastAsk[s],"terminal_reason="+terminalReason+";known_final_outcome="+BoolText(baselineKnown),(long)terminalUtc*1000);PositionActive[s]=false;TotalOutcomes++;if(rightCensored)TotalRightCensored++;
  }

void ObservePosition(const int s,const long now)
  {
   if(BaselineTerminal[s]){FinalizePosition(s,StructuralStopUtc[s],false,BaselineTerminalReason[s]);return;}
   UpdateRunnerStructuralStop(s,now);ProcessPositionTick(s,(long)now*1000,LastBid[s],LastAsk[s]);
   if(BaselineTerminal[s]){FinalizePosition(s,StructuralStopUtc[s],false,BaselineTerminalReason[s]);return;}
   if(ResearchSafetyHorizonDays>0&&now-EntryUtc[s]>=(long)ResearchSafetyHorizonDays*86400){FinalizePosition(s,now,true,"RESEARCH_SAFETY_HORIZON");return;}
   if(!FeatureWindowReady(s))return;
   double x[];double transition,r1,r5,r30,p1,p5,p30,sp5,sp30,mc1,mc5,mc30,arrival,corrret,corralign;bool pullback,resume;int corr;long corrlag;FillModelFeatures(s,PositionDirection[s],now,(int)(now-OpportunityDetected[s]),x,transition,pullback,resume,r1,r5,r30,p1,p5,p30,sp5,sp30,mc1,mc5,mc30,arrival,corr,corrret,corralign,corrlag);double r=CurrentR(s,LastBid[s],LastAsk[s]);double m1m5=(M1[s].trend+M5[s].trend)*PositionDirection[s];
   for(int c=0;c<CANDIDATE_COUNT;c++)if(!Invalidated[s][c]&&CandidateCondition(c,r,transition,pullback,resume,m1m5)){Invalidated[s][c]=true;InvalidationUtc[s][c]=now;InvalidationR[s][c]=r;InvalidationTransition[s][c]=transition;WriteEvent(s,"CAUSAL_INVALIDATION",CandidateId[c],r,transition,PositionDirection[s]>0?LastBid[s]:LastAsk[s],"adverse_r_and_material_evidence_failure",(long)now*1000);}
   int h=OpenObservation((datetime)now);if(h!=INVALID_HANDLE){double point=SymbolInfoDouble(Symbols[s],SYMBOL_POINT),spread=LastAsk[s]-LastBid[s],spreadPoints=point>0?spread/point:0,tickSize=SymbolInfoDouble(Symbols[s],SYMBOL_TRADE_TICK_SIZE),tickValue=SymbolInfoDouble(Symbols[s],SYMBOL_TRADE_TICK_VALUE_LOSS),spreadCash=(tickSize>0&&tickValue>0)?spread/tickSize*tickValue:0;
      string line="";
      AppendCsv(line,OBS_SCHEMA);AppendCsv(line,TRACKER_VERSION);AppendCsv(line,V3_TRACKING_MODEL_ID);AppendCsv(line,IntegerToString((long)now*1000));AppendCsv(line,OpportunityId[s]);AppendCsv(line,Symbols[s]);AppendCsv(line,PositionDirection[s]>0?"LONG":"SHORT");AppendCsv(line,IntegerToString(EntryUtc[s]));AppendCsv(line,IntegerToString(now-EntryUtc[s]));
      AppendCsv(line,DoubleToString(EntryPrice[s],10));AppendCsv(line,DoubleToString(InitialStop[s],10));AppendCsv(line,DoubleToString(InitialRisk[s],10));AppendCsv(line,DoubleToString(Bank1Reached[s]?RunnerStop[s]:InitialStop[s],10));AppendCsv(line,IntegerToString(RunnerStopUtc[s]));AppendCsv(line,IntegerToString(RunnerTrailUpdates[s]));AppendCsv(line,DoubleToString(PositionDirection[s]>0?LastBid[s]:LastAsk[s],10));AppendCsv(line,DoubleToString(r,8));AppendCsv(line,DoubleToString(MfeR[s],8));AppendCsv(line,DoubleToString(MaeR[s],8));AppendCsv(line,DoubleToString(LastBid[s],10));AppendCsv(line,DoubleToString(LastAsk[s],10));AppendCsv(line,DoubleToString((LastBid[s]-EntryPrice[s])*PositionDirection[s]/InitialRisk[s],8));AppendCsv(line,DoubleToString((LastAsk[s]-EntryPrice[s])*PositionDirection[s]/InitialRisk[s],8));
      AppendCsv(line,DoubleToString(r1,4));AppendCsv(line,DoubleToString(r5,4));AppendCsv(line,DoubleToString(r30,4));AppendCsv(line,DoubleToString(r5/MathMax(r30,.05),6));AppendCsv(line,DoubleToString(p1*PositionDirection[s],6));AppendCsv(line,DoubleToString(p5*PositionDirection[s],6));AppendCsv(line,DoubleToString(p30*PositionDirection[s],6));AppendCsv(line,BoolText(p5*PositionDirection[s]<0));AppendCsv(line,DoubleToString(x[10],8));AppendCsv(line,DoubleToString(x[11],10));AppendCsv(line,DoubleToString(x[12],10));AppendCsv(line,DoubleToString(x[13],10));AppendCsv(line,DoubleToString(spread,10));AppendCsv(line,DoubleToString(spreadPoints,3));AppendCsv(line,DoubleToString(sp5/MathMax(sp30,1e-12),6));AppendCsv(line,DoubleToString(arrival,3));AppendCsv(line,BoolText(pullback));AppendCsv(line,BoolText(resume));AppendCsv(line,DoubleToString(transition,8));
      AppendCsv(line,BarText(M1[s]));AppendCsv(line,BarText(M5[s]));AppendCsv(line,BarText(M15[s]));AppendCsv(line,BarText(H1[s]));AppendCsv(line,IntegerToString(corr));AppendCsv(line,DoubleToString(corrret,8));AppendCsv(line,DoubleToString(corralign,6));AppendCsv(line,IntegerToString(corrlag));AppendCsv(line,DoubleToString(M1[s].vol_ratio,6));AppendCsv(line,DoubleToString(M5[s].vol_ratio,6));AppendCsv(line,DoubleToString(M15[s].vol_ratio,6));AppendCsv(line,DoubleToString(spreadCash,6));AppendCsv(line,DoubleToString(spread/InitialRisk[s],8));AppendCsv(line,BoolText(Bank1Reached[s]));AppendCsv(line,IntegerToString(BankUtc[s]));AppendCsv(line,Bank1Reached[s]?"0.50":"0.00");AppendCsv(line,BoolText(Bank1Reached[s]&&!StructuralStopReached[s]));AppendCsv(line,BoolText(StructuralStopReached[s]));AppendCsv(line,IntegerToString(StructuralStopUtc[s]));AppendCsv(line,BoolText(PositionActive[s]&&!BaselineTerminal[s]));
      AppendCsv(line,BoolText(Invalidated[s][0]));AppendCsv(line,IntegerToString(InvalidationUtc[s][0]));AppendCsv(line,DoubleToString(InvalidationR[s][0],8));AppendCsv(line,BoolText(Invalidated[s][1]));AppendCsv(line,DoubleToString(InvalidationR[s][1],8));AppendCsv(line,BoolText(Invalidated[s][2]));AppendCsv(line,DoubleToString(InvalidationR[s][2],8));AppendCsv(line,BoolText(Invalidated[s][3]));AppendCsv(line,DoubleToString(InvalidationR[s][3],8));AppendCsv(line,"true");AppendCsv(line,"true");AppendCsv(line,"false");FileWriteString(h,line+"\r\n");TotalObservations++;}
  }

void ObserveOpportunity(const int s,const long now)
  {
   if(now>OpportunityExpiry[s]){WriteEvent(s,"OPPORTUNITY_ABANDONED","",0,0,LastMid[s],"TRANSITION_EXPIRED",(long)now*1000);OpportunityActive[s]=false;return;}if(OpportunityLastObserved[s]>0&&now-OpportunityLastObserved[s]<15)return;OpportunityLastObserved[s]=now;
   double xl[],xs[];double tl,ts,r1,r5,r30,p1,p5,p30,sp5,sp30,mc1,mc5,mc30,arrival,corrret,corralign;bool pl,rl,ps,rs;int corr;long corrlag;FillModelFeatures(s,1,now,(int)(now-OpportunityDetected[s]),xl,tl,pl,rl,r1,r5,r30,p1,p5,p30,sp5,sp30,mc1,mc5,mc30,arrival,corr,corrret,corralign,corrlag);FillModelFeatures(s,-1,now,(int)(now-OpportunityDetected[s]),xs,ts,ps,rs,r1,r5,r30,p1,p5,p30,sp5,sp30,mc1,mc5,mc30,arrival,corr,corrret,corralign,corrlag);
   double evl=Score(5,xl),evs=Score(5,xs);int direction=evl>=evs?1:-1;double ev=direction>0?evl:evs,other=direction>0?evs:evl;double loss=direction>0?Score(0,xl):Score(0,xs),bank=direction>0?Score(1,xl):Score(1,xs);if(ev>=V3_MIN_EV&&loss<=V3_MAX_FULL_LOSS&&bank>=V3_MIN_BANK1&&ev-other>=V3_DIRECTION_MARGIN)TriggerPosition(s,direction,now,ev,loss,bank,other);
  }

void ProcessObservationCycle(const long now)
  {
   RefreshBars(now);for(int s=0;s<SYMBOL_COUNT;s++)
     {
      if(LastTickMsc[s]<=0||!M1[s].ready||!M5[s].ready||!M15[s].ready||!H1[s].ready)continue;
      if(!SymbolFresh(s,now)){if(OpportunityActive[s]&&!PositionActive[s]){WriteEvent(s,"OPPORTUNITY_ABANDONED","",0,0,LastMid[s],"STALE_MARKET_NO_CURRENT_TICK",(long)now*1000);OpportunityActive[s]=false;}continue;}
      if(PositionActive[s]){ObservePosition(s,now);continue;}if(OpportunityActive[s]){ObserveOpportunity(s,now);continue;}if(now<BlockedUntil[s]||now<(long)StartedUtc+60)continue;int hypothesis;string family;if(DetectOpportunity(s,hypothesis,family))StartOpportunity(s,now,hypothesis,family);
     }
  }

void WriteStateValue(const int h,const string symbol,const string key,const string value){FileWrite(h,symbol,key,value);}
void SaveState()
  {
   string tmp=Root+"status\\state.tmp",path=Root+"status\\state.csv";int h=FileOpen(tmp,FILE_WRITE|FILE_CSV|FILE_ANSI,',');if(h==INVALID_HANDLE)return;FileWrite(h,"symbol","key","value");
   WriteStateValue(h,"__tracker__","total_ticks",IntegerToString(TotalTicks));WriteStateValue(h,"__tracker__","total_observations",IntegerToString(TotalObservations));WriteStateValue(h,"__tracker__","total_opportunities",IntegerToString(TotalOpportunities));WriteStateValue(h,"__tracker__","total_triggered",IntegerToString(TotalTriggered));WriteStateValue(h,"__tracker__","total_outcomes",IntegerToString(TotalOutcomes));WriteStateValue(h,"__tracker__","total_right_censored",IntegerToString(TotalRightCensored));WriteStateValue(h,"__tracker__","copy_errors",IntegerToString(CopyErrors));
   for(int s=0;s<SYMBOL_COUNT;s++)
     {
      string sym=Symbols[s];WriteStateValue(h,sym,"last_tick_msc",IntegerToString(LastTickMsc[s]));WriteStateValue(h,sym,"opportunity_counter",IntegerToString(OpportunityCounter[s]));WriteStateValue(h,sym,"blocked_until",IntegerToString(BlockedUntil[s]));WriteStateValue(h,sym,"opportunity_active",BoolText(OpportunityActive[s]));WriteStateValue(h,sym,"opportunity_id",OpportunityId[s]);WriteStateValue(h,sym,"opportunity_family",OpportunityFamily[s]);WriteStateValue(h,sym,"opportunity_detected",IntegerToString(OpportunityDetected[s]));WriteStateValue(h,sym,"opportunity_expiry",IntegerToString(OpportunityExpiry[s]));WriteStateValue(h,sym,"opportunity_last_observed",IntegerToString(OpportunityLastObserved[s]));WriteStateValue(h,sym,"opportunity_hypothesis",IntegerToString(OpportunityHypothesis[s]));WriteStateValue(h,sym,"first_pressure5",DoubleToString(FirstPressure5[s],12));WriteStateValue(h,sym,"first_rate5",DoubleToString(FirstRate5[s],12));WriteStateValue(h,sym,"first_spread_points",DoubleToString(FirstSpreadPoints[s],12));WriteStateValue(h,sym,"first_mid30",DoubleToString(FirstMid30[s],12));WriteStateValue(h,sym,"first_bid",DoubleToString(FirstBid[s],12));WriteStateValue(h,sym,"first_ask",DoubleToString(FirstAsk[s],12));WriteStateValue(h,sym,"first_entry_long",DoubleToString(FirstEntryLong[s],12));WriteStateValue(h,sym,"first_entry_short",DoubleToString(FirstEntryShort[s],12));WriteStateValue(h,sym,"first_risk_long",DoubleToString(FirstRiskLong[s],12));WriteStateValue(h,sym,"first_risk_short",DoubleToString(FirstRiskShort[s],12));
      WriteStateValue(h,sym,"position_active",BoolText(PositionActive[s]));WriteStateValue(h,sym,"position_direction",IntegerToString(PositionDirection[s]));WriteStateValue(h,sym,"entry_utc",IntegerToString(EntryUtc[s]));WriteStateValue(h,sym,"entry_price",DoubleToString(EntryPrice[s],12));WriteStateValue(h,sym,"initial_stop",DoubleToString(InitialStop[s],12));WriteStateValue(h,sym,"initial_risk",DoubleToString(InitialRisk[s],12));WriteStateValue(h,sym,"runner_stop",DoubleToString(RunnerStop[s],12));WriteStateValue(h,sym,"runner_stop_utc",IntegerToString(RunnerStopUtc[s]));WriteStateValue(h,sym,"runner_trail_updates",IntegerToString(RunnerTrailUpdates[s]));WriteStateValue(h,sym,"mfe_r",DoubleToString(MfeR[s],12));WriteStateValue(h,sym,"mae_r",DoubleToString(MaeR[s],12));WriteStateValue(h,sym,"bank1",BoolText(Bank1Reached[s]));WriteStateValue(h,sym,"bank_utc",IntegerToString(BankUtc[s]));WriteStateValue(h,sym,"structural_stop",BoolText(StructuralStopReached[s]));WriteStateValue(h,sym,"structural_stop_utc",IntegerToString(StructuralStopUtc[s]));WriteStateValue(h,sym,"baseline_terminal",BoolText(BaselineTerminal[s]));WriteStateValue(h,sym,"baseline_exit_r",DoubleToString(BaselineExitR[s],12));WriteStateValue(h,sym,"baseline_terminal_reason",BaselineTerminalReason[s]);WriteStateValue(h,sym,"last_current_r",DoubleToString(LastCurrentR[s],12));
      for(int c=0;c<CANDIDATE_COUNT;c++){string p="candidate_"+IntegerToString(c)+"_";WriteStateValue(h,sym,p+"invalidated",BoolText(Invalidated[s][c]));WriteStateValue(h,sym,p+"utc",IntegerToString(InvalidationUtc[s][c]));WriteStateValue(h,sym,p+"r",DoubleToString(InvalidationR[s][c],12));WriteStateValue(h,sym,p+"transition",DoubleToString(InvalidationTransition[s][c],12));WriteStateValue(h,sym,p+"minus1",BoolText(AfterMinus1[s][c]));WriteStateValue(h,sym,p+"breakeven",BoolText(AfterBreakeven[s][c]));WriteStateValue(h,sym,p+"bank1",BoolText(AfterBank1[s][c]));WriteStateValue(h,sym,p+"plus2",BoolText(AfterPlus2[s][c]));WriteStateValue(h,sym,p+"plus3",BoolText(AfterPlus3[s][c]));WriteStateValue(h,sym,p+"plus5",BoolText(AfterPlus5[s][c]));}
     }
   FileClose(h);FileMove(tmp,0,path,FILE_REWRITE);LastStateUtc=(datetime)UtcNow();
  }

int SymbolIndex(const string symbol){for(int s=0;s<SYMBOL_COUNT;s++)if(Symbols[s]==symbol)return s;return -1;}
bool ParseBool(const string value){return value=="true"||value=="1";}
void LoadState()
  {
   string path=Root+"status\\state.csv";if(!FileIsExist(path))return;int h=FileOpen(path,FILE_READ|FILE_CSV|FILE_ANSI,',');if(h==INVALID_HANDLE)return;for(int i=0;i<3;i++)FileReadString(h);
   while(!FileIsEnding(h)){string sym=FileReadString(h),key=FileReadString(h),value=FileReadString(h);if(sym=="__tracker__"){if(key=="total_ticks")TotalTicks=StringToInteger(value);else if(key=="total_observations")TotalObservations=StringToInteger(value);else if(key=="total_opportunities")TotalOpportunities=StringToInteger(value);else if(key=="total_triggered")TotalTriggered=StringToInteger(value);else if(key=="total_outcomes")TotalOutcomes=StringToInteger(value);else if(key=="total_right_censored")TotalRightCensored=StringToInteger(value);else if(key=="copy_errors")CopyErrors=StringToInteger(value);continue;}int s=SymbolIndex(sym);if(s<0)continue;if(key=="last_tick_msc")LastTickMsc[s]=StringToInteger(value);else if(key=="opportunity_counter")OpportunityCounter[s]=(int)StringToInteger(value);else if(key=="blocked_until")BlockedUntil[s]=StringToInteger(value);else if(key=="opportunity_active")OpportunityActive[s]=ParseBool(value);else if(key=="opportunity_id")OpportunityId[s]=value;else if(key=="opportunity_family")OpportunityFamily[s]=value;else if(key=="opportunity_detected")OpportunityDetected[s]=StringToInteger(value);else if(key=="opportunity_expiry")OpportunityExpiry[s]=StringToInteger(value);else if(key=="opportunity_last_observed")OpportunityLastObserved[s]=StringToInteger(value);else if(key=="opportunity_hypothesis")OpportunityHypothesis[s]=(int)StringToInteger(value);else if(key=="first_pressure5")FirstPressure5[s]=StringToDouble(value);else if(key=="first_rate5")FirstRate5[s]=StringToDouble(value);else if(key=="first_spread_points")FirstSpreadPoints[s]=StringToDouble(value);else if(key=="first_mid30")FirstMid30[s]=StringToDouble(value);else if(key=="first_bid")FirstBid[s]=StringToDouble(value);else if(key=="first_ask")FirstAsk[s]=StringToDouble(value);else if(key=="first_entry_long")FirstEntryLong[s]=StringToDouble(value);else if(key=="first_entry_short")FirstEntryShort[s]=StringToDouble(value);else if(key=="first_risk_long")FirstRiskLong[s]=StringToDouble(value);else if(key=="first_risk_short")FirstRiskShort[s]=StringToDouble(value);else if(key=="position_active")PositionActive[s]=ParseBool(value);else if(key=="position_direction")PositionDirection[s]=(int)StringToInteger(value);else if(key=="entry_utc")EntryUtc[s]=StringToInteger(value);else if(key=="entry_price")EntryPrice[s]=StringToDouble(value);else if(key=="initial_stop")InitialStop[s]=StringToDouble(value);else if(key=="initial_risk")InitialRisk[s]=StringToDouble(value);else if(key=="runner_stop")RunnerStop[s]=StringToDouble(value);else if(key=="runner_stop_utc")RunnerStopUtc[s]=StringToInteger(value);else if(key=="runner_trail_updates")RunnerTrailUpdates[s]=(int)StringToInteger(value);else if(key=="mfe_r")MfeR[s]=StringToDouble(value);else if(key=="mae_r")MaeR[s]=StringToDouble(value);else if(key=="bank1")Bank1Reached[s]=ParseBool(value);else if(key=="bank_utc")BankUtc[s]=StringToInteger(value);else if(key=="structural_stop")StructuralStopReached[s]=ParseBool(value);else if(key=="structural_stop_utc")StructuralStopUtc[s]=StringToInteger(value);else if(key=="baseline_terminal")BaselineTerminal[s]=ParseBool(value);else if(key=="baseline_exit_r")BaselineExitR[s]=StringToDouble(value);else if(key=="baseline_terminal_reason")BaselineTerminalReason[s]=value;else if(key=="last_current_r")LastCurrentR[s]=StringToDouble(value);else if(StringFind(key,"candidate_")==0){string parts[];int n=StringSplit(key,'_',parts);if(n==3){int c=(int)StringToInteger(parts[1]);if(c>=0&&c<CANDIDATE_COUNT){string field=parts[2];if(field=="invalidated")Invalidated[s][c]=ParseBool(value);else if(field=="utc")InvalidationUtc[s][c]=StringToInteger(value);else if(field=="r")InvalidationR[s][c]=StringToDouble(value);else if(field=="transition")InvalidationTransition[s][c]=StringToDouble(value);else if(field=="minus1")AfterMinus1[s][c]=ParseBool(value);else if(field=="breakeven")AfterBreakeven[s][c]=ParseBool(value);else if(field=="bank1")AfterBank1[s][c]=ParseBool(value);else if(field=="plus2")AfterPlus2[s][c]=ParseBool(value);else if(field=="plus3")AfterPlus3[s][c]=ParseBool(value);else if(field=="plus5")AfterPlus5[s][c]=ParseBool(value);}}}}
   FileClose(h);
  }

void WriteCandidates()
  {
   string path=Root+"frozen-invalidation-candidates.csv";int h=FileOpen(path,FILE_WRITE|FILE_CSV|FILE_ANSI,',');if(h==INVALID_HANDLE)return;FileWrite(h,"schema","candidate_id","adverse_r_lte","transition_score_lte","additional_requirement","frozen_before_forward_results","order_capability");for(int c=0;c<CANDIDATE_COUNT;c++){string requirement=c==0?"none":(c==1?"resumption_evidence=false":(c==2?"m1_plus_m5_trend_aligned<=-1":"pullback_expanding=true AND resumption_evidence=false"));FileWrite(h,"SOLTRADE_CAUSAL_INVALIDATION_CANDIDATE_V1",CandidateId[c],DoubleToString(CandidateAdverse[c],2),DoubleToString(CandidateTransition[c],2),requirement,"true","false");}FileClose(h);
  }

void WriteManifest()
  {
   string path=Root+"manifest.csv";int h=FileOpen(path,FILE_WRITE|FILE_CSV|FILE_ANSI,',');if(h==INVALID_HANDLE)return;FileWrite(h,"schema","tracker_version","model_id","created_utc","account","server","terminal_path","order_capability","trade_api_linked","forming_bar_data","production_authority","automatic_promotion","entry_specification","episode_independence_seconds","position_time_limit","baseline_terminal_path","research_safety_horizon_days","safety_horizon_disposition","bank_action","ratchet_deployed");FileWrite(h,"SOLTRADE_V3_LIFETIME_MANIFEST_V2",TRACKER_VERSION,V3_TRACKING_MODEL_ID,UtcNow(),AccountInfoInteger(ACCOUNT_LOGIN),AccountInfoString(ACCOUNT_SERVER),TerminalInfoString(TERMINAL_PATH),"false","false","false","false","false","FROZEN_V3_72_FEATURES_8_INTERACTIONS_THRESHOLDS",EPISODE_INDEPENDENCE_SECONDS,"none","INITIAL_STRUCTURAL_STOP_OR_BANK1R_THEN_MONOTONIC_COMPLETED_M5_M15_RUNNER_STOP",ResearchSafetyHorizonDays,"RIGHT_CENSORED","PLUS_1R_BANK_50_PERCENT_ONCE","false");FileClose(h);
  }

void WriteHeartbeat()
  {
   string tmp=Root+"status\\heartbeat.tmp",path=Root+"status\\heartbeat.csv";int h=FileOpen(tmp,FILE_WRITE|FILE_CSV|FILE_ANSI,',');if(h==INVALID_HANDLE)return;int activeOpp=0,activePos=0,overFourHours=0;long now=UtcNow();for(int s=0;s<SYMBOL_COUNT;s++){if(OpportunityActive[s])activeOpp++;if(PositionActive[s]){activePos++;if(now-EntryUtc[s]>EPISODE_INDEPENDENCE_SECONDS)overFourHours++;}}FileWrite(h,"schema","tracker_version","model_id","status","utc","started_utc","restart_count","account","server","connected","terminal_trade_allowed","mql_trade_allowed","order_capability","total_ticks","total_opportunities","total_triggered","active_opportunities","active_positions","active_positions_over_four_hours","lifetime_observations","completed_outcomes","right_censored_outcomes","position_time_limit","research_safety_horizon_days","copy_errors","symbols","state_utc");FileWrite(h,"SOLTRADE_V3_LIFETIME_HEARTBEAT_V2",TRACKER_VERSION,V3_TRACKING_MODEL_ID,"COLLECTING_FULL_LIFETIMES",now,StartedUtc,RestartCount,AccountInfoInteger(ACCOUNT_LOGIN),AccountInfoString(ACCOUNT_SERVER),BoolText(TerminalInfoInteger(TERMINAL_CONNECTED)),BoolText(TerminalInfoInteger(TERMINAL_TRADE_ALLOWED)),BoolText(MQLInfoInteger(MQL_TRADE_ALLOWED)),"false",TotalTicks,TotalOpportunities,TotalTriggered,activeOpp,activePos,overFourHours,TotalObservations,TotalOutcomes,TotalRightCensored,"none",ResearchSafetyHorizonDays,CopyErrors,SYMBOL_COUNT,LastStateUtc);FileClose(h);FileMove(tmp,0,path,FILE_REWRITE);
  }

int OnInit()
  {
   string path=TerminalInfoString(TERMINAL_PATH);StringToLower(path);if(!ObserverConfirmed||StringFind(path,"soltrade-full-lifetime-tracker-v1")<0||MQLInfoInteger(MQL_TESTER))return INIT_FAILED;if(AccountInfoInteger(ACCOUNT_LOGIN)!=7404213||AccountInfoString(ACCOUNT_SERVER)!="FPMarketsSC-Demo")return INIT_FAILED;if(MQLInfoInteger(MQL_TRADE_ALLOWED)||TerminalInfoInteger(TERMINAL_TRADE_ALLOWED))return INIT_FAILED;if(ResearchSafetyHorizonDays<0)return INIT_PARAMETERS_INCORRECT;StartedUtc=(datetime)UtcNow();ServerOffsetSeconds=OffsetNow();EnsureFolders(StartedUtc);LoadState();for(int s=0;s<SYMBOL_COUNT;s++)if(PositionActive[s]&&RunnerStop[s]<=0)RunnerStop[s]=InitialStop[s];string restartPath=Root+"status\\restart-count.txt";if(FileIsExist(restartPath)){int f=FileOpen(restartPath,FILE_READ|FILE_TXT|FILE_ANSI);if(f!=INVALID_HANDLE){RestartCount=(int)StringToInteger(FileReadString(f));FileClose(f);}}RestartCount++;int rf=FileOpen(restartPath,FILE_WRITE|FILE_TXT|FILE_ANSI);if(rf!=INVALID_HANDLE){FileWriteString(rf,IntegerToString(RestartCount));FileClose(rf);}WriteCandidates();WriteManifest();SaveState();WriteHeartbeat();if(!EventSetMillisecondTimer(MathMax(100,TimerMilliseconds)))return INIT_FAILED;return INIT_SUCCEEDED;
  }

void OnDeinit(const int reason){EventKillTimer();SaveState();WriteHeartbeat();CloseHandle(ObsHandle);CloseHandle(EventHandle);CloseHandle(OutcomeHandle);}

void OnTimer()
  {
   if(AccountInfoInteger(ACCOUNT_LOGIN)!=7404213||AccountInfoString(ACCOUNT_SERVER)!="FPMarketsSC-Demo")return;if(MQLInfoInteger(MQL_TRADE_ALLOWED)||TerminalInfoInteger(TERMINAL_TRADE_ALLOWED)){ExpertRemove();return;}if(!TerminalInfoInteger(TERMINAL_CONNECTED)){WriteHeartbeat();return;}ServerOffsetSeconds=OffsetNow();for(int s=0;s<SYMBOL_COUNT;s++)CollectSymbol(s);long now=UtcNow();if(LastObservationUtc==0||now-LastObservationUtc>=ObservationIntervalSeconds){ProcessObservationCycle(now);LastObservationUtc=(datetime)now;}if(LastStateUtc==0||now-LastStateUtc>=1)SaveState();if(LastFlushUtc==0||now-LastFlushUtc>=FlushIntervalSeconds){if(ObsHandle!=INVALID_HANDLE)FileFlush(ObsHandle);if(EventHandle!=INVALID_HANDLE)FileFlush(EventHandle);if(OutcomeHandle!=INVALID_HANDLE)FileFlush(OutcomeHandle);WriteHeartbeat();LastFlushUtc=(datetime)now;}
  }
