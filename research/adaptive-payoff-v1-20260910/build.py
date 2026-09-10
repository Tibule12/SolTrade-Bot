#!/usr/bin/env python3
import hashlib,json,re,sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT/'tools'))
from build_v202_validation import function_span
HERE=Path(__file__).resolve().parent
BASE=ROOT/'research/fp-banking-20260909/SolTradeFastMultiMarketV2.mq5'
BASE_SHA='30ac5d246db33aed873cb60a07d628d00c9f3411acdd169241a849dd2b85591c'
OUT=HERE/'SolTradeFastMultiMarketV2.mq5'
def sha(b): return hashlib.sha256(b).hexdigest()
def replace_function(s,name,new):
 a,b=function_span(s,name);return s[:a]+new.rstrip()+"\n\n"+s[b:]
def build():
 assert sha(BASE.read_bytes())==BASE_SHA
 original=BASE.read_text();s=original
 module=(HERE/'adaptive_payoff.mqh').read_text()
 a,b=function_span(s,'ManageFastPositions');s=s[:a]+module+'\n\n'+s[b:]
 # Remove only the research initialization lock.
 lock='   Print("FP_BANKING_RESEARCH_ONLY_NOT_DEPLOYABLE");\n   return INIT_FAILED;\n\n'
 assert s.count(lock)==1;s=s.replace(lock,'')
 s=s.replace('complete?"PROFIT_BANKED":"BANK_REQUEST_UNCONFIRMED"','complete?"PARTIAL_BANK_2R":"BANK_REQUEST_UNCONFIRMED"')
 # Fail closed when any existing exposure cannot be valued.
 old='''double PositionRiskAmount(const ulong ticket)
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
  }'''
 new='''bool g_portfolio_risk_known=true;

double PositionRiskAmount(const ulong ticket)
  {
   if(!PositionSelectByTicket(ticket)) { g_portfolio_risk_known=false; return 0; }
   double sl=PositionGetDouble(POSITION_SL),volume=PositionGetDouble(POSITION_VOLUME);
   if(sl<=0 || volume<=0) { g_portfolio_risk_known=false; return 0; }
   string symbol=PositionGetString(POSITION_SYMBOL); long type=PositionGetInteger(POSITION_TYPE);
   MqlTick tick; if(!SymbolInfoTick(symbol,tick)) { g_portfolio_risk_known=false; return 0; }
   double from=type==POSITION_TYPE_BUY?tick.bid:tick.ask;
   if((type==POSITION_TYPE_BUY && sl>=from) || (type==POSITION_TYPE_SELL && sl<=from)) return 0;
   double pnl=0; ENUM_ORDER_TYPE order_type=type==POSITION_TYPE_BUY?ORDER_TYPE_BUY:ORDER_TYPE_SELL;
   if(!OrderCalcProfit(order_type,symbol,volume,from,sl,pnl) || !MathIsValidNumber(pnl))
     { g_portfolio_risk_known=false; return 0; }
   return MathMax(0.0,-pnl);
  }'''
 assert s.count(old)==1;s=s.replace(old,new)
 s=s.replace('''double PortfolioRiskAmount()
  {
   double total=0;''','''double PortfolioRiskAmount()
  {
   g_portfolio_risk_known=true;
   double total=0;''')
 needle='''   double current_risk=PortfolioRiskAmount();
   double candidate_budget='''
 assert s.count(needle)==1;s=s.replace(needle,'''   double current_risk=PortfolioRiskAmount();
   if(!g_portfolio_risk_known) { reason="PORTFOLIO_RISK_UNKNOWN_DENY_NEW_RISK"; return false; }
   double candidate_budget=''')
 # Every new position must acquire durable AP state or is immediately flattened.
 needle='''   GlobalVariableSet(MfeKey(identifier),0.0); GlobalVariableSet(MaeKey(identifier),0.0);
   int index='''
 assert s.count(needle)==1;s=s.replace(needle,'''   GlobalVariableSet(MfeKey(identifier),0.0); GlobalVariableSet(MaeKey(identifier),0.0);
   if(!APInitializePosition(identifier,PositionGetDouble(POSITION_VOLUME),actual_fill,
                            PositionGetDouble(POSITION_SL),actual_risk))
     {
      if(VerifyOrderOwnership("POSITION_CLOSE_ADAPTIVE_STATE_FAILED",ownership_reason))
        { g_trade.PositionClose((ulong)PositionGetInteger(POSITION_TICKET)); reason="ADAPTIVE_PAYOFF_STATE_NOT_DURABLE_FLATTENED"; }
      else reason="ADAPTIVE_PAYOFF_STATE_NOT_DURABLE_OWNERSHIP_BLOCKED_BROKER_SL_REMAINS_ACTIVE";
      return false;
     }
   int index=''')
 # Restart reconciliation requires the exact lifecycle state.
 needle='''         if(!GlobalVariableCheck(MfeKey(identifier)) || !GlobalVariableCheck(MaeKey(identifier)))
           { reason="MFE_MAE_STATE_UNRECOVERABLE_"+symbol; return false; }'''
 assert s.count(needle)==1;s=s.replace(needle,needle+'''\n         if(!APStateKnown(identifier)) { reason="ADAPTIVE_PAYOFF_STATE_UNRECOVERABLE_"+symbol; return false; }''')
 # Run diagnostic-only post-exit observations from the normal scan.
 needle='''   if(owned_position_history_ready) ManageFastPositions();
   else AppendLifecycle("POSITION_MANAGEMENT_HISTORY_WARMUP_BLOCKED",
                        "broker_stops_remain_active;no_modification_or_exit_from_unstable_history=true");'''
 assert s.count(needle)==1;s=s.replace(needle,needle+'\n   APUpdateProbationShadows();')
 # Runtime advertises exact manager and exposure certainty.
 s=s.replace('''"equity","portfolio_risk_amount","portfolio_risk_percent","status",''','''"equity","portfolio_risk_amount","portfolio_risk_percent","portfolio_risk_known","manager_version","status",''')
 s=s.replace('''DoubleToString(risk,2),DoubleToString(equity>0?100.0*risk/equity:0,4),g_status_reason,''','''DoubleToString(risk,2),DoubleToString(equity>0?100.0*risk/equity:0,4),BoolText(g_portfolio_risk_known),"ADAPTIVE_PAYOFF_V1",g_status_reason,''')
 s=s.replace('''AppendLifecycle("EA_INITIALIZATION_STARTED","version=2.202;''','''AppendLifecycle("EA_INITIALIZATION_STARTED","version=2.202;manager=ADAPTIVE_PAYOFF_V1;''')
 # Final transaction reason and complete payoff evidence.
 old='''      bool invalidated=GlobalVariableCheck("SFM2_INV_"+IntegerToString(position_id)) &&
                       GlobalVariableGet("SFM2_INV_"+IntegerToString(position_id))>0;'''
 assert s.count(old)==1;s=s.replace(old,old+'''\n      int adaptive_exit=(int)APGet(position_id,"EXIT_REASON",0);''')
 old='''         string exit_class=delayed_early_failure?"DELAYED_EARLY_FAILURE_EXIT":
            immediate_scratch?"IMMEDIATE_DIRECTIONAL_SCRATCH_EXIT":invalidated?"THESIS_INVALIDATION":
            deal_reason==DEAL_REASON_SL?(runner.protected_r>-0.50?"PROTECTED_STOP_EXIT":"INITIAL_STRUCTURAL_STOP_EXIT"):
            "BROKER_OR_EXTERNAL_EXIT";'''
 new='''         double banked_volume=0,banked_cash=0; bool bank_known=APReadBankedCash(position_id,symbol,banked_volume,banked_cash);
         double initial_risk=APGet(position_id,"INITIAL_RISK",0);
         if(!bank_known) banked_cash=0;
         double banked_r=initial_risk>0?banked_cash/initial_risk:0;
         string explicit_exit=APExitName(adaptive_exit);
         string exit_class=explicit_exit!=""?explicit_exit:
            invalidated?"THESIS_INVALIDATION":
            deal_reason==DEAL_REASON_SL?(APGet(position_id,"BANKED",0)>0?"RUNNER_STRUCTURAL_EXIT":"INITIAL_STRUCTURAL_STOP_EXIT"):
            "BROKER_OR_EXTERNAL_EXIT";'''
 assert s.count(old)==1;s=s.replace(old,new)
 s=s.replace('''         AppendEvidence("EXIT",score,0,StringFormat(
            "position_id=%I64d;entry_time=''','''         AppendEvidence("EXIT",score,0,StringFormat(
            "manager=ADAPTIVE_PAYOFF_V1;state=%s;original_stop=%.8f;original_price_risk=%.8f;initial_dollar_risk=%.2f;original_volume=%.8f;remaining_volume=0;half_risk_touched=%s;probation_failed=%s;reached_1r=%s;reached_2r=%s;partial_banking=%s;banked_cash=%.2f;banked_r=%.5f;runner_cash=%.2f;runner_r=%.5f;final_total_cash=%.2f;final_total_r=%.5f;position_id=%I64d;entry_time=''')
 old_args='''            position_id,TimeToString(entry_time,TIME_DATE|TIME_SECONDS),entry_price,'''
 new_args='''            APStateName((int)APGet(position_id,"STATE",AP_STATE_ENTRY_PROBATION)),APGet(position_id,"ORIGINAL_STOP",0),
            MathAbs(APGet(position_id,"ENTRY",entry_price)-APGet(position_id,"ORIGINAL_STOP",0)),initial_risk,
            APGet(position_id,"ORIGINAL_VOLUME",0),BoolText(APGet(position_id,"HALF_RISK_TOUCHED",0)>0),
            BoolText(APGet(position_id,"PROBATION_FAILED",0)>0),BoolText(APGet(position_id,"REACHED_1R",0)>0),
            BoolText(APGet(position_id,"REACHED_2R",0)>0),BoolText(APGet(position_id,"BANKED",0)>0),banked_cash,banked_r,
            net-banked_cash,initial_risk>0?(net-banked_cash)/initial_risk:0,net,initial_risk>0?net/initial_risk:0,
            position_id,TimeToString(entry_time,TIME_DATE|TIME_SECONDS),entry_price,'''
 assert s.count(old_args)==1;s=s.replace(old_args,new_args)
 # Queue false-exit diagnostic only after the deal and final cash are known.
 needle='''         if(immediate_scratch) GlobalVariableDel(scratch_marker);'''
 assert s.count(needle)==1;s=s.replace(needle,'''         if(exit_class=="ENTRY_PROBATION_FAILED" && initial_risk>0)
            APStartProbationShadow(position_id,index,prior_direction,entry_price,exit_price,
                                   MathAbs(entry_price-APGet(position_id,"ORIGINAL_STOP",0)));
'''+needle)
 OUT.write_text(s)
 changed={'ManageFastPositions','PositionRiskAmount','PortfolioRiskAmount','CandidatePortfolioSafe','ReconcileBrokerState','OpenCandidate','WriteRuntimeStatus','ScanAndAct','OnInit','OnTradeTransaction'}
 preserved={}
 for name in re.findall(r'^(?:void|bool|int|long|ulong|double|string|datetime)\s+(\w+)\s*\(',original,re.M):
  if name in changed or name in ('FPTryBank',): continue
  try:
   a,b=function_span(original,name);c,d=function_span(s,name)
  except Exception: continue
  if original[a:b]!=s[c:d]: raise AssertionError(name)
  preserved[name]=sha(s[c:d].encode())
 manifest={'schema':'FP_ADAPTIVE_PAYOFF_V1_RELEASE','base_sha256':BASE_SHA,'source_sha256':sha(OUT.read_bytes()),
  'manager':'ADAPTIVE_PAYOFF_V1','account':7404213,'server':'FPMarketsSC-Demo','risk_percent':1.0,
  'aggregate_risk_percent':1.5,'bank_at_r':2.0,'bank_original_fraction':0.5,'fxify_forbidden':[7196820,7198096],
  'entry_policy_changed':False,'deployment_allowed_after_technical_tests':True,'preserved_functions':preserved}
 (HERE/'manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
 print(json.dumps({k:v for k,v in manifest.items() if k!='preserved_functions'},indent=2))
if __name__=='__main__': build()
