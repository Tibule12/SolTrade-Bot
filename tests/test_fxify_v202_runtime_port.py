#!/usr/bin/env python3

import importlib.util
import sys
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).parents[1]
MODULE_PATH = ROOT / "tools" / "build_fxify_v202_runtime_port.py"
SPEC = importlib.util.spec_from_file_location("build_fxify_v202_runtime_port", MODULE_PATH)
port = importlib.util.module_from_spec(SPEC)
assert SPEC.loader
sys.modules[SPEC.name] = port
SPEC.loader.exec_module(port)

SOURCE = ROOT / "MQL5" / "Experts" / "SolTradeFastMultiMarketV2.mq5"
PRESET = ROOT / "ops" / "forexvps" / "payload" / "fp-demo" / "SolTradeFastMultiMarketV2-FPMarkets-demo.set"


class FxifyV202RuntimePortTests(unittest.TestCase):
    def build_target(self, target):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        result = port.build(SOURCE, PRESET, target, Path(temporary.name))
        expert = next(Path(temporary.name).glob("*.mq5")).read_text(encoding="utf-8")
        preset = next(Path(temporary.name).glob("*.set")).read_text(encoding="utf-8")
        return result, expert, preset

    def test_both_accounts_are_bound_and_state_isolated(self):
        targets = {
            "fxify-10k": (7196820, 2108202610, "F10"),
            "fxify-100k": (7198096, 2108202620, "F100"),
        }
        sources = []
        for target, (account, magic, suffix) in targets.items():
            result, expert, preset = self.build_target(target)
            sources.append(result["generated_source_sha256"])
            self.assertIn(f"#define REQUIRED_DEMO_LOGIN {account}", expert)
            self.assertIn(f"#define V1_MAGIC {magic}", expert)
            self.assertIn(f"SolTradeFastMultiMarketV2{suffix}\\", expert)
            self.assertIn(f'"SFM2{suffix}', expert)
            self.assertIn(f"ApprovedDemoAccount={account}", preset)
            self.assertIn("ApprovedDemoServer=FXIFY-Server", preset)
        self.assertEqual(len(set(sources)), 2)

    def test_corrected_strategy_and_frozen_risk_are_present(self):
        for target in port.ALLOWED:
            result, expert, preset = self.build_target(target)
            self.assertEqual(result["strategy_version"], "2.202")
            self.assertIn("complete_admission_qualified", expert)
            self.assertIn("ManageImmediateScratchPositions", expert)
            self.assertIn("ImmediateDirectionalScratchEnabled=false", expert)
            self.assertIn("COMPLETE_ADMISSION_PERSISTENCE_PENDING", expert)
            self.assertIn("DELAYED_FAILURE_MIN_AGE_SECONDS 900", expert)
            self.assertIn("POSITION_CLOSE_DELAYED_EARLY_FAILURE", expert)
            self.assertIn("SFM2F10_EARLY_FAIL_SINCE_" if target == "fxify-10k" else "SFM2F100_EARLY_FAIL_SINCE_", expert)
            self.assertIn("RiskPerTradePercent=0.25", preset)
            self.assertIn("MaxPortfolioRiskPercent=1.50", preset)
            self.assertIn("MaxSimultaneousTrades=6", preset)
            self.assertIn("MaxStronglyCorrelatedTrades=2", preset)
            self.assertIn("MinRewardRisk=1.15", preset)
            self.assertIn("ImmediateDirectionalScratchEnabled=false", preset)

    def test_global_algo_is_the_final_fail_closed_entry_gate(self):
        for target in port.ALLOWED:
            _, expert, preset = self.build_target(target)
            self.assertIn("FINAL_MANUAL_ALGO_SWITCH_OFF", expert)
            self.assertIn("TerminalInfoInteger(TERMINAL_TRADE_ALLOWED)", expert)
            self.assertIn("MQLInfoInteger(MQL_TRADE_ALLOWED)", expert)
            self.assertIn("DryRunOnly=false", preset)
            self.assertIn("OwnershipLeaseRequired=true", preset)
            self.assertIn("OwnershipEligible=true", preset)

    def test_startup_preserves_user_activated_algo_and_uses_v202(self):
        for target, expert in (
            ("fxify-10k", "SolTradeFastMultiMarketV202F10"),
            ("fxify-100k", "SolTradeFastMultiMarketV202F100"),
        ):
            startup = (ROOT / "ops" / "forexvps" / "runtime" / f"{target}.ini").read_text(encoding="utf-8")
            self.assertIn("AllowLiveTrading=1", startup)
            self.assertIn("Enabled=1", startup)
            self.assertIn(f"Expert=SolTrade\\{expert}", startup)
            self.assertIn(f"ExpertParameters={expert}-FINAL-ALGO-OFF.set", startup)


if __name__ == "__main__":
    unittest.main()
