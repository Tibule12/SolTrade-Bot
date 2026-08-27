#property strict
#property version "1.000"
#property description "Read-only V2.200 opposing-structure and unit probe; contains no order submission path"

#define REQUIRED_DEMO_LOGIN 7404213

input string ApprovedDemoServer="FPMarketsSC-Demo";
input string RequestFile="SolTradeFastMultiMarketV220Shadow\\structure-probe-requests.csv";
input string OutputFile="SolTradeFastMultiMarketV220Shadow\\structure-probe-results.csv";
input double RiskPerTradePercent=0.25;
input int MaxSlippagePoints=12;

struct SwingDetail
  {
   double price;
   datetime bar_time;
   datetime confirmed_time;
   int series_index;
   string timeframe;
  };

double TrueRange(const MqlRates &current,const MqlRates &previous)
  {
   return MathMax(current.high-current.low,
                  MathMax(MathAbs(current.high-previous.close),MathAbs(current.low-previous.close)));
  }

double AverageRange(MqlRates &rates[],const int from,const int count)
  {
   double total=0;
   for(int index=from;index<from+count;index++) total+=TrueRange(rates[index],rates[index+1]);
   return count>0?total/count:0;
  }

bool LoadRatesAt(const string symbol,const ENUM_TIMEFRAMES timeframe,const datetime decision_server,
                 const int required,MqlRates &rates[])
  {
   ArraySetAsSeries(rates,true);
   int seconds=PeriodSeconds(timeframe);
   datetime from=decision_server-seconds*(required+40);
   int copied=CopyRates(symbol,timeframe,from,decision_server,rates);
   return copied>=required;
  }

SwingDetail NearestOpposingSwingDetail(MqlRates &rates[],const int direction,const double entry,
                                       const int from,const int count,const string timeframe)
  {
   SwingDetail nearest;
   nearest.price=0; nearest.bar_time=0; nearest.confirmed_time=0; nearest.series_index=-1; nearest.timeframe=timeframe;
   int limit=MathMin(from+count,ArraySize(rates)-1);
   int seconds=timeframe=="M5"?PeriodSeconds(PERIOD_M5):timeframe=="M15"?PeriodSeconds(PERIOD_M15):PeriodSeconds(PERIOD_H1);
   for(int index=MathMax(from,2);index<limit;index++)
     {
      bool swing=direction>0?
         rates[index].high>=rates[index-1].high && rates[index].high>=rates[index+1].high:
         rates[index].low<=rates[index-1].low && rates[index].low<=rates[index+1].low;
      double price=direction>0?rates[index].high:rates[index].low;
      bool ahead=direction>0?price>entry:price<entry;
      bool nearer=nearest.price<=0 || (direction>0?price<nearest.price:price>nearest.price);
      if(swing && ahead && nearer)
        {
         nearest.price=price;
         nearest.bar_time=rates[index].time;
         nearest.confirmed_time=rates[index-1].time+seconds;
         nearest.series_index=index;
        }
     }
   return nearest;
  }

double Room(const int direction,const double entry,const double level)
  { return level>0?direction*(level-entry):0; }

double EstimatedRoundTripCommissionPerLot(const string symbol)
  {
   if(!HistorySelect(TimeCurrent()-90*86400,TimeCurrent())) return 6.0;
   double total=0; int count=0;
   for(int index=HistoryDealsTotal()-1;index>=0 && count<40;index--)
     {
      ulong deal=HistoryDealGetTicket(index);
      if(deal==0 || HistoryDealGetString(deal,DEAL_SYMBOL)!=symbol) continue;
      double volume=HistoryDealGetDouble(deal,DEAL_VOLUME);
      double commission=MathAbs(HistoryDealGetDouble(deal,DEAL_COMMISSION)+HistoryDealGetDouble(deal,DEAL_FEE));
      if(volume<=0) continue;
      total+=commission/volume; count++;
     }
   return count>0?2.0*total/count:6.0;
  }

double ProposedLots(const string symbol,const int direction,const double entry,const double stop,
                    const double commission_per_lot,double &risk_usd)
  {
   risk_usd=0;
   double one_lot=0;
   ENUM_ORDER_TYPE type=direction>0?ORDER_TYPE_BUY:ORDER_TYPE_SELL;
   if(!OrderCalcProfit(type,symbol,1.0,entry,stop,one_lot) || one_lot>=0) return 0;
   one_lot-=commission_per_lot;
   double budget=AccountInfoDouble(ACCOUNT_EQUITY)*RiskPerTradePercent/100.0;
   double minimum=SymbolInfoDouble(symbol,SYMBOL_VOLUME_MIN);
   double maximum=SymbolInfoDouble(symbol,SYMBOL_VOLUME_MAX);
   double step=SymbolInfoDouble(symbol,SYMBOL_VOLUME_STEP);
   if(step<=0 || minimum<=0) return 0;
   double lots=MathFloor((budget/(-one_lot))/step+1e-10)*step;
   lots=MathMin(maximum,lots);
   if(lots<minimum) return 0;
   risk_usd=-one_lot*lots;
   return lots;
  }

string UtcText(const datetime server_time,const long server_utc_offset)
  {
   if(server_time<=0) return "NOT_AVAILABLE";
   return TimeToString(server_time-server_utc_offset,TIME_DATE|TIME_SECONDS);
  }

void ProcessRequests()
  {
   int request_handle=FileOpen(RequestFile,FILE_READ|FILE_CSV|FILE_ANSI|FILE_COMMON|FILE_SHARE_READ,',');
   int output=FileOpen(OutputFile+".tmp",FILE_WRITE|FILE_CSV|FILE_ANSI|FILE_COMMON,',');
   if(output==INVALID_HANDLE) { Print("SHADOW_STRUCTURE_PROBE_OUTPUT_OPEN_FAILED error=",GetLastError()); return; }
   FileWrite(output,"schema","research_label","request_id","timestamp_utc","symbol","direction","status",
      "server_utc_offset_seconds","m5_atr","m15_atr","production_spread","spread_m5_atr_percent_rebuilt",
      "m5_opposing_level","m5_swing_created_utc","m5_swing_confirmed_utc","m5_age_minutes","m5_series_index",
      "m15_opposing_level","m15_swing_created_utc","m15_swing_confirmed_utc","m15_age_minutes","m15_series_index",
      "h1_opposing_level","h1_swing_created_utc","h1_swing_confirmed_utc","h1_age_minutes","h1_series_index",
      "selected_opposing_level","selected_timeframe","selected_created_utc","selected_confirmed_utc",
      "selected_existed_before_decision","selected_distance","selected_distance_m5_atr","unopposed_projection",
      "structure_is_binding","production_available_move","reconstructed_available_move","available_move_delta",
      "tick_size","point","tick_value_profit","tick_value_loss","contract_size","commission_per_lot",
      "proposed_lots","structural_risk_usd","spread_cost_usd","gross_remaining_room_usd",
      "production_expected_net_reward_usd","production_reward_r","production_rejecting_gate",
      "production_opposing_structure_found","unit_check");
   if(request_handle==INVALID_HANDLE)
     {
      FileWrite(output,"SOLTRADE_V220_STRUCTURE_PROBE_V1","POST_DECISION_RESEARCH_ONLY","NA","NA","NA",0,
         "REQUEST_FILE_OPEN_FAILED",0);
      FileClose(output); FileMove(OutputFile+".tmp",FILE_COMMON,OutputFile,FILE_REWRITE|FILE_COMMON); return;
     }
   // Consume the header in its exact 17-column request schema.
   for(int header=0;header<17 && !FileIsEnding(request_handle);header++) FileReadString(request_handle);
   long offset=(long)TimeTradeServer()-(long)TimeGMT();
   while(!FileIsEnding(request_handle))
     {
      string request_id=FileReadString(request_handle);
      if(request_id=="") break;
      long decision_utc=(long)StringToInteger(FileReadString(request_handle));
      string timestamp_utc=FileReadString(request_handle);
      string intended=FileReadString(request_handle);
      string symbol=FileReadString(request_handle);
      int direction=(int)StringToInteger(FileReadString(request_handle));
      double entry=StringToDouble(FileReadString(request_handle));
      double stop=StringToDouble(FileReadString(request_handle));
      double stop_distance=StringToDouble(FileReadString(request_handle));
      double spread=StringToDouble(FileReadString(request_handle));
      double production_spread_atr=StringToDouble(FileReadString(request_handle));
      double expected_cost=StringToDouble(FileReadString(request_handle));
      double production_available=StringToDouble(FileReadString(request_handle));
      double production_reward=StringToDouble(FileReadString(request_handle));
      double admission_score=StringToDouble(FileReadString(request_handle));
      string rejection=FileReadString(request_handle);
      string production_opposing=FileReadString(request_handle);
      datetime decision_server=(datetime)(decision_utc+offset);
      if(!SymbolSelect(symbol,true))
        {
         FileWrite(output,"SOLTRADE_V220_STRUCTURE_PROBE_V1","POST_DECISION_RESEARCH_ONLY",request_id,timestamp_utc,
            intended,direction,"SYMBOL_SELECT_FAILED",offset);
         continue;
        }
      MqlRates m5[],m15[],h1[];
      if(!LoadRatesAt(symbol,PERIOD_M5,decision_server,45,m5) ||
         !LoadRatesAt(symbol,PERIOD_M15,decision_server,50,m15) ||
         !LoadRatesAt(symbol,PERIOD_H1,decision_server,46,h1))
        {
         FileWrite(output,"SOLTRADE_V220_STRUCTURE_PROBE_V1","POST_DECISION_RESEARCH_ONLY",request_id,timestamp_utc,
            intended,direction,"HISTORY_NOT_AVAILABLE",offset);
         continue;
        }
      double atr5=AverageRange(m5,1,14),atr15=AverageRange(m15,1,14);
      SwingDetail s5=NearestOpposingSwingDetail(m5,direction,entry,2,32,"M5");
      SwingDetail s15=NearestOpposingSwingDetail(m15,direction,entry,2,40,"M15");
      SwingDetail s1=NearestOpposingSwingDetail(h1,direction,entry,2,36,"H1");
      SwingDetail selected; selected.price=0; selected.bar_time=0; selected.confirmed_time=0; selected.series_index=-1; selected.timeframe="NONE";
      SwingDetail candidates[3]; candidates[0]=s5; candidates[1]=s15; candidates[2]=s1;
      for(int candidate=0;candidate<3;candidate++)
        {
         double candidate_room=Room(direction,entry,candidates[candidate].price);
         double selected_room=Room(direction,entry,selected.price);
         if(candidate_room>0 && (selected_room<=0 || candidate_room<selected_room)) selected=candidates[candidate];
        }
      double selected_room=Room(direction,entry,selected.price);
      double projection=MathMax(2.20*atr5,0.75*atr15);
      double reconstructed=selected_room>0?MathMin(selected_room,projection):projection;
      bool binding=selected_room>0 && selected_room<=projection;
      double commission=EstimatedRoundTripCommissionPerLot(symbol),risk_usd=0;
      double lots=ProposedLots(symbol,direction,entry,stop,commission,risk_usd);
      ENUM_ORDER_TYPE type=direction>0?ORDER_TYPE_BUY:ORDER_TYPE_SELL;
      double spread_cost=0,gross_room=0,net_reward=0;
      if(lots>0)
        {
         double temporary=0;
         if(OrderCalcProfit(type,symbol,lots,entry,entry-direction*spread,temporary)) spread_cost=MathAbs(temporary);
         if(OrderCalcProfit(type,symbol,lots,entry,entry+direction*production_available,temporary)) gross_room=temporary;
         double production_net=production_available-expected_cost;
         if(OrderCalcProfit(type,symbol,lots,entry,entry+direction*production_net,temporary)) net_reward=temporary;
        }
      double rebuilt_spread_atr=atr5>0?100.0*spread/atr5:0;
      string unit_check=(atr5>0 && spread>=0 && MathAbs(rebuilt_spread_atr-production_spread_atr)<=0.001)?
         "PRICE_UNITS_DIMENSIONLESS_PASS":"PRODUCTION_REBUILD_MISMATCH";
      FileWrite(output,"SOLTRADE_V220_STRUCTURE_PROBE_V1","POST_DECISION_RESEARCH_ONLY",request_id,timestamp_utc,
         intended,direction,"PASS",offset,
         DoubleToString(atr5,10),DoubleToString(atr15,10),DoubleToString(spread,10),DoubleToString(rebuilt_spread_atr,6),
         DoubleToString(s5.price,10),UtcText(s5.bar_time,offset),UtcText(s5.confirmed_time,offset),
         s5.bar_time>0?DoubleToString((decision_server-s5.bar_time)/60.0,1):"NA",s5.series_index,
         DoubleToString(s15.price,10),UtcText(s15.bar_time,offset),UtcText(s15.confirmed_time,offset),
         s15.bar_time>0?DoubleToString((decision_server-s15.bar_time)/60.0,1):"NA",s15.series_index,
         DoubleToString(s1.price,10),UtcText(s1.bar_time,offset),UtcText(s1.confirmed_time,offset),
         s1.bar_time>0?DoubleToString((decision_server-s1.bar_time)/60.0,1):"NA",s1.series_index,
         DoubleToString(selected.price,10),selected.timeframe,UtcText(selected.bar_time,offset),UtcText(selected.confirmed_time,offset),
         selected.confirmed_time>0 && selected.confirmed_time<=decision_server,
         DoubleToString(selected_room,10),atr5>0?DoubleToString(selected_room/atr5,6):"NA",DoubleToString(projection,10),
         binding,DoubleToString(production_available,10),DoubleToString(reconstructed,10),DoubleToString(reconstructed-production_available,10),
         DoubleToString(SymbolInfoDouble(symbol,SYMBOL_TRADE_TICK_SIZE),10),DoubleToString(SymbolInfoDouble(symbol,SYMBOL_POINT),10),
         DoubleToString(SymbolInfoDouble(symbol,SYMBOL_TRADE_TICK_VALUE_PROFIT),6),DoubleToString(SymbolInfoDouble(symbol,SYMBOL_TRADE_TICK_VALUE_LOSS),6),
         DoubleToString(SymbolInfoDouble(symbol,SYMBOL_TRADE_CONTRACT_SIZE),2),DoubleToString(commission,4),DoubleToString(lots,4),
         DoubleToString(risk_usd,2),DoubleToString(spread_cost,2),DoubleToString(gross_room,2),DoubleToString(net_reward,2),
         DoubleToString(production_reward,6),rejection,production_opposing,unit_check);
     }
   FileFlush(output); FileClose(request_handle); FileClose(output);
   if(!FileMove(OutputFile+".tmp",FILE_COMMON,OutputFile,FILE_REWRITE|FILE_COMMON))
      Print("SHADOW_STRUCTURE_PROBE_ATOMIC_MOVE_FAILED error=",GetLastError());
  }

int OnInit()
  {
   if(AccountInfoInteger(ACCOUNT_LOGIN)!=REQUIRED_DEMO_LOGIN ||
      AccountInfoString(ACCOUNT_SERVER)!=ApprovedDemoServer ||
      (ENUM_ACCOUNT_TRADE_MODE)AccountInfoInteger(ACCOUNT_TRADE_MODE)!=ACCOUNT_TRADE_MODE_DEMO)
     {
      Print("SHADOW_STRUCTURE_PROBE_REFUSED demo_identity_mismatch=true real_accounts_blocked=true");
      return INIT_FAILED;
     }
   ProcessRequests();
   Print("SHADOW_STRUCTURE_PROBE_COMPLETE research_only=true no_order_path=true");
   TerminalClose(0);
   return INIT_SUCCEEDED;
  }

void OnTick() {}
