#property strict
#property version   "1.010"
#property description "Exact-account demo-only fast multi-market scanner, execution, and management"

#include <Trade/Trade.mqh>

input bool   SetupEnabled=true;
input bool   DemoExecutionConfirmed=false;
input bool   DryRunOnly=true;
input long   ApprovedDemoAccount=0;
input string ApprovedDemoServer="FPMarketsSC-Demo";
input long   FastMagic=2108202601;
input double RiskPerTradePercent=0.25;
input double MaxPortfolioRiskPercent=1.50;
input int    MaxSimultaneousTrades=6;
input int    MaxStronglyCorrelatedTrades=2;
input int    ScanSeconds=10;
input int    MaxTickAgeSeconds=8;
input double MaxSpreadAtrPercent=8.0;
input double MinMovementToSpread=5.0;
input double MinRewardRisk=1.25;
input double MinEntryScore=66.0;
input int    MaxSlippagePoints=12;

#define REQUIRED_DEMO_LOGIN 7404213
#define LEGACY_PILOT_MAGIC 2082026032
#define LEGACY_PILOT_TARGET_POSITIONS 3
#define SYMBOL_COUNT 19
#define PRIORITY_COUNT 9

string BASE_SYMBOLS[SYMBOL_COUNT]={
   "XAUUSD","USTEC","GBPJPY","XAGUSD","DE30","EURJPY","AUDJPY","USDJPY","GBPUSD",
   "EURUSD","US500","USDCAD","AUDUSD","NZDUSD","USDCHF","STOXX50","UK100","EURGBP","AUDNZD"
};

struct MarketScore
  {
   string symbol;
   bool available;
   bool eligible;
   bool fresh;
   int priority;
   int direction;
   double score;
   double buy_score;
   double sell_score;
   double spread;
   double spread_atr_pct;
   double movement_spread;
   double atr;
   double acceleration;
   double reward_r;
   double entry;
   double stop;
   string regime;
   string behaviour;
   string decision;
   string reason;
  };

CTrade g_trade;
MarketScore g_ranked[];
string g_suffix=".r";
string g_symbols[SYMBOL_COUNT];
string g_cached_symbols[SYMBOL_COUNT];
string g_mapping_status[SYMBOL_COUNT];
string g_mapping_source[SYMBOL_COUNT];
long g_last_scan_bucket=-1;
bool g_initialised=false;
bool g_immediate_rescan_requested=false;
string g_status_reason="STARTING";

string BoolText(const bool value) { return value?"true":"false"; }
string DirectionText(const int direction) { return direction>0?"BUY":direction<0?"SELL":"NONE"; }

bool DemoIdentitySafe(string &reason)
  {
   reason="";
   if((bool)MQLInfoInteger(MQL_TESTER)) { reason="TESTER_NOT_AUTHORIZED_FOR_CONNECTED_SETUP"; return false; }
   long login=(long)AccountInfoInteger(ACCOUNT_LOGIN);
   if(login!=REQUIRED_DEMO_LOGIN || login!=ApprovedDemoAccount) { reason="EXACT_DEMO_LOGIN_MISMATCH"; return false; }
   if(AccountInfoString(ACCOUNT_SERVER)!=ApprovedDemoServer) { reason="EXACT_DEMO_SERVER_MISMATCH"; return false; }
   if((ENUM_ACCOUNT_TRADE_MODE)AccountInfoInteger(ACCOUNT_TRADE_MODE)!=ACCOUNT_TRADE_MODE_DEMO)
     { reason="REAL_OR_NON_DEMO_ACCOUNT_BLOCKED"; return false; }
   if(!SetupEnabled || !DemoExecutionConfirmed) { reason="DEMO_EXECUTION_INTERLOCK_OFF"; return false; }
   if(!(bool)AccountInfoInteger(ACCOUNT_TRADE_ALLOWED) || !(bool)TerminalInfoInteger(TERMINAL_TRADE_ALLOWED) ||
      !(bool)MQLInfoInteger(MQL_TRADE_ALLOWED)) { reason="TRADING_PERMISSION_OFF"; return false; }
   if(AccountInfoInteger(ACCOUNT_MARGIN_MODE)!=ACCOUNT_MARGIN_MODE_RETAIL_HEDGING)
     { reason="HEDGING_ACCOUNT_REQUIRED"; return false; }
   return true;
  }

string ConfiguredSymbol(const int index)
  { return BASE_SYMBOLS[index]+g_suffix; }

bool IsIndexAliasMarket(const int index)
  { return index==1 || index==4 || index==10 || index==15 || index==16; }

string NormalizedMetadata(string value)
  {
   StringToUpper(value);
   string normalized="";
   for(int i=0;i<StringLen(value);i++)
     {
      ushort character=StringGetCharacter(value,i);
      if((character>='A' && character<='Z') || (character>='0' && character<='9'))
         normalized+=ShortToString(character);
     }
   return normalized;
  }

bool ContainsText(const string text,const string token)
  { return StringFind(text,token)>=0; }

bool StartsWithText(const string text,const string prefix)
  { return StringFind(text,prefix)==0; }

bool AliasNameMatches(const int index,const string symbol)
  {
   string name=NormalizedMetadata(symbol);
   if(index==1)
      return StartsWithText(name,"USTEC") || StartsWithText(name,"NAS100") || StartsWithText(name,"US100") ||
             StartsWithText(name,"NASDAQ") || StartsWithText(name,"NDX");
   if(index==4)
      return StartsWithText(name,"DE30") || StartsWithText(name,"DE40") || StartsWithText(name,"GER30") ||
             StartsWithText(name,"GER40") || StartsWithText(name,"DAX");
   if(index==10)
      return StartsWithText(name,"US500") || StartsWithText(name,"SPX500") || StartsWithText(name,"SP500");
   if(index==15)
      return StartsWithText(name,"STOXX50") || StartsWithText(name,"EU50") || StartsWithText(name,"ESTX50") ||
             StartsWithText(name,"EURO50");
   if(index==16)
      return StartsWithText(name,"UK100") || StartsWithText(name,"FTSE100");
   return false;
  }

bool MarketMetadataMatches(const int index,const string symbol)
  {
   if(!AliasNameMatches(index,symbol)) return false;
   string description=NormalizedMetadata(SymbolInfoString(symbol,SYMBOL_DESCRIPTION));
   string path=NormalizedMetadata(SymbolInfoString(symbol,SYMBOL_PATH));
   string metadata=description+path;
   if(ContainsText(metadata,"FUTURE")) return false;
   bool index_context=ContainsText(metadata,"INDEX") || ContainsText(metadata,"INDICES") ||
                      ContainsText(metadata,"CASH") || ContainsText(metadata,"CFD");
   bool identity_context=false;
   if(index==1)
      identity_context=ContainsText(metadata,"USTEC") || ContainsText(metadata,"NAS100") ||
                       ContainsText(metadata,"US100") || ContainsText(metadata,"NASDAQ") ||
                       ContainsText(metadata,"NDX") || ContainsText(metadata,"USTECH100");
   else if(index==4)
      identity_context=ContainsText(metadata,"DE30") || ContainsText(metadata,"DE40") ||
                       ContainsText(metadata,"GER30") || ContainsText(metadata,"GER40") ||
                       ContainsText(metadata,"DAX") || ContainsText(metadata,"GERMANY30") ||
                       ContainsText(metadata,"GERMANY40");
   else if(index==10)
      identity_context=ContainsText(metadata,"US500") || ContainsText(metadata,"SPX500") ||
                       ContainsText(metadata,"SP500") || ContainsText(metadata,"STANDARDPOORS500");
   else if(index==15)
      identity_context=ContainsText(metadata,"STOXX50") || ContainsText(metadata,"EU50") ||
                       ContainsText(metadata,"ESTX50") || ContainsText(metadata,"EURO50") ||
                       ContainsText(metadata,"EUROSTOXX50") ||
                       ContainsText(metadata,"EUROPE50");
   else if(index==16)
      identity_context=ContainsText(metadata,"UK100") || ContainsText(metadata,"FTSE100") ||
                       ContainsText(metadata,"UKFOOTSIE100");
   return index_context && (identity_context || AliasNameMatches(index,description));
  }

bool VerifyResolvedSymbol(const int index,const string symbol,string &reason)
  {
   reason="";
   if(symbol=="" || !SymbolSelect(symbol,true) || !SymbolInfoInteger(symbol,SYMBOL_EXIST))
     { reason="NOT_IN_BROKER_CATALOGUE"; return false; }
   if(!MarketMetadataMatches(index,symbol))
     { reason="METADATA_IDENTITY_MISMATCH"; return false; }
   if((ENUM_SYMBOL_TRADE_MODE)SymbolInfoInteger(symbol,SYMBOL_TRADE_MODE)!=SYMBOL_TRADE_MODE_FULL)
     { reason="TRADE_NOT_FULLY_ENABLED"; return false; }
   double point=SymbolInfoDouble(symbol,SYMBOL_POINT);
   double tick_size=SymbolInfoDouble(symbol,SYMBOL_TRADE_TICK_SIZE);
   double contract_size=SymbolInfoDouble(symbol,SYMBOL_TRADE_CONTRACT_SIZE);
   double min_volume=SymbolInfoDouble(symbol,SYMBOL_VOLUME_MIN);
   double max_volume=SymbolInfoDouble(symbol,SYMBOL_VOLUME_MAX);
   double volume_step=SymbolInfoDouble(symbol,SYMBOL_VOLUME_STEP);
   if(point<=0 || tick_size<=0 || contract_size<=0 || min_volume<=0 || max_volume<min_volume || volume_step<=0)
     { reason="INVALID_CONTRACT_SPECIFICATION"; return false; }
   MqlTick tick;
   if(!SymbolInfoTick(symbol,tick) || tick.bid<=0 || tick.ask<=tick.bid)
     { reason="INVALID_BID_ASK"; return false; }
   long reference_msc=(long)TimeTradeServer()*1000;
   double tick_age=MathMax(0.0,(reference_msc-tick.time_msc)/1000.0);
   if(tick_age>MaxTickAgeSeconds)
     { reason="STALE_TICK"; return false; }
   double test_distance=MathMax(100.0*point,10.0*tick_size);
   double buy_risk=0,sell_risk=0;
   if(!OrderCalcProfit(ORDER_TYPE_BUY,symbol,min_volume,tick.ask,tick.ask-test_distance,buy_risk) || buy_risk>=0 ||
      !OrderCalcProfit(ORDER_TYPE_SELL,symbol,min_volume,tick.bid,tick.bid+test_distance,sell_risk) || sell_risk>=0)
     { reason="RISK_CALCULATOR_UNUSABLE"; return false; }
   reason="FULL_TRADE_FRESH_CONTRACT_RISK_OK";
   return true;
  }

int AliasCandidateScore(const int index,const string symbol)
  {
   string name=NormalizedMetadata(symbol);
   string configured=NormalizedMetadata(ConfiguredSymbol(index));
   int score=name==configured?1000:100;
   if(StringFind(symbol,".r")>=0 || StringFind(symbol,".R")>=0) score+=30;
   string metadata=NormalizedMetadata(SymbolInfoString(symbol,SYMBOL_DESCRIPTION)+SymbolInfoString(symbol,SYMBOL_PATH));
   if(ContainsText(metadata,"CASH")) score+=20;
   if(ContainsText(metadata,"INDEX") || ContainsText(metadata,"INDICES")) score+=10;
   return score;
  }

bool DiscoverIndexSymbol(const int index)
  {
   string cached_reason;
   if(g_cached_symbols[index]!="" && VerifyResolvedSymbol(index,g_cached_symbols[index],cached_reason))
     {
      g_symbols[index]=g_cached_symbols[index];
      g_mapping_status[index]=cached_reason;
      g_mapping_source[index]="CACHE_REVALIDATED";
      return true;
     }
   string best="",best_status="";
   int best_score=-1,best_count=0;
   int total=SymbolsTotal(false);
   for(int position=0;position<total;position++)
     {
      string candidate=SymbolName(position,false);
      if(candidate=="" || !AliasNameMatches(index,candidate) || !MarketMetadataMatches(index,candidate)) continue;
      string validation;
      if(!VerifyResolvedSymbol(index,candidate,validation)) continue;
      int score=AliasCandidateScore(index,candidate);
      if(score>best_score) { best=candidate; best_status=validation; best_score=score; best_count=1; }
      else if(score==best_score && candidate!=best) best_count++;
     }
   if(best=="" || best_count!=1)
     {
      g_symbols[index]="";
      g_mapping_status[index]=best_count>1?"AMBIGUOUS_VERIFIED_ALIASES":"NO_VERIFIED_ALIAS";
      g_mapping_source[index]="BROKER_ENUMERATION";
      return false;
     }
   g_symbols[index]=best;
   g_cached_symbols[index]=best;
   g_mapping_status[index]=best_status;
   g_mapping_source[index]="BROKER_ENUMERATION";
   return true;
  }

void LoadMappingCache()
  {
   int handle=FileOpen("SolTradeFastMultiMarketV1\\symbol-map.csv",FILE_READ|FILE_CSV|FILE_ANSI|FILE_COMMON,',');
   if(handle==INVALID_HANDLE) return;
   while(!FileIsEnding(handle))
     {
      string schema=FileReadString(handle);
      string server=FileReadString(handle);
      string intended=FileReadString(handle);
      string actual=FileReadString(handle);
      if(schema!="SOLTRADE_FAST_SYMBOL_MAP_V1" || server!=AccountInfoString(ACCOUNT_SERVER)) continue;
      for(int i=0;i<SYMBOL_COUNT;i++)
         if(IsIndexAliasMarket(i) && intended==ConfiguredSymbol(i)) g_cached_symbols[i]=actual;
     }
   FileClose(handle);
  }

void SaveMappingCache()
  {
   int handle=FileOpen("SolTradeFastMultiMarketV1\\symbol-map.csv",FILE_WRITE|FILE_CSV|FILE_ANSI|FILE_COMMON,',');
   if(handle==INVALID_HANDLE) return;
   for(int i=0;i<SYMBOL_COUNT;i++)
      if(IsIndexAliasMarket(i) && g_cached_symbols[i]!="")
         FileWrite(handle,"SOLTRADE_FAST_SYMBOL_MAP_V1",AccountInfoString(ACCOUNT_SERVER),ConfiguredSymbol(i),g_cached_symbols[i]);
   FileFlush(handle);
   FileClose(handle);
  }

void WriteBrokerSymbolCatalogue()
  {
   int handle=FileOpen("SolTradeFastMultiMarketV1\\broker-symbol-catalogue.csv",FILE_WRITE|FILE_CSV|FILE_ANSI|FILE_COMMON,',');
   if(handle==INVALID_HANDLE) return;
   FileWrite(handle,"symbol","description","path","trade_mode");
   int total=SymbolsTotal(false);
   for(int i=0;i<total;i++)
     {
      string symbol=SymbolName(i,false);
      if(symbol!="")
         FileWrite(handle,symbol,SymbolInfoString(symbol,SYMBOL_DESCRIPTION),SymbolInfoString(symbol,SYMBOL_PATH),
                   EnumToString((ENUM_SYMBOL_TRADE_MODE)SymbolInfoInteger(symbol,SYMBOL_TRADE_MODE)));
     }
   FileFlush(handle);
   FileClose(handle);
  }

bool SelectUniverse()
  {
   WriteBrokerSymbolCatalogue();
   LoadMappingCache();
   int selected=0;
   for(int i=0;i<SYMBOL_COUNT;i++)
     {
      if(IsIndexAliasMarket(i))
        {
         if(DiscoverIndexSymbol(i)) selected++;
         continue;
        }
      g_symbols[i]=ConfiguredSymbol(i);
      g_mapping_status[i]="CONFIGURED_EXACT";
      g_mapping_source[i]="CONFIGURATION";
      if(SymbolSelect(g_symbols[i],true) && SymbolInfoInteger(g_symbols[i],SYMBOL_EXIST)) selected++;
     }
   SaveMappingCache();
   return selected>0;
  }

double TrueRange(const MqlRates &current,const MqlRates &previous)
  {
   return MathMax(current.high-current.low,
                  MathMax(MathAbs(current.high-previous.close),MathAbs(current.low-previous.close)));
  }

double AverageRange(MqlRates &rates[],const int from,const int count)
  {
   double total=0;
   for(int i=from;i<from+count;i++) total+=TrueRange(rates[i],rates[i+1]);
   return count>0?total/count:0;
  }

double AverageClose(MqlRates &rates[],const int from,const int count)
  {
   double total=0;
   for(int i=from;i<from+count;i++) total+=rates[i].close;
   return count>0?total/count:0;
  }

double HighestHigh(MqlRates &rates[],const int from,const int count)
  {
   double value=-DBL_MAX;
   for(int i=from;i<from+count;i++) value=MathMax(value,rates[i].high);
   return value;
  }

double LowestLow(MqlRates &rates[],const int from,const int count)
  {
   double value=DBL_MAX;
   for(int i=from;i<from+count;i++) value=MathMin(value,rates[i].low);
   return value;
  }

double Clamp(const double value,const double low,const double high)
  { return MathMax(low,MathMin(high,value)); }

string ThemeForSymbol(const string symbol)
  {
   string intended=symbol;
   for(int i=0;i<SYMBOL_COUNT;i++)
      if(g_symbols[i]!="" && g_symbols[i]==symbol) { intended=BASE_SYMBOLS[i]; break; }
   if(StringFind(intended,"XAUUSD")==0 || StringFind(intended,"XAGUSD")==0) return "METALS_USD";
   if(StringFind(intended,"USTEC")==0 || StringFind(intended,"US500")==0) return "US_RISK_INDEX";
   if(StringFind(intended,"DE30")==0 || StringFind(intended,"STOXX50")==0 || StringFind(intended,"UK100")==0) return "EUROPE_INDEX";
   if(StringFind(intended,"JPY")>=0) return "JPY_FACTOR";
   if(StringFind(intended,"USD")>=0) return "USD_FX";
   if(StringFind(intended,"AUD")>=0 || StringFind(intended,"NZD")>=0) return "ANTIPODEAN_FX";
   return "EUROPE_FX";
  }

bool ScoreSymbol(const int index,MarketScore &out)
  {
   ZeroMemory(out);
   if(IsIndexAliasMarket(index) && g_symbols[index]=="")
     {
      if(DiscoverIndexSymbol(index)) SaveMappingCache();
      else
        {
         out.symbol=ConfiguredSymbol(index);
         out.priority=index<PRIORITY_COUNT?2:1;
         out.reason=g_mapping_status[index];
         return false;
        }
     }
   out.symbol=g_symbols[index];
   out.priority=index<PRIORITY_COUNT?2:1;
   out.reason="NO_DATA";
   if(!SymbolSelect(out.symbol,true) || !SymbolInfoInteger(out.symbol,SYMBOL_EXIST)) return false;
   out.available=true;
   MqlTick tick;
   if(!SymbolInfoTick(out.symbol,tick) || tick.bid<=0 || tick.ask<=tick.bid) return false;
   MqlRates rates[]; ArraySetAsSeries(rates,true);
   int copied=CopyRates(out.symbol,PERIOD_M5,0,90,rates);
   if(copied<70) { out.reason="INSUFFICIENT_M5_HISTORY"; return false; }

   long reference_msc=(long)TimeTradeServer()*1000;
   double tick_age=MathMax(0.0,(reference_msc-tick.time_msc)/1000.0);
   out.fresh=tick_age<=MaxTickAgeSeconds;
   out.spread=tick.ask-tick.bid;
   out.atr=AverageRange(rates,1,14);
   if(out.atr<=0) { out.reason="ATR_INVALID"; return true; }
   out.spread_atr_pct=100.0*out.spread/out.atr;

   double movement=MathAbs(rates[1].close-rates[7].close);
   out.movement_spread=movement/MathMax(out.spread,SymbolInfoDouble(out.symbol,SYMBOL_POINT));
   double fast=AverageClose(rates,1,8),slow=AverageClose(rates,1,24);
   double momentum=rates[1].close-rates[4].close;
   double prior_momentum=rates[4].close-rates[7].close;
   out.acceleration=(momentum-prior_momentum)/out.atr;
   double prior_high=HighestHigh(rates,2,20),prior_low=LowestLow(rates,2,20);
   bool breakout_up=rates[1].close>prior_high;
   bool breakout_down=rates[1].close<prior_low;
   double body=MathAbs(rates[1].close-rates[1].open);
   double upper_wick=rates[1].high-MathMax(rates[1].open,rates[1].close);
   double lower_wick=MathMin(rates[1].open,rates[1].close)-rates[1].low;
   bool reject_up=lower_wick>MathMax(body,0.15*out.atr) && rates[1].close>rates[1].open;
   bool reject_down=upper_wick>MathMax(body,0.15*out.atr) && rates[1].close<rates[1].open;

   double trend_strength=(fast-slow)/out.atr;
   double momentum_strength=momentum/out.atr;
   double movement_quality=Clamp(out.movement_spread/12.0,0.0,1.0);
   double spread_quality=Clamp(1.0-out.spread_atr_pct/MaxSpreadAtrPercent,0.0,1.0);
   out.buy_score=20.0+18.0*Clamp(trend_strength,0.0,1.5)/1.5+
                 17.0*Clamp(momentum_strength,0.0,1.2)/1.2+
                 10.0*Clamp(out.acceleration,0.0,1.0)+12.0*movement_quality+10.0*spread_quality+
                 (breakout_up?10.0:0.0)+(reject_up?6.0:0.0)+(out.priority==2?2.0:0.0);
   out.sell_score=20.0+18.0*Clamp(-trend_strength,0.0,1.5)/1.5+
                  17.0*Clamp(-momentum_strength,0.0,1.2)/1.2+
                  10.0*Clamp(-out.acceleration,0.0,1.0)+12.0*movement_quality+10.0*spread_quality+
                  (breakout_down?10.0:0.0)+(reject_down?6.0:0.0)+(out.priority==2?2.0:0.0);
   out.direction=out.buy_score>=out.sell_score?1:-1;
   out.score=MathMax(out.buy_score,out.sell_score);
   out.entry=out.direction>0?tick.ask:tick.bid;

   double structural_stop=out.direction>0?LowestLow(rates,1,12):HighestHigh(rates,1,12);
   double stop_distance=MathMax(1.10*out.atr,3.0*out.spread);
   if(out.direction>0 && structural_stop<out.entry) stop_distance=MathMax(stop_distance,out.entry-structural_stop+0.10*out.atr);
   if(out.direction<0 && structural_stop>out.entry) stop_distance=MathMax(stop_distance,structural_stop-out.entry+0.10*out.atr);
   stop_distance=MathMin(stop_distance,2.25*out.atr);
   double point=SymbolInfoDouble(out.symbol,SYMBOL_POINT);
   double broker_min=MathMax((double)SymbolInfoInteger(out.symbol,SYMBOL_TRADE_STOPS_LEVEL),
                             (double)SymbolInfoInteger(out.symbol,SYMBOL_TRADE_FREEZE_LEVEL))*point;
   stop_distance=MathMax(stop_distance,broker_min+2.0*point);
   out.stop=out.direction>0?out.entry-stop_distance:out.entry+stop_distance;

   double opposing=out.direction>0?HighestHigh(rates,2,60):LowestLow(rates,2,60);
   double room=out.direction>0?opposing-out.entry:out.entry-opposing;
   if(room<=0) room=1.5*out.atr;
   out.reward_r=room/stop_distance;

   if(MathAbs(trend_strength)<0.18 && MathAbs(momentum_strength)<0.18) out.regime="CHOP";
   else if(MathAbs(trend_strength)>0.55 && MathAbs(momentum_strength)>0.35) out.regime="TREND_ACCELERATING";
   else out.regime="DIRECTIONAL_TRANSITION";
   out.behaviour=breakout_up?"BREAKOUT_UP":breakout_down?"BREAKOUT_DOWN":reject_up?"BULL_REJECTION":reject_down?"BEAR_REJECTION":"STRUCTURE_INSIDE";

   if(!out.fresh) out.reason="STALE_TICK";
   else if(out.spread_atr_pct>MaxSpreadAtrPercent) out.reason="ABNORMAL_SPREAD";
   else if(out.movement_spread<MinMovementToSpread) out.reason="MOVEMENT_WEAK_RELATIVE_TO_SPREAD";
   else if(out.regime=="CHOP") out.reason="CHOP";
   else if(out.reward_r<MinRewardRisk) out.reason="OPPOSING_STRUCTURE_TOO_CLOSE";
   else if(out.score<MinEntryScore) out.reason="DIRECTIONAL_EVIDENCE_WEAK";
   else { out.eligible=true; out.reason="QUALIFIED"; }
   out.decision=out.eligible?DirectionText(out.direction):"NO_TRADE";
   return true;
  }

void SortRanked()
  {
   int n=ArraySize(g_ranked);
   for(int i=0;i<n-1;i++) for(int j=i+1;j<n;j++)
     {
      double a=(g_ranked[i].eligible?1000.0:0.0)+g_ranked[i].score;
      double b=(g_ranked[j].eligible?1000.0:0.0)+g_ranked[j].score;
      if(b>a) { MarketScore swap=g_ranked[i]; g_ranked[i]=g_ranked[j]; g_ranked[j]=swap; }
     }
  }

bool HasSymbolPosition(const string symbol)
  {
   for(int i=PositionsTotal()-1;i>=0;i--)
     { ulong ticket=PositionGetTicket(i); if(ticket>0 && PositionGetString(POSITION_SYMBOL)==symbol) return true; }
   return false;
  }

double PositionRiskAmount(const ulong ticket)
  {
   if(!PositionSelectByTicket(ticket)) return 0;
   double sl=PositionGetDouble(POSITION_SL),volume=PositionGetDouble(POSITION_VOLUME);
   if(sl<=0 || volume<=0) return 0;
   string symbol=PositionGetString(POSITION_SYMBOL);
   long type=PositionGetInteger(POSITION_TYPE);
   MqlTick tick; if(!SymbolInfoTick(symbol,tick)) return 0;
   double from=type==POSITION_TYPE_BUY?tick.bid:tick.ask;
   if((type==POSITION_TYPE_BUY && sl>=from) || (type==POSITION_TYPE_SELL && sl<=from)) return 0;
   double pnl=0;
   ENUM_ORDER_TYPE order_type=type==POSITION_TYPE_BUY?ORDER_TYPE_BUY:ORDER_TYPE_SELL;
   if(!OrderCalcProfit(order_type,symbol,volume,from,sl,pnl)) return 0;
   return MathMax(0.0,-pnl);
  }

double PortfolioRiskAmount()
  {
   double total=0;
   for(int i=PositionsTotal()-1;i>=0;i--) { ulong ticket=PositionGetTicket(i); if(ticket>0) total+=PositionRiskAmount(ticket); }
   return total;
  }

int ThemePositionCount(const string theme)
  {
   int count=0;
   for(int i=PositionsTotal()-1;i>=0;i--)
     { ulong ticket=PositionGetTicket(i); if(ticket>0 && ThemeForSymbol(PositionGetString(POSITION_SYMBOL))==theme) count++; }
   return count;
  }

int LegacyPilotPositionCount()
  {
   int count=0;
   for(int i=PositionsTotal()-1;i>=0;i--)
     {
      ulong ticket=PositionGetTicket(i);
      if(ticket>0 && PositionGetInteger(POSITION_MAGIC)==LEGACY_PILOT_MAGIC) count++;
     }
   return count;
  }

bool ReturnSeries(const string symbol,double &returns[])
  {
   MqlRates rates[]; ArraySetAsSeries(rates,true);
   if(CopyRates(symbol,PERIOD_M5,1,50,rates)<50) return false;
   ArrayResize(returns,48);
   for(int i=0;i<48;i++)
     { if(rates[i+1].close<=0) return false; returns[i]=MathLog(rates[i].close/rates[i+1].close); }
   return true;
  }

double Correlation(const string left,const string right,bool &valid)
  {
   valid=false; double a[],b[];
   if(!ReturnSeries(left,a) || !ReturnSeries(right,b)) return 0;
   double ma=0,mb=0; for(int i=0;i<48;i++) { ma+=a[i]; mb+=b[i]; } ma/=48.0; mb/=48.0;
   double cov=0,va=0,vb=0;
   for(int i=0;i<48;i++) { double da=a[i]-ma,db=b[i]-mb; cov+=da*db; va+=da*da; vb+=db*db; }
   if(va<=0 || vb<=0) return 0; valid=true; return cov/MathSqrt(va*vb);
  }

int StrongCorrelationCount(const MarketScore &candidate,string &evidence)
  {
   int count=0; evidence="";
   for(int i=PositionsTotal()-1;i>=0;i--)
     {
      ulong ticket=PositionGetTicket(i); if(ticket==0) continue;
      string other=PositionGetString(POSITION_SYMBOL); bool valid=false;
      double corr=Correlation(candidate.symbol,other,valid);
      int other_direction=PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY?1:-1;
      double directional_corr=valid?corr*candidate.direction*other_direction:0;
      if(evidence!="") evidence+="|";
      evidence+=other+":"+(valid?DoubleToString(directional_corr,3):"NA");
      if(valid && directional_corr>=0.75) count++;
     }
   return count;
  }

double NormalizePrice(const string symbol,const double value)
  {
   double tick_size=SymbolInfoDouble(symbol,SYMBOL_TRADE_TICK_SIZE);
   int digits=(int)SymbolInfoInteger(symbol,SYMBOL_DIGITS);
   if(tick_size<=0) return NormalizeDouble(value,digits);
   return NormalizeDouble(MathRound(value/tick_size)*tick_size,digits);
  }

bool CalculateLots(const MarketScore &candidate,double &lots,double &actual_risk,string &reason)
  {
   lots=0; actual_risk=0; reason="";
   double equity=AccountInfoDouble(ACCOUNT_EQUITY);
   double budget=equity*RiskPerTradePercent/100.0;
   double one_lot_pnl=0;
   ENUM_ORDER_TYPE type=candidate.direction>0?ORDER_TYPE_BUY:ORDER_TYPE_SELL;
   if(!OrderCalcProfit(type,candidate.symbol,1.0,candidate.entry,candidate.stop,one_lot_pnl) || one_lot_pnl>=0)
     { reason="RISK_CALCULATION_FAILED"; return false; }
   double min_volume=SymbolInfoDouble(candidate.symbol,SYMBOL_VOLUME_MIN);
   double max_volume=SymbolInfoDouble(candidate.symbol,SYMBOL_VOLUME_MAX);
   double step=SymbolInfoDouble(candidate.symbol,SYMBOL_VOLUME_STEP);
   if(step<=0 || min_volume<=0) { reason="VOLUME_SPEC_INVALID"; return false; }
   lots=MathFloor((budget/(-one_lot_pnl))/step+1e-10)*step;
   lots=MathMin(max_volume,lots);
   int volume_digits=step>=1?0:step>=0.1?1:step>=0.01?2:3;
   lots=NormalizeDouble(lots,volume_digits);
   if(lots<min_volume) { reason="RISK_BUDGET_BELOW_MINIMUM_LOT"; return false; }
   actual_risk=-one_lot_pnl*lots;
   if(actual_risk>budget+0.01) { reason="POST_ROUNDING_RISK_EXCEEDED"; return false; }
   return true;
  }

string RiskKey(const long identifier) { return "SFM1_R_"+IntegerToString(identifier); }

void PersistInitialDistance(const string symbol,const double distance)
  {
   if(!PositionSelect(symbol)) return;
   long identifier=PositionGetInteger(POSITION_IDENTIFIER);
   if(identifier>0) GlobalVariableSet(RiskKey(identifier),distance);
  }

double InitialDistanceForSelectedPosition()
  {
   long identifier=PositionGetInteger(POSITION_IDENTIFIER);
   string key=RiskKey(identifier);
   if(GlobalVariableCheck(key)) return GlobalVariableGet(key);
   double distance=MathAbs(PositionGetDouble(POSITION_PRICE_OPEN)-PositionGetDouble(POSITION_SL));
   if(distance>0) GlobalVariableSet(key,distance);
   return distance;
  }

bool FindScore(const string symbol,MarketScore &score)
  {
   for(int i=0;i<ArraySize(g_ranked);i++) if(g_ranked[i].symbol==symbol) { score=g_ranked[i]; return true; }
   return false;
  }

void ManageFastPositions()
  {
   for(int i=PositionsTotal()-1;i>=0;i--)
     {
      ulong ticket=PositionGetTicket(i);
      if(ticket==0 || PositionGetInteger(POSITION_MAGIC)!=FastMagic) continue;
      string symbol=PositionGetString(POSITION_SYMBOL);
      int direction=PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY?1:-1;
      double entry=PositionGetDouble(POSITION_PRICE_OPEN),sl=PositionGetDouble(POSITION_SL);
      double initial=InitialDistanceForSelectedPosition();
      MqlTick tick; if(initial<=0 || !SymbolInfoTick(symbol,tick)) continue;
      double current=direction>0?tick.bid:tick.ask;
      double current_r=direction*(current-entry)/initial;
      MarketScore score; bool scored=FindScore(symbol,score);
      double held_score=scored?(direction>0?score.buy_score:score.sell_score):50.0;
      double opposite_score=scored?(direction>0?score.sell_score:score.buy_score):0.0;
      bool thesis_bad=scored && score.fresh && (opposite_score>held_score+8.0 || held_score<38.0);
      if(thesis_bad)
        {
         g_trade.SetExpertMagicNumber(FastMagic);
         if(!g_trade.PositionClose(ticket)) g_status_reason="THESIS_EXIT_FAILED_"+symbol;
         else g_status_reason="THESIS_EXIT_"+symbol;
         continue;
        }
      double desired=0;
      if(current_r>=0.75)
        {
         double trail=MathMax(0.55*score.atr,2.5*(tick.ask-tick.bid));
         desired=direction>0?MathMax(entry+0.35*initial,current-trail):MathMin(entry-0.35*initial,current+trail);
        }
      else if(current_r>=0.50) desired=entry+direction*0.10*initial;
      else if(current_r>=0.25 && held_score<MinEntryScore) desired=entry-direction*0.10*initial;
      if(desired==0) continue;
      desired=NormalizePrice(symbol,desired);
      bool tighter=direction>0?desired>sl:desired<sl;
      double point=SymbolInfoDouble(symbol,SYMBOL_POINT);
      double min_distance=MathMax((double)SymbolInfoInteger(symbol,SYMBOL_TRADE_STOPS_LEVEL),
                                  (double)SymbolInfoInteger(symbol,SYMBOL_TRADE_FREEZE_LEVEL))*point;
      bool correct_side=direction>0?desired<tick.bid-min_distance:desired>tick.ask+min_distance;
      if(tighter && correct_side)
        {
         g_trade.SetExpertMagicNumber(FastMagic);
         if(!g_trade.PositionModify(ticket,desired,0)) g_status_reason="PROTECTION_FAILED_"+symbol;
        }
     }
  }

bool CandidatePortfolioSafe(const MarketScore &candidate,string &reason)
  {
   reason="";
   int legacy_reserve=MathMax(0,LEGACY_PILOT_TARGET_POSITIONS-LegacyPilotPositionCount());
   if(PositionsTotal()+legacy_reserve>=MaxSimultaneousTrades)
     { reason="MAX_SIX_POSITIONS_WITH_LEGACY_REENTRY_RESERVE"; return false; }
   if(HasSymbolPosition(candidate.symbol)) { reason="SYMBOL_ALREADY_OPEN"; return false; }
   if(ThemePositionCount(ThemeForSymbol(candidate.symbol))>=MaxStronglyCorrelatedTrades)
     { reason="THEME_LIMIT"; return false; }
   string correlation_evidence;
   if(StrongCorrelationCount(candidate,correlation_evidence)>=MaxStronglyCorrelatedTrades)
     { reason="CORRELATION_LIMIT_"+correlation_evidence; return false; }
   double equity=AccountInfoDouble(ACCOUNT_EQUITY);
   double current_risk=PortfolioRiskAmount();
   double candidate_budget=equity*RiskPerTradePercent/100.0;
   double legacy_reserve_risk=legacy_reserve*candidate_budget;
   if(current_risk+candidate_budget+legacy_reserve_risk>equity*MaxPortfolioRiskPercent/100.0+0.01)
     { reason="PORTFOLIO_RISK_LIMIT"; return false; }
   return true;
  }

bool OpenCandidate(const MarketScore &candidate,string &reason)
  {
   reason=""; string identity;
   if(!DemoIdentitySafe(identity)) { reason=identity; return false; }
   if(!candidate.eligible) { reason="NOT_ELIGIBLE"; return false; }
   if(!CandidatePortfolioSafe(candidate,reason)) return false;
   MarketScore live=candidate; MqlTick tick;
   if(!SymbolInfoTick(live.symbol,tick)) { reason="TICK_LOST"; return false; }
   live.entry=live.direction>0?tick.ask:tick.bid;
   double stop_distance=MathAbs(candidate.entry-candidate.stop);
   live.stop=NormalizePrice(live.symbol,live.direction>0?live.entry-stop_distance:live.entry+stop_distance);
   double lots=0,actual_risk=0;
   if(!CalculateLots(live,lots,actual_risk,reason)) return false;
   g_trade.SetExpertMagicNumber(FastMagic);
   g_trade.SetDeviationInPoints(MaxSlippagePoints);
   g_trade.SetTypeFillingBySymbol(live.symbol);
   string comment="SFM1-"+DirectionText(live.direction);
   bool sent=live.direction>0?g_trade.Buy(lots,live.symbol,0,live.stop,0,comment):
                              g_trade.Sell(lots,live.symbol,0,live.stop,0,comment);
   if(!sent) { reason="ORDER_REJECTED_"+IntegerToString((int)g_trade.ResultRetcode()); return false; }
   if(!PositionSelect(live.symbol) || PositionGetDouble(POSITION_SL)<=0)
     {
      g_trade.PositionClose(live.symbol);
      reason="PROTECTIVE_STOP_NOT_CONFIRMED_FLATTENED";
      return false;
     }
   PersistInitialDistance(live.symbol,stop_distance);
   reason="OPENED_"+live.symbol+"_RISK_"+DoubleToString(actual_risk,2);
   return true;
  }

void WriteRuntimeStatus()
  {
   int h=FileOpen("SolTradeFastMultiMarketV1\\runtime.csv",FILE_WRITE|FILE_CSV|FILE_ANSI|FILE_COMMON,',');
   if(h==INVALID_HANDLE) return;
   double equity=AccountInfoDouble(ACCOUNT_EQUITY),risk=PortfolioRiskAmount();
   FileWrite(h,"schema","timestamp_utc","setup_active","login","server","account_mode_demo","real_accounts_blocked",
             "connected","positions","orders","equity","portfolio_risk_amount","portfolio_risk_percent","status");
   FileWrite(h,"SOLTRADE_FAST_MULTI_MARKET_RUNTIME_V1",TimeToString(TimeGMT(),TIME_DATE|TIME_SECONDS),BoolText(g_initialised),
             AccountInfoInteger(ACCOUNT_LOGIN),AccountInfoString(ACCOUNT_SERVER),
             BoolText((ENUM_ACCOUNT_TRADE_MODE)AccountInfoInteger(ACCOUNT_TRADE_MODE)==ACCOUNT_TRADE_MODE_DEMO),"true",
             BoolText((bool)TerminalInfoInteger(TERMINAL_CONNECTED)),PositionsTotal(),OrdersTotal(),DoubleToString(equity,2),
             DoubleToString(risk,2),DoubleToString(equity>0?100.0*risk/equity:0,4),g_status_reason);
   FileWrite(h,"rank","symbol","available","eligible","decision","score","buy_case","sell_case","no_trade_case",
             "regime","behaviour","movement_to_spread","spread_atr_percent","tick_fresh","reward_r","theme");
   for(int i=0;i<ArraySize(g_ranked);i++)
     {
      MarketScore s=g_ranked[i];
      FileWrite(h,i+1,s.symbol,BoolText(s.available),BoolText(s.eligible),s.decision,DoubleToString(s.score,2),
                DoubleToString(s.buy_score,2),DoubleToString(s.sell_score,2),s.eligible?"NONE":s.reason,s.regime,s.behaviour,
                DoubleToString(s.movement_spread,2),DoubleToString(s.spread_atr_pct,2),BoolText(s.fresh),
                DoubleToString(s.reward_r,2),ThemeForSymbol(s.symbol));
     }
   FileWrite(h,"position_ticket","symbol","owner","direction","volume","entry","stop","profit","risk_amount","theme");
   for(int i=PositionsTotal()-1;i>=0;i--)
     {
      ulong ticket=PositionGetTicket(i); if(ticket==0) continue;
      string symbol=PositionGetString(POSITION_SYMBOL);
      FileWrite(h,ticket,symbol,PositionGetInteger(POSITION_MAGIC)==FastMagic?"FAST_MULTI":"LEGACY_OR_OTHER",
                PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY?"BUY":"SELL",
                DoubleToString(PositionGetDouble(POSITION_VOLUME),2),DoubleToString(PositionGetDouble(POSITION_PRICE_OPEN),
                (int)SymbolInfoInteger(symbol,SYMBOL_DIGITS)),DoubleToString(PositionGetDouble(POSITION_SL),
                (int)SymbolInfoInteger(symbol,SYMBOL_DIGITS)),DoubleToString(PositionGetDouble(POSITION_PROFIT),2),
                DoubleToString(PositionRiskAmount(ticket),2),ThemeForSymbol(symbol));
     }
   FileWrite(h,"correlation_group","open_count","maximum");
   string themes[7]={"METALS_USD","US_RISK_INDEX","EUROPE_INDEX","EUROPE_FX","JPY_FACTOR","USD_FX","ANTIPODEAN_FX"};
   for(int i=0;i<7;i++) FileWrite(h,themes[i],ThemePositionCount(themes[i]),MaxStronglyCorrelatedTrades);
   FileWrite(h,"intended_market","configured_symbol","actual_broker_symbol","trade_status","mapping_source");
   for(int i=0;i<SYMBOL_COUNT;i++)
      if(IsIndexAliasMarket(i))
         FileWrite(h,BASE_SYMBOLS[i],ConfiguredSymbol(i),g_symbols[i],g_mapping_status[i],g_mapping_source[i]);
   FileFlush(h); FileClose(h);
  }

void ScanAndAct()
  {
   ArrayResize(g_ranked,SYMBOL_COUNT);
   for(int i=0;i<SYMBOL_COUNT;i++) ScoreSymbol(i,g_ranked[i]);
   SortRanked();
   ManageFastPositions();
   string reason=DryRunOnly?"DRY_RUN_SCAN_COMPLETE":"NO_QUALIFYING_REPLACEMENT";
   if(!DryRunOnly)
      for(int i=0;i<ArraySize(g_ranked);i++)
        {
         if(!g_ranked[i].eligible) continue;
         if(OpenCandidate(g_ranked[i],reason)) break;
        }
   g_status_reason=reason;
   WriteRuntimeStatus();
  }

int OnInit()
  {
   string reason;
   if(!DemoIdentitySafe(reason)) { Print("SOLTRADE_FAST_MULTI_INIT_REFUSED ",reason," REAL_ACCOUNTS_BLOCKED=true"); return INIT_FAILED; }
   if(RiskPerTradePercent!=0.25 || MaxPortfolioRiskPercent!=1.50 || MaxSimultaneousTrades!=6 ||
      MaxStronglyCorrelatedTrades!=2 || ScanSeconds<5)
     { Print("SOLTRADE_FAST_MULTI_INIT_REFUSED FROZEN_PORTFOLIO_POLICY_MISMATCH"); return INIT_PARAMETERS_INCORRECT; }
   if(!SelectUniverse()) { Print("SOLTRADE_FAST_MULTI_INIT_REFUSED NO_UNIVERSE_SYMBOL_AVAILABLE"); return INIT_FAILED; }
   g_trade.SetAsyncMode(false);
   g_trade.SetExpertMagicNumber(FastMagic);
   EventSetTimer(1);
   g_initialised=true;
   g_status_reason="SOLTRADE_FAST_MULTI_MARKET_SETUP_ACTIVE";
   ScanAndAct();
   Print("SOLTRADE_FAST_MULTI_MARKET_SETUP_ACTIVE account=",AccountInfoInteger(ACCOUNT_LOGIN),
         " server=",AccountInfoString(ACCOUNT_SERVER)," real_accounts_blocked=true universe=19 max_positions=6 dry_run=",DryRunOnly);
   for(int i=0;i<SYMBOL_COUNT;i++)
      if(IsIndexAliasMarket(i))
         Print("SOLTRADE_FAST_INDEX_MAPPING intended=",ConfiguredSymbol(i)," actual=",g_symbols[i],
               " status=",g_mapping_status[i]," source=",g_mapping_source[i]);
   return INIT_SUCCEEDED;
  }

void OnDeinit(const int reason)
  {
   EventKillTimer();
   g_initialised=false;
   WriteRuntimeStatus();
  }

void OnTimer()
  {
   if(!g_initialised) return;
   string reason;
   if(!DemoIdentitySafe(reason)) { g_status_reason=reason; g_initialised=false; EventKillTimer(); WriteRuntimeStatus(); return; }
   long bucket=(long)TimeGMT()/ScanSeconds;
   if(!g_immediate_rescan_requested && bucket==g_last_scan_bucket) return;
   g_immediate_rescan_requested=false;
   g_last_scan_bucket=bucket;
   ScanAndAct();
  }

void OnTradeTransaction(const MqlTradeTransaction &transaction,
                        const MqlTradeRequest &request,
                        const MqlTradeResult &result)
  {
   if(transaction.type!=TRADE_TRANSACTION_DEAL_ADD || transaction.deal==0) return;
   ENUM_DEAL_ENTRY entry=(ENUM_DEAL_ENTRY)HistoryDealGetInteger(transaction.deal,DEAL_ENTRY);
   if(entry==DEAL_ENTRY_OUT || entry==DEAL_ENTRY_OUT_BY || entry==DEAL_ENTRY_INOUT)
      g_immediate_rescan_requested=true;
  }
