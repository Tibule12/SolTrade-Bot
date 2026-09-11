import hashlib
import json
import re
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import build

SOURCE = HERE / "SolTradeFastMultiMarketV2.mq5"


class BankAtOneRTests(unittest.TestCase):
    def setUp(self):
        self.source = SOURCE.read_text()
        self.base = build.BASE.read_text()

    def body(self, text, name):
        a, b = build.function_span(text, name)
        return text[a:b]

    def test_scope_identity_and_frozen_inputs(self):
        manifest = json.loads((HERE / "manifest.json").read_text())
        self.assertEqual(hashlib.sha256(SOURCE.read_bytes()).hexdigest(), manifest["source_sha256"])
        self.assertEqual(re.findall(r"^input .*?;", self.source, re.M), re.findall(r"^input .*?;", self.base, re.M))
        self.assertEqual(manifest["fxify_forbidden"], [7196820, 7198096])
        self.assertIn("#define REQUIRED_DEMO_LOGIN 7404213", self.source)
        self.assertIn("ADAPTIVE_PAYOFF_V1_BANK1R", self.body(self.source, "WriteRuntimeStatus"))

    def test_entries_stops_sizing_risk_and_ownership_unchanged(self):
        for name in (
            "ScoreSymbol", "EntryQuoteStillValid", "CalculateLots", "NearestOpposingSwing",
            "CandidatePortfolioSafe", "OpenCandidate", "VerifyOrderOwnership",
            "InitializeOwnership", "StrongCorrelationCount",
        ):
            self.assertEqual(self.body(self.source, name), self.body(self.base, name), name)
        self.assertIn("RiskPerTradePercent!=1.00", self.body(self.source, "OnInit"))
        self.assertIn("MaxPortfolioRiskPercent!=1.50", self.body(self.source, "OnInit"))
        self.assertIn("PORTFOLIO_RISK_UNKNOWN_DENY_NEW_RISK", self.body(self.source, "CandidatePortfolioSafe"))

    def test_exact_bank_rule_and_recorded_risk_trigger(self):
        bank = self.body(self.source, "FPTryBank")
        manager = self.body(self.source, "ManageFastPositions")
        self.assertIn("if(bank_trigger_r<1.0", bank)
        self.assertNotIn("1000", bank + manager)
        self.assertIn('APGet(identifier,"INITIAL_RISK",0)', manager)
        self.assertIn("bank_trigger_cash/initial_risk_budget", manager)
        self.assertIn('complete?"PARTIAL_BANK_1R"', bank)
        self.assertIn('VerifyOrderOwnership("POSITION_PARTIAL_BANK_1R"', bank)
        self.assertIn("0.50*original", self.body(self.source, "FPBankTarget"))

    def test_bank_persistence_costs_and_remaining_volume(self):
        ledger = self.body(self.source, "FPReadBankLedger")
        bank = self.body(self.source, "FPTryBank")
        for field in ("BANKED", "BANKED_VOLUME", "REMAINING_VOLUME", "BANKED_CASH", "BANKED_R"):
            self.assertIn(f'APSet(id,"{field}"', bank)
        self.assertIn("b.opening_cost+=cost", ledger)
        self.assertIn("b.closed_net+=b.opening_cost*b.closed_volume/b.original_volume", ledger)
        self.assertIn("remaining_volume=", bank)
        self.assertIn("broker_deals_authoritative=true", bank)

    def test_precedence_probation_and_runner_semantics(self):
        manager = self.body(self.source, "ManageFastPositions")
        hard = manager.index("if(structure_broken)")
        bank = manager.index("FPTryBank(")
        probation = manager.index("if(state==AP_STATE_ENTRY_PROBATION && current_r<=-0.50")
        soft = manager.index("if(soft_bad_bars>=2)")
        self.assertLess(hard, bank)
        self.assertLess(bank, probation)
        self.assertLess(bank, soft)
        self.assertIn("current_r<=-0.50 && runner.peak_r<0.15 && soft_bad_bars>=2", manager)
        self.assertIn("if(GlobalVariableCheck(FPBankIntentKey(identifier))) continue;", manager)
        self.assertIn("state==AP_STATE_STRUCTURAL_RUNNER", manager)
        self.assertIn("bool tighter=direction>0?desired>sl:desired<sl;", manager)
        self.assertIn("if(tighter && profitable && correct_side)", manager)
        self.assertNotIn("MinimumProtectedR(", manager)
        self.assertNotIn("ReachedApproximateR(", manager)

    def test_partial_close_broker_dispositions_restart_and_volume_steps(self):
        functions = "\n".join(self.body(self.source, n) for n in (
            "FPReadBankLedger", "FPBankTarget", "FPBankIntentKey", "FPBankComplete", "FPTryBank"
        ))
        pre = r'''
#include <cmath>
#include <string>
#include <vector>
#include <map>
#include <cassert>
#include <iostream>
using string=std::string; using ulong=unsigned long; using uint=unsigned int;
enum {DEAL_SYMBOL,DEAL_MAGIC,DEAL_ENTRY,DEAL_VOLUME,DEAL_COMMISSION,DEAL_FEE,DEAL_PROFIT,DEAL_SWAP,
DEAL_ENTRY_IN,DEAL_ENTRY_OUT,DEAL_ENTRY_OUT_BY,ACCOUNT_LOGIN,ACCOUNT_TRADE_MODE,ACCOUNT_TRADE_MODE_DEMO,
ACCOUNT_MARGIN_MODE,ACCOUNT_MARGIN_MODE_RETAIL_HEDGING,SYMBOL_VOLUME_STEP,SYMBOL_VOLUME_MIN,POSITION_VOLUME,
TRADE_RETCODE_DONE,TRADE_RETCODE_DONE_PARTIAL,TRADE_RETCODE_REJECT,TRADE_RETCODE_INVALID_VOLUME,
TRADE_RETCODE_MARKET_CLOSED,TRADE_RETCODE_TRADE_DISABLED,TRADE_RETCODE_REQUOTE,TRADE_RETCODE_PRICE_CHANGED,
TRADE_RETCODE_PRICE_OFF,TRADE_RETCODE_TIMEOUT};
long FastMagic=42; int MaxSlippagePoints=12; struct MarketScore{};
struct FPBankLedger{double original_volume,closed_volume,closed_gross,closed_net,opening_cost;};
struct Deal{long entry;double volume,profit,swap,commission,fee;};
std::vector<Deal> deals; std::map<string,double> globals;
long login=7404213,mode=ACCOUNT_MARGIN_MODE_RETAIL_HEDGING,trade_mode=ACCOUNT_TRADE_MODE_DEMO;
bool owner=true,history=true,position=true,persist=true; double step=.01,minimum=.01,remaining=2,fill_fraction=1;
int orders=0; uint outcome=TRADE_RETCODE_DONE;
bool HistorySelectByPosition(ulong){return history;} int HistoryDealsTotal(){return deals.size();}
ulong HistoryDealGetTicket(int i){return i+1;} string HistoryDealGetString(ulong,int){return "TEST";}
long HistoryDealGetInteger(ulong d,int f){return f==DEAL_MAGIC?FastMagic:deals[d-1].entry;}
double HistoryDealGetDouble(ulong d,int f){auto x=deals[d-1];if(f==DEAL_VOLUME)return x.volume;if(f==DEAL_PROFIT)return x.profit;if(f==DEAL_SWAP)return x.swap;if(f==DEAL_COMMISSION)return x.commission;if(f==DEAL_FEE)return x.fee;return 0;}
template<class T> void ZeroMemory(T &b){b={};} double MathFloor(double x){return std::floor(x);}
double NormalizeDouble(double x,int n){auto p=std::pow(10,n);return std::round(x*p)/p;}
long AccountInfoInteger(int f){return f==ACCOUNT_LOGIN?login:f==ACCOUNT_TRADE_MODE?trade_mode:mode;}
string IntegerToString(long i){return std::to_string(i);} double SymbolInfoDouble(string,int f){return f==SYMBOL_VOLUME_STEP?step:minimum;}
bool GlobalVariableCheck(string k){return globals.count(k);} long GlobalVariableSet(string k,double v){if(!persist)return 0;globals[k]=v;return 1;}
void GlobalVariableDel(string k){globals.erase(k);} void GlobalVariablesFlush(){} bool PositionSelectByTicket(ulong){return position;}
double PositionGetDouble(int){return remaining;} bool VerifyOrderOwnership(string,string &){return owner;}
string BoolText(bool x){return x?"true":"false";} template<class... T> string StringFormat(string s,T...){return s;}
void AppendEvidence(string,MarketScore&,ulong,string){} string APKey(long id,string f){return std::to_string(id)+f;}
bool APSet(long id,string f,double v){return GlobalVariableSet(APKey(id,f),v)!=0;}
double APGet(long id,string f,double fallback=0){auto k=APKey(id,f);return GlobalVariableCheck(k)?globals[k]:fallback;}
struct Trade {void SetExpertMagicNumber(long){} bool PositionClosePartial(ulong,double v,ulong){orders++;assert(v>0&&v<remaining);if(outcome==TRADE_RETCODE_DONE||outcome==TRADE_RETCODE_DONE_PARTIAL){v*=fill_fraction;remaining-=v;deals.push_back({DEAL_ENTRY_OUT,v,200*v,0,-v,0});}return outcome==TRADE_RETCODE_DONE||outcome==TRADE_RETCODE_DONE_PARTIAL;} uint ResultRetcode(){return outcome;}} g_trade;
void reset(){deals={{DEAL_ENTRY_IN,2,0,0,-2,0}};globals.clear();remaining=2;orders=0;outcome=TRADE_RETCODE_DONE;fill_fraction=1;login=7404213;mode=ACCOUNT_MARGIN_MODE_RETAIL_HEDGING;trade_mode=ACCOUNT_TRADE_MODE_DEMO;owner=history=position=persist=true;step=minimum=.01;}
'''
        checks = r'''
int main(){MarketScore s;int cases=0;
for(double st:{.01,.1,1.})for(int n=1;n<=101;n++){auto v=n*st;auto t=FPBankTarget(v,st,st);if(n==1)assert(t==0);else{assert(t<=v*.5+1e-8);assert(v-t>=st-1e-8);}cases++;}
reset();assert(!FPTryBank(99,7,"TEST",.9999,999.9,1000,s));assert(orders==0);cases++;
assert(FPTryBank(99,7,"TEST",1.0,1000,1000,s));assert(orders==1&&remaining==1);cases++;
assert(FPTryBank(99,7,"TEST",3.0,3000,1000,s));assert(orders==1);cases++;
FPBankLedger b;assert(FPReadBankLedger(7,"TEST",b));assert(b.closed_volume==1&&b.closed_net==198&&b.opening_cost==-2);cases++;
reset();outcome=TRADE_RETCODE_TIMEOUT;assert(!FPTryBank(99,7,"TEST",1.1,1100,1000,s));assert(orders==1);outcome=TRADE_RETCODE_DONE;assert(!FPTryBank(99,7,"TEST",3,3000,1000,s));assert(orders==1);cases++;
remaining=1;deals.push_back({DEAL_ENTRY_OUT,1,200,0,-1,0});assert(FPTryBank(99,7,"TEST",-.5,-500,1000,s));assert(orders==1);cases++;
reset();outcome=TRADE_RETCODE_REJECT;assert(!FPTryBank(99,7,"TEST",1,1000,1000,s));assert(globals.empty());outcome=TRADE_RETCODE_DONE;assert(FPTryBank(99,7,"TEST",1,1000,1000,s));assert(orders==2);cases++;
reset();outcome=TRADE_RETCODE_DONE_PARTIAL;fill_fraction=.5;assert(!FPTryBank(99,7,"TEST",1,1000,1000,s));assert(remaining==1.5);outcome=TRADE_RETCODE_DONE;fill_fraction=1;assert(FPTryBank(99,7,"TEST",1,1000,1000,s));assert(remaining==1);cases++;
for(long bad:{7196820,7198096}){reset();login=bad;assert(!FPTryBank(99,7,"TEST",2,2000,1000,s));assert(orders==0);cases++;}
reset();owner=false;assert(!FPTryBank(99,7,"TEST",2,2000,1000,s));assert(orders==0);cases++;
reset();history=false;assert(!FPTryBank(99,7,"TEST",2,2000,1000,s));assert(orders==0);cases++;
reset();step=minimum=2;assert(!FPTryBank(99,7,"TEST",2,2000,1000,s));assert(orders==0);cases++;
std::cout<<cases<<" banking and volume/restart cases passed\n";}
'''
        with tempfile.TemporaryDirectory() as directory:
            src = Path(directory) / "bank.cpp"
            exe = Path(directory) / "bank"
            src.write_text(pre + functions + checks)
            compiled = subprocess.run(["g++", "-std=c++17", "-O2", str(src), "-o", str(exe)], capture_output=True, text=True)
            self.assertEqual(compiled.returncode, 0, compiled.stderr)
            ran = subprocess.run([str(exe)], capture_output=True, text=True)
            self.assertEqual(ran.returncode, 0, ran.stderr)
            self.assertIn("banking and volume/restart cases passed", ran.stdout)

    def test_partial_deal_is_not_final_exit(self):
        tx = self.body(self.source, "OnTradeTransaction")
        self.assertLess(tx.index("if(FPPositionStillOpen(position_id))"), tx.index("string final_key="))
        self.assertIn("return;", tx[tx.index("if(FPPositionStillOpen(position_id))"):tx.index("string final_key=")])


if __name__ == "__main__":
    unittest.main(verbosity=2)
