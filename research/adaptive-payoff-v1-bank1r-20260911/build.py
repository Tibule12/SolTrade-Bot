#!/usr/bin/env python3
"""Build the FP-only ADAPTIVE_PAYOFF_V1 Bank-at-1R release."""
import hashlib
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools"))
from build_v202_validation import function_span

HERE = Path(__file__).resolve().parent
BASE = ROOT / "ops/forexvps/releases/fp-adaptive-payoff-v1-20260910/SolTradeFastMultiMarketV2.mq5"
BASE_SHA = "8e5fcce13b770aa84c0487f3e178710e535a2c05088161be59bbbffc4411e1b2"
OUT = HERE / "SolTradeFastMultiMarketV2.mq5"


def sha(data):
    return hashlib.sha256(data).hexdigest()


def replace_function(source, name, replacement):
    start, end = function_span(source, name)
    return source[:start] + replacement.rstrip() + "\n\n" + source[end:]


def build():
    assert sha(BASE.read_bytes()) == BASE_SHA
    original = BASE.read_text()
    source = original

    source = source.replace(
        "double original_volume,closed_volume,closed_gross,closed_net;",
        "double original_volume,closed_volume,closed_gross,closed_net,opening_cost;",
        1,
    )

    source = replace_function(source, "FPReadBankLedger", r'''bool FPReadBankLedger(const long id,const string symbol,FPBankLedger &b)
  {
   ZeroMemory(b);
   if(!HistorySelectByPosition((ulong)id)) return false;
   for(int i=0;i<HistoryDealsTotal();i++)
     {
      ulong d=HistoryDealGetTicket(i); if(d==0) return false;
      if(HistoryDealGetString(d,DEAL_SYMBOL)!=symbol || HistoryDealGetInteger(d,DEAL_MAGIC)!=FastMagic) return false;
      long e=HistoryDealGetInteger(d,DEAL_ENTRY);
      double v=HistoryDealGetDouble(d,DEAL_VOLUME);
      double cost=HistoryDealGetDouble(d,DEAL_COMMISSION)+HistoryDealGetDouble(d,DEAL_FEE);
      if(e==DEAL_ENTRY_IN) { b.original_volume+=v; b.opening_cost+=cost; }
      else if(e==DEAL_ENTRY_OUT || e==DEAL_ENTRY_OUT_BY)
        {
         b.closed_volume+=v;
         double gross=HistoryDealGetDouble(d,DEAL_PROFIT)+HistoryDealGetDouble(d,DEAL_SWAP);
         b.closed_gross+=gross; b.closed_net+=gross+cost;
        }
      else return false; // No inference across a netting reversal.
     }
   if(b.original_volume<=0 || b.closed_volume>b.original_volume+1e-8) return false;
   b.closed_net+=b.opening_cost*b.closed_volume/b.original_volume;
   return true;
  }''')

    source = replace_function(source, "FPTryBank", r'''bool FPTryBank(const ulong ticket,const long id,const string symbol,const double bank_trigger_r,
               const double bank_trigger_cash,const double initial_risk,MarketScore &score)
  {
   FPBankLedger b; if(!FPReadBankLedger(id,symbol,b)) return false;
   double step=SymbolInfoDouble(symbol,SYMBOL_VOLUME_STEP),minimum=SymbolInfoDouble(symbol,SYMBOL_VOLUME_MIN);
   double target=FPBankTarget(b.original_volume,step,minimum);
   if(FPBankComplete(b,target,step))
     {
      if(!PositionSelectByTicket(ticket)) return false;
      double remaining=PositionGetDouble(POSITION_VOLUME);
      bool already_persisted=APGet(id,"BANKED",0)>0;
      bool persisted=APSet(id,"BANKED",1) && APSet(id,"BANKED_VOLUME",b.closed_volume) &&
                     APSet(id,"REMAINING_VOLUME",remaining) && APSet(id,"BANKED_CASH",b.closed_net) &&
                     APSet(id,"BANKED_R",initial_risk>0?b.closed_net/initial_risk:0);
      GlobalVariablesFlush();
      if(persisted && !already_persisted)
         AppendEvidence("PARTIAL_BANK_1R",score,ticket,StringFormat(
            "position_id=%I64d;recovered_from_broker_history=true;closed_volume=%.8f;remaining_volume=%.8f;banked_net=%.2f;banked_r=%.5f;broker_deals_authoritative=true",
            id,b.closed_volume,remaining,b.closed_net,initial_risk>0?b.closed_net/initial_risk:0));
      return persisted;
     }
   // Ambiguous requests remain latched, including across restart. Never retry
   // an unknown broker disposition merely because the marked trade is still +1R.
   string intent=FPBankIntentKey(id);
   if(GlobalVariableCheck(intent)) return false;
   if(bank_trigger_r<1.0 || initial_risk<=0 || target<=0 || b.closed_volume>target || !PositionSelectByTicket(ticket)) return false;
   double volume=PositionGetDouble(POSITION_VOLUME);
   double close_volume=NormalizeDouble(target-b.closed_volume,8);
   if(close_volume<minimum-step*1e-7 || volume-close_volume<minimum-step*1e-7) return false;
   if(AccountInfoInteger(ACCOUNT_LOGIN)!=7404213 || AccountInfoInteger(ACCOUNT_TRADE_MODE)!=ACCOUNT_TRADE_MODE_DEMO ||
      AccountInfoInteger(ACCOUNT_MARGIN_MODE)!=ACCOUNT_MARGIN_MODE_RETAIL_HEDGING) return false;
   string reason; if(!VerifyOrderOwnership("POSITION_PARTIAL_BANK_1R",reason)) return false;
   // Persist intent before sending. A successful API call alone is not cash.
   if(GlobalVariableSet(intent,target)==0) return false;
   GlobalVariablesFlush();
   g_trade.SetExpertMagicNumber(FastMagic);
   bool sent=g_trade.PositionClosePartial(ticket,close_volume,(ulong)MaxSlippagePoints);
   uint ret=g_trade.ResultRetcode();
   FPBankLedger after;
   bool known=FPReadBankLedger(id,symbol,after);
   bool complete=known && FPBankComplete(after,target,step);
   double remaining=0;
   if(PositionSelectByTicket(ticket)) remaining=PositionGetDouble(POSITION_VOLUME);
   bool persisted=false;
   if(complete)
     {
      persisted=APSet(id,"BANKED",1) && APSet(id,"BANKED_VOLUME",after.closed_volume) &&
                APSet(id,"REMAINING_VOLUME",remaining) && APSet(id,"BANKED_CASH",after.closed_net) &&
                APSet(id,"BANKED_R",after.closed_net/initial_risk);
      GlobalVariablesFlush();
      complete=persisted;
     }
   // Clear only on evidenced completed fill, or an explicit no-fill rejection.
   // An unfilled remainder after DONE_PARTIAL may retry on a later +1R scan.
   if(complete || (known && after.closed_volume>b.closed_volume && ret==TRADE_RETCODE_DONE_PARTIAL) ||
      ret==TRADE_RETCODE_REJECT || ret==TRADE_RETCODE_INVALID_VOLUME || ret==TRADE_RETCODE_MARKET_CLOSED ||
      ret==TRADE_RETCODE_TRADE_DISABLED || ret==TRADE_RETCODE_REQUOTE || ret==TRADE_RETCODE_PRICE_CHANGED ||
      ret==TRADE_RETCODE_PRICE_OFF)
     { GlobalVariableDel(intent); GlobalVariablesFlush(); }
   AppendEvidence(complete?"PARTIAL_BANK_1R":"BANK_REQUEST_UNCONFIRMED",score,ticket,StringFormat(
      "position_id=%I64d;trigger_r=%.5f;trigger_cash=%.2f;initial_risk=%.2f;requested_volume=%.8f;target_total=%.8f;closed_volume=%.8f;remaining_volume=%.8f;banked_net=%.2f;banked_r=%.5f;retcode=%u;api_ok=%s;broker_deals_authoritative=true",
      id,bank_trigger_r,bank_trigger_cash,initial_risk,close_volume,target,known?after.closed_volume:0,remaining,
      known?after.closed_net:0,known?after.closed_net/initial_risk:0,ret,BoolText(sent)));
   return complete;
  }''')

    start, end = function_span(source, "ManageFastPositions")
    manager = source[start:end]
    old = '''      if(runner.peak_r>=1.0) APSet(identifier,"REACHED_1R",1);
      if(current_r>=2.0 || runner.peak_r>=2.0) APSet(identifier,"REACHED_2R",1);'''
    new = '''      double initial_risk_budget=APGet(identifier,"INITIAL_RISK",0);
      double bank_trigger_cash=ledger_known?PositionGetDouble(POSITION_PROFIT)+PositionGetDouble(POSITION_SWAP)+ledger.closed_gross+ledger.opening_cost:0;
      double bank_trigger_r=ledger_known && initial_risk_budget>0?bank_trigger_cash/initial_risk_budget:-1.0e100;
      if(bank_trigger_r>=1.0) APSet(identifier,"REACHED_1R",1);
      if(current_r>=2.0 || runner.peak_r>=2.0) APSet(identifier,"REACHED_2R",1);'''
    assert manager.count(old) == 1
    manager = manager.replace(old, new)

    probation_start = manager.index('      if(state==AP_STATE_ENTRY_PROBATION && current_r<=-0.50')
    transitions_start = manager.index('      if(state==AP_STATE_ENTRY_PROBATION && (runner.peak_r>=0.15', probation_start)
    runner_comment = manager.index('      // Only a banked runner may advance its broker stop.', transitions_start)
    old_block = manager[probation_start:runner_comment]
    prob_soft = manager[probation_start:transitions_start]
    transitions_bank = manager[transitions_start:runner_comment]
    transitions_bank = transitions_bank.replace(
        'bool banked=FPTryBank(ticket,identifier,symbol,current_r,score);',
        'bool banked=FPTryBank(ticket,identifier,symbol,bank_trigger_r,bank_trigger_cash,initial_risk_budget,score);',
    ).replace('event=PARTIAL_BANK_2R;', 'event=PARTIAL_BANK_1R;')
    # Hard structural invalidation remains first. Banking then receives priority
    # over probation/soft deterioration. An ambiguous bank request suppresses a
    # competing discretionary close until broker history resolves its outcome.
    new_block = transitions_bank + '''      if(GlobalVariableCheck(FPBankIntentKey(identifier))) continue;

''' + prob_soft
    manager = manager.replace(old_block, new_block)
    source = source[:start] + manager + source[end:]

    source = source.replace('"ADAPTIVE_PAYOFF_V1",g_status_reason', '"ADAPTIVE_PAYOFF_V1_BANK1R",g_status_reason', 1)
    source = source.replace('version=2.202;manager=ADAPTIVE_PAYOFF_V1;', 'version=2.202;manager=ADAPTIVE_PAYOFF_V1_BANK1R;', 1)
    source = source.replace('manager=ADAPTIVE_PAYOFF_V1;state=%s;', 'manager=ADAPTIVE_PAYOFF_V1_BANK1R;state=%s;', 1)
    source = source.replace('// ADAPTIVE_PAYOFF_V1: FP 7404213 only.', '// ADAPTIVE_PAYOFF_V1_BANK1R: FP 7404213 only.', 1)

    OUT.write_text(source)

    changed = {"FPReadBankLedger", "FPTryBank", "ManageFastPositions", "WriteRuntimeStatus", "OnInit", "OnTradeTransaction"}
    preserved = {}
    for name in re.findall(r'^(?:void|bool|int|long|ulong|double|string|datetime)\s+(\w+)\s*\(', original, re.M):
        if name in changed:
            continue
        try:
            a, b = function_span(original, name)
            c, d = function_span(source, name)
        except Exception:
            continue
        if original[a:b] != source[c:d]:
            raise AssertionError(f"unexpected changed function: {name}")
        preserved[name] = sha(source[c:d].encode())

    assert re.findall(r'^input .*?;', original, re.M) == re.findall(r'^input .*?;', source, re.M)
    manifest = {
        "schema": "FP_ADAPTIVE_PAYOFF_V1_BANK1R_RELEASE",
        "base_sha256": BASE_SHA,
        "source_sha256": sha(OUT.read_bytes()),
        "manager": "ADAPTIVE_PAYOFF_V1_BANK1R",
        "account": 7404213,
        "server": "FPMarketsSC-Demo",
        "risk_percent": 1.0,
        "aggregate_risk_percent": 1.5,
        "bank_at_r": 1.0,
        "bank_original_fraction": 0.5,
        "bank_trigger": "MARKED_NET_CASH_DIVIDED_BY_RECORDED_INITIAL_RISK",
        "fxify_forbidden": [7196820, 7198096],
        "entry_policy_changed": False,
        "probation_changed": False,
        "runner_structure_changed": False,
        "deployment_allowed_after_technical_tests": True,
        "changed_existing_functions": sorted(changed),
        "preserved_functions": preserved,
    }
    (HERE / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
    print(json.dumps({k: v for k, v in manifest.items() if k != "preserved_functions"}, indent=2))


if __name__ == "__main__":
    build()
