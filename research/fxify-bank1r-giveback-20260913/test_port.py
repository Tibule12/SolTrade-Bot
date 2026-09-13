#!/usr/bin/env python3
import importlib.util
import re
import unittest
from pathlib import Path

HERE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location("builder", HERE / "build.py")
builder = importlib.util.module_from_spec(spec); spec.loader.exec_module(builder)


class PortTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        builder.main()
        cls.base = builder.SOURCE.read_text()

    def normalized(self, text, account, suffix, magic):
        text = text.replace(str(account), "7404213")
        text = text.replace(str(magic), "2108202601")
        text = text.replace("FXIFY-Server", "FPMarketsSC-Demo")
        text = text.replace(f"SolTradeFastMultiMarketV2{suffix}", "SolTradeFastMultiMarketV2")
        text = text.replace(f"SFM2{suffix}", "SFM2").replace(f"SFM1{suffix}", "SFM1")
        text = text.replace("ADAPTIVE_PAYOFF_V1_BANK1R_GIVEBACK: FXIFY", "ADAPTIVE_PAYOFF_V1_BANK1R_GIVEBACK: FP")
        text = re.sub(r'#property description ".*?"', '#property description "Demo-only active intraday multi-market context, execution, and management engine"', text, count=1)
        text = text.replace("#define FORBIDDEN_LIVE_LOGIN 0", "#define FORBIDDEN_LIVE_LOGIN 7196820")
        text = text.replace("input long   ApprovedDemoAccount=7404213;", "input long   ApprovedDemoAccount=0;")
        return text

    def test_exact_portability_only(self):
        for name, s in builder.ACCOUNTS.items():
            p = builder.OUT/name/f"SolTradeFastMultiMarketV202{s['suffix']}.mq5"
            text = p.read_text()
            self.assertEqual(self.normalized(text, s['account'], s['suffix'], s['magic']), self.base, name)

    def test_account_isolation_and_live_policy(self):
        for name, s in builder.ACCOUNTS.items():
            stem=f"SolTradeFastMultiMarketV202{s['suffix']}"
            text=(builder.OUT/name/f"{stem}.mq5").read_text()
            preset=(builder.OUT/name/f"{stem}-FINAL-ACTIVE.set").read_text()
            self.assertIn(f"#define REQUIRED_DEMO_LOGIN {s['account']}", text)
            self.assertIn(f"AccountInfoInteger(ACCOUNT_LOGIN)!={s['account']}", text)
            self.assertIn("ADAPTIVE_PAYOFF_V1_BANK1R_GIVEBACK", text)
            self.assertIn("AP_STATE_PRE_BANK_GIVEBACK", text)
            self.assertNotIn('"SFM2_', text)
            self.assertNotIn('"SFM2C_', text)
            self.assertNotIn('"SFM1_', text)
            self.assertIn("RiskPerTradePercent=1.00", preset)
            self.assertIn("MaxPortfolioRiskPercent=1.50", preset)
            self.assertIn("DryRunOnly=false", preset)
            self.assertIn(f"ApprovedDemoAccount={s['account']}", preset)
            self.assertIn("OwnershipEligible=true", preset)
            self.assertIn("if(bank_trigger_r<1.0", text)
            self.assertIn("0.50*original", text)


if __name__ == '__main__': unittest.main(verbosity=2)
