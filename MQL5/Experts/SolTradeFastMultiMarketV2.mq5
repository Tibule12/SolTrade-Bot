#property strict
#property version   "2.001"
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
#define RECOVERY_HISTORY_STABLE_SCANS 3
#define RECOVERY_HISTORY_MIN_SECONDS 30

string BASE_SYMBOLS[SYMBOL_COUNT]={
   "XAUUSD","USTEC","GBPJPY","XAGUSD","DE30","EURJPY","AUDJPY","USDJPY","GBPUSD",
   "EURUSD","US500","USDCAD","AUDUSD","NZDUSD","USDCHF","STOXX50","UK100","EURGBP","AUDNZD"
};

struct MarketScore
  {
   int source_index;
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
   double bid;
   double ask;
   double point;
   double tick_size;
   int digits;
   double spread_points;
   double spread_pips;
   double recent_median_spread;
   double spread_median_ratio;
   int spread_samples;
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
double g_recent_median_spread[SYMBOL_COUNT];
double g_spread_median_ratio[SYMBOL_COUNT];
int g_spread_samples[SYMBOL_COUNT];
long g_spread_audit_msc[SYMBOL_COUNT];
string g_scan_order_status[];
string g_scan_order_result[];
bool g_reconciliation_required=true;
bool g_connection_seen=false;
bool g_first_scan_after_recovery=true;
string g_last_reconciliation_failure="";
long g_last_timer_utc=0;
long g_scan_sequence=0;
long g_last_audit_prune_day=-1;
long g_alias_attempts[SYMBOL_COUNT];
long g_last_alias_log_utc[SYMBOL_COUNT];
string g_history_fingerprint[SYMBOL_COUNT];
int g_history_stable_scans[SYMBOL_COUNT];
long g_history_last_scan[SYMBOL_COUNT];
bool g_history_ready[SYMBOL_COUNT];
long g_history_warmup_started_utc=0;

struct RunnerState
  {
   bool active;
   double peak_r;
   double peak_dollars;
   double protected_r;
   double protected_dollars;
   int trail_updates;
  };

string BoolText(const bool value) { return value?"true":"false"; }
string DirectionText(const int direction) { return direction>0?"BUY":direction<0?"SELL":"NONE"; }

string UtcStamp()
  { return TimeToString(TimeGMT(),TIME_DATE|TIME_SECONDS); }

string SastStamp()
  { return TimeToString(TimeGMT()+2*3600,TIME_DATE|TIME_SECONDS); }

string CompactUtcDay(const datetime value)
  {
   MqlDateTime parts; TimeToStruct(value,parts);
   return StringFormat("%04d%02d%02d",parts.year,parts.mon,parts.day);
  }

void AppendLifecycle(const string event_name,const string detail)
  {
   string path="SolTradeFastMultiMarketV2\\lifecycle-"+CompactUtcDay(TimeGMT())+".csv";
   int h=FileOpen(path,FILE_READ|FILE_WRITE|FILE_CSV|FILE_ANSI|FILE_COMMON,',');
   if(h==INVALID_HANDLE) return;
   if(FileSize(h)==0)
      FileWrite(h,"schema","utc","sast","event","login","server","terminal_connected","positions","orders","detail");
   FileSeek(h,0,SEEK_END);
   FileWrite(h,"SOLTRADE_FAST_MULTI_V2_LIFECYCLE_V1",UtcStamp(),SastStamp(),event_name,
             AccountInfoInteger(ACCOUNT_LOGIN),AccountInfoString(ACCOUNT_SERVER),
             BoolText((bool)TerminalInfoInteger(TERMINAL_CONNECTED)),PositionsTotal(),OrdersTotal(),detail);
   FileFlush(h); FileClose(h);
  }

void ResetHistoryWarmup(const string reason)
  {
   g_history_warmup_started_utc=(long)TimeGMT();
   for(int i=0;i<SYMBOL_COUNT;i++)
     {
      g_history_fingerprint[i]="";
      g_history_stable_scans[i]=0;
      g_history_last_scan[i]=-1;
      g_history_ready[i]=false;
     }
   AppendLifecycle("HISTORY_WARMUP_STARTED",StringFormat(
      "reason=%s;minimum_seconds=%d;stable_scans=%d;new_entries_and_unstable_management_blocked=true",
      reason,RECOVERY_HISTORY_MIN_SECONDS,RECOVERY_HISTORY_STABLE_SCANS));
  }

bool UpdateHistoryReadiness(const int index,const string fingerprint)
  {
   if(index<0 || index>=SYMBOL_COUNT || fingerprint=="") return false;
   if(g_history_last_scan[index]==g_scan_sequence) return g_history_ready[index];
   g_history_last_scan[index]=g_scan_sequence;
   if(g_history_fingerprint[index]==fingerprint) g_history_stable_scans[index]++;
   else
     {
      g_history_fingerprint[index]=fingerprint;
      g_history_stable_scans[index]=1;
      g_history_ready[index]=false;
     }
   bool ready=g_history_stable_scans[index]>=RECOVERY_HISTORY_STABLE_SCANS &&
              (long)TimeGMT()-g_history_warmup_started_utc>=RECOVERY_HISTORY_MIN_SECONDS;
   if(ready && !g_history_ready[index])
      AppendLifecycle("HISTORY_WARMUP_SYMBOL_READY",StringFormat(
         "intended=%s;actual=%s;stable_scans=%d;elapsed_seconds=%I64d",
         BASE_SYMBOLS[index],g_symbols[index],g_history_stable_scans[index],
         (long)TimeGMT()-g_history_warmup_started_utc));
   g_history_ready[index]=ready;
   return ready;
  }

string DeinitReasonText(const int reason)
  {
   if(reason==REASON_PROGRAM) return "REASON_PROGRAM";
   if(reason==REASON_REMOVE) return "REASON_REMOVE";
   if(reason==REASON_RECOMPILE) return "REASON_RECOMPILE";
   if(reason==REASON_CHARTCHANGE) return "REASON_CHARTCHANGE";
   if(reason==REASON_CHARTCLOSE) return "REASON_CHARTCLOSE";
   if(reason==REASON_PARAMETERS) return "REASON_PARAMETERS";
   if(reason==REASON_ACCOUNT) return "REASON_ACCOUNT";
   if(reason==REASON_TEMPLATE) return "REASON_TEMPLATE";
   if(reason==REASON_INITFAILED) return "REASON_INITFAILED";
   if(reason==REASON_CLOSE) return "REASON_TERMINAL_CLOSE_OR_UPDATE";
   return "REASON_"+IntegerToString(reason);
  }

void PruneRotatedAuditFiles()
  {
   long utc_day=(long)TimeGMT()/86400;
   if(utc_day==g_last_audit_prune_day) return;
   g_last_audit_prune_day=utc_day;
   datetime expired=(datetime)((utc_day-8)*86400);
   string day=CompactUtcDay(expired);
   FileDelete("SolTradeFastMultiMarketV2\\scan-history-"+day+".csv",FILE_COMMON);
   FileDelete("SolTradeFastMultiMarketV2\\lifecycle-"+day+".csv",FILE_COMMON);
  }

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

bool IsFxMarket(const int index)
  {
   string market=BASE_SYMBOLS[index];
   return StringLen(market)==6 && market!="XAUUSD" && market!="XAGUSD";
  }

string SpreadRepresentation(const int index)
  {
   if(IsFxMarket(index)) return "FX_PIP_AND_POINT";
   if(BASE_SYMBOLS[index]=="XAUUSD" || BASE_SYMBOLS[index]=="XAGUSD") return "METAL_TICK_AND_POINT";
   return "INDEX_TICK_AND_POINT";
  }

void UpdateRecentSpreadAudit(const int index,const string symbol,const MqlTick &current)
  {
   bool refresh=g_spread_audit_msc[index]<=0 || current.time_msc-g_spread_audit_msc[index]>=300000;
   if(refresh)
     {
      MqlTick ticks[];
      ulong end_msc=(ulong)current.time_msc;
      ulong start_msc=end_msc>3600000?end_msc-3600000:0;
      int copied=CopyTicksRange(symbol,ticks,COPY_TICKS_INFO,start_msc,end_msc);
      double spreads[]; int count=0;
      if(copied>0)
        {
         ArrayResize(spreads,copied);
         for(int i=0;i<copied;i++)
           {
            double value=ticks[i].ask-ticks[i].bid;
            if(ticks[i].bid>0 && ticks[i].ask>ticks[i].bid && value>0) spreads[count++]=value;
           }
        }
      if(count>0)
        {
         ArrayResize(spreads,count); ArraySort(spreads);
         g_recent_median_spread[index]=count%2==1?spreads[count/2]:0.5*(spreads[count/2-1]+spreads[count/2]);
         g_spread_samples[index]=count;
        }
      g_spread_audit_msc[index]=current.time_msc;
     }
   double current_spread=current.ask-current.bid;
   g_spread_median_ratio[index]=g_recent_median_spread[index]>0?current_spread/g_recent_median_spread[index]:0;
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
   string prior_symbol=g_symbols[index];
   string prior_status=g_mapping_status[index];
   g_alias_attempts[index]++;
   string cached_reason;
   if(g_cached_symbols[index]!="" && VerifyResolvedSymbol(index,g_cached_symbols[index],cached_reason))
     {
      g_symbols[index]=g_cached_symbols[index];
      g_mapping_status[index]=cached_reason;
      g_mapping_source[index]="CACHE_REVALIDATED";
      bool changed=prior_symbol!=g_symbols[index] || prior_status!=g_mapping_status[index];
      if(changed || g_last_alias_log_utc[index]<=0 || (long)TimeGMT()-g_last_alias_log_utc[index]>=300)
        {
         AppendLifecycle(changed?"INDEX_ALIAS_VERIFIED":"INDEX_ALIAS_REVERIFIED",
            StringFormat("intended=%s;actual=%s;status=%s;source=%s;attempt=%I64d",
               ConfiguredSymbol(index),g_symbols[index],g_mapping_status[index],g_mapping_source[index],g_alias_attempts[index]));
         g_last_alias_log_utc[index]=(long)TimeGMT();
        }
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
      bool changed=prior_symbol!=g_symbols[index] || prior_status!=g_mapping_status[index];
      if(changed || g_last_alias_log_utc[index]<=0 || (long)TimeGMT()-g_last_alias_log_utc[index]>=300)
        {
         AppendLifecycle("INDEX_ALIAS_RETRY_FAILED",StringFormat(
            "intended=%s;cached=%s;cached_validation=%s;status=%s;attempt=%I64d;retry_later=true",
            ConfiguredSymbol(index),g_cached_symbols[index],cached_reason,g_mapping_status[index],g_alias_attempts[index]));
         g_last_alias_log_utc[index]=(long)TimeGMT();
        }
      return false;
     }
   g_symbols[index]=best;
   g_cached_symbols[index]=best;
   g_mapping_status[index]=best_status;
   g_mapping_source[index]="BROKER_ENUMERATION";
   AppendLifecycle("INDEX_ALIAS_VERIFIED",StringFormat(
      "intended=%s;actual=%s;status=%s;source=%s;attempt=%I64d",
      ConfiguredSymbol(index),g_symbols[index],g_mapping_status[index],g_mapping_source[index],g_alias_attempts[index]));
   g_last_alias_log_utc[index]=(long)TimeGMT();
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
   out.source_index=index;
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
   if(CopyRates(out.symbol,PERIOD_M1,0,82,m1)<75)
     { g_history_ready[index]=false; out.reason="INSUFFICIENT_M1_HISTORY"; return false; }
   if(CopyRates(out.symbol,PERIOD_M5,0,102,m5)<90)
     { g_history_ready[index]=false; out.reason="INSUFFICIENT_M5_HISTORY"; return false; }
   if(CopyRates(out.symbol,PERIOD_M15,0,82,m15)<72)
     { g_history_ready[index]=false; out.reason="INSUFFICIENT_M15_HISTORY"; return false; }
   if(CopyRates(out.symbol,PERIOD_H1,0,52,h1)<48)
     { g_history_ready[index]=false; out.reason="INSUFFICIENT_H1_HISTORY"; return false; }
   bool series_synchronised=(bool)SeriesInfoInteger(out.symbol,PERIOD_M1,SERIES_SYNCHRONIZED) &&
                            (bool)SeriesInfoInteger(out.symbol,PERIOD_M5,SERIES_SYNCHRONIZED) &&
                            (bool)SeriesInfoInteger(out.symbol,PERIOD_M15,SERIES_SYNCHRONIZED) &&
                            (bool)SeriesInfoInteger(out.symbol,PERIOD_H1,SERIES_SYNCHRONIZED);
   if(!series_synchronised)
     {
      g_history_ready[index]=false;
      g_history_stable_scans[index]=0;
      g_history_fingerprint[index]="";
      out.reason="POST_RECOVERY_HISTORY_NOT_SYNCHRONISED";
      return true;
     }
   string history_fingerprint=StringFormat(
      "%I64d:%.8f:%.8f:%.8f|%I64d:%.8f:%.8f:%.8f:%.8f:%.8f:%.8f|%I64d:%.8f:%.8f:%.8f|%I64d:%.8f:%.8f:%.8f",
      (long)m1[1].time,m1[1].close,m1[8].close,m1[30].close,
      (long)m5[1].time,m5[1].open,m5[1].high,m5[1].low,m5[1].close,m5[13].close,m5[30].close,
      (long)m15[1].time,m15[1].close,m15[12].close,m15[30].close,
      (long)h1[1].time,h1[1].close,h1[8].close,h1[24].close);
   bool history_ready=UpdateHistoryReadiness(index,history_fingerprint);

   long reference_msc=(long)TimeTradeServer()*1000;
   out.fresh=MathMax(0.0,(reference_msc-tick.time_msc)/1000.0)<=MaxTickAgeSeconds;
   out.bid=tick.bid; out.ask=tick.ask;
   out.point=SymbolInfoDouble(out.symbol,SYMBOL_POINT);
   out.tick_size=SymbolInfoDouble(out.symbol,SYMBOL_TRADE_TICK_SIZE);
   out.digits=(int)SymbolInfoInteger(out.symbol,SYMBOL_DIGITS);
   UpdateRecentSpreadAudit(index,out.symbol,tick);
   out.spread=tick.ask-tick.bid;
   out.spread_points=out.point>0?out.spread/out.point:0;
   double pip_size=(IsFxMarket(index) && (out.digits==3 || out.digits==5))?10.0*out.point:out.point;
   out.spread_pips=(IsFxMarket(index) && pip_size>0)?out.spread/pip_size:0;
   out.recent_median_spread=g_recent_median_spread[index];
   out.spread_median_ratio=g_spread_median_ratio[index];
   out.spread_samples=g_spread_samples[index];
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

   if(!history_ready) out.reason="POST_RECOVERY_HISTORY_WARMUP";
   else if(!out.fresh) out.reason="STALE_TICK";
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

string RunnerStatePath(const long identifier)
  { return "SolTradeFastMultiMarketV2\\runner-state-"+IntegerToString(identifier)+".csv"; }

void ResetRunnerState(RunnerState &state)
  {
   state.active=false; state.peak_r=0; state.peak_dollars=0;
   state.protected_r=0; state.protected_dollars=0; state.trail_updates=0;
  }

bool LoadRunnerState(const long identifier,const string symbol,RunnerState &state)
  {
   ResetRunnerState(state);
   int h=FileOpen(RunnerStatePath(identifier),FILE_READ|FILE_CSV|FILE_ANSI|FILE_COMMON,',');
   if(h==INVALID_HANDLE) return false;
   string schema=FileReadString(h); long account=(long)StringToInteger(FileReadString(h));
   long saved_identifier=(long)StringToInteger(FileReadString(h)); string saved_symbol=FileReadString(h);
   state.active=FileReadString(h)=="true";
   state.peak_r=StringToDouble(FileReadString(h)); state.peak_dollars=StringToDouble(FileReadString(h));
   state.protected_r=StringToDouble(FileReadString(h)); state.protected_dollars=StringToDouble(FileReadString(h));
   state.trail_updates=(int)StringToInteger(FileReadString(h)); FileClose(h);
   if(schema!="SOLTRADE_FAST_MULTI_V2_RUNNER_V1" || account!=AccountInfoInteger(ACCOUNT_LOGIN) ||
      saved_identifier!=identifier || saved_symbol!=symbol) { ResetRunnerState(state); return false; }
   return true;
  }

void SaveRunnerState(const long identifier,const string symbol,const RunnerState &state)
  {
   if(identifier<=0) return;
   string path=RunnerStatePath(identifier);
   int h=FileOpen(path+".tmp",FILE_WRITE|FILE_CSV|FILE_ANSI|FILE_COMMON,',');
   if(h==INVALID_HANDLE) return;
   FileWrite(h,"SOLTRADE_FAST_MULTI_V2_RUNNER_V1",AccountInfoInteger(ACCOUNT_LOGIN),identifier,symbol,
             BoolText(state.active),DoubleToString(state.peak_r,8),DoubleToString(state.peak_dollars,8),
             DoubleToString(state.protected_r,8),DoubleToString(state.protected_dollars,8),state.trail_updates);
   FileFlush(h); FileClose(h); FileDelete(path,FILE_COMMON);
   FileMove(path+".tmp",FILE_COMMON,path,FILE_COMMON|FILE_REWRITE);
  }

double NetProfitAtPrice(const string symbol,const int direction,const double volume,const double entry,const double price)
  {
   double gross=0; ENUM_ORDER_TYPE type=direction>0?ORDER_TYPE_BUY:ORDER_TYPE_SELL;
   if(!OrderCalcProfit(type,symbol,volume,entry,price,gross)) return 0;
   return gross-EstimatedRoundTripCommissionPerLot(symbol)*volume;
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
      RunnerState runner; LoadRunnerState(identifier,symbol,runner);
      bool runner_changed=false;
      if(current_r>runner.peak_r) { runner.peak_r=current_r; runner_changed=true; }
      if(net_floating>runner.peak_dollars) { runner.peak_dollars=net_floating; runner_changed=true; }
      MarketScore score; ZeroMemory(score); bool scored=FindScore(symbol,score);
      if(!scored) score.atr=MathMax(initial/5.0,SymbolInfoDouble(symbol,SYMBOL_POINT));
      double held_score=scored?(direction>0?score.buy_score:score.sell_score):50.0;
      double opposite_score=scored?(direction>0?score.sell_score:score.buy_score):0.0;
      bool would_open_now=scored && score.fresh && score.eligible && score.direction==direction;
      bool structure_broken=scored && score.fresh && score.direction==-direction && score.structural_reversal;
      bool thesis_bad=scored && score.fresh && (structure_broken || opposite_score>=held_score+MinDirectionalDominance ||
                       (score.no_trade_score>=held_score && held_score<MinEntryScore) || score.expected_net_move<=0);
      if(current_r>=0.75 && !runner.active)
        {
         runner.active=true; runner_changed=true;
         AppendEvidence("RUNNER_MODE_ENTERED",score,ticket,StringFormat(
            "current_r=%.5f;RUNNER_PEAK_R=%.5f;RUNNER_PEAK_DOLLARS=%.2f;no_fixed_take_profit=true",
            current_r,runner.peak_r,runner.peak_dollars));
        }
      if(runner_changed) SaveRunnerState(identifier,symbol,runner);
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
      if(runner.active)
        {
         MqlRates m5[],m15[]; ArraySetAsSeries(m5,true); ArraySetAsSeries(m15,true);
         bool m5_ready=CopyRates(symbol,PERIOD_M5,0,18,m5)>=16;
         bool m15_ready=CopyRates(symbol,PERIOD_M15,0,12,m15)>=10;
         double atr5=m5_ready?AverageRange(m5,1,14):score.atr;
         double atr15=m15_ready?AverageRange(m15,1,8):3.0*score.atr;
         double m5_structure=direction>0?(m5_ready?LowestLow(m5,1,8):minute_structure):(m5_ready?HighestHigh(m5,1,8):minute_structure);
         double m15_structure=direction>0?(m15_ready?LowestLow(m15,1,6):m5_structure):(m15_ready?HighestHigh(m15,1,6):m5_structure);
         double structure_anchor=direction>0?MathMin(m5_structure,m15_structure):MathMax(m5_structure,m15_structure);
         double breathing=MathMax(MathMax(0.25*atr5,0.12*atr15),2.5*(tick.ask-tick.bid));
         double trail=MathMax(0.55*score.atr,3.0*(tick.ask-tick.bid));
         double price_trail=direction>0?current-trail:current+trail;
         double structure_trail=direction>0?structure_anchor-breathing:structure_anchor+breathing;
         bool confirmed_profitable_structure=direction>0?structure_trail>entry:structure_trail<entry;
         if(confirmed_profitable_structure)
           {
            desired=direction>0?MathMin(price_trail,structure_trail):MathMax(price_trail,structure_trail);
            management="RUNNER_TRAIL";
           }
        }
      else if(current_r>=0.50)
        {
         double structural=direction>0?minute_structure-0.30*minute_atr:minute_structure+0.30*minute_atr;
         bool structure_permits=minute_ready && (direction>0?structural>entry:structural<entry);
         if(structure_permits)
           {
            desired=structural;
            management=strong_continuation?"TIGHTEN_STOP":"PROTECT_PROFIT";
           }
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
         if(g_trade.ResultRetcode()==TRADE_RETCODE_DONE || g_trade.ResultRetcode()==TRADE_RETCODE_DONE_PARTIAL)
           {
            if(runner.active)
              {
               runner.trail_updates++;
               runner.protected_r=direction*(desired-entry)/initial;
               runner.protected_dollars=NetProfitAtPrice(symbol,direction,PositionGetDouble(POSITION_VOLUME),entry,desired);
               SaveRunnerState(identifier,symbol,runner);
               if(scored) AppendEvidence("RUNNER_TRAIL_UPDATE",score,ticket,StringFormat(
                  "RUNNER_PEAK_R=%.5f;RUNNER_PEAK_DOLLARS=%.2f;PROTECTED_R=%.5f;PROTECTED_DOLLARS=%.2f;TRAIL_UPDATES=%d;old_stop=%.8f;new_stop=%.8f",
                  runner.peak_r,runner.peak_dollars,runner.protected_r,runner.protected_dollars,runner.trail_updates,sl,desired));
              }
           }
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

bool ReconcileBrokerState(string &reason)
  {
   reason="";
   string identity;
   if(!DemoIdentitySafe(identity)) { reason=identity; return false; }
   string seen_symbols="|";
   int owned_positions=0,owned_orders=0;
   for(int i=OrdersTotal()-1;i>=0;i--)
     {
      ulong ticket=OrderGetTicket(i); if(ticket==0 || OrderGetInteger(ORDER_MAGIC)!=FastMagic) continue;
      owned_orders++;
     }
   if(owned_orders>0) { reason="AMBIGUOUS_PENDING_FAST_MULTI_ORDER"; return false; }
   for(int i=PositionsTotal()-1;i>=0;i--)
     {
      ulong ticket=PositionGetTicket(i); if(ticket==0 || PositionGetInteger(POSITION_MAGIC)!=FastMagic) continue;
      owned_positions++;
      string symbol=PositionGetString(POSITION_SYMBOL);
      if(StringFind(seen_symbols,"|"+symbol+"|")>=0) { reason="DUPLICATE_FAST_MULTI_POSITION_"+symbol; return false; }
      seen_symbols+=symbol+"|";
      if(SymbolIndexByActual(symbol)<0) { reason="UNRESOLVED_OPEN_POSITION_SYMBOL_"+symbol; return false; }
      if(PositionGetDouble(POSITION_SL)<=0) { reason="OPEN_POSITION_WITHOUT_BROKER_STOP_"+symbol; return false; }
      long identifier=PositionGetInteger(POSITION_IDENTIFIER);
      double distance=InitialDistanceForSelectedPosition();
      if(distance<=0) { reason="INITIAL_RISK_STATE_UNRECOVERABLE_"+symbol; return false; }
      if((datetime)PositionGetInteger(POSITION_TIME)>=(datetime)g_v2_start_server)
        {
         RunnerState runner;
         if(!LoadRunnerState(identifier,symbol,runner)) { reason="RUNNER_STATE_UNRECOVERABLE_"+symbol; return false; }
         if(!GlobalVariableCheck(MfeKey(identifier)) || !GlobalVariableCheck(MaeKey(identifier)))
           { reason="MFE_MAE_STATE_UNRECOVERABLE_"+symbol; return false; }
        }
     }
   reason=StringFormat("BROKER_RECONCILIATION_PASS;owned_positions=%d;owned_orders=%d;all_stops_confirmed=true;duplicates=0",
                       owned_positions,owned_orders);
   return true;
  }

bool OpenCandidate(const MarketScore &candidate,string &reason,bool &broker_attempted)
  {
   reason=""; broker_attempted=false; string identity;
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
   broker_attempted=true;
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
   RunnerState runner; ResetRunnerState(runner); SaveRunnerState(identifier,live.symbol,runner);
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

void WriteSpreadAudit()
  {
   string path="SolTradeFastMultiMarketV2\\spread-audit.csv";
   int h=FileOpen(path+".tmp",FILE_WRITE|FILE_CSV|FILE_ANSI|FILE_COMMON,',');
   if(h==INVALID_HANDLE) return;
   FileWrite(h,"schema","utc","base_market","broker_symbol","representation","point","tick_size","digits",
             "bid","ask","raw_spread","spread_points","spread_pips","median_raw_spread","median_points","median_pips",
             "current_median_ratio","median_sample_count","spread_atr_percent","spread_filter_result");
   for(int i=0;i<ArraySize(g_ranked);i++)
     {
      MarketScore s=g_ranked[i]; int index=SymbolIndexByActual(s.symbol); if(index<0) continue;
      string current_pips=IsFxMarket(index)?DoubleToString(s.spread_pips,4):"NOT_APPLICABLE";
      string median_pips="NOT_APPLICABLE";
      double pip_size=(IsFxMarket(index) && (s.digits==3 || s.digits==5))?10.0*s.point:s.point;
      if(IsFxMarket(index) && pip_size>0) median_pips=DoubleToString(s.recent_median_spread/pip_size,4);
      FileWrite(h,"SOLTRADE_FAST_MULTI_V2_SPREAD_AUDIT_V1",TimeToString(TimeGMT(),TIME_DATE|TIME_SECONDS),BASE_SYMBOLS[index],s.symbol,
                SpreadRepresentation(index),DoubleToString(s.point,10),DoubleToString(s.tick_size,10),s.digits,
                DoubleToString(s.bid,s.digits),DoubleToString(s.ask,s.digits),DoubleToString(s.spread,10),
                DoubleToString(s.spread_points,4),current_pips,DoubleToString(s.recent_median_spread,10),
                DoubleToString(s.point>0?s.recent_median_spread/s.point:0,4),median_pips,DoubleToString(s.spread_median_ratio,4),
                s.spread_samples,DoubleToString(s.spread_atr_pct,4),s.spread_atr_pct>MaxSpreadAtrPercent?"ABNORMAL_SPREAD":"PASS");
     }
   FileFlush(h); FileClose(h); FileDelete(path,FILE_COMMON);
   FileMove(path+".tmp",FILE_COMMON,path,FILE_COMMON|FILE_REWRITE);
  }

void AppendScanAudit()
  {
   PruneRotatedAuditFiles();
   string path="SolTradeFastMultiMarketV2\\scan-history-"+CompactUtcDay(TimeGMT())+".csv";
   int h=FileOpen(path,FILE_READ|FILE_WRITE|FILE_CSV|FILE_ANSI|FILE_COMMON,',');
   if(h==INVALID_HANDLE) return;
   if(FileSize(h)==0)
      FileWrite(h,"schema","scan_sequence","utc","sast","rank","intended_market","configured_symbol",
         "resolved_broker_symbol","mapping_status","mapping_source","available","candidate_direction","decision",
         "score","buy_score","sell_score","no_trade_score","tick_state","raw_spread","spread_points","spread_pips",
         "spread_to_m5_atr_percent","movement_to_spread","structural_reversal","m5_confirmed","m15_confirmed",
         "reward_r","reward_check","expected_net_move","cost_multiple","primary_rejection_reason","eligible",
         "order_attempt_status","order_result","setup_key");
   FileSeek(h,0,SEEK_END);
   for(int rank=0;rank<ArraySize(g_ranked);rank++)
     {
      MarketScore s=g_ranked[rank];
      int index=s.source_index;
      string intended=index>=0 && index<SYMBOL_COUNT?BASE_SYMBOLS[index]:"UNKNOWN";
      string configured=index>=0 && index<SYMBOL_COUNT?ConfiguredSymbol(index):"";
      string resolved=index>=0 && index<SYMBOL_COUNT?g_symbols[index]:s.symbol;
      string mapping_status=index>=0 && index<SYMBOL_COUNT?g_mapping_status[index]:"UNKNOWN";
      string mapping_source=index>=0 && index<SYMBOL_COUNT?g_mapping_source[index]:"UNKNOWN";
      string spread_pips=index>=0 && index<SYMBOL_COUNT && IsFxMarket(index)?DoubleToString(s.spread_pips,4):"NOT_APPLICABLE";
      string order_status=rank<ArraySize(g_scan_order_status)?g_scan_order_status[rank]:"NOT_ATTEMPTED";
      string order_result=rank<ArraySize(g_scan_order_result)?g_scan_order_result[rank]:"NOT_APPLICABLE";
      FileWrite(h,"SOLTRADE_FAST_MULTI_V2_SCAN_AUDIT_V1",g_scan_sequence,UtcStamp(),SastStamp(),rank+1,
         intended,configured,resolved,mapping_status,mapping_source,BoolText(s.available),DirectionText(s.direction),s.decision,
         DoubleToString(s.score,4),DoubleToString(s.buy_score,4),DoubleToString(s.sell_score,4),DoubleToString(s.no_trade_score,4),
         s.fresh?"FRESH":"STALE_OR_UNAVAILABLE",DoubleToString(s.spread,10),DoubleToString(s.spread_points,4),spread_pips,
         DoubleToString(s.spread_atr_pct,4),DoubleToString(s.movement_spread,4),BoolText(s.structural_reversal),
         BoolText(s.m5_confirmed),BoolText(s.m15_confirmed),DoubleToString(s.reward_r,4),
         s.reward_r>=MinRewardRisk?"PASS":"FAIL",DoubleToString(s.expected_net_move,10),DoubleToString(s.cost_multiple,4),
         s.reason,BoolText(s.eligible),order_status,order_result,s.setup_key);
     }
   FileFlush(h); FileClose(h);
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
   WriteSpreadAudit();
  }

void ScanAndAct()
  {
   g_scan_sequence++;
   ArrayResize(g_ranked,SYMBOL_COUNT);
   for(int i=0;i<SYMBOL_COUNT;i++) ScoreSymbol(i,g_ranked[i]);
   SortRanked();
   ArrayResize(g_scan_order_status,SYMBOL_COUNT);
   ArrayResize(g_scan_order_result,SYMBOL_COUNT);
   for(int audit_index=0;audit_index<SYMBOL_COUNT;audit_index++)
     {
      g_scan_order_status[audit_index]="NOT_ATTEMPTED";
      g_scan_order_result[audit_index]="NOT_APPLICABLE";
     }
   bool owned_position_history_ready=true;
   for(int position_index=PositionsTotal()-1;position_index>=0;position_index--)
     {
      ulong ticket=PositionGetTicket(position_index);
      if(ticket==0 || PositionGetInteger(POSITION_MAGIC)!=FastMagic) continue;
      int symbol_index=SymbolIndexByActual(PositionGetString(POSITION_SYMBOL));
      if(symbol_index<0 || !g_history_ready[symbol_index]) { owned_position_history_ready=false; break; }
     }
   if(owned_position_history_ready) ManageFastPositions();
   else AppendLifecycle("POSITION_MANAGEMENT_HISTORY_WARMUP_BLOCKED",
                        "broker_stops_remain_active;no_modification_or_exit_from_unstable_history=true");
   string reason=DryRunOnly?"DRY_RUN_SCAN_COMPLETE":"NO_QUALIFYING_REPLACEMENT";
   if(!DryRunOnly && LegacyPilotPositionCount()==0)
      for(int i=0;i<ArraySize(g_ranked);i++)
        {
         if(!g_ranked[i].eligible) continue;
         string candidate_reason;
         bool broker_attempted=false;
         if(OpenCandidate(g_ranked[i],candidate_reason,broker_attempted)) reason=candidate_reason;
         else if(reason=="NO_QUALIFYING_REPLACEMENT") reason=candidate_reason;
         g_scan_order_status[i]=broker_attempted?"BROKER_ORDER_SUBMITTED":"PRE_SUBMISSION_EVALUATED";
         g_scan_order_result[i]=candidate_reason;
         if(PositionsTotal()>=MaxSimultaneousTrades) break;
        }
   else if(LegacyPilotPositionCount()>0)
     {
      reason="LEGACY_SLOW_DEMO_CLEANUP_REQUIRED_BEFORE_V2_ENTRY";
      for(int i=0;i<ArraySize(g_ranked);i++) if(g_ranked[i].eligible)
        { g_scan_order_status[i]="BLOCKED_BEFORE_SUBMISSION"; g_scan_order_result[i]=reason; }
     }
   g_status_reason=reason;
   AppendScanAudit();
   WriteRuntimeStatus();
   if(g_first_scan_after_recovery)
     {
      int available=0,eligible=0,verified_indices=0;
      for(int i=0;i<ArraySize(g_ranked);i++) { if(g_ranked[i].available) available++; if(g_ranked[i].eligible) eligible++; }
      for(int i=0;i<SYMBOL_COUNT;i++) if(IsIndexAliasMarket(i) && g_symbols[i]!="") verified_indices++;
      AppendLifecycle("FIRST_SUCCESSFUL_SCAN_AFTER_RECOVERY",StringFormat(
         "scan_sequence=%I64d;available=%d;eligible=%d;verified_indices=%d;status=%s",
         g_scan_sequence,available,eligible,verified_indices,g_status_reason));
      g_first_scan_after_recovery=false;
     }
  }

int OnInit()
  {
   AppendLifecycle("EA_INITIALIZATION_STARTED","version=2.001;isolated_fast_multi_expected=true");
   string reason;
   if(!DemoIdentitySafe(reason))
     {
      AppendLifecycle("EA_INITIALIZATION_REFUSED",reason);
      Print("SOLTRADE_FAST_MULTI_INIT_REFUSED ",reason," REAL_ACCOUNTS_BLOCKED=true"); return INIT_FAILED;
     }
   if(RiskPerTradePercent!=0.25 || MaxPortfolioRiskPercent!=1.50 || MaxSimultaneousTrades!=6 ||
      MaxStronglyCorrelatedTrades!=2 || ScanSeconds<5 || FastMagic!=V1_MAGIC || MinEntryScore!=68.0 ||
      MinDirectionalDominance!=12.0 || MinNoTradeDominance!=8.0 || MinExpectedMoveCostMultiple!=3.0)
     { AppendLifecycle("EA_INITIALIZATION_REFUSED","FROZEN_PORTFOLIO_POLICY_MISMATCH"); Print("SOLTRADE_FAST_MULTI_INIT_REFUSED FROZEN_PORTFOLIO_POLICY_MISMATCH"); return INIT_PARAMETERS_INCORRECT; }
   if(!SelectUniverse()) { AppendLifecycle("EA_INITIALIZATION_REFUSED","NO_UNIVERSE_SYMBOL_AVAILABLE"); Print("SOLTRADE_FAST_MULTI_INIT_REFUSED NO_UNIVERSE_SYMBOL_AVAILABLE"); return INIT_FAILED; }
   LoadReversalState();
   g_v2_start_server=LoadOrCreateV2Epoch();
   g_trade.SetAsyncMode(false);
   g_trade.SetExpertMagicNumber(FastMagic);
   if(!CloseLegacySlowDemoPositions(reason))
     { AppendLifecycle("EA_INITIALIZATION_REFUSED",reason); Print("SOLTRADE_FAST_MULTI_V2_INIT_REFUSED ",reason); return INIT_FAILED; }
   if(!ReconcileBrokerState(reason))
     { AppendLifecycle("BROKER_RECONCILIATION_FAILED",reason); Print("SOLTRADE_FAST_MULTI_V2_INIT_REFUSED ",reason); return INIT_FAILED; }
   AppendLifecycle("BROKER_RECONCILIATION_PASS",reason);
   g_reconciliation_required=false;
   ResetHistoryWarmup("EA_INITIALIZATION");
   g_connection_seen=(bool)TerminalInfoInteger(TERMINAL_CONNECTED);
   g_first_scan_after_recovery=true;
   g_last_timer_utc=(long)TimeGMT();
   EventSetTimer(1);
   g_initialised=true;
   g_status_reason="SOLTRADE_FAST_MULTI_MARKET_V2_ACTIVE";
   ScanAndAct();
   Print("SOLTRADE_FAST_MULTI_MARKET_V2_ACTIVE account=",AccountInfoInteger(ACCOUNT_LOGIN),
         " server=",AccountInfoString(ACCOUNT_SERVER)," real_accounts_blocked=true universe=19 max_positions=6 dry_run=",DryRunOnly);
   AppendLifecycle("EA_INITIALIZED_ACTIVE",StringFormat(
      "account=%I64d;server=%s;epoch=%I64d;real_accounts_blocked=true;universe=19;dry_run=%s",
      AccountInfoInteger(ACCOUNT_LOGIN),AccountInfoString(ACCOUNT_SERVER),g_v2_start_server,BoolText(DryRunOnly)));
   for(int i=0;i<SYMBOL_COUNT;i++)
      if(IsIndexAliasMarket(i))
         Print("SOLTRADE_FAST_INDEX_MAPPING intended=",ConfiguredSymbol(i)," actual=",g_symbols[i],
               " status=",g_mapping_status[i]," source=",g_mapping_source[i]);
   return INIT_SUCCEEDED;
  }

void OnDeinit(const int reason)
  {
   EventKillTimer();
   AppendLifecycle("EA_REMOVED",DeinitReasonText(reason));
   g_initialised=false;
   WriteRuntimeStatus();
  }

void OnTimer()
  {
   if(!g_initialised) return;
   long timer_now=(long)TimeGMT();
   long timer_gap=g_last_timer_utc>0?timer_now-g_last_timer_utc:0;
   g_last_timer_utc=timer_now;
   if(timer_gap>MathMax(30,3*ScanSeconds))
     {
      AppendLifecycle("RUNTIME_TIMER_GAP_RECOVERY",StringFormat(
         "gap_seconds=%I64d;reconciliation_required_before_scan=true",timer_gap));
      g_reconciliation_required=true;
      g_first_scan_after_recovery=true;
      ResetHistoryWarmup("RUNTIME_TIMER_GAP");
     }
   bool connected=(bool)TerminalInfoInteger(TERMINAL_CONNECTED);
   if(!connected)
     {
      if(g_connection_seen) AppendLifecycle("BROKER_DISCONNECTED","scanning_and_new_entries_blocked=true;reconciliation_required=true");
      g_connection_seen=false;
      g_reconciliation_required=true;
      g_first_scan_after_recovery=true;
      g_status_reason="BROKER_DISCONNECTED_RECONCILIATION_REQUIRED";
      WriteRuntimeStatus();
      return;
     }
   if(!g_connection_seen)
     {
      AppendLifecycle("BROKER_RECONNECTED","reconciliation_required_before_scan=true");
      g_connection_seen=true;
      g_reconciliation_required=true;
      g_first_scan_after_recovery=true;
      ResetHistoryWarmup("BROKER_RECONNECT");
     }
   string reason;
   if(!DemoIdentitySafe(reason)) { g_status_reason=reason; g_initialised=false; EventKillTimer(); WriteRuntimeStatus(); return; }
   if(g_reconciliation_required)
     {
      if(!ReconcileBrokerState(reason))
        {
         g_status_reason="BROKER_RECONCILIATION_FAILED_"+reason;
         if(reason!=g_last_reconciliation_failure) AppendLifecycle("BROKER_RECONCILIATION_FAILED",reason);
         g_last_reconciliation_failure=reason;
         WriteRuntimeStatus();
         return;
        }
      AppendLifecycle("BROKER_RECONCILIATION_PASS",reason);
      g_last_reconciliation_failure="";
      g_reconciliation_required=false;
     }
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
         RunnerState runner; LoadRunnerState(position_id,symbol,runner);
         double capture_ratio=runner.peak_dollars>0?MathMax(0.0,net)/runner.peak_dollars:0;
         AppendEvidence("EXIT",score,0,StringFormat("position_id=%I64d;gross=%.2f;commission=%.2f;swap=%.2f;net=%.2f;mfe=%.2f;mae=%.2f;invalidated=%s;reason=%s;RUNNER_MODE_ENTERED=%s;RUNNER_PEAK_R=%.5f;RUNNER_PEAK_DOLLARS=%.2f;PROTECTED_R=%.5f;PROTECTED_DOLLARS=%.2f;TRAIL_UPDATES=%d;FINAL_CAPTURE_RATIO=%.6f",
            position_id,gross,commission,swap,net,mfe,mae,BoolText(invalidated),EnumToString((ENUM_DEAL_REASON)HistoryDealGetInteger(transaction.deal,DEAL_REASON)),
            BoolText(runner.active),runner.peak_r,runner.peak_dollars,runner.protected_r,runner.protected_dollars,runner.trail_updates,capture_ratio));
        }
      g_immediate_rescan_requested=true;
     }
  }
