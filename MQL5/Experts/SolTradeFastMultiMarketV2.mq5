#property strict
#property version   "2.000"
#property description "Demo-only active intraday multi-market context, execution, and management engine"

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
input double MinEntryScore=68.0;
input double MinDirectionalDominance=12.0;
input double MinNoTradeDominance=8.0;
input double MinExpectedMoveCostMultiple=3.0;
input int    MaxSlippagePoints=12;

#define REQUIRED_DEMO_LOGIN 7404213
#define FORBIDDEN_LIVE_LOGIN 7196820
#define FORBIDDEN_OBSERVATION_LOGIN 2100139002
#define LEGACY_PILOT_MAGIC 2082026032
#define SYMBOL_COUNT 19
#define V1_MAGIC 2108202601

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
   double no_trade_score;
   double spread;
   double spread_atr_pct;
   double movement_spread;
   double atr;
   double acceleration;
   double reward_r;
   double available_move;
   double expected_cost_move;
   double expected_net_move;
   double cost_multiple;
   double volatility_expansion;
   double path_impulse;
   double path_efficiency;
   double factor_alignment;
   double entry;
   double stop;
   long setup_key;
   bool m5_confirmed;
   bool m15_confirmed;
   bool structural_reversal;
   bool exhausted;
   string buy_case;
   string sell_case;
   string no_trade_case;
   string context_m1;
   string context_m5;
   string context_m15;
   string context_h1;
   string session_context;
   string previous_session_context;
   string structural_levels;
   string opposing_evidence;
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
int g_last_exit_direction[SYMBOL_COUNT];
long g_last_exit_time[SYMBOL_COUNT];
long g_last_setup_key[SYMBOL_COUNT];
bool g_last_exit_invalidated[SYMBOL_COUNT];
long g_v2_start_server=0;

string BoolText(const bool value) { return value?"true":"false"; }
string DirectionText(const int direction) { return direction>0?"BUY":direction<0?"SELL":"NONE"; }

bool DemoIdentitySafe(string &reason)
  {
   reason="";
   if((bool)MQLInfoInteger(MQL_TESTER)) { reason="TESTER_NOT_AUTHORIZED_FOR_CONNECTED_SETUP"; return false; }
   long login=(long)AccountInfoInteger(ACCOUNT_LOGIN);
   if(login==FORBIDDEN_LIVE_LOGIN || login==FORBIDDEN_OBSERVATION_LOGIN)
     { reason="EXPLICITLY_FORBIDDEN_ACCOUNT"; return false; }
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
  {
   string market=BASE_SYMBOLS[index];
   return market=="USTEC" || market=="DE30" || market=="US500" || market=="STOXX50" || market=="UK100";
  }

bool IsPriorityMarket(const int index)
  {
   string market=BASE_SYMBOLS[index];
   return market=="XAUUSD" || market=="XAGUSD" || market=="USTEC" || market=="US500" || market=="DE30" ||
          market=="GBPJPY" || market=="EURJPY" || market=="AUDJPY" || market=="USDJPY" || market=="GBPUSD";
  }

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
   string market=BASE_SYMBOLS[index];
   if(market=="USTEC")
      return StartsWithText(name,"USTEC") || StartsWithText(name,"NAS100") || StartsWithText(name,"US100") ||
             StartsWithText(name,"NASDAQ") || StartsWithText(name,"NDX");
   if(market=="DE30")
      return StartsWithText(name,"DE30") || StartsWithText(name,"DE40") || StartsWithText(name,"GER30") ||
             StartsWithText(name,"GER40") || StartsWithText(name,"DAX");
   if(market=="US500")
      return StartsWithText(name,"US500") || StartsWithText(name,"SPX500") || StartsWithText(name,"SP500");
   if(market=="STOXX50")
      return StartsWithText(name,"STOXX50") || StartsWithText(name,"EU50") || StartsWithText(name,"ESTX50") ||
             StartsWithText(name,"EURO50");
   if(market=="UK100")
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
   string market=BASE_SYMBOLS[index];
   if(market=="USTEC")
      identity_context=ContainsText(metadata,"USTEC") || ContainsText(metadata,"NAS100") ||
                       ContainsText(metadata,"US100") || ContainsText(metadata,"NASDAQ") ||
                       ContainsText(metadata,"NDX") || ContainsText(metadata,"USTECH100");
   else if(market=="DE30")
      identity_context=ContainsText(metadata,"DE30") || ContainsText(metadata,"DE40") ||
                       ContainsText(metadata,"GER30") || ContainsText(metadata,"GER40") ||
                       ContainsText(metadata,"DAX") || ContainsText(metadata,"GERMANY30") ||
                       ContainsText(metadata,"GERMANY40");
   else if(market=="US500")
      identity_context=ContainsText(metadata,"US500") || ContainsText(metadata,"SPX500") ||
                       ContainsText(metadata,"SP500") || ContainsText(metadata,"STANDARDPOORS500");
   else if(market=="STOXX50")
      identity_context=ContainsText(metadata,"STOXX50") || ContainsText(metadata,"EU50") ||
                       ContainsText(metadata,"ESTX50") || ContainsText(metadata,"EURO50") ||
                       ContainsText(metadata,"EUROSTOXX50") ||
                       ContainsText(metadata,"EUROPE50");
   else if(market=="UK100")
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
   int handle=FileOpen("SolTradeFastMultiMarketV2\\symbol-map.csv",FILE_READ|FILE_CSV|FILE_ANSI|FILE_COMMON,',');
   if(handle==INVALID_HANDLE) return;
   while(!FileIsEnding(handle))
     {
      string schema=FileReadString(handle);
      string server=FileReadString(handle);
      string intended=FileReadString(handle);
      string actual=FileReadString(handle);
      if(schema!="SOLTRADE_FAST_SYMBOL_MAP_V2" || server!=AccountInfoString(ACCOUNT_SERVER)) continue;
      for(int i=0;i<SYMBOL_COUNT;i++)
         if(IsIndexAliasMarket(i) && intended==ConfiguredSymbol(i)) g_cached_symbols[i]=actual;
     }
   FileClose(handle);
  }

void SaveMappingCache()
  {
   int handle=FileOpen("SolTradeFastMultiMarketV2\\symbol-map.csv",FILE_WRITE|FILE_CSV|FILE_ANSI|FILE_COMMON,',');
   if(handle==INVALID_HANDLE) return;
   for(int i=0;i<SYMBOL_COUNT;i++)
      if(IsIndexAliasMarket(i) && g_cached_symbols[i]!="")
         FileWrite(handle,"SOLTRADE_FAST_SYMBOL_MAP_V2",AccountInfoString(ACCOUNT_SERVER),ConfiguredSymbol(i),g_cached_symbols[i]);
   FileFlush(handle);
   FileClose(handle);
  }

void WriteBrokerSymbolCatalogue()
  {
   int handle=FileOpen("SolTradeFastMultiMarketV2\\broker-symbol-catalogue.csv",FILE_WRITE|FILE_CSV|FILE_ANSI|FILE_COMMON,',');
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

double TrendStrength(MqlRates &rates[],const int fast_count,const int slow_count,const double atr)
  { return atr>0?(AverageClose(rates,1,fast_count)-AverageClose(rates,1,slow_count))/atr:0; }

double PathEfficiency(MqlRates &rates[],const int count)
  {
   double travelled=0;
   for(int i=1;i<=count;i++) travelled+=MathAbs(rates[i].close-rates[i+1].close);
   return travelled>0?MathAbs(rates[1].close-rates[count+1].close)/travelled:0;
  }

string ContextLabel(const double trend,const double efficiency)
  {
   if(efficiency<0.24) return "RANGE_CHOP";
   if(trend>0.20) return trend>0.60?"BULL_TREND_STRONG":"BULL_TREND";
   if(trend<-0.20) return trend<-0.60?"BEAR_TREND_STRONG":"BEAR_TREND";
   return "TRANSITION";
  }

datetime ServerTimeToUtc(const datetime server_time)
  {
   long offset=(long)TimeTradeServer()-(long)TimeGMT();
   return (datetime)((long)server_time-offset);
  }

int SessionBucket(const datetime utc_time)
  {
   MqlDateTime value; TimeToStruct(utc_time,value);
   if(value.hour<7) return 0;
   if(value.hour<12) return 1;
   if(value.hour<17) return 2;
   return 3;
  }

string SessionName(const int bucket)
  {
   if(bucket==0) return "ASIA";
   if(bucket==1) return "LONDON";
   if(bucket==2) return "LONDON_NEWYORK_OVERLAP";
   return "NEWYORK_LATE";
  }

void BuildSessionEvidence(MqlRates &m15[],MqlRates &h1[],string &current_context,string &previous_context,
                          double &session_open,double &session_high,double &session_low,
                          double &previous_high,double &previous_low,double &previous_day_high,double &previous_day_low)
  {
   datetime now_utc=TimeGMT(); int active_bucket=SessionBucket(now_utc);
   session_open=0; session_high=-DBL_MAX; session_low=DBL_MAX;
   previous_high=-DBL_MAX; previous_low=DBL_MAX; int prior_bucket=-1; int current_bars=0,prior_bars=0;
   for(int i=1;i<ArraySize(m15);i++)
     {
      datetime utc=ServerTimeToUtc(m15[i].time); int bucket=SessionBucket(utc);
      if(bucket==active_bucket && prior_bucket<0)
        {
         session_open=m15[i].open; session_high=MathMax(session_high,m15[i].high); session_low=MathMin(session_low,m15[i].low); current_bars++;
        }
      else
        {
         if(prior_bucket<0) prior_bucket=bucket;
         if(bucket!=prior_bucket) break;
         previous_high=MathMax(previous_high,m15[i].high); previous_low=MathMin(previous_low,m15[i].low); prior_bars++;
        }
     }
   if(current_bars==0) { session_open=m15[1].open; session_high=m15[1].high; session_low=m15[1].low; }
   if(prior_bars==0) { previous_high=m15[2].high; previous_low=m15[2].low; prior_bucket=SessionBucket(ServerTimeToUtc(m15[2].time)); }
   current_context=SessionName(active_bucket)+StringFormat(";open=%.8f;high=%.8f;low=%.8f",session_open,session_high,session_low);
   previous_context=SessionName(prior_bucket)+StringFormat(";high=%.8f;low=%.8f",previous_high,previous_low);

   MqlDateTime now_value; TimeToStruct(now_utc,now_value);
   int today_key=now_value.year*1000+now_value.day_of_year;
   previous_day_high=-DBL_MAX; previous_day_low=DBL_MAX; int previous_key=-1;
   for(int i=1;i<ArraySize(h1);i++)
     {
      MqlDateTime bar; TimeToStruct(ServerTimeToUtc(h1[i].time),bar); int key=bar.year*1000+bar.day_of_year;
      if(key==today_key) continue;
      if(previous_key<0) previous_key=key;
      if(key!=previous_key) break;
      previous_day_high=MathMax(previous_day_high,h1[i].high); previous_day_low=MathMin(previous_day_low,h1[i].low);
     }
   if(previous_day_high==-DBL_MAX) previous_day_high=HighestHigh(h1,2,24);
   if(previous_day_low==DBL_MAX) previous_day_low=LowestLow(h1,2,24);
  }

double CompletedReturn(const string symbol,const ENUM_TIMEFRAMES timeframe,const int bars,bool &valid)
  {
   valid=false; MqlRates rates[]; ArraySetAsSeries(rates,true);
   if(CopyRates(symbol,timeframe,0,bars+2,rates)<bars+2 || rates[bars+1].close<=0) return 0;
   valid=true; return MathLog(rates[1].close/rates[bars+1].close);
  }

double CrossMarketAlignment(const int candidate_index,const int direction)
  {
   string intended=BASE_SYMBOLS[candidate_index];
   if(StringLen(intended)!=6) return 0;
   string cb=StringSubstr(intended,0,3),cq=StringSubstr(intended,3,3);
   double sum=0; int observations=0;
   for(int i=0;i<SYMBOL_COUNT;i++)
     {
      if(i==candidate_index || StringLen(BASE_SYMBOLS[i])!=6 || g_symbols[i]=="") continue;
      string ob=StringSubstr(BASE_SYMBOLS[i],0,3),oq=StringSubstr(BASE_SYMBOLS[i],3,3);
      double overlap=(cb==ob?1.0:0.0)+(cq==oq?1.0:0.0)-(cb==oq?1.0:0.0)-(cq==ob?1.0:0.0);
      if(overlap==0) continue;
      bool valid=false; double value=CompletedReturn(g_symbols[i],PERIOD_M5,6,valid);
      if(!valid) continue;
      sum+=direction*overlap*(value>0?1.0:value<0?-1.0:0.0); observations++;
     }
   return observations>0?Clamp(sum/observations,-1.0,1.0):0;
  }

double EstimatedRoundTripCommissionPerLot(const string symbol)
  {
   if(!HistorySelect(TimeCurrent()-90*86400,TimeCurrent())) return 6.0;
   double total=0; int count=0;
   for(int i=HistoryDealsTotal()-1;i>=0 && count<40;i--)
     {
      ulong deal=HistoryDealGetTicket(i); if(deal==0 || HistoryDealGetString(deal,DEAL_SYMBOL)!=symbol) continue;
      double volume=HistoryDealGetDouble(deal,DEAL_VOLUME);
      double commission=MathAbs(HistoryDealGetDouble(deal,DEAL_COMMISSION)+HistoryDealGetDouble(deal,DEAL_FEE));
      if(volume<=0 || commission<=0) continue;
      total+=commission/volume; count++;
     }
   return count>0?2.0*total/count:6.0;
  }

double CommissionAsPriceMove(const string symbol,const double entry,const double round_trip_per_lot)
  {
   double tick_size=SymbolInfoDouble(symbol,SYMBOL_TRADE_TICK_SIZE),pnl=0;
   if(tick_size<=0 || !OrderCalcProfit(ORDER_TYPE_BUY,symbol,1.0,entry,entry+tick_size,pnl) || MathAbs(pnl)<=0) return DBL_MAX;
   return round_trip_per_lot/(MathAbs(pnl)/tick_size);
  }

long SetupKey(const int direction,const string behaviour,const double anchor,const double atr)
  {
   int code=behaviour=="BREAKOUT_UP"?11:behaviour=="BREAKOUT_DOWN"?12:behaviour=="BULL_REJECTION"?21:
            behaviour=="BEAR_REJECTION"?22:behaviour=="FAILED_BREAKOUT_UP"?31:behaviour=="FAILED_BREAKOUT_DOWN"?32:40;
   long zone=(long)MathRound(anchor/MathMax(atr*0.25,0.00000001));
   return direction*(long)(code*100000000+MathAbs(zone)%100000000);
  }

bool ScoreSymbol(const int index,MarketScore &out)
  {
   ZeroMemory(out);
   if(IsIndexAliasMarket(index) && g_symbols[index]=="")
     {
      if(DiscoverIndexSymbol(index)) SaveMappingCache();
      else { out.symbol=ConfiguredSymbol(index); out.priority=IsPriorityMarket(index)?2:1; out.reason=g_mapping_status[index]; return false; }
     }
   out.symbol=g_symbols[index]; out.priority=IsPriorityMarket(index)?2:1; out.reason="NO_DATA";
   if(!SymbolSelect(out.symbol,true) || !SymbolInfoInteger(out.symbol,SYMBOL_EXIST)) return false;
   out.available=true;
   MqlTick tick; if(!SymbolInfoTick(out.symbol,tick) || tick.bid<=0 || tick.ask<=tick.bid) return false;
   MqlRates m1[],m5[],m15[],h1[];
   ArraySetAsSeries(m1,true); ArraySetAsSeries(m5,true); ArraySetAsSeries(m15,true); ArraySetAsSeries(h1,true);
   if(CopyRates(out.symbol,PERIOD_M1,0,82,m1)<75) { out.reason="INSUFFICIENT_M1_HISTORY"; return false; }
   if(CopyRates(out.symbol,PERIOD_M5,0,102,m5)<90) { out.reason="INSUFFICIENT_M5_HISTORY"; return false; }
   if(CopyRates(out.symbol,PERIOD_M15,0,82,m15)<72) { out.reason="INSUFFICIENT_M15_HISTORY"; return false; }
   if(CopyRates(out.symbol,PERIOD_H1,0,52,h1)<48) { out.reason="INSUFFICIENT_H1_HISTORY"; return false; }

   long reference_msc=(long)TimeTradeServer()*1000;
   out.fresh=MathMax(0.0,(reference_msc-tick.time_msc)/1000.0)<=MaxTickAgeSeconds;
   out.spread=tick.ask-tick.bid;
   out.atr=AverageRange(m5,1,14);
   double atr15=AverageRange(m15,1,14);
   if(out.atr<=0 || atr15<=0) { out.reason="ATR_INVALID"; return true; }
   out.spread_atr_pct=100.0*out.spread/out.atr;

   double t1=TrendStrength(m1,8,30,AverageRange(m1,1,20));
   double t5=TrendStrength(m5,8,30,out.atr);
   double t15=TrendStrength(m15,6,24,atr15);
   double t60=TrendStrength(h1,4,16,AverageRange(h1,1,14));
   double e1=PathEfficiency(m1,20),e5=PathEfficiency(m5,18),e15=PathEfficiency(m15,12),e60=PathEfficiency(h1,8);
   out.context_m1=ContextLabel(t1,e1); out.context_m5=ContextLabel(t5,e5);
   out.context_m15=ContextLabel(t15,e15); out.context_h1=ContextLabel(t60,e60);
   out.path_efficiency=e5;
   out.path_impulse=(m5[1].close-m5[13].close)/out.atr;
   double recent_momentum=(m5[1].close-m5[4].close)/out.atr;
   double prior_momentum=(m5[4].close-m5[7].close)/out.atr;
   out.acceleration=recent_momentum-prior_momentum;
   out.volatility_expansion=AverageRange(m5,1,4)/MathMax(AverageRange(m5,5,12),SymbolInfoDouble(out.symbol,SYMBOL_POINT));
   double movement=MathAbs(m5[1].close-m5[13].close);
   out.movement_spread=movement/MathMax(out.spread,SymbolInfoDouble(out.symbol,SYMBOL_POINT));

   double prior_high=HighestHigh(m5,2,20),prior_low=LowestLow(m5,2,20);
   bool breakout_up=m5[1].close>prior_high,breakout_down=m5[1].close<prior_low;
   bool failed_up=m5[1].high>prior_high && m5[1].close<prior_high;
   bool failed_down=m5[1].low<prior_low && m5[1].close>prior_low;
   double body=MathAbs(m5[1].close-m5[1].open);
   double upper_wick=m5[1].high-MathMax(m5[1].open,m5[1].close);
   double lower_wick=MathMin(m5[1].open,m5[1].close)-m5[1].low;
   bool reject_up=lower_wick>MathMax(body,0.18*out.atr) && m5[1].close>m5[1].open;
   bool reject_down=upper_wick>MathMax(body,0.18*out.atr) && m5[1].close<m5[1].open;
   bool hh=HighestHigh(m5,1,5)>HighestHigh(m5,6,5),hl=LowestLow(m5,1,5)>LowestLow(m5,6,5);
   bool lh=HighestHigh(m5,1,5)<HighestHigh(m5,6,5),ll=LowestLow(m5,1,5)<LowestLow(m5,6,5);
   out.m5_confirmed=MathAbs(t5)>=0.20; out.m15_confirmed=MathAbs(t15)>=0.16;

   double spread_quality=Clamp(1.0-out.spread_atr_pct/MaxSpreadAtrPercent,0.0,1.0);
   double movement_quality=Clamp(out.movement_spread/18.0,0.0,1.0);
   double factor_buy=CrossMarketAlignment(index,1); out.factor_alignment=factor_buy;
   out.buy_score=16+10*Clamp(t1,0,1)+17*Clamp(t5,0,1.5)/1.5+15*Clamp(t15,0,1.5)/1.5+
                 8*Clamp(t60,0,1)+10*Clamp(recent_momentum,0,1)+7*Clamp(out.acceleration,0,1)+
                 7*movement_quality+6*spread_quality+(breakout_up?12:0)+(reject_up?7:0)+((hh&&hl)?9:0)+4*Clamp(factor_buy,0,1);
   out.sell_score=16+10*Clamp(-t1,0,1)+17*Clamp(-t5,0,1.5)/1.5+15*Clamp(-t15,0,1.5)/1.5+
                  8*Clamp(-t60,0,1)+10*Clamp(-recent_momentum,0,1)+7*Clamp(-out.acceleration,0,1)+
                  7*movement_quality+6*spread_quality+(breakout_down?12:0)+(reject_down?7:0)+((lh&&ll)?9:0)+4*Clamp(-factor_buy,0,1);
   if(failed_up) out.sell_score+=8; if(failed_down) out.buy_score+=8;
   out.exhausted=out.volatility_expansion>1.65 && MathAbs(out.path_impulse)>3.5 &&
                 ((out.path_impulse>0 && upper_wick>body) || (out.path_impulse<0 && lower_wick>body));
   bool timeframe_conflict=(t5>0.20 && t15<-0.16)||(t5<-0.20 && t15>0.16);
   out.no_trade_score=12+(e5<0.25?24:0)+(timeframe_conflict?24:0)+(out.exhausted?25:0)+
                      (out.spread_atr_pct>MaxSpreadAtrPercent?30:0)+(out.movement_spread<MinMovementToSpread?18:0)+
                      (MathAbs(t5)<0.16 && MathAbs(recent_momentum)<0.16?18:0);
   out.direction=out.buy_score>=out.sell_score?1:-1; out.score=MathMax(out.buy_score,out.sell_score);
   double opposite=out.direction>0?out.sell_score:out.buy_score;
   out.entry=out.direction>0?tick.ask:tick.bid;
   out.behaviour=breakout_up?"BREAKOUT_UP":breakout_down?"BREAKOUT_DOWN":failed_up?"FAILED_BREAKOUT_UP":
                 failed_down?"FAILED_BREAKOUT_DOWN":reject_up?"BULL_REJECTION":reject_down?"BEAR_REJECTION":"STRUCTURE_INSIDE";
   out.structural_reversal=(out.direction>0 && (breakout_up||failed_down) && t5>0.20 && t15>0.16) ||
                           (out.direction<0 && (breakout_down||failed_up) && t5<-0.20 && t15<-0.16);

   double m5_swing=out.direction>0?LowestLow(m5,1,20):HighestHigh(m5,1,20);
   double m15_swing=out.direction>0?LowestLow(m15,1,12):HighestHigh(m15,1,12);
   double invalidation=out.direction>0?MathMin(m5_swing,m15_swing):MathMax(m5_swing,m15_swing);
   double expansion_buffer=(0.18+0.22*Clamp(out.volatility_expansion-1.0,0.0,1.5))*out.atr+2.0*out.spread;
   double stop_distance=out.direction>0?out.entry-invalidation+expansion_buffer:invalidation-out.entry+expansion_buffer;
   stop_distance=MathMax(stop_distance,MathMax(1.15*out.atr,0.55*atr15));
   double point=SymbolInfoDouble(out.symbol,SYMBOL_POINT);
   double broker_min=MathMax((double)SymbolInfoInteger(out.symbol,SYMBOL_TRADE_STOPS_LEVEL),
                             (double)SymbolInfoInteger(out.symbol,SYMBOL_TRADE_FREEZE_LEVEL))*point;
   stop_distance=MathMax(stop_distance,broker_min+2.0*point);
   out.stop=out.direction>0?out.entry-stop_distance:out.entry+stop_distance;

   double opposing=out.direction>0?MathMin(HighestHigh(m15,2,32),HighestHigh(h1,2,24)):
                                       MathMax(LowestLow(m15,2,32),LowestLow(h1,2,24));
   double room=out.direction>0?opposing-out.entry:out.entry-opposing;
   if(room<=0) room=MathMax(1.60*out.atr,0.65*atr15);
   out.available_move=MathMin(room,MathMax(2.20*out.atr,0.75*atr15));
   double commission_move=CommissionAsPriceMove(out.symbol,out.entry,EstimatedRoundTripCommissionPerLot(out.symbol));
   double slippage_move=MaxSlippagePoints*point;
   out.expected_cost_move=out.spread+commission_move+slippage_move;
   out.expected_net_move=out.available_move-out.expected_cost_move;
   out.cost_multiple=out.available_move/MathMax(out.expected_cost_move,point);
   out.reward_r=out.expected_net_move/stop_distance;
   out.setup_key=SetupKey(out.direction,out.behaviour,out.direction>0?prior_high:prior_low,out.atr);

   double session_open=0,session_high=0,session_low=0,previous_session_high=0,previous_session_low=0,previous_day_high=0,previous_day_low=0;
   BuildSessionEvidence(m15,h1,out.session_context,out.previous_session_context,session_open,session_high,session_low,
                        previous_session_high,previous_session_low,previous_day_high,previous_day_low);
   int high_struggles=0,low_struggles=0;
   double zone_tolerance=0.18*out.atr;
   for(int zone_bar=1;zone_bar<=20;zone_bar++)
     {
      if(MathAbs(m5[zone_bar].high-prior_high)<=zone_tolerance) high_struggles++;
      if(MathAbs(m5[zone_bar].low-prior_low)<=zone_tolerance) low_struggles++;
     }
   double impulse_high=-DBL_MAX,impulse_low=DBL_MAX;
   for(int impulse_bar=1;impulse_bar<=12;impulse_bar++)
     {
      double impulse=m5[impulse_bar].close-m5[impulse_bar].open;
      impulse_high=MathMax(impulse_high,impulse); impulse_low=MathMin(impulse_low,impulse);
     }
   out.structural_levels=StringFormat("m5_high=%.8f;m5_low=%.8f;m15_swing=%.8f;session_open=%.8f;session_high=%.8f;session_low=%.8f;previous_session_high=%.8f;previous_session_low=%.8f;previous_day_high=%.8f;previous_day_low=%.8f;high_struggles=%d;low_struggles=%d;strongest_bull_impulse=%.8f;strongest_bear_impulse=%.8f",
      prior_high,prior_low,m15_swing,session_open,session_high,session_low,previous_session_high,previous_session_low,
      previous_day_high,previous_day_low,high_struggles,low_struggles,impulse_high,impulse_low);
   out.opposing_evidence=StringFormat("opposite=%.2f;no_trade=%.2f;timeframe_conflict=%s;exhausted=%s;factor=%.3f",
      opposite,out.no_trade_score,BoolText(timeframe_conflict),BoolText(out.exhausted),out.factor_alignment);
   out.buy_case=StringFormat("score=%.2f;M1=%s;M5=%s;M15=%s;H1=%s;HHHL=%s;breakout=%s;factor=%.3f",
      out.buy_score,out.context_m1,out.context_m5,out.context_m15,out.context_h1,BoolText(hh&&hl),BoolText(breakout_up),factor_buy);
   out.sell_case=StringFormat("score=%.2f;M1=%s;M5=%s;M15=%s;H1=%s;LHLL=%s;breakout=%s;factor=%.3f",
      out.sell_score,out.context_m1,out.context_m5,out.context_m15,out.context_h1,BoolText(lh&&ll),BoolText(breakout_down),-factor_buy);
   out.no_trade_case=StringFormat("score=%.2f;cost_multiple=%.2f;room=%.8f;conflict=%s;exhausted=%s;spread_atr=%.2f",
      out.no_trade_score,out.cost_multiple,out.available_move,BoolText(timeframe_conflict),BoolText(out.exhausted),out.spread_atr_pct);
   if(MathAbs(t5)>0.55 && MathAbs(t15)>0.35 && e5>0.35) out.regime="TREND_PERSISTENT";
   else if(out.volatility_expansion>1.25 && e5>0.32) out.regime="VOLATILITY_EXPANSION";
   else if(e5<0.25) out.regime="RANGE_CHOP"; else out.regime="DIRECTIONAL_TRANSITION";

   if(!out.fresh) out.reason="STALE_TICK";
   else if(out.spread_atr_pct>MaxSpreadAtrPercent) out.reason="ABNORMAL_SPREAD";
   else if(out.movement_spread<MinMovementToSpread) out.reason="MOVEMENT_WEAK_RELATIVE_TO_SPREAD";
   else if(out.exhausted) out.reason="MOVE_EXHAUSTED_OR_LATE_CHASE";
   else if(out.expected_net_move<=0 || out.cost_multiple<MinExpectedMoveCostMultiple) out.reason="EXPECTED_NET_MOVE_INSUFFICIENT_AFTER_COSTS";
   else if(out.reward_r<MinRewardRisk) out.reason="OPPOSING_STRUCTURE_TOO_CLOSE_AFTER_COSTS";
   else if(out.score<MinEntryScore) out.reason="DIRECTIONAL_EVIDENCE_WEAK";
   else if(out.score<opposite+MinDirectionalDominance) out.reason="OPPOSITE_CASE_NOT_CLEARLY_DEFEATED";
   else if(out.score<out.no_trade_score+MinNoTradeDominance) out.reason="NO_TRADE_CASE_DOMINATES";
   else if(out.direction>0 && t5<-0.20 && !out.structural_reversal) out.reason="BUY_FIGHTS_OBVIOUS_M5_MOMENTUM";
   else if(out.direction<0 && t5>0.20 && !out.structural_reversal) out.reason="SELL_FIGHTS_OBVIOUS_M5_MOMENTUM";
   else { out.eligible=true; out.reason="QUALIFIED_CONTEXT_COST_STRUCTURE"; }
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
   one_lot_pnl-=EstimatedRoundTripCommissionPerLot(candidate.symbol);
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

string RiskKey(const long identifier) { return "SFM2_R_"+IntegerToString(identifier); }
string LegacyRiskKey(const long identifier) { return "SFM1_R_"+IntegerToString(identifier); }
string MfeKey(const long identifier) { return "SFM2_MFE_"+IntegerToString(identifier); }
string MaeKey(const long identifier) { return "SFM2_MAE_"+IntegerToString(identifier); }
string InitialRiskPath(const long identifier) { return "SolTradeFastMultiMarketV2\\initial-risk-"+IntegerToString(identifier)+".csv"; }

void SaveInitialDistance(const long identifier,const string symbol,const double entry,const double distance)
  {
   if(identifier<=0 || distance<=0) return;
   string path=InitialRiskPath(identifier);
   int h=FileOpen(path+".tmp",FILE_WRITE|FILE_CSV|FILE_ANSI|FILE_COMMON,',');
   if(h==INVALID_HANDLE) return;
   FileWrite(h,"SOLTRADE_FAST_MULTI_V2_INITIAL_RISK_V1",AccountInfoInteger(ACCOUNT_LOGIN),identifier,symbol,
             DoubleToString(entry,8),DoubleToString(distance,8));
   FileFlush(h); FileClose(h);
   FileDelete(path,FILE_COMMON);
   FileMove(path+".tmp",FILE_COMMON,path,FILE_COMMON|FILE_REWRITE);
   GlobalVariableSet(RiskKey(identifier),distance); GlobalVariablesFlush();
  }

double LoadInitialDistance(const long identifier,const string symbol,const double entry)
  {
   int h=FileOpen(InitialRiskPath(identifier),FILE_READ|FILE_CSV|FILE_ANSI|FILE_COMMON,',');
   if(h==INVALID_HANDLE) return 0;
   string schema=FileReadString(h); long account=(long)StringToInteger(FileReadString(h));
   long saved_identifier=(long)StringToInteger(FileReadString(h)); string saved_symbol=FileReadString(h);
   double saved_entry=StringToDouble(FileReadString(h)); double distance=StringToDouble(FileReadString(h));
   FileClose(h);
   double point=SymbolInfoDouble(symbol,SYMBOL_POINT);
   if(schema!="SOLTRADE_FAST_MULTI_V2_INITIAL_RISK_V1" || account!=AccountInfoInteger(ACCOUNT_LOGIN) ||
      saved_identifier!=identifier || saved_symbol!=symbol || MathAbs(saved_entry-entry)>2.0*point || distance<=0) return 0;
   return distance;
  }

double OriginalDistanceFromBrokerHistory(const long identifier,const string symbol,const double entry)
  {
   if(!HistorySelectByPosition((ulong)identifier)) return 0;
   datetime earliest=0; double original_stop=0;
   for(int i=0;i<HistoryOrdersTotal();i++)
     {
      ulong order=HistoryOrderGetTicket(i); if(order==0 || HistoryOrderGetString(order,ORDER_SYMBOL)!=symbol) continue;
      if(HistoryOrderGetInteger(order,ORDER_MAGIC)!=FastMagic) continue;
      ENUM_ORDER_TYPE type=(ENUM_ORDER_TYPE)HistoryOrderGetInteger(order,ORDER_TYPE);
      if(type!=ORDER_TYPE_BUY && type!=ORDER_TYPE_SELL) continue;
      double stop=HistoryOrderGetDouble(order,ORDER_SL); datetime setup=(datetime)HistoryOrderGetInteger(order,ORDER_TIME_SETUP);
      if(stop>0 && (earliest==0 || setup<earliest)) { earliest=setup; original_stop=stop; }
     }
   return original_stop>0?MathAbs(entry-original_stop):0;
  }

void PersistInitialDistance(const string symbol,const double distance)
  {
   if(!PositionSelect(symbol)) return;
   long identifier=PositionGetInteger(POSITION_IDENTIFIER);
   SaveInitialDistance(identifier,symbol,PositionGetDouble(POSITION_PRICE_OPEN),distance);
  }

double InitialDistanceForSelectedPosition()
  {
   long identifier=PositionGetInteger(POSITION_IDENTIFIER);
   string symbol=PositionGetString(POSITION_SYMBOL); double entry=PositionGetDouble(POSITION_PRICE_OPEN);
   double durable=LoadInitialDistance(identifier,symbol,entry);
   if(durable>0) { GlobalVariableSet(RiskKey(identifier),durable); return durable; }
   double broker_original=OriginalDistanceFromBrokerHistory(identifier,symbol,entry);
   if(broker_original>0) { SaveInitialDistance(identifier,symbol,entry,broker_original); return broker_original; }
   string key=RiskKey(identifier);
   string legacy_key=LegacyRiskKey(identifier);
   if(GlobalVariableCheck(legacy_key))
     {
      double legacy=GlobalVariableGet(legacy_key); SaveInitialDistance(identifier,symbol,entry,legacy); return legacy;
     }
   if(GlobalVariableCheck(key))
     {
      double existing=GlobalVariableGet(key); SaveInitialDistance(identifier,symbol,entry,existing); return existing;
     }
   double distance=MathAbs(PositionGetDouble(POSITION_PRICE_OPEN)-PositionGetDouble(POSITION_SL));
   if(distance>0) SaveInitialDistance(identifier,symbol,entry,distance);
   return distance;
  }

string EpochStatePath() { return "SolTradeFastMultiMarketV2\\epoch-state.csv"; }

long LoadOrCreateV2Epoch()
  {
   long epoch=0; int h=FileOpen(EpochStatePath(),FILE_READ|FILE_CSV|FILE_ANSI|FILE_COMMON,',');
   if(h!=INVALID_HANDLE)
     {
      string schema=FileReadString(h); long account=(long)StringToInteger(FileReadString(h)); string server=FileReadString(h);
      long saved=(long)StringToInteger(FileReadString(h)); FileClose(h);
      if(schema=="SOLTRADE_FAST_MULTI_V2_EPOCH_V1" && account==AccountInfoInteger(ACCOUNT_LOGIN) &&
         server==AccountInfoString(ACCOUNT_SERVER) && saved>0) epoch=saved;
     }
   string key="SFM2_EPOCH_"+IntegerToString((long)AccountInfoInteger(ACCOUNT_LOGIN));
   if(epoch<=0 && GlobalVariableCheck(key)) epoch=(long)GlobalVariableGet(key);
   if(epoch<=0) epoch=(long)TimeTradeServer();
   int out=FileOpen(EpochStatePath()+".tmp",FILE_WRITE|FILE_CSV|FILE_ANSI|FILE_COMMON,',');
   if(out!=INVALID_HANDLE)
     {
      FileWrite(out,"SOLTRADE_FAST_MULTI_V2_EPOCH_V1",AccountInfoInteger(ACCOUNT_LOGIN),AccountInfoString(ACCOUNT_SERVER),epoch);
      FileFlush(out); FileClose(out); FileDelete(EpochStatePath(),FILE_COMMON);
      FileMove(EpochStatePath()+".tmp",FILE_COMMON,EpochStatePath(),FILE_COMMON|FILE_REWRITE);
     }
   GlobalVariableSet(key,(double)epoch); GlobalVariablesFlush();
   return epoch;
  }

int SymbolIndexByActual(const string symbol)
  {
   for(int i=0;i<SYMBOL_COUNT;i++) if(g_symbols[i]==symbol) return i;
   return -1;
  }

string ReversalStatePath() { return "SolTradeFastMultiMarketV2\\reversal-state.csv"; }

void SaveReversalState()
  {
   int h=FileOpen(ReversalStatePath()+".tmp",FILE_WRITE|FILE_CSV|FILE_ANSI|FILE_COMMON,',');
   if(h==INVALID_HANDLE) return;
   FileWrite(h,"schema","symbol","last_exit_direction","last_exit_time","last_setup_key","last_exit_invalidated");
   for(int i=0;i<SYMBOL_COUNT;i++) FileWrite(h,"SOLTRADE_FAST_MULTI_V2_REVERSAL_V1",BASE_SYMBOLS[i],g_last_exit_direction[i],
      g_last_exit_time[i],g_last_setup_key[i],BoolText(g_last_exit_invalidated[i]));
   FileFlush(h); FileClose(h);
   FileDelete(ReversalStatePath(),FILE_COMMON);
   FileMove(ReversalStatePath()+".tmp",FILE_COMMON,ReversalStatePath(),FILE_COMMON|FILE_REWRITE);
  }

void LoadReversalState()
  {
   ArrayInitialize(g_last_exit_direction,0); ArrayInitialize(g_last_exit_time,0); ArrayInitialize(g_last_setup_key,0);
   ArrayInitialize(g_last_exit_invalidated,false);
   int h=FileOpen(ReversalStatePath(),FILE_READ|FILE_CSV|FILE_ANSI|FILE_COMMON,',');
   if(h==INVALID_HANDLE) return;
   for(int header=0;header<6 && !FileIsEnding(h);header++) FileReadString(h);
   while(!FileIsEnding(h))
     {
      string schema=FileReadString(h),base=FileReadString(h);
      int direction=(int)StringToInteger(FileReadString(h)); long exit_time=(long)StringToInteger(FileReadString(h));
      long setup=(long)StringToInteger(FileReadString(h)); bool invalidated=FileReadString(h)=="true";
      if(schema!="SOLTRADE_FAST_MULTI_V2_REVERSAL_V1") continue;
      for(int i=0;i<SYMBOL_COUNT;i++) if(BASE_SYMBOLS[i]==base)
        { g_last_exit_direction[i]=direction; g_last_exit_time[i]=exit_time; g_last_setup_key[i]=setup; g_last_exit_invalidated[i]=invalidated; break; }
     }
   FileClose(h);
  }

void AppendEvidence(const string event_name,const MarketScore &score,const ulong ticket,const string detail)
  {
   int h=FileOpen("SolTradeFastMultiMarketV2\\evidence.csv",FILE_READ|FILE_WRITE|FILE_CSV|FILE_ANSI|FILE_COMMON,',');
   if(h==INVALID_HANDLE) return;
   if(FileSize(h)==0) FileWrite(h,"schema","utc","event","ticket","symbol","direction","entry","stop","buy_case","sell_case",
      "no_trade_case","regime","m1","m5","m15","h1","session","previous_session","levels","available_move","expected_cost_move","expected_net_move",
      "spread","setup_key","detail");
   FileSeek(h,0,SEEK_END);
   FileWrite(h,"SOLTRADE_FAST_MULTI_V2_EVIDENCE_V1",TimeToString(TimeGMT(),TIME_DATE|TIME_SECONDS),event_name,ticket,score.symbol,
      DirectionText(score.direction),DoubleToString(score.entry,8),DoubleToString(score.stop,8),score.buy_case,score.sell_case,
      score.no_trade_case,score.regime,score.context_m1,score.context_m5,score.context_m15,score.context_h1,score.session_context,score.previous_session_context,
      score.structural_levels,DoubleToString(score.available_move,8),DoubleToString(score.expected_cost_move,8),
      DoubleToString(score.expected_net_move,8),DoubleToString(score.spread,8),score.setup_key,detail);
   FileFlush(h); FileClose(h);
  }

bool ReversalAndDistinctSetupAllowed(const int index,const MarketScore &candidate,string &reason)
  {
   reason="";
   if(g_last_setup_key[index]!=0 && candidate.setup_key==g_last_setup_key[index])
     { reason="SAME_STRUCTURAL_SETUP_ALREADY_CONSUMED"; return false; }
   if(g_last_exit_direction[index]==0 || g_last_exit_direction[index]==candidate.direction) return true;
   if(!g_last_exit_invalidated[index]) { reason="PREVIOUS_OPPOSITE_THESIS_NOT_EXPLICITLY_INVALIDATED"; return false; }
   double opposite=candidate.direction>0?candidate.sell_score:candidate.buy_score;
   if(!candidate.structural_reversal) { reason="NO_GENUINE_STRUCTURAL_REVERSAL"; return false; }
   if(!candidate.m5_confirmed || !candidate.m15_confirmed) { reason="M5_M15_REVERSAL_NOT_CONFIRMED"; return false; }
   if(candidate.score<opposite+MinDirectionalDominance || candidate.score<candidate.no_trade_score+MinNoTradeDominance)
     { reason="REVERSAL_DOES_NOT_DOMINATE_COMPETING_CASES"; return false; }
   if(candidate.expected_net_move<=0 || candidate.cost_multiple<MinExpectedMoveCostMultiple)
     { reason="REVERSAL_HAS_INSUFFICIENT_ROOM_AFTER_COSTS"; return false; }
   return true;
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
      long identifier=PositionGetInteger(POSITION_IDENTIFIER);
      double net_floating=PositionGetDouble(POSITION_PROFIT)+PositionGetDouble(POSITION_SWAP);
      if(!GlobalVariableCheck(MfeKey(identifier)) || net_floating>GlobalVariableGet(MfeKey(identifier))) GlobalVariableSet(MfeKey(identifier),net_floating);
      if(!GlobalVariableCheck(MaeKey(identifier)) || net_floating<GlobalVariableGet(MaeKey(identifier))) GlobalVariableSet(MaeKey(identifier),net_floating);
      MarketScore score; ZeroMemory(score); bool scored=FindScore(symbol,score);
      if(!scored) score.atr=MathMax(initial/5.0,SymbolInfoDouble(symbol,SYMBOL_POINT));
      double held_score=scored?(direction>0?score.buy_score:score.sell_score):50.0;
      double opposite_score=scored?(direction>0?score.sell_score:score.buy_score):0.0;
      bool would_open_now=scored && score.fresh && score.eligible && score.direction==direction;
      bool structure_broken=scored && score.fresh && score.direction==-direction && score.structural_reversal;
      bool thesis_bad=scored && score.fresh && (structure_broken || opposite_score>=held_score+MinDirectionalDominance ||
                       (score.no_trade_score>=held_score && held_score<MinEntryScore) || score.expected_net_move<=0);
      if(thesis_bad)
        {
         GlobalVariableSet("SFM2_INV_"+IntegerToString(identifier),1.0);
         AppendEvidence("THESIS_INVALIDATION_EXIT",score,ticket,StringFormat("current_r=%.5f;held=%.2f;opposite=%.2f;no_trade=%.2f;would_open_now=false",
            current_r,held_score,opposite_score,score.no_trade_score));
         g_trade.SetExpertMagicNumber(FastMagic);
         if(!g_trade.PositionClose(ticket)) g_status_reason="THESIS_EXIT_FAILED_"+symbol;
         else g_status_reason="THESIS_EXIT_"+symbol;
         continue;
        }
      double desired=0;
      string management="HOLD";
      MqlRates minute[]; ArraySetAsSeries(minute,true);
      bool minute_ready=CopyRates(symbol,PERIOD_M1,0,18,minute)>=16;
      double minute_atr=minute_ready?AverageRange(minute,1,12):score.atr/5.0;
      double minute_structure=direction>0?(minute_ready?LowestLow(minute,1,10):entry):(minute_ready?HighestHigh(minute,1,10):entry);
      bool strong_continuation=would_open_now && score.path_efficiency>0.48 && score.score>=78 && score.expected_net_move>score.expected_cost_move*4.0;
      if(current_r>=1.00)
        {
         double trail=MathMax(0.45*score.atr,2.5*(tick.ask-tick.bid));
         double price_trail=direction>0?current-trail:current+trail;
         double structure_trail=direction>0?minute_structure-0.35*minute_atr:minute_structure+0.35*minute_atr;
         desired=direction>0?MathMax(entry+0.50*initial,MathMin(price_trail,structure_trail)):
                              MathMin(entry-0.50*initial,MathMax(price_trail,structure_trail));
         management="TRAIL";
        }
      else if(current_r>=0.75)
        {
         double structural=direction>0?minute_structure-0.30*minute_atr:minute_structure+0.30*minute_atr;
         desired=direction>0?MathMax(entry+0.30*initial,structural):MathMin(entry-0.30*initial,structural);
         management="PROTECT_PROFIT";
        }
      else if(current_r>=0.50)
        {
         desired=entry+direction*(strong_continuation?0.05:0.15)*initial;
         management=strong_continuation?"TIGHTEN_STOP":"PROTECT_PROFIT";
        }
      else if(current_r>=0.25 && !strong_continuation && (!would_open_now || score.volatility_expansion<0.85))
        {
         desired=entry-direction*0.03*initial;
         management="TIGHTEN_STOP";
        }
      if(desired==0)
        {
         string hold_key="SFM2_HOLD_"+IntegerToString(identifier);
         long completed_bar=minute_ready?(long)minute[1].time:(long)TimeGMT()/60;
         if(!GlobalVariableCheck(hold_key) || (long)GlobalVariableGet(hold_key)!=completed_bar)
           {
            GlobalVariableSet(hold_key,(double)completed_bar);
            if(scored) AppendEvidence("HOLD",score,ticket,StringFormat("current_r=%.5f;would_open_now=%s;explicit_support=%s",
               current_r,BoolText(would_open_now),would_open_now?"THESIS_STILL_QUALIFIES":"NO_MATERIAL_INVALIDATION_YET"));
           }
         continue;
        }
      desired=NormalizePrice(symbol,desired);
      bool tighter=direction>0?desired>sl:desired<sl;
      double point=SymbolInfoDouble(symbol,SYMBOL_POINT);
      double min_distance=MathMax((double)SymbolInfoInteger(symbol,SYMBOL_TRADE_STOPS_LEVEL),
                                  (double)SymbolInfoInteger(symbol,SYMBOL_TRADE_FREEZE_LEVEL))*point;
      bool correct_side=direction>0?desired<tick.bid-min_distance:desired>tick.ask+min_distance;
      if(tighter && correct_side)
        {
         g_trade.SetExpertMagicNumber(FastMagic);
         if(!g_trade.PositionModify(ticket,desired,0))
           {
            g_status_reason="PROTECTION_FAILED_"+symbol;
            if(scored) AppendEvidence("PROTECTION_FAILED",score,ticket,"action="+management+";retcode="+IntegerToString((int)g_trade.ResultRetcode()));
           }
         else if(scored) AppendEvidence(management,score,ticket,StringFormat("current_r=%.5f;old_stop=%.8f;new_stop=%.8f;structure_aware=true",
            current_r,sl,desired));
        }
     }
  }

bool CandidatePortfolioSafe(const MarketScore &candidate,string &reason)
  {
   reason="";
   if(PositionsTotal()>=MaxSimultaneousTrades)
     { reason="MAX_SIX_POSITIONS"; return false; }
   if(HasSymbolPosition(candidate.symbol)) { reason="SYMBOL_ALREADY_OPEN"; return false; }
   int index=SymbolIndexByActual(candidate.symbol);
   if(index<0 || !ReversalAndDistinctSetupAllowed(index,candidate,reason)) return false;
   if(ThemePositionCount(ThemeForSymbol(candidate.symbol))>=MaxStronglyCorrelatedTrades)
     { reason="THEME_LIMIT"; return false; }
   string correlation_evidence;
   if(StrongCorrelationCount(candidate,correlation_evidence)>=MaxStronglyCorrelatedTrades)
     { reason="CORRELATION_LIMIT_"+correlation_evidence; return false; }
   double equity=AccountInfoDouble(ACCOUNT_EQUITY);
   double current_risk=PortfolioRiskAmount();
   double candidate_budget=equity*RiskPerTradePercent/100.0;
   if(current_risk+candidate_budget>equity*MaxPortfolioRiskPercent/100.0+0.01)
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
   string comment="SFM2-"+DirectionText(live.direction);
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
   long identifier=PositionGetInteger(POSITION_IDENTIFIER);
   GlobalVariableSet(MfeKey(identifier),0.0); GlobalVariableSet(MaeKey(identifier),0.0);
   int index=SymbolIndexByActual(live.symbol);
   if(index>=0) { g_last_setup_key[index]=live.setup_key; SaveReversalState(); }
   AppendEvidence("ENTRY",live,(ulong)PositionGetInteger(POSITION_TICKET),StringFormat("lot=%.4f;initial_risk=%.2f;broker_sl_confirmed=true;net_cost_gate=%.2f",
      lots,actual_risk,live.cost_multiple));
   reason="OPENED_"+live.symbol+"_RISK_"+DoubleToString(actual_risk,2);
   return true;
  }

bool IsLegacySlowSymbol(const string symbol)
  { return symbol=="EURGBP.r" || symbol=="AUDJPY.r" || symbol=="NZDUSD.r"; }

bool CloseLegacySlowDemoPositions(string &reason)
  {
   reason=""; string identity;
   if(!DemoIdentitySafe(identity)) { reason=identity; return false; }
   bool all_closed=true;
   for(int i=PositionsTotal()-1;i>=0;i--)
     {
      ulong ticket=PositionGetTicket(i); if(ticket==0) continue;
      if(PositionGetInteger(POSITION_MAGIC)!=LEGACY_PILOT_MAGIC || !IsLegacySlowSymbol(PositionGetString(POSITION_SYMBOL))) continue;
      string symbol=PositionGetString(POSITION_SYMBOL); MarketScore empty; ZeroMemory(empty); empty.symbol=symbol;
      AppendEvidence("LEGACY_SLOW_DEMO_V1_RETIRE",empty,ticket,"classification=LEGACY_SLOW_DEMO_V1_COMPLETED;excluded_from_fast_multi_v2=true");
      g_trade.SetExpertMagicNumber(LEGACY_PILOT_MAGIC);
      if(!g_trade.PositionClose(ticket)) { all_closed=false; reason="LEGACY_CLOSE_FAILED_"+symbol; }
     }
   if(LegacyPilotPositionCount()>0) { reason="LEGACY_EXPOSURE_REMAINS"; return false; }
   reason="LEGACY_SLOW_DEMO_V1_COMPLETED";
   return all_closed;
  }

void AggregateMagicHistoryBefore(const long magic,const datetime before,double &gross,double &commission,double &swap,double &net)
  {
   gross=0; commission=0; swap=0; net=0;
   if(!HistorySelect(0,TimeCurrent())) return;
   for(int i=0;i<HistoryDealsTotal();i++)
     {
      ulong deal=HistoryDealGetTicket(i); if(deal==0 || HistoryDealGetInteger(deal,DEAL_MAGIC)!=magic) continue;
      if(before>0 && (datetime)HistoryDealGetInteger(deal,DEAL_TIME)>=before) continue;
      gross+=HistoryDealGetDouble(deal,DEAL_PROFIT);
      commission+=HistoryDealGetDouble(deal,DEAL_COMMISSION)+HistoryDealGetDouble(deal,DEAL_FEE);
      swap+=HistoryDealGetDouble(deal,DEAL_SWAP);
     }
   net=gross+commission+swap;
  }

void WriteRuntimeStatus()
  {
   int h=FileOpen("SolTradeFastMultiMarketV2\\runtime.csv",FILE_WRITE|FILE_CSV|FILE_ANSI|FILE_COMMON,',');
   if(h==INVALID_HANDLE) return;
   double equity=AccountInfoDouble(ACCOUNT_EQUITY),risk=PortfolioRiskAmount();
   double v1_gross=0,v1_commission=0,v1_swap=0,v1_net=0;
   AggregateMagicHistoryBefore(V1_MAGIC,(datetime)g_v2_start_server,v1_gross,v1_commission,v1_swap,v1_net);
   FileWrite(h,"schema","timestamp_utc","setup_active","login","server","account_mode_demo","real_accounts_blocked",
             "connected","positions","orders","equity","portfolio_risk_amount","portfolio_risk_percent","status",
             "v1_gross","v1_commission","v1_swap","v1_net","v2_epoch_server");
   FileWrite(h,"SOLTRADE_FAST_MULTI_MARKET_RUNTIME_V2",TimeToString(TimeGMT(),TIME_DATE|TIME_SECONDS),BoolText(g_initialised),
             AccountInfoInteger(ACCOUNT_LOGIN),AccountInfoString(ACCOUNT_SERVER),
             BoolText((ENUM_ACCOUNT_TRADE_MODE)AccountInfoInteger(ACCOUNT_TRADE_MODE)==ACCOUNT_TRADE_MODE_DEMO),"true",
             BoolText((bool)TerminalInfoInteger(TERMINAL_CONNECTED)),PositionsTotal(),OrdersTotal(),DoubleToString(equity,2),
             DoubleToString(risk,2),DoubleToString(equity>0?100.0*risk/equity:0,4),g_status_reason,
             DoubleToString(v1_gross,2),DoubleToString(v1_commission,2),DoubleToString(v1_swap,2),DoubleToString(v1_net,2),g_v2_start_server);
   FileWrite(h,"rank","symbol","available","eligible","decision","score","buy_case","sell_case","no_trade_case",
             "regime","behaviour","movement_to_spread","spread_atr_percent","tick_fresh","reward_r","theme",
             "buy_case_detail","sell_case_detail","no_trade_case_detail","available_move","expected_cost_move","expected_net_move","setup_key");
   for(int i=0;i<ArraySize(g_ranked);i++)
     {
      MarketScore s=g_ranked[i];
      FileWrite(h,i+1,s.symbol,BoolText(s.available),BoolText(s.eligible),s.decision,DoubleToString(s.score,2),
                DoubleToString(s.buy_score,2),DoubleToString(s.sell_score,2),DoubleToString(s.no_trade_score,2)+":"+(s.eligible?"DEFEATED":s.reason),s.regime,s.behaviour,
                DoubleToString(s.movement_spread,2),DoubleToString(s.spread_atr_pct,2),BoolText(s.fresh),
                DoubleToString(s.reward_r,2),ThemeForSymbol(s.symbol),s.buy_case,s.sell_case,s.no_trade_case,
                DoubleToString(s.available_move,8),DoubleToString(s.expected_cost_move,8),DoubleToString(s.expected_net_move,8),s.setup_key);
     }
   FileWrite(h,"position_ticket","symbol","owner","direction","volume","entry","stop","profit","risk_amount","theme");
   for(int i=PositionsTotal()-1;i>=0;i--)
     {
      ulong ticket=PositionGetTicket(i); if(ticket==0) continue;
      string symbol=PositionGetString(POSITION_SYMBOL);
      string owner=PositionGetInteger(POSITION_MAGIC)==FastMagic?
                   ((datetime)PositionGetInteger(POSITION_TIME)>=(datetime)g_v2_start_server?"FAST_MULTI_V2":"FAST_MULTI_V1_CARRYOVER"):"LEGACY_OR_OTHER";
      FileWrite(h,ticket,symbol,owner,
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
   if(!DryRunOnly && LegacyPilotPositionCount()==0)
      for(int i=0;i<ArraySize(g_ranked);i++)
        {
         if(!g_ranked[i].eligible) continue;
         string candidate_reason;
         if(OpenCandidate(g_ranked[i],candidate_reason)) reason=candidate_reason;
         else if(reason=="NO_QUALIFYING_REPLACEMENT") reason=candidate_reason;
         if(PositionsTotal()>=MaxSimultaneousTrades) break;
        }
   else if(LegacyPilotPositionCount()>0) reason="LEGACY_SLOW_DEMO_CLEANUP_REQUIRED_BEFORE_V2_ENTRY";
   g_status_reason=reason;
   WriteRuntimeStatus();
  }

int OnInit()
  {
   string reason;
   if(!DemoIdentitySafe(reason)) { Print("SOLTRADE_FAST_MULTI_INIT_REFUSED ",reason," REAL_ACCOUNTS_BLOCKED=true"); return INIT_FAILED; }
   if(RiskPerTradePercent!=0.25 || MaxPortfolioRiskPercent!=1.50 || MaxSimultaneousTrades!=6 ||
      MaxStronglyCorrelatedTrades!=2 || ScanSeconds<5 || FastMagic!=V1_MAGIC || MinEntryScore!=68.0 ||
      MinDirectionalDominance!=12.0 || MinNoTradeDominance!=8.0 || MinExpectedMoveCostMultiple!=3.0)
     { Print("SOLTRADE_FAST_MULTI_INIT_REFUSED FROZEN_PORTFOLIO_POLICY_MISMATCH"); return INIT_PARAMETERS_INCORRECT; }
   if(!SelectUniverse()) { Print("SOLTRADE_FAST_MULTI_INIT_REFUSED NO_UNIVERSE_SYMBOL_AVAILABLE"); return INIT_FAILED; }
   LoadReversalState();
   g_v2_start_server=LoadOrCreateV2Epoch();
   g_trade.SetAsyncMode(false);
   g_trade.SetExpertMagicNumber(FastMagic);
   if(!CloseLegacySlowDemoPositions(reason))
     { Print("SOLTRADE_FAST_MULTI_V2_INIT_REFUSED ",reason); return INIT_FAILED; }
   EventSetTimer(1);
   g_initialised=true;
   g_status_reason="SOLTRADE_FAST_MULTI_MARKET_V2_ACTIVE";
   ScanAndAct();
   Print("SOLTRADE_FAST_MULTI_MARKET_V2_ACTIVE account=",AccountInfoInteger(ACCOUNT_LOGIN),
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
   if(!HistoryDealSelect(transaction.deal) || HistoryDealGetInteger(transaction.deal,DEAL_MAGIC)!=FastMagic) return;
   ENUM_DEAL_ENTRY entry=(ENUM_DEAL_ENTRY)HistoryDealGetInteger(transaction.deal,DEAL_ENTRY);
   if(entry==DEAL_ENTRY_OUT || entry==DEAL_ENTRY_OUT_BY || entry==DEAL_ENTRY_INOUT)
     {
      string symbol=HistoryDealGetString(transaction.deal,DEAL_SYMBOL); int index=SymbolIndexByActual(symbol);
      int prior_direction=HistoryDealGetInteger(transaction.deal,DEAL_TYPE)==DEAL_TYPE_SELL?1:-1;
      long position_id=HistoryDealGetInteger(transaction.deal,DEAL_POSITION_ID);
      bool invalidated=HistoryDealGetInteger(transaction.deal,DEAL_REASON)==DEAL_REASON_SL ||
                       (GlobalVariableCheck("SFM2_INV_"+IntegerToString(position_id)) && GlobalVariableGet("SFM2_INV_"+IntegerToString(position_id))>0);
      if(index>=0)
        {
         g_last_exit_direction[index]=prior_direction; g_last_exit_time[index]=(long)HistoryDealGetInteger(transaction.deal,DEAL_TIME);
         g_last_exit_invalidated[index]=invalidated; SaveReversalState();
         MarketScore score; if(!FindScore(symbol,score)) { ZeroMemory(score); score.symbol=symbol; score.direction=prior_direction; }
         double gross=0,commission=0,swap=0,net=0;
         if(HistorySelectByPosition((ulong)position_id))
            for(int i=0;i<HistoryDealsTotal();i++)
              {
               ulong deal=HistoryDealGetTicket(i); if(deal==0) continue;
               gross+=HistoryDealGetDouble(deal,DEAL_PROFIT); commission+=HistoryDealGetDouble(deal,DEAL_COMMISSION)+HistoryDealGetDouble(deal,DEAL_FEE);
               swap+=HistoryDealGetDouble(deal,DEAL_SWAP);
              }
         net=gross+commission+swap;
         double mfe=GlobalVariableCheck(MfeKey(position_id))?GlobalVariableGet(MfeKey(position_id)):0;
         double mae=GlobalVariableCheck(MaeKey(position_id))?GlobalVariableGet(MaeKey(position_id)):0;
         AppendEvidence("EXIT",score,0,StringFormat("position_id=%I64d;gross=%.2f;commission=%.2f;swap=%.2f;net=%.2f;mfe=%.2f;mae=%.2f;invalidated=%s;reason=%s",
            position_id,gross,commission,swap,net,mfe,mae,BoolText(invalidated),EnumToString((ENUM_DEAL_REASON)HistoryDealGetInteger(transaction.deal,DEAL_REASON))));
        }
      g_immediate_rescan_requested=true;
     }
  }
