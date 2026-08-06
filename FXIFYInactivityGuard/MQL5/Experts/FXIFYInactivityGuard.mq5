#property copyright "SolTrade Bot"
#property version   "1.000"
#property strict
#property description "Independent FXIFY 60-day inactivity compliance guard"
#property description "History-reconstructed, minimum-volume, risk-capped maintenance entry"

input group "Guard schedule"
input bool   GuardEnabled              = true;
input int    WarningDay                = 45;
input int    MaintenanceDay            = 50;
input int    CriticalAlertDay          = 55;
input string MaintenanceSymbol         = "EURUSD";
input int    RetryIntervalMinutes      = 15;
input bool   DryRunMode                = true;

input group "Maintenance order"
input double MaximumVolume             = 0.01;
input double StopLossPips              = 10.0;
input double TakeProfitPips            = 5.0;
input int    MaximumHoldingMinutes      = 60;
input double MaximumSpreadPips         = 1.5;
input double MaximumSlippagePips       = 1.0;
input double EstimatedCommissionPerLot = 6.0;
input double MaximumStopRiskUSD        = 1.10;
input double MaximumProjectedLossUSD   = 2.0;

input group "FXIFY loss protection"
input double ReferenceInitialBalance   = 10000.0;
input double DailyLossLimitPercent     = 4.0;
input double MaximumLossLimitPercent   = 8.0;
input double LossLimitSafetyBuffer     = 50.0;

input group "Identity and monitoring"
input ulong  GuardMagicNumber          = 608055001;
input string GuardOrderComment         = "FXIFY_INACT_GUARD";
input int    MaximumTickAgeSeconds     = 120;
input string AuditLogDirectory         = "FXIFYInactivityGuard";

#define GUARD_SCHEMA "FXIFY_INACTIVITY_GUARD_EVENT_V1"
#define SECONDS_PER_DAY 86400
#define GUARD_EXECUTION_LOCK "FXIFY_INACTIVITY_GUARD_EXECUTION_LOCK"

struct GuardEntryState
  {
   bool     history_ok;
   bool     has_anchor;
   datetime anchor_time;
   datetime last_entry_time;
   long     last_entry_time_msc;
   ulong    last_entry_deal;
   long     last_entry_magic;
   string   last_entry_symbol;
   string   last_entry_source;
  };

struct GuardPlan
  {
   bool                    valid;
   string                  reason_code;
   string                  reason;
   string                  symbol;
   ENUM_ORDER_TYPE         order_type;
   ENUM_ORDER_TYPE_FILLING filling_type;
   double                  volume;
   double                  entry_price;
   double                  stop_loss;
   double                  take_profit;
   double                  pip_size;
   double                  spread_pips;
   double                  stop_risk;
   double                  spread_risk;
   double                  slippage_risk;
   double                  commission_risk;
   double                  projected_loss;
   double                  margin_required;
   double                  daily_floor;
   double                  maximum_floor;
   int                     deviation_points;
  };

string   g_resolved_symbol = "";
datetime g_last_attempt_time = 0;
datetime g_warning_cycle = 0;
datetime g_critical_cycle = 0;
long     g_last_logged_entry_msc = 0;
bool     g_submission_in_flight = false;

datetime GuardServerTime()
  {
   datetime value=TimeTradeServer();
   if(value<=0)
      value=TimeCurrent();
   return value;
  }

string GuardTimeText(const datetime value)
  {
   if(value<=0)
      return "NONE";
   return TimeToString(value,TIME_DATE|TIME_SECONDS);
  }

string GuardOrderTypeText(const ENUM_ORDER_TYPE value)
  {
   if(value==ORDER_TYPE_BUY)
      return "BUY";
   if(value==ORDER_TYPE_SELL)
      return "SELL";
   return "UNKNOWN";
  }

void ResetEntryState(GuardEntryState &state)
  {
   state.history_ok=false;
   state.has_anchor=false;
   state.anchor_time=0;
   state.last_entry_time=0;
   state.last_entry_time_msc=0;
   state.last_entry_deal=0;
   state.last_entry_magic=0;
   state.last_entry_symbol="";
   state.last_entry_source="NONE";
  }

void ResetGuardPlan(GuardPlan &plan)
  {
   plan.valid=false;
   plan.reason_code="NOT_EVALUATED";
   plan.reason="Maintenance plan has not been evaluated";
   plan.symbol="";
   plan.order_type=ORDER_TYPE_BUY;
   plan.filling_type=ORDER_FILLING_FOK;
   plan.volume=0.0;
   plan.entry_price=0.0;
   plan.stop_loss=0.0;
   plan.take_profit=0.0;
   plan.pip_size=0.0;
   plan.spread_pips=0.0;
   plan.stop_risk=0.0;
   plan.spread_risk=0.0;
   plan.slippage_risk=0.0;
   plan.commission_risk=0.0;
   plan.projected_loss=0.0;
   plan.margin_required=0.0;
   plan.daily_floor=0.0;
   plan.maximum_floor=0.0;
   plan.deviation_points=0;
  }

string GuardLogPath()
  {
   return AuditLogDirectory+"\\events.csv";
  }

void LogGuardEvent(const string event_type,
                   const string reason_code,
                   const string reason,
                   const double elapsed_days,
                   const GuardPlan &plan,
                   const ulong order_ticket=0,
                   const ulong deal_ticket=0)
  {
   FolderCreate(AuditLogDirectory);
   const string path=GuardLogPath();
   const int handle=FileOpen(path,
                             FILE_READ|FILE_WRITE|FILE_CSV|FILE_ANSI|
                             FILE_SHARE_READ,',');
   if(handle==INVALID_HANDLE)
     {
      PrintFormat("FXIFY_INACTIVITY_GUARD_LOG_FAILURE | magic=%I64u | comment=%s | event=%s | reason=%s | error=%d",
                  GuardMagicNumber,GuardOrderComment,event_type,
                  reason_code,GetLastError());
      return;
     }
   if(FileSize(handle)==0)
      FileWrite(handle,"schema","server_time","event_type","reason_code",
                "reason","elapsed_days","symbol","direction","volume",
                "entry_price","stop_loss","take_profit","projected_loss",
                "margin_required","magic_number","order_comment",
                "order_ticket","deal_ticket","dry_run");
   FileSeek(handle,0,SEEK_END);
   FileWrite(handle,GUARD_SCHEMA,GuardTimeText(GuardServerTime()),event_type,
             reason_code,reason,DoubleToString(elapsed_days,8),plan.symbol,
             GuardOrderTypeText(plan.order_type),DoubleToString(plan.volume,8),
             DoubleToString(plan.entry_price,10),
             DoubleToString(plan.stop_loss,10),
             DoubleToString(plan.take_profit,10),
             DoubleToString(plan.projected_loss,8),
             DoubleToString(plan.margin_required,8),
             StringFormat("%I64u",GuardMagicNumber),GuardOrderComment,
             StringFormat("%I64u",order_ticket),
             StringFormat("%I64u",deal_ticket),DryRunMode ? "YES" : "NO");
   FileFlush(handle);
   FileClose(handle);
   PrintFormat("FXIFY_INACTIVITY_GUARD | magic=%I64u | comment=%s | event=%s | reason_code=%s | reason=%s",
               GuardMagicNumber,GuardOrderComment,event_type,reason_code,reason);
  }

void SendGuardAlert(const string level,
                    const string reason_code,
                    const string reason)
  {
   const string message="FXIFY inactivity guard "+level+" ["+
                        reason_code+"]: "+reason;
   Alert(message);
   PrintFormat("FXIFY_INACTIVITY_GUARD_ALERT | magic=%I64u | comment=%s | level=%s | reason_code=%s | reason=%s",
               GuardMagicNumber,GuardOrderComment,level,reason_code,reason);
  }

bool IsEntryDeal(const ulong ticket)
  {
   const ENUM_DEAL_TYPE type=(ENUM_DEAL_TYPE)
      HistoryDealGetInteger(ticket,DEAL_TYPE);
   if(type!=DEAL_TYPE_BUY && type!=DEAL_TYPE_SELL)
      return false;
   const ENUM_DEAL_ENTRY entry=(ENUM_DEAL_ENTRY)
      HistoryDealGetInteger(ticket,DEAL_ENTRY);
   return (entry==DEAL_ENTRY_IN || entry==DEAL_ENTRY_INOUT) &&
          HistoryDealGetDouble(ticket,DEAL_VOLUME)>0.0;
  }

bool RebuildEntryState(const datetime now,GuardEntryState &state)
  {
   ResetEntryState(state);
   if(!HistorySelect(0,now))
      return false;
   state.history_ok=true;
   const int total=HistoryDealsTotal();
   for(int index=0;index<total;index++)
     {
      const ulong ticket=HistoryDealGetTicket(index);
      if(ticket==0)
         continue;
      const datetime deal_time=(datetime)
         HistoryDealGetInteger(ticket,DEAL_TIME);
      const long deal_time_msc=HistoryDealGetInteger(ticket,DEAL_TIME_MSC);
      if(deal_time>0 && (!state.has_anchor || deal_time<state.anchor_time))
        {
         state.has_anchor=true;
         state.anchor_time=deal_time;
        }
      if(!IsEntryDeal(ticket) || deal_time_msc<state.last_entry_time_msc)
         continue;
      state.last_entry_time=deal_time;
      state.last_entry_time_msc=deal_time_msc;
      state.last_entry_deal=ticket;
      state.last_entry_magic=HistoryDealGetInteger(ticket,DEAL_MAGIC);
      state.last_entry_symbol=HistoryDealGetString(ticket,DEAL_SYMBOL);
      state.last_entry_source=
         ((ulong)state.last_entry_magic==GuardMagicNumber)
         ? "GUARD" : "ACCOUNT_NON_GUARD";
     }
   if(state.last_entry_time>0)
     {
      state.anchor_time=state.last_entry_time;
      state.has_anchor=true;
     }
   return true;
  }

double ElapsedCalendarDays(const datetime now,const datetime anchor)
  {
   if(now<=anchor || anchor<=0)
      return 0.0;
   return (double)(now-anchor)/(double)SECONDS_PER_DAY;
  }

bool ResolveMaintenanceSymbol(string &resolved,string &reason)
  {
   resolved="";
   reason="";
   bool custom=false;
   if(SymbolExist(MaintenanceSymbol,custom))
      resolved=MaintenanceSymbol;
   else
     {
      const string raw_name=MaintenanceSymbol+".r";
      if(SymbolExist(raw_name,custom))
         resolved=raw_name;
     }
   if(resolved=="")
     {
      reason="Neither "+MaintenanceSymbol+" nor the captured RAW suffix candidate "+MaintenanceSymbol+".r exists";
      return false;
     }
   if(!SymbolSelect(resolved,true))
     {
      reason="SymbolSelect failed for "+resolved+"; error "+
             IntegerToString(GetLastError());
      return false;
     }
   return true;
  }

double SymbolPipSize(const string symbol)
  {
   const double point=SymbolInfoDouble(symbol,SYMBOL_POINT);
   const int digits=(int)SymbolInfoInteger(symbol,SYMBOL_DIGITS);
   return point*((digits==3 || digits==5) ? 10.0 : 1.0);
  }

double RoundPriceDown(const double price,const double tick_size,const int digits)
  {
   if(tick_size<=0.0)
      return 0.0;
   return NormalizeDouble(MathFloor((price+1e-12)/tick_size)*tick_size,digits);
  }

double RoundPriceUp(const double price,const double tick_size,const int digits)
  {
   if(tick_size<=0.0)
      return 0.0;
   return NormalizeDouble(MathCeil((price-1e-12)/tick_size)*tick_size,digits);
  }

bool TradingSessionOpen(const string symbol,const datetime now)
  {
   MqlDateTime parts={};
   if(!TimeToStruct(now,parts))
      return false;
   const int current_seconds=parts.hour*3600+parts.min*60+parts.sec;
   for(uint session=0;session<24;session++)
     {
      datetime from=0,to=0;
      if(!SymbolInfoSessionTrade(symbol,
                                 (ENUM_DAY_OF_WEEK)parts.day_of_week,
                                 session,from,to))
         break;
      MqlDateTime from_parts={},to_parts={};
      TimeToStruct(from,from_parts);
      TimeToStruct(to,to_parts);
      const int from_seconds=from_parts.hour*3600+from_parts.min*60+
                             from_parts.sec;
      int to_seconds=to_parts.hour*3600+to_parts.min*60+to_parts.sec;
      if(to_seconds==0 && to>from)
         to_seconds=SECONDS_PER_DAY;
      if(from_seconds<=to_seconds)
        {
         if(current_seconds>=from_seconds && current_seconds<to_seconds)
            return true;
        }
      else if(current_seconds>=from_seconds || current_seconds<to_seconds)
         return true;
     }
   return false;
  }

ENUM_ORDER_TYPE_FILLING GuardFillingMode(const string symbol)
  {
   const long flags=SymbolInfoInteger(symbol,SYMBOL_FILLING_MODE);
   const ENUM_SYMBOL_TRADE_EXECUTION execution=
      (ENUM_SYMBOL_TRADE_EXECUTION)
      SymbolInfoInteger(symbol,SYMBOL_TRADE_EXEMODE);
   if((flags&SYMBOL_FILLING_FOK)==SYMBOL_FILLING_FOK)
      return ORDER_FILLING_FOK;
   if((flags&SYMBOL_FILLING_IOC)==SYMBOL_FILLING_IOC)
      return ORDER_FILLING_IOC;
   if(execution!=SYMBOL_TRADE_EXECUTION_MARKET)
      return ORDER_FILLING_RETURN;
   return ORDER_FILLING_FOK;
  }

bool AnyPositionOnSymbol(const string symbol)
  {
   for(int index=PositionsTotal()-1;index>=0;index--)
     {
      if(PositionGetTicket(index)>0 &&
         PositionGetString(POSITION_SYMBOL)==symbol)
         return true;
     }
   return false;
  }

bool HasActiveGuardOrder()
  {
   for(int index=OrdersTotal()-1;index>=0;index--)
     {
      if(OrderGetTicket(index)==0)
         continue;
      if((ulong)OrderGetInteger(ORDER_MAGIC)==GuardMagicNumber ||
         OrderGetString(ORDER_COMMENT)==GuardOrderComment)
         return true;
     }
   return false;
  }

bool SelectGuardPosition(ulong &ticket)
  {
   ticket=0;
   for(int index=PositionsTotal()-1;index>=0;index--)
     {
      const ulong candidate=PositionGetTicket(index);
      if(candidate==0)
         continue;
      if((ulong)PositionGetInteger(POSITION_MAGIC)==GuardMagicNumber)
        {
         ticket=candidate;
         return true;
        }
     }
   return false;
  }

bool SelectGuardPositionWithChangedOwnership(ulong &ticket)
  {
   ticket=0;
   if(!HistorySelect(0,GuardServerTime()))
      return false;
   ulong guard_identifiers[];
   ArrayResize(guard_identifiers,0);
   const int deals=HistoryDealsTotal();
   for(int index=0;index<deals;index++)
     {
      const ulong deal=HistoryDealGetTicket(index);
      if(deal==0 || !IsEntryDeal(deal) ||
         (ulong)HistoryDealGetInteger(deal,DEAL_MAGIC)!=GuardMagicNumber)
         continue;
      const ulong identifier=(ulong)
         HistoryDealGetInteger(deal,DEAL_POSITION_ID);
      const int size=ArraySize(guard_identifiers);
      ArrayResize(guard_identifiers,size+1);
      guard_identifiers[size]=identifier;
     }
   for(int position_index=PositionsTotal()-1;position_index>=0;
       position_index--)
     {
      const ulong candidate=PositionGetTicket(position_index);
      if(candidate==0 ||
         (ulong)PositionGetInteger(POSITION_MAGIC)==GuardMagicNumber)
         continue;
      const ulong identifier=(ulong)
         PositionGetInteger(POSITION_IDENTIFIER);
      for(int guard_index=0;guard_index<ArraySize(guard_identifiers);
          guard_index++)
        {
         if(identifier==guard_identifiers[guard_index])
           {
            ticket=candidate;
            return true;
           }
        }
     }
   return false;
  }

bool AcquireExecutionLock(const datetime now)
  {
   if(!GlobalVariableCheck(GUARD_EXECUTION_LOCK))
      GlobalVariableSet(GUARD_EXECUTION_LOCK,0.0);
   const double current=GlobalVariableGet(GUARD_EXECUTION_LOCK);
   if(current>(double)now)
      return false;
   return GlobalVariableSetOnCondition(
             GUARD_EXECUTION_LOCK,
             (double)(now+RetryIntervalMinutes*60),current);
  }

void ReleaseExecutionLock()
  {
   if(GlobalVariableCheck(GUARD_EXECUTION_LOCK))
      GlobalVariableSet(GUARD_EXECUTION_LOCK,0.0);
  }

bool BasicTradingPermissions(string &reason_code,string &reason)
  {
   if(!TerminalInfoInteger(TERMINAL_CONNECTED))
     {
      reason_code="TERMINAL_DISCONNECTED";
      reason="Terminal is not connected";
      return false;
     }
   if(!TerminalInfoInteger(TERMINAL_TRADE_ALLOWED))
     {
      reason_code="ALGO_TRADING_DISABLED";
      reason="Terminal Algo Trading permission is disabled";
      return false;
     }
   if(!MQLInfoInteger(MQL_TRADE_ALLOWED))
     {
      reason_code="PROGRAM_TRADING_DISABLED";
      reason="EA trading permission is disabled";
      return false;
     }
   if(!AccountInfoInteger(ACCOUNT_TRADE_ALLOWED) ||
      !AccountInfoInteger(ACCOUNT_TRADE_EXPERT))
     {
      reason_code="ACCOUNT_READ_ONLY_OR_TRADE_DISABLED";
      reason="Account trading or expert permission is disabled";
      return false;
     }
   return true;
  }

bool DetermineDirection(const string symbol,
                        ENUM_ORDER_TYPE &order_type,
                        string &reason)
  {
   MqlRates completed_bar[1];
   if(CopyRates(symbol,PERIOD_H1,1,1,completed_bar)!=1)
     {
      reason="Cannot read the last completed H1 bar for deterministic direction";
      return false;
     }
   order_type=(completed_bar[0].close>=completed_bar[0].open)
              ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
   return true;
  }

bool ReconstructBoundaryBalance(const datetime now,
                                double &boundary_balance,
                                datetime &boundary_server_time,
                                string &reason)
  {
   const datetime gmt=TimeGMT();
   if(gmt<=0 || now<=0)
     {
      reason="Valid server/GMT clocks are unavailable";
      return false;
     }
   const long server_offset=(long)now-(long)gmt;
   const datetime utc_now=(datetime)((long)now-server_offset);
   MqlDateTime parts={};
   if(!TimeToStruct(utc_now,parts))
     {
      reason="Cannot convert UTC clock for fixed 17:00 UTC-5 boundary";
      return false;
     }
   const int current_seconds=parts.hour*3600+parts.min*60+parts.sec;
   parts.hour=22;
   parts.min=0;
   parts.sec=0;
   datetime boundary_utc=StructToTime(parts);
   if(current_seconds<22*3600)
      boundary_utc-=SECONDS_PER_DAY;
   boundary_server_time=(datetime)((long)boundary_utc+server_offset);
   if(!HistorySelect(boundary_server_time,now))
     {
      reason="Cannot select deal history from the fixed daily boundary";
      return false;
     }
   double since_boundary_cash=0.0;
   const int total=HistoryDealsTotal();
   for(int index=0;index<total;index++)
     {
      const ulong deal=HistoryDealGetTicket(index);
      if(deal==0)
         continue;
      since_boundary_cash+=HistoryDealGetDouble(deal,DEAL_PROFIT)+
                           HistoryDealGetDouble(deal,DEAL_COMMISSION)+
                           HistoryDealGetDouble(deal,DEAL_SWAP)+
                           HistoryDealGetDouble(deal,DEAL_FEE);
     }
   boundary_balance=AccountInfoDouble(ACCOUNT_BALANCE)-since_boundary_cash;
   if(boundary_balance<=0.0 || !MathIsValidNumber(boundary_balance))
     {
      reason="Reconstructed fixed-boundary balance is invalid";
      return false;
     }
   return true;
  }

bool BuildMaintenancePlan(const datetime now,GuardPlan &plan)
  {
   ResetGuardPlan(plan);
   string reason_code="";
   string reason="";
   if(!BasicTradingPermissions(reason_code,reason))
     {
      plan.reason_code=reason_code;
      plan.reason=reason;
      return false;
     }
   if(AccountInfoString(ACCOUNT_CURRENCY)!="USD")
     {
      plan.reason_code="NON_USD_ACCOUNT_UNSUPPORTED";
      plan.reason="Commission and reference-loss inputs are denominated in USD";
      return false;
     }
   if(!ResolveMaintenanceSymbol(plan.symbol,reason))
     {
      plan.reason_code="SYMBOL_UNAVAILABLE";
      plan.reason=reason;
      return false;
     }
   g_resolved_symbol=plan.symbol;
   const ENUM_SYMBOL_TRADE_MODE trade_mode=(ENUM_SYMBOL_TRADE_MODE)
      SymbolInfoInteger(plan.symbol,SYMBOL_TRADE_MODE);
   if(trade_mode==SYMBOL_TRADE_MODE_DISABLED ||
      trade_mode==SYMBOL_TRADE_MODE_CLOSEONLY ||
      !TradingSessionOpen(plan.symbol,now))
     {
      plan.reason_code="MARKET_CLOSED_OR_NOT_TRADEABLE";
      plan.reason="Symbol is closed, disabled, or close-only";
      return false;
     }
   MqlTick tick={};
   if(!SymbolInfoTick(plan.symbol,tick) || tick.bid<=0.0 ||
      tick.ask<=tick.bid || tick.time_msc<=0)
     {
      plan.reason_code="INVALID_MARKET_DATA";
      plan.reason="Bid/ask tick is unavailable or invalid";
      return false;
     }
   if((long)(now-tick.time)>MaximumTickAgeSeconds)
     {
      plan.reason_code="STALE_MARKET_DATA";
      plan.reason="Latest market tick exceeds MaximumTickAgeSeconds";
      return false;
     }
   if(HasActiveGuardOrder() || g_submission_in_flight)
     {
      plan.reason_code="GUARD_ORDER_ACTIVE";
      plan.reason="An existing guard order or in-flight request prevents duplication";
      return false;
     }
   ulong guard_position=0;
   if(SelectGuardPosition(guard_position))
     {
      plan.reason_code="GUARD_POSITION_ACTIVE";
      plan.reason="An existing guard position prevents another entry";
      return false;
     }
   if(AnyPositionOnSymbol(plan.symbol))
     {
      plan.reason_code="SYMBOL_POSITION_CONFLICT";
      plan.reason="A position already exists on the maintenance symbol; guard will not merge with or hedge V28";
      return false;
     }
   const double point=SymbolInfoDouble(plan.symbol,SYMBOL_POINT);
   const double tick_size=SymbolInfoDouble(plan.symbol,SYMBOL_TRADE_TICK_SIZE);
   const double tick_value_loss=SymbolInfoDouble(plan.symbol,SYMBOL_TRADE_TICK_VALUE_LOSS);
   const double volume_min=SymbolInfoDouble(plan.symbol,SYMBOL_VOLUME_MIN);
   const double volume_step=SymbolInfoDouble(plan.symbol,SYMBOL_VOLUME_STEP);
   const double volume_max=SymbolInfoDouble(plan.symbol,SYMBOL_VOLUME_MAX);
   const int digits=(int)SymbolInfoInteger(plan.symbol,SYMBOL_DIGITS);
   const long order_mode=SymbolInfoInteger(plan.symbol,SYMBOL_ORDER_MODE);
   if(point<=0.0 || tick_size<=0.0 || tick_value_loss<=0.0 ||
      volume_min<=0.0 || volume_step<=0.0 || volume_max<volume_min ||
      MaximumVolume<volume_min ||
      (order_mode&SYMBOL_ORDER_MARKET)!=SYMBOL_ORDER_MARKET ||
      (order_mode&SYMBOL_ORDER_SL)!=SYMBOL_ORDER_SL ||
      (order_mode&SYMBOL_ORDER_TP)!=SYMBOL_ORDER_TP)
     {
      plan.reason_code="INVALID_SYMBOL_SPECIFICATIONS";
      plan.reason="Tick, volume, market-order, SL, or TP specification is invalid";
      return false;
     }
   plan.volume=NormalizeDouble(volume_min,8);
   if(plan.volume>MaximumVolume+1e-10 || plan.volume>volume_max+1e-10)
     {
      plan.reason_code="VOLUME_LIMIT_REJECTED";
      plan.reason="Broker minimum volume exceeds configured MaximumVolume";
      return false;
     }
   plan.pip_size=SymbolPipSize(plan.symbol);
   if(plan.pip_size<=0.0 || StopLossPips<=0.0 ||
      TakeProfitPips<=0.0 || MaximumSpreadPips<=0.0)
     {
      plan.reason_code="INVALID_GUARD_INPUTS";
      plan.reason="Pip, stop, take-profit, or spread inputs are invalid";
      return false;
     }
   plan.spread_pips=(tick.ask-tick.bid)/plan.pip_size;
   if(plan.spread_pips>MaximumSpreadPips+1e-10)
     {
      plan.reason_code="EXCESSIVE_SPREAD";
      plan.reason="Observed spread exceeds MaximumSpreadPips";
      return false;
     }
   if(!DetermineDirection(plan.symbol,plan.order_type,reason))
     {
      plan.reason_code="DIRECTION_DATA_UNAVAILABLE";
      plan.reason=reason;
      return false;
     }
   if((plan.order_type==ORDER_TYPE_BUY &&
       trade_mode==SYMBOL_TRADE_MODE_SHORTONLY) ||
      (plan.order_type==ORDER_TYPE_SELL &&
       trade_mode==SYMBOL_TRADE_MODE_LONGONLY))
     {
      plan.reason_code="DIRECTION_NOT_PERMITTED";
      plan.reason="Deterministic direction is not allowed by symbol trade mode";
      return false;
     }
   const double broker_stop_distance=
      (double)SymbolInfoInteger(plan.symbol,SYMBOL_TRADE_STOPS_LEVEL)*point;
   double stop_distance=MathMax(StopLossPips*plan.pip_size,
                                broker_stop_distance);
   double take_distance=MathMax(TakeProfitPips*plan.pip_size,
                                broker_stop_distance);
   stop_distance=MathCeil((stop_distance-1e-12)/tick_size)*tick_size;
   take_distance=MathCeil((take_distance-1e-12)/tick_size)*tick_size;
   plan.entry_price=(plan.order_type==ORDER_TYPE_BUY) ? tick.ask : tick.bid;
   if(plan.order_type==ORDER_TYPE_BUY)
     {
      plan.stop_loss=RoundPriceDown(plan.entry_price-stop_distance,
                                    tick_size,digits);
      plan.take_profit=RoundPriceUp(plan.entry_price+take_distance,
                                   tick_size,digits);
     }
   else
     {
      plan.stop_loss=RoundPriceUp(plan.entry_price+stop_distance,
                                  tick_size,digits);
      plan.take_profit=RoundPriceDown(plan.entry_price-take_distance,
                                     tick_size,digits);
     }
   if(plan.stop_loss<=0.0 || plan.take_profit<=0.0)
     {
      plan.reason_code="INVALID_PROTECTIVE_PRICES";
      plan.reason="Rounded server-side stop or take-profit price is invalid";
      return false;
     }
   const double value_per_tick=tick_value_loss*plan.volume;
   plan.stop_risk=(stop_distance/tick_size)*value_per_tick;
   plan.spread_risk=((tick.ask-tick.bid)/tick_size)*value_per_tick;
   plan.slippage_risk=((MaximumSlippagePips*plan.pip_size)/tick_size)*
                      value_per_tick;
   plan.commission_risk=EstimatedCommissionPerLot*plan.volume;
   plan.projected_loss=plan.stop_risk+plan.spread_risk+
                       plan.slippage_risk+plan.commission_risk;
   if(!MathIsValidNumber(plan.stop_risk) || plan.stop_risk<=0.0 ||
      plan.stop_risk>MaximumStopRiskUSD+1e-10)
     {
      plan.reason_code="STOP_RISK_TOO_HIGH";
      plan.reason="Broker-adjusted server stop exceeds MaximumStopRiskUSD";
      return false;
     }
   if(!MathIsValidNumber(plan.projected_loss) || plan.projected_loss<=0.0 ||
      plan.projected_loss>MaximumProjectedLossUSD+1e-10)
     {
      plan.reason_code="PROJECTED_LOSS_TOO_HIGH";
      plan.reason="Stop, spread, commission, and slippage exceed MaximumProjectedLossUSD";
      return false;
     }
   datetime boundary=0;
   double boundary_balance=0.0;
   if(!ReconstructBoundaryBalance(now,boundary_balance,boundary,reason))
     {
      plan.reason_code="DAILY_BOUNDARY_RECONSTRUCTION_FAILED";
      plan.reason=reason;
      return false;
     }
   const double equity=AccountInfoDouble(ACCOUNT_EQUITY);
   plan.daily_floor=boundary_balance*(1.0-DailyLossLimitPercent/100.0);
   plan.maximum_floor=ReferenceInitialBalance*
                      (1.0-MaximumLossLimitPercent/100.0);
   if(equity-plan.projected_loss<plan.daily_floor+LossLimitSafetyBuffer)
     {
      plan.reason_code="DAILY_LOSS_SAFETY_BUFFER";
      plan.reason="Projected worst-case equity would enter the daily-loss safety buffer";
      return false;
     }
   if(equity-plan.projected_loss<plan.maximum_floor+LossLimitSafetyBuffer)
     {
      plan.reason_code="MAXIMUM_LOSS_SAFETY_BUFFER";
      plan.reason="Projected worst-case equity would enter the maximum-loss safety buffer";
      return false;
     }
   if(!OrderCalcMargin(plan.order_type,plan.symbol,plan.volume,
                       plan.entry_price,plan.margin_required) ||
      !MathIsValidNumber(plan.margin_required) || plan.margin_required<0.0)
     {
      plan.reason_code="MARGIN_CALCULATION_FAILED";
      plan.reason="OrderCalcMargin failed for the maintenance request";
      return false;
     }
   if(AccountInfoDouble(ACCOUNT_MARGIN_FREE)<
      plan.margin_required+plan.projected_loss+LossLimitSafetyBuffer)
     {
      plan.reason_code="INSUFFICIENT_MARGIN";
      plan.reason="Free margin cannot cover margin, projected loss, and safety buffer";
      return false;
     }
   plan.filling_type=GuardFillingMode(plan.symbol);
   plan.deviation_points=(int)MathCeil(MaximumSlippagePips*
                                       plan.pip_size/point);
   plan.valid=true;
   plan.reason_code="PLAN_SAFE";
   plan.reason="All maintenance-entry safety checks passed";
   return true;
  }

bool GuardRetcodeAccepted(const uint retcode)
  {
   return retcode==TRADE_RETCODE_DONE ||
          retcode==TRADE_RETCODE_DONE_PARTIAL ||
          retcode==TRADE_RETCODE_PLACED;
  }

bool CheckGuardRequest(MqlTradeRequest &request,
                       string &reason_code,
                       string &reason)
  {
   MqlTradeCheckResult check={};
   ResetLastError();
   const bool check_succeeded=OrderCheck(request,check);
   const int check_error=GetLastError();
   // MqlTradeCheckResult reports success with retcode 0. DONE/PLACED belong
   // to the later MqlTradeResult and must not be accepted here.
   if(!check_succeeded || check.retcode!=0)
     {
      reason_code="ORDER_CHECK_REJECTED";
      reason=StringFormat("OrderCheck boolean/retcode/error: %s/%u/%d; %s",
                          check_succeeded ? "true" : "false",
                          check.retcode,check_error,check.comment);
      return false;
     }
   reason_code="ORDER_CHECK_ACCEPTED";
   reason="Broker preflight accepted the request without submitting an order";
   return true;
  }

bool SendGuardRequest(MqlTradeRequest &request,
                      MqlTradeResult &result,
                      string &reason_code,
                      string &reason)
  {
   if(!CheckGuardRequest(request,reason_code,reason))
      return false;
   ResetLastError();
   const bool sent=OrderSend(request,result);
   const int terminal_error=GetLastError();
   if(!sent || !GuardRetcodeAccepted(result.retcode))
     {
      reason_code="ORDER_SEND_REJECTED";
      reason=StringFormat("OrderSend boolean/retcode/error: %s/%u/%d; %s",
                          sent ? "true" : "false",result.retcode,
                          terminal_error,result.comment);
      return false;
     }
   reason_code="ORDER_ACCEPTED_AWAITING_DEAL";
   reason="Broker accepted request; only an executed entry deal resets inactivity";
   return true;
  }

bool SubmitMaintenanceEntry(const datetime now,
                            const double elapsed_days,
                            GuardPlan &plan)
  {
   if(!BuildMaintenancePlan(now,plan))
     {
      LogGuardEvent("MAINTENANCE_BLOCKED",plan.reason_code,plan.reason,
                    elapsed_days,plan);
      SendGuardAlert(elapsed_days>=CriticalAlertDay ? "CRITICAL" : "BLOCKED",
                     plan.reason_code,plan.reason);
      return false;
     }
   LogGuardEvent(DryRunMode ? "DRY_RUN_ENTRY_PLAN" : "ENTRY_PLAN_SAFE",
                 plan.reason_code,plan.reason,elapsed_days,plan);
   MqlTradeRequest request={};
   MqlTradeResult result={};
   request.action=TRADE_ACTION_DEAL;
   request.magic=GuardMagicNumber;
   request.symbol=plan.symbol;
   request.volume=plan.volume;
   request.type=plan.order_type;
   request.price=plan.entry_price;
   request.sl=plan.stop_loss;
   request.tp=plan.take_profit;
   request.deviation=plan.deviation_points;
   request.type_filling=plan.filling_type;
   request.type_time=ORDER_TIME_GTC;
   request.comment=GuardOrderComment;
   if(DryRunMode)
     {
      string check_code="";
      string check_reason="";
      if(!CheckGuardRequest(request,check_code,check_reason))
        {
         plan.reason_code=check_code;
         plan.reason=check_reason;
         LogGuardEvent("DRY_RUN_BROKER_PREFLIGHT_REJECTED",
                       check_code,check_reason,elapsed_days,plan);
         SendGuardAlert("BLOCKED",check_code,check_reason);
         return false;
        }
      LogGuardEvent("DRY_RUN_BROKER_PREFLIGHT_ACCEPTED",
                    check_code,check_reason,elapsed_days,plan);
      SendGuardAlert("DRY_RUN","DRY_RUN_NO_ORDER",
                     "Safe maintenance entry calculated; no order was sent");
      return true;
     }
   if(!AcquireExecutionLock(now))
     {
      plan.reason_code="CROSS_INSTANCE_EXECUTION_LOCKED";
      plan.reason="Another guard instance owns the atomic execution lock";
      LogGuardEvent("MAINTENANCE_BLOCKED",plan.reason_code,plan.reason,
                    elapsed_days,plan);
      SendGuardAlert("BLOCKED",plan.reason_code,plan.reason);
      return false;
     }
   string reason_code="";
   string reason="";
   if(!SendGuardRequest(request,result,reason_code,reason))
     {
      g_submission_in_flight=false;
      ReleaseExecutionLock();
      LogGuardEvent("ENTRY_REJECTED",reason_code,reason,elapsed_days,plan,
                    result.order,result.deal);
      SendGuardAlert("RETRY_REQUIRED",reason_code,reason);
      return false;
     }
   g_submission_in_flight=true;
   LogGuardEvent("ENTRY_ACCEPTED_AWAITING_DEAL",reason_code,reason,
                 elapsed_days,plan,result.order,result.deal);
   return true;
  }

bool BuildCloseRequest(const ulong position_ticket,
                       MqlTradeRequest &request,
                       GuardPlan &plan,
                       string &reason_code,
                       string &reason)
  {
   ResetGuardPlan(plan);
   if(!PositionSelectByTicket(position_ticket))
     {
      reason_code="GUARD_POSITION_NOT_FOUND";
      reason="Guard position disappeared before close planning";
      return false;
     }
   if((ulong)PositionGetInteger(POSITION_MAGIC)!=GuardMagicNumber)
     {
      reason_code="POSITION_OWNERSHIP_CHANGED";
      reason="Position no longer has guard identity; automatic close refused";
      return false;
     }
   plan.symbol=PositionGetString(POSITION_SYMBOL);
   plan.volume=PositionGetDouble(POSITION_VOLUME);
   const ENUM_POSITION_TYPE position_type=(ENUM_POSITION_TYPE)
      PositionGetInteger(POSITION_TYPE);
   MqlTick tick={};
   if(!SymbolInfoTick(plan.symbol,tick) || tick.bid<=0.0 || tick.ask<=tick.bid)
     {
      reason_code="CLOSE_MARKET_DATA_INVALID";
      reason="Cannot obtain a valid close price";
      return false;
     }
   plan.order_type=(position_type==POSITION_TYPE_BUY)
                   ? ORDER_TYPE_SELL : ORDER_TYPE_BUY;
   plan.entry_price=(plan.order_type==ORDER_TYPE_SELL) ? tick.bid : tick.ask;
   plan.filling_type=GuardFillingMode(plan.symbol);
   const double point=SymbolInfoDouble(plan.symbol,SYMBOL_POINT);
   plan.pip_size=SymbolPipSize(plan.symbol);
   plan.deviation_points=(int)MathCeil(MaximumSlippagePips*
                                       plan.pip_size/point);
   request.action=TRADE_ACTION_DEAL;
   request.position=position_ticket;
   request.magic=GuardMagicNumber;
   request.symbol=plan.symbol;
   request.volume=plan.volume;
   request.type=plan.order_type;
   request.price=plan.entry_price;
   request.deviation=plan.deviation_points;
   request.type_filling=plan.filling_type;
   request.type_time=ORDER_TIME_GTC;
   request.comment=GuardOrderComment;
   plan.valid=true;
   return true;
  }

void CloseGuardPosition(const ulong position_ticket,const string trigger)
  {
   GuardPlan plan;
   MqlTradeRequest request={};
   MqlTradeResult result={};
   string reason_code="";
   string reason="";
   if(!BuildCloseRequest(position_ticket,request,plan,reason_code,reason))
     {
      LogGuardEvent("GUARD_CLOSE_BLOCKED",reason_code,reason,0.0,plan);
      SendGuardAlert("CRITICAL",reason_code,reason);
      return;
     }
   if(DryRunMode)
     {
      LogGuardEvent("DRY_RUN_GUARD_CLOSE",trigger,
                    "Maximum-holding or missing-stop close calculated; no order sent",
                    0.0,plan);
      return;
     }
   if(!SendGuardRequest(request,result,reason_code,reason))
     {
      LogGuardEvent("GUARD_CLOSE_REJECTED",reason_code,reason,0.0,plan,
                    result.order,result.deal);
      SendGuardAlert("CRITICAL",reason_code,reason);
      return;
     }
   LogGuardEvent("GUARD_CLOSE_ACCEPTED",trigger,reason,0.0,plan,
                 result.order,result.deal);
  }

bool ManageExistingGuardPosition(const datetime now)
  {
   ulong ticket=0;
   if(!SelectGuardPosition(ticket))
     {
      if(SelectGuardPositionWithChangedOwnership(ticket))
        {
         GuardPlan plan;
         ResetGuardPlan(plan);
         if(PositionSelectByTicket(ticket))
           {
            plan.symbol=PositionGetString(POSITION_SYMBOL);
            plan.volume=PositionGetDouble(POSITION_VOLUME);
           }
         LogGuardEvent("POSITION_OWNERSHIP_CHANGED",
                       "POSITION_OWNERSHIP_CHANGED",
                       "A netting position containing a guard entry now has non-guard ownership; automatic close refused to protect V28",
                       0.0,plan);
         SendGuardAlert("CRITICAL","POSITION_OWNERSHIP_CHANGED",
                        "Guard will not close a netting position now owned by another strategy");
         return true;
        }
      return false;
     }
   if(!PositionSelectByTicket(ticket))
      return true;
   const double stop=PositionGetDouble(POSITION_SL);
   const datetime opened=(datetime)PositionGetInteger(POSITION_TIME);
   if(stop<=0.0)
     {
      GuardPlan plan;
      ResetGuardPlan(plan);
      plan.symbol=PositionGetString(POSITION_SYMBOL);
      plan.volume=PositionGetDouble(POSITION_VOLUME);
      LogGuardEvent("SERVER_STOP_MISSING","SERVER_STOP_MISSING",
                    "Guard position has no server-side stop; emergency close requested",
                    0.0,plan);
      SendGuardAlert("CRITICAL","SERVER_STOP_MISSING",
                     "Guard position has no server-side stop; attempting close");
      CloseGuardPosition(ticket,"SERVER_STOP_MISSING");
      return true;
     }
   if(MaximumHoldingMinutes>0 &&
      now-opened>=(datetime)(MaximumHoldingMinutes*60))
     {
      CloseGuardPosition(ticket,"MAXIMUM_HOLDING_TIME");
      return true;
     }
   return true;
  }

void EvaluateGuard()
  {
   const datetime now=GuardServerTime();
   GuardPlan empty_plan;
   ResetGuardPlan(empty_plan);
   if(!GuardEnabled)
      return;
   if(now<=0)
     {
      LogGuardEvent("EVALUATION_BLOCKED","CLOCK_UNAVAILABLE",
                    "Server clock is unavailable",0.0,empty_plan);
      return;
     }
   if(ManageExistingGuardPosition(now))
      return;
   GuardEntryState state;
   if(!RebuildEntryState(now,state) || !state.history_ok)
     {
      LogGuardEvent("EVALUATION_BLOCKED","HISTORY_UNAVAILABLE",
                    "Account deal history cannot be reconstructed",0.0,
                    empty_plan);
      SendGuardAlert("BLOCKED","HISTORY_UNAVAILABLE",
                     "Account deal history cannot be reconstructed");
      return;
     }
   g_submission_in_flight=HasActiveGuardOrder();
   if(!state.has_anchor)
     {
      LogGuardEvent("EVALUATION_BLOCKED","NO_HISTORY_ANCHOR",
                    "No executed entry or account-history anchor is available",
                    0.0,empty_plan);
      SendGuardAlert("BLOCKED","NO_HISTORY_ANCHOR",
                     "Cannot establish the inactivity timer origin");
      return;
     }
   if(state.last_entry_time_msc>g_last_logged_entry_msc)
     {
      g_last_logged_entry_msc=state.last_entry_time_msc;
      LogGuardEvent("ACCOUNT_ENTRY_RECONSTRUCTED",state.last_entry_source,
                    "Latest successful entry deal reconstructed from account history; symbol="+
                    state.last_entry_symbol+"; deal="+
                    StringFormat("%I64u",state.last_entry_deal),0.0,
                    empty_plan,0,state.last_entry_deal);
     }
   const double elapsed=ElapsedCalendarDays(now,state.anchor_time);
   if(elapsed>=WarningDay && state.anchor_time!=g_warning_cycle)
     {
      g_warning_cycle=state.anchor_time;
      LogGuardEvent("DAY_45_WARNING","INACTIVITY_WARNING",
                    "No executed account entry has occurred for WarningDay",
                    elapsed,empty_plan);
      SendGuardAlert("WARNING","INACTIVITY_WARNING",
                     "No executed entry for "+DoubleToString(elapsed,2)+" days");
     }
   if(elapsed>=CriticalAlertDay && state.anchor_time!=g_critical_cycle)
     {
      g_critical_cycle=state.anchor_time;
      LogGuardEvent("DAY_55_CRITICAL","INACTIVITY_CRITICAL",
                    "No successful maintenance entry exists by CriticalAlertDay",
                    elapsed,empty_plan);
      SendGuardAlert("CRITICAL","INACTIVITY_CRITICAL",
                     "No executed entry for "+DoubleToString(elapsed,2)+" days");
     }
   if(elapsed<MaintenanceDay)
      return;
   if(g_last_attempt_time>0 &&
      now-g_last_attempt_time<RetryIntervalMinutes*60)
      return;
   g_last_attempt_time=now;
   GuardPlan plan;
   SubmitMaintenanceEntry(now,elapsed,plan);
  }

int OnInit()
  {
   GuardPlan plan;
   ResetGuardPlan(plan);
   if(WarningDay<=0 || MaintenanceDay<=WarningDay ||
      CriticalAlertDay<MaintenanceDay || CriticalAlertDay>=60 ||
      RetryIntervalMinutes<=0 || MaximumHoldingMinutes<=0 ||
      MaximumTickAgeSeconds<=0 || MaximumVolume<=0.0 ||
      StopLossPips<=0.0 || TakeProfitPips<=0.0 ||
      MaximumSpreadPips<=0.0 || MaximumSlippagePips<0.0 ||
      EstimatedCommissionPerLot<0.0 || MaximumStopRiskUSD<=0.0 ||
      MaximumProjectedLossUSD<=0.0 || ReferenceInitialBalance<=0.0 ||
      DailyLossLimitPercent<=0.0 || DailyLossLimitPercent>=100.0 ||
      MaximumLossLimitPercent<=0.0 || MaximumLossLimitPercent>=100.0 ||
      LossLimitSafetyBuffer<0.0 || GuardMagicNumber==0 ||
      GuardOrderComment=="" || AuditLogDirectory=="")
     {
      LogGuardEvent("INITIALISATION_FAILED","INVALID_SCHEDULE_OR_IDENTITY",
                    "Require 0 < WarningDay < MaintenanceDay <= CriticalAlertDay < 60 and valid identity/intervals",
                    0.0,plan);
      return INIT_PARAMETERS_INCORRECT;
     }
   ResetLastError();
   if(!EventSetTimer(60))
     {
      LogGuardEvent("INITIALISATION_FAILED","TIMER_START_FAILED",
                    "Cannot start the 60-second guard timer; error "+
                    IntegerToString(GetLastError()),0.0,plan);
      return INIT_FAILED;
     }
   LogGuardEvent("GUARD_INITIALISED",DryRunMode ? "DRY_RUN" : "EXECUTION_ARMED",
                 "Independent history-reconstructed guard initialised",
                 0.0,plan);
   EvaluateGuard();
   return INIT_SUCCEEDED;
  }

void OnDeinit(const int reason)
  {
   EventKillTimer();
   GuardPlan plan;
   ResetGuardPlan(plan);
   LogGuardEvent("GUARD_DEINITIALISED","DEINIT_REASON_"+
                 IntegerToString(reason),
                 "Guard removed; state will be reconstructed from account history on restart",
                 0.0,plan);
  }

void OnTick()
  {
   // Timer owns scheduling. Trade transactions and account history own state.
  }

void OnTimer()
  {
   EvaluateGuard();
  }

void OnTradeTransaction(const MqlTradeTransaction &transaction,
                        const MqlTradeRequest &request,
                        const MqlTradeResult &result)
  {
   if(transaction.type!=TRADE_TRANSACTION_DEAL_ADD || transaction.deal==0)
      return;
   if(!HistoryDealSelect(transaction.deal) || !IsEntryDeal(transaction.deal))
      return;
   GuardPlan plan;
   ResetGuardPlan(plan);
   plan.symbol=HistoryDealGetString(transaction.deal,DEAL_SYMBOL);
   plan.volume=HistoryDealGetDouble(transaction.deal,DEAL_VOLUME);
   plan.entry_price=HistoryDealGetDouble(transaction.deal,DEAL_PRICE);
   const ulong magic=(ulong)HistoryDealGetInteger(transaction.deal,DEAL_MAGIC);
   const string source=(magic==GuardMagicNumber) ? "GUARD" : "ACCOUNT_NON_GUARD";
   if(magic==GuardMagicNumber)
     {
      g_submission_in_flight=false;
      ReleaseExecutionLock();
     }
   LogGuardEvent("EXECUTED_ENTRY_CONFIRMED",source,
                 "Executed DEAL_ENTRY_IN/INOUT reset the account inactivity timer",
                 0.0,plan,transaction.order,transaction.deal);
   if(magic!=GuardMagicNumber)
      return;
   ulong ticket=0;
   if(SelectGuardPosition(ticket) && PositionSelectByTicket(ticket))
     {
      if(PositionGetDouble(POSITION_SL)>0.0)
         LogGuardEvent("SERVER_STOP_CONFIRMED","SERVER_STOP_PRESENT",
                       "Guard position has a real server-side stop",
                       0.0,plan,transaction.order,transaction.deal);
      else
         SendGuardAlert("CRITICAL","SERVER_STOP_MISSING",
                        "Guard entry executed without a visible server-side stop");
     }
  }
