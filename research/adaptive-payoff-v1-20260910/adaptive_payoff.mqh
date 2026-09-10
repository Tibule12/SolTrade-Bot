// ADAPTIVE_PAYOFF_V1: FP 7404213 only. This module owns every discretionary
// position-management action. The broker structural stop remains authoritative.
#define AP_STATE_ENTRY_PROBATION 0
#define AP_STATE_HEALTHY_POSITION 1
#define AP_STATE_PRE_BANK_PROFIT 2
#define AP_STATE_STRUCTURAL_RUNNER 3
#define AP_EXIT_ENTRY_PROBATION_FAILED 1
#define AP_EXIT_THESIS_INVALIDATION 2
#define AP_EXIT_PRE_BANK_DETERIORATION 3
#define AP_EXIT_RUNNER_STRUCTURAL 4
#define AP_EXIT_ACCOUNT_RISK 5

string APKey(const long id,const string field)
  { return "SFM2_APV1_"+IntegerToString(AccountInfoInteger(ACCOUNT_LOGIN))+"_"+IntegerToString(id)+"_"+field; }

string APStateName(const int state)
  {
   if(state==AP_STATE_ENTRY_PROBATION) return "ENTRY_PROBATION";
   if(state==AP_STATE_HEALTHY_POSITION) return "HEALTHY_POSITION";
   if(state==AP_STATE_PRE_BANK_PROFIT) return "PRE_BANK_PROFIT";
   if(state==AP_STATE_STRUCTURAL_RUNNER) return "STRUCTURAL_RUNNER";
   return "UNKNOWN";
  }

bool APSet(const long id,const string field,const double value)
  { return GlobalVariableSet(APKey(id,field),value)!=0; }

double APGet(const long id,const string field,const double fallback=0)
  { return GlobalVariableCheck(APKey(id,field))?GlobalVariableGet(APKey(id,field)):fallback; }

bool APStateKnown(const long id)
  { return GlobalVariableCheck(APKey(id,"STATE")) && GlobalVariableCheck(APKey(id,"ORIGINAL_VOLUME")); }

bool APInitializePosition(const long id,const double original_volume,const double entry,
                          const double stop,const double initial_risk)
  {
   if(id<=0 || original_volume<=0 || entry<=0 || stop<=0 || initial_risk<=0) return false;
   bool ok=APSet(id,"STATE",AP_STATE_ENTRY_PROBATION) &&
           APSet(id,"ORIGINAL_VOLUME",original_volume) && APSet(id,"ENTRY",entry) &&
           APSet(id,"ORIGINAL_STOP",stop) && APSet(id,"INITIAL_RISK",initial_risk) &&
           APSet(id,"HALF_RISK_TOUCHED",0) && APSet(id,"PROBATION_FAILED",0) &&
           APSet(id,"REACHED_1R",0) && APSet(id,"REACHED_2R",0) &&
           APSet(id,"BANKED",0) && APSet(id,"EXIT_REASON",0);
   GlobalVariablesFlush();
   return ok;
  }

void APTransition(const long id,const int next,MarketScore &score,const ulong ticket,
                  const string evidence)
  {
   int prior=(int)APGet(id,"STATE",AP_STATE_ENTRY_PROBATION);
   if(prior==next) return;
   APSet(id,"STATE",next); GlobalVariablesFlush();
   AppendEvidence("PAYOFF_STATE_TRANSITION",score,ticket,StringFormat(
      "position_id=%I64d;from=%s;to=%s;%s",id,APStateName(prior),APStateName(next),evidence));
  }

void APMarkExit(const long id,const int reason)
  { APSet(id,"EXIT_REASON",reason); GlobalVariablesFlush(); }

string APExitName(const int reason)
  {
   if(reason==AP_EXIT_ENTRY_PROBATION_FAILED) return "ENTRY_PROBATION_FAILED";
   if(reason==AP_EXIT_THESIS_INVALIDATION) return "THESIS_INVALIDATION";
   if(reason==AP_EXIT_PRE_BANK_DETERIORATION) return "PRE_BANK_PROFIT_DERIORATION_EXIT";
   if(reason==AP_EXIT_RUNNER_STRUCTURAL) return "RUNNER_STRUCTURAL_EXIT";
   if(reason==AP_EXIT_ACCOUNT_RISK) return "ACCOUNT_RISK_EXIT";
   return "";
  }

bool APReadBankedCash(const long id,const string symbol,double &banked_volume,double &banked_net)
  {
   banked_volume=0; banked_net=0;
   if(!HistorySelectByPosition((ulong)id)) return false;
   double original_volume=0,opening_cost=0;
   for(int i=0;i<HistoryDealsTotal();i++)
     {
      ulong d=HistoryDealGetTicket(i); if(d==0 || HistoryDealGetString(d,DEAL_SYMBOL)!=symbol ||
         HistoryDealGetInteger(d,DEAL_MAGIC)!=FastMagic) return false;
      ENUM_DEAL_ENTRY e=(ENUM_DEAL_ENTRY)HistoryDealGetInteger(d,DEAL_ENTRY);
      if(e==DEAL_ENTRY_IN)
        { original_volume+=HistoryDealGetDouble(d,DEAL_VOLUME); opening_cost+=HistoryDealGetDouble(d,DEAL_COMMISSION)+HistoryDealGetDouble(d,DEAL_FEE); }
     }
   double step=SymbolInfoDouble(symbol,SYMBOL_VOLUME_STEP),minimum=SymbolInfoDouble(symbol,SYMBOL_VOLUME_MIN);
   double target=FPBankTarget(original_volume,step,minimum);
   if(target<=0) return true;
   for(int i=0;i<HistoryDealsTotal() && banked_volume<target-step*1e-7;i++)
     {
      ulong d=HistoryDealGetTicket(i); ENUM_DEAL_ENTRY e=(ENUM_DEAL_ENTRY)HistoryDealGetInteger(d,DEAL_ENTRY);
      if(e!=DEAL_ENTRY_OUT && e!=DEAL_ENTRY_OUT_BY) continue;
      double deal_volume=HistoryDealGetDouble(d,DEAL_VOLUME);
      double used=MathMin(deal_volume,target-banked_volume),fraction=deal_volume>0?used/deal_volume:0;
      banked_volume+=used;
      banked_net+=fraction*(HistoryDealGetDouble(d,DEAL_PROFIT)+HistoryDealGetDouble(d,DEAL_SWAP)+
                            HistoryDealGetDouble(d,DEAL_COMMISSION)+HistoryDealGetDouble(d,DEAL_FEE));
     }
   if(original_volume>0) banked_net+=opening_cost*banked_volume/original_volume;
   return true;
  }

bool APCloseOwned(const ulong ticket,const long id,const int exit_reason,const string operation,
                  MarketScore &score,const string evidence)
  {
   APMarkExit(id,exit_reason);
   AppendEvidence(APExitName(exit_reason),score,ticket,evidence+";broker_structural_sl_retained_until_fill=true");
   string ownership_reason;
   if(!VerifyOrderOwnership(operation,ownership_reason))
     { g_status_reason="OWNERSHIP_BLOCKED_"+APExitName(exit_reason)+"_"+score.symbol; return false; }
   g_trade.SetExpertMagicNumber(FastMagic);
   if(!g_trade.PositionClose(ticket))
     {
      APMarkExit(id,0);
      AppendEvidence(APExitName(exit_reason)+"_FAILED",score,ticket,
         "retcode="+IntegerToString((int)g_trade.ResultRetcode())+";broker_sl_remains_active=true");
      g_status_reason=APExitName(exit_reason)+"_FAILED_"+score.symbol;
      return false;
     }
   g_status_reason=APExitName(exit_reason)+"_"+score.symbol;
   return true;
  }

void APStartProbationShadow(const long id,const int symbol_index,const int direction,
                            const double entry,const double exit_price,const double initial)
  {
   APSet(id,"SHADOW_END",(double)((long)TimeTradeServer()+3600));
   APSet(id,"SHADOW_INDEX",symbol_index); APSet(id,"SHADOW_DIR",direction);
   APSet(id,"SHADOW_ENTRY",entry); APSet(id,"SHADOW_EXIT",exit_price);
   APSet(id,"SHADOW_DISTANCE",initial); APSet(id,"SHADOW_MFE",0);
   APSet(id,"SHADOW_MAE",0); APSet(id,"SHADOW_RECOVERED_ENTRY",0);
   APSet(id,"SHADOW_REACHED_1R",0); GlobalVariablesFlush();
  }

void APUpdateProbationShadows()
  {
   string prefix="SFM2_APV1_"+IntegerToString(AccountInfoInteger(ACCOUNT_LOGIN))+"_";
   long now=(long)TimeTradeServer();
   for(int i=GlobalVariablesTotal()-1;i>=0;i--)
     {
      string key=GlobalVariableName(i);
      if(StringFind(key,prefix)!=0 || StringFind(key,"_SHADOW_END")<0) continue;
      int suffix=StringFind(key,"_SHADOW_END");
      long id=(long)StringToInteger(StringSubstr(key,StringLen(prefix),suffix-StringLen(prefix)));
      long finish=(long)APGet(id,"SHADOW_END",0); int index=(int)APGet(id,"SHADOW_INDEX",-1);
      if(finish<=0 || index<0 || index>=SYMBOL_COUNT || g_symbols[index]=="") continue;
      int direction=(int)APGet(id,"SHADOW_DIR",0); double entry=APGet(id,"SHADOW_ENTRY",0);
      double initial=APGet(id,"SHADOW_DISTANCE",0); MqlTick tick;
      if(direction==0 || initial<=0 || !SymbolInfoTick(g_symbols[index],tick)) continue;
      double price=direction>0?tick.bid:tick.ask; double r=direction*(price-entry)/initial;
      APSet(id,"SHADOW_MFE",MathMax(APGet(id,"SHADOW_MFE",r),r));
      APSet(id,"SHADOW_MAE",MathMin(APGet(id,"SHADOW_MAE",r),r));
      if(r>=0) APSet(id,"SHADOW_RECOVERED_ENTRY",1); if(r>=1) APSet(id,"SHADOW_REACHED_1R",1);
      if(now>=finish)
        {
         MarketScore score; if(!FindScore(g_symbols[index],score)) { ZeroMemory(score); score.symbol=g_symbols[index]; }
         score.direction=direction;
         AppendEvidence("ENTRY_PROBATION_SHADOW_COMPLETE",score,0,StringFormat(
            "position_id=%I64d;diagnostic_only=true;window_seconds=3600;mfe_r=%.5f;mae_r=%.5f;recovered_entry=%s;reached_1r=%s;altered_closed_trade=false",
            id,APGet(id,"SHADOW_MFE",0),APGet(id,"SHADOW_MAE",0),
            BoolText(APGet(id,"SHADOW_RECOVERED_ENTRY",0)>0),BoolText(APGet(id,"SHADOW_REACHED_1R",0)>0)));
         GlobalVariableDel(APKey(id,"SHADOW_END"));
        }
     }
   GlobalVariablesFlush();
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
      if(!APStateKnown(identifier)) { g_status_reason="ADAPTIVE_PAYOFF_STATE_UNKNOWN_"+symbol; continue; }
      int state=(int)APGet(identifier,"STATE",AP_STATE_ENTRY_PROBATION);
      double net_floating=PositionGetDouble(POSITION_PROFIT)+PositionGetDouble(POSITION_SWAP);
      FPBankLedger ledger; bool ledger_known=FPReadBankLedger(identifier,symbol,ledger);
      if(ledger_known) net_floating+=ledger.closed_gross;
      if(!GlobalVariableCheck(MfeKey(identifier)) || net_floating>GlobalVariableGet(MfeKey(identifier))) GlobalVariableSet(MfeKey(identifier),net_floating);
      if(!GlobalVariableCheck(MaeKey(identifier)) || net_floating<GlobalVariableGet(MaeKey(identifier))) GlobalVariableSet(MaeKey(identifier),net_floating);
      RunnerState runner; if(!LoadRunnerState(identifier,symbol,runner)) continue;
      bool runner_changed=false;
      if(current_r>runner.peak_r) { runner.peak_r=current_r; runner_changed=true; }
      if(net_floating>runner.peak_dollars) { runner.peak_dollars=net_floating; runner_changed=true; }
      double giveback_r=MathMax(0.0,runner.peak_r-current_r),giveback_dollars=MathMax(0.0,runner.peak_dollars-net_floating);
      if(giveback_r>runner.max_giveback_r) { runner.max_giveback_r=giveback_r; runner_changed=true; }
      if(giveback_dollars>runner.max_giveback_dollars) { runner.max_giveback_dollars=giveback_dollars; runner_changed=true; }
      double broker_protected_r=direction*(sl-entry)/initial;
      if(broker_protected_r>runner.protected_r)
        { runner.protected_r=broker_protected_r; runner.protected_dollars=NetProfitAtPrice(symbol,direction,PositionGetDouble(POSITION_VOLUME),entry,sl); runner_changed=true; }
      if(runner_changed) SaveRunnerState(identifier,symbol,runner);

      MarketScore score; ZeroMemory(score); bool scored=FindScore(symbol,score);
      if(!scored) score.atr=MathMax(initial/5.0,SymbolInfoDouble(symbol,SYMBOL_POINT));
      double held_score=scored?(direction>0?score.buy_score:score.sell_score):50.0;
      double opposite_score=scored?(direction>0?score.sell_score:score.buy_score):0.0;
      bool would_open_now=scored && score.fresh && score.eligible && score.direction==direction;
      bool structure_broken=scored && score.fresh && score.direction==-direction && score.structural_reversal;
      bool m15_support=scored && direction*score.trend_m15>0.16;
      bool opposite_structure=scored && (direction>0?score.bearish_structure:score.bullish_structure);
      bool normal_pullback=scored && score.fresh && !structure_broken && m15_support &&
                           (score.direction!=direction || score.no_trade_score>=held_score);
      bool structural_deterioration=scored && score.fresh && !structure_broken && !normal_pullback &&
         ((score.direction==-direction && direction*score.trend_m5<-0.20 && direction*score.trend_m15<=0.05 && opposite_score>=held_score+MinDirectionalDominance) ||
          (opposite_structure && direction*score.trend_m15<=0.05 && opposite_score>held_score));
      bool exit_state_advanced=false;
      int soft_bad_bars=scored && score.fresh?UpdateSoftExitPersistence(identifier,score.completed_m5_bar_time,structural_deterioration,exit_state_advanced):0;
      score.direction=direction; score.entry=entry; score.stop=sl;

      if(current_r<=-0.50 && APGet(identifier,"HALF_RISK_TOUCHED",0)==0)
        { APSet(identifier,"HALF_RISK_TOUCHED",1); AppendEvidence("HALF_RISK_DAMAGE_AREA_REACHED",score,ticket,StringFormat("current_r=%.5f;automatic_exit=false;state=%s",current_r,APStateName(state))); }
      if(runner.peak_r>=1.0) APSet(identifier,"REACHED_1R",1);
      if(current_r>=2.0 || runner.peak_r>=2.0) APSet(identifier,"REACHED_2R",1);

      if(structure_broken)
        {
         GlobalVariableSet("SFM2_INV_"+IntegerToString(identifier),1.0);
         APCloseOwned(ticket,identifier,AP_EXIT_THESIS_INVALIDATION,"POSITION_CLOSE_THESIS_INVALIDATION",score,StringFormat(
            "state=%s;current_r=%.5f;hard_structural=true;held=%.2f;opposite=%.2f",APStateName(state),current_r,held_score,opposite_score));
         continue;
        }
      if(state==AP_STATE_ENTRY_PROBATION && current_r<=-0.50 && runner.peak_r<0.15 && soft_bad_bars>=2)
        {
         APSet(identifier,"PROBATION_FAILED",1);
         APCloseOwned(ticket,identifier,AP_EXIT_ENTRY_PROBATION_FAILED,"POSITION_CLOSE_ENTRY_PROBATION_FAILED",score,StringFormat(
            "classification=ENTRY_PROBATION_FAILED;current_r=%.5f;peak_r=%.5f;causal=failed_resumption_and_structural_deterioration;soft_bad_completed_m5_bars=%d;m15_support=%s;held=%.2f;opposite=%.2f;no_trade=%.2f",
            current_r,runner.peak_r,soft_bad_bars,BoolText(m15_support),held_score,opposite_score,score.no_trade_score));
         continue;
        }
      if(soft_bad_bars>=2)
        {
         int reason=(state==AP_STATE_PRE_BANK_PROFIT && runner.peak_r>=0.50 && current_r>0)?AP_EXIT_PRE_BANK_DETERIORATION:
                    (state==AP_STATE_STRUCTURAL_RUNNER?AP_EXIT_RUNNER_STRUCTURAL:AP_EXIT_THESIS_INVALIDATION);
         APCloseOwned(ticket,identifier,reason,reason==AP_EXIT_PRE_BANK_DETERIORATION?"POSITION_CLOSE_PRE_BANK_DETERIORATION":
                      reason==AP_EXIT_RUNNER_STRUCTURAL?"POSITION_CLOSE_RUNNER_STRUCTURE":"POSITION_CLOSE_THESIS_INVALIDATION",score,StringFormat(
            "state=%s;current_r=%.5f;peak_r=%.5f;causal=two_consecutive_completed_m5_structural_deterioration;soft_bad_bars=%d;m15_support=%s;held=%.2f;opposite=%.2f;no_trade=%.2f",
            APStateName(state),current_r,runner.peak_r,soft_bad_bars,BoolText(m15_support),held_score,opposite_score,score.no_trade_score));
         continue;
        }

      if(state==AP_STATE_ENTRY_PROBATION && (runner.peak_r>=0.15 || would_open_now))
        { APTransition(identifier,AP_STATE_HEALTHY_POSITION,score,ticket,StringFormat("current_r=%.5f;peak_r=%.5f;thesis_currently_qualified=%s",current_r,runner.peak_r,BoolText(would_open_now))); state=AP_STATE_HEALTHY_POSITION; }
      if(state==AP_STATE_HEALTHY_POSITION && runner.peak_r>=0.50)
        { APTransition(identifier,AP_STATE_PRE_BANK_PROFIT,score,ticket,StringFormat("peak_r=%.5f;monetary_trailing_enabled=false",runner.peak_r)); state=AP_STATE_PRE_BANK_PROFIT; }

      bool banked=FPTryBank(ticket,identifier,symbol,current_r,score);
      if(!PositionSelectByTicket(ticket)) continue;
      if(banked && state!=AP_STATE_STRUCTURAL_RUNNER)
        {
         APSet(identifier,"BANKED",1); APTransition(identifier,AP_STATE_STRUCTURAL_RUNNER,score,ticket,
            "event=PARTIAL_BANK_2R;banking_confirmed_in_broker_history=true;remaining_half_is_structural_runner=true");
         runner.active=true; runner.phase=TRADE_PHASE_RUNNER; SaveRunnerState(identifier,symbol,runner);
         state=AP_STATE_STRUCTURAL_RUNNER;
        }

      // Only a banked runner may advance its broker stop. The proposed stop is
      // based on completed favorable structure and is applied monotonically.
      if(state==AP_STATE_STRUCTURAL_RUNNER)
        {
         MqlRates m5[],m15[]; ArraySetAsSeries(m5,true); ArraySetAsSeries(m15,true);
         if(CopyRates(symbol,PERIOD_M5,0,18,m5)>=16 && CopyRates(symbol,PERIOD_M15,0,12,m15)>=10)
           {
            double a5=AverageRange(m5,1,14),a15=AverageRange(m15,1,8);
            double anchor=direction>0?MathMin(LowestLow(m5,1,8),LowestLow(m15,1,6)):MathMax(HighestHigh(m5,1,8),HighestHigh(m15,1,6));
            double breathing=MathMax(MathMax(0.25*a5,0.12*a15),2.5*(tick.ask-tick.bid));
            double desired=NormalizePrice(symbol,anchor-direction*breathing);
            double point=SymbolInfoDouble(symbol,SYMBOL_POINT);
            double min_distance=MathMax((double)SymbolInfoInteger(symbol,SYMBOL_TRADE_STOPS_LEVEL),(double)SymbolInfoInteger(symbol,SYMBOL_TRADE_FREEZE_LEVEL))*point;
            bool tighter=direction>0?desired>sl:desired<sl;
            bool profitable=direction*(desired-entry)>0 && NetProfitAtPrice(symbol,direction,PositionGetDouble(POSITION_VOLUME),entry,desired)>0;
            bool correct_side=direction>0?desired<tick.bid-min_distance:desired>tick.ask+min_distance;
            if(tighter && profitable && correct_side)
              {
               string ownership_reason;
               if(VerifyOrderOwnership("POSITION_MODIFY_STRUCTURAL_RUNNER",ownership_reason))
                 {
                  g_trade.SetExpertMagicNumber(FastMagic);
                  if(g_trade.PositionModify(ticket,desired,0))
                    { runner.trail_updates++; runner.protected_r=MathMax(runner.protected_r,direction*(desired-entry)/initial); runner.protected_dollars=NetProfitAtPrice(symbol,direction,PositionGetDouble(POSITION_VOLUME),entry,desired); SaveRunnerState(identifier,symbol,runner); AppendEvidence("RUNNER_STRUCTURE_ADVANCED",score,ticket,StringFormat("old_stop=%.8f;new_stop=%.8f;monotonic=true;original_stop_never_widened=true",sl,desired)); }
                 }
              }
           }
        }
      if(exit_state_advanced)
        AppendEvidence(normal_pullback?"NORMAL_NOISE":"ENTRY_PROBATION_HEALTHY",score,ticket,StringFormat(
           "state=%s;current_r=%.5f;peak_r=%.5f;soft_bad_bars=%d;exit=false;broker_structural_sl_retained=true",APStateName(state),current_r,runner.peak_r,soft_bad_bars));
     }
  }
