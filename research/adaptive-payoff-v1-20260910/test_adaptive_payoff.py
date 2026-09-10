import hashlib,json,re,subprocess,tempfile,unittest
from pathlib import Path
import build

HERE=Path(__file__).resolve().parent
SOURCE=HERE/'SolTradeFastMultiMarketV2.mq5'
BASE=build.BASE

class AdaptivePayoffTests(unittest.TestCase):
 def setUp(self):
  self.s=SOURCE.read_text();self.base=BASE.read_text()

 def body(self,text,name):
  a,b=build.function_span(text,name);return text[a:b]

 def test_identity_scope_and_frozen_inputs(self):
  m=json.loads((HERE/'manifest.json').read_text())
  self.assertEqual(hashlib.sha256(SOURCE.read_bytes()).hexdigest(),m['source_sha256'])
  self.assertEqual(re.findall(r'^input .*?;',self.s,re.M),re.findall(r'^input .*?;',self.base,re.M))
  self.assertIn('#define REQUIRED_DEMO_LOGIN 7404213',self.s)
  self.assertIn('#define FORBIDDEN_LIVE_LOGIN 7196820',self.s)
  self.assertIn('AccountInfoInteger(ACCOUNT_LOGIN)!=7404213',self.s)
  self.assertNotIn('FP_BANKING_RESEARCH_ONLY_NOT_DEPLOYABLE',self.s)
  self.assertEqual(m['fxify_forbidden'],[7196820,7198096])

 def test_entry_stop_sizing_and_ownership_are_preserved(self):
  for name in ('ScoreSymbol','EntryQuoteStillValid','CalculateLots','NearestOpposingSwing',
               'VerifyOrderOwnership','InitializeOwnership','StrongCorrelationCount'):
   self.assertEqual(self.body(self.s,name),self.body(self.base,name),name)
  self.assertIn('live.stop=NormalizePrice(live.symbol,live.stop);',self.body(self.s,'OpenCandidate'))
  self.assertIn('if(!CandidatePortfolioSafe(live,reason)) return false;',self.body(self.s,'OpenCandidate'))
  self.assertIn('POSITION_CLOSE_UNPROTECTED_ENTRY',self.body(self.s,'OpenCandidate'))

 def test_one_manager_and_no_monetary_peak_floor(self):
  f=self.body(self.s,'ManageFastPositions')
  self.assertNotIn('MinimumProtectedR(',f)
  self.assertNotIn('ReachedApproximateR(',f)
  self.assertNotIn('DELAYED_EARLY_FAILURE',f)
  self.assertNotIn('current_r<=-0.50)',f)
  self.assertIn('current_r<=-0.50 && runner.peak_r<0.15 && soft_bad_bars>=2',f)
  self.assertIn('two_consecutive_completed_m5_structural_deterioration',f)
  self.assertIn('state==AP_STATE_STRUCTURAL_RUNNER',f)
  self.assertIn('bool tighter=direction>0?desired>sl:desired<sl;',f)
  self.assertIn('if(tighter && profitable && correct_side)',f)
  self.assertEqual(f.count('PositionClose('),0)
  self.assertEqual(self.s.count('void ManageFastPositions()'),1)

 def test_bank_is_frozen_and_broker_authoritative(self):
  f=self.body(self.s,'FPTryBank')
  self.assertIn('if(current_r<2.0',f)
  self.assertIn('0.50*original',self.body(self.s,'FPBankTarget'))
  self.assertIn('complete?"PARTIAL_BANK_2R"',f)
  self.assertIn('Persist intent before sending',f)
  self.assertIn('PositionClosePartial(ticket,close_volume',f)
  tx=self.body(self.s,'OnTradeTransaction')
  partial=tx.index('if(FPPositionStillOpen(position_id))')
  final=tx.index('string final_key=')
  self.assertLess(partial,final)
  self.assertIn('return;',tx[partial:final])

 def test_exact_banked_cash_excludes_runner_exit(self):
  helper=self.body(self.s,'FPBankTarget')+'\n'+self.body(self.s,'APReadBankedCash')
  harness=r'''
#include <cmath>
#include <string>
#include <vector>
#include <cassert>
#include <iostream>
using string=std::string;using ENUM_DEAL_ENTRY=long;
enum {DEAL_SYMBOL,DEAL_MAGIC,DEAL_ENTRY,DEAL_VOLUME,DEAL_COMMISSION,DEAL_FEE,DEAL_PROFIT,DEAL_SWAP,
DEAL_ENTRY_IN,DEAL_ENTRY_OUT,DEAL_ENTRY_OUT_BY,SYMBOL_VOLUME_STEP,SYMBOL_VOLUME_MIN};
struct Deal{long entry;double volume,profit,swap,commission,fee;};
std::vector<Deal> deals;long FastMagic=42;double step=.01,minimum=.01;
bool HistorySelectByPosition(ulong){return true;}int HistoryDealsTotal(){return deals.size();}
ulong HistoryDealGetTicket(int i){return i+1;}string HistoryDealGetString(ulong,int){return "TEST";}
long HistoryDealGetInteger(ulong d,int f){return f==DEAL_MAGIC?FastMagic:deals[d-1].entry;}
double HistoryDealGetDouble(ulong d,int f){auto x=deals[d-1];if(f==DEAL_VOLUME)return x.volume;if(f==DEAL_PROFIT)return x.profit;if(f==DEAL_SWAP)return x.swap;if(f==DEAL_COMMISSION)return x.commission;if(f==DEAL_FEE)return x.fee;return 0;}
double SymbolInfoDouble(string,int f){return f==SYMBOL_VOLUME_STEP?step:minimum;}
double MathFloor(double x){return std::floor(x);}double MathMin(double a,double b){return std::min(a,b);}
double NormalizeDouble(double x,int n){auto p=std::pow(10,n);return std::round(x*p)/p;}
'''+helper+r'''
int main(){
 deals={{DEAL_ENTRY_IN,2,0,0,-2,0},{DEAL_ENTRY_OUT,1,200,0,-1,0},{DEAL_ENTRY_OUT,1,500,0,-1,0}};
 double volume=0,cash=0;assert(APReadBankedCash(7,"TEST",volume,cash));assert(std::abs(volume-1)<1e-9);assert(std::abs(cash-198)<1e-9);
 std::cout<<"exact bank allocation passed";
}
'''
  with tempfile.TemporaryDirectory() as d:
   p=Path(d)/'account.cpp';p.write_text(harness);binary=Path(d)/'account'
   c=subprocess.run(['g++','-std=c++17','-O2',str(p),'-o',str(binary)],capture_output=True,text=True)
   self.assertEqual(c.returncode,0,c.stderr)
   run=subprocess.run([str(binary)],capture_output=True,text=True)
   self.assertEqual(run.returncode,0,run.stderr);self.assertIn('exact bank allocation passed',run.stdout)

 def test_durable_state_and_restart_fail_closed(self):
  self.assertIn('APInitializePosition(identifier',self.body(self.s,'OpenCandidate'))
  self.assertIn('ADAPTIVE_PAYOFF_STATE_UNRECOVERABLE_',self.body(self.s,'ReconcileBrokerState'))
  self.assertIn('PORTFOLIO_RISK_UNKNOWN_DENY_NEW_RISK',self.body(self.s,'CandidatePortfolioSafe'))
  self.assertIn('g_portfolio_risk_known=false',self.body(self.s,'PositionRiskAmount'))
  self.assertIn('manager_version',self.body(self.s,'WriteRuntimeStatus'))
  self.assertIn('ADAPTIVE_PAYOFF_V1',self.body(self.s,'WriteRuntimeStatus'))

 def test_required_evidence_and_false_exit_shadow(self):
  tx=self.body(self.s,'OnTradeTransaction')
  for token in ('original_stop=','initial_dollar_risk=','half_risk_touched=',
                'probation_failed=','banked_cash=','runner_cash=','final_total_r='):
   self.assertIn(token,tx)
  self.assertIn('APStartProbationShadow',tx)
  self.assertIn('APReadBankedCash',tx)
  self.assertIn('ENTRY_PROBATION_SHADOW_COMPLETE',self.body(self.s,'APUpdateProbationShadows'))

if __name__=='__main__': unittest.main(verbosity=2)
