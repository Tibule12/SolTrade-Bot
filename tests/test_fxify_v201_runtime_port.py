#!/usr/bin/env python3

import importlib.util
import sys
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).parents[1]
MODULE_PATH = ROOT / "tools" / "build_fxify_v201_runtime_port.py"
SPEC = importlib.util.spec_from_file_location("build_fxify_v201_runtime_port", MODULE_PATH)
port = importlib.util.module_from_spec(SPEC)
assert SPEC.loader
sys.modules[SPEC.name] = port
SPEC.loader.exec_module(port)

V201 = Path("/home/tibule12/.wine-fpmarkets/drive_c/soltrade-v201-release-kVxvRe")


class FxifyV201RuntimePortTests(unittest.TestCase):
    def build_target(self, target):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        result = port.build(
            V201 / "SolTradeFastMultiMarketV2.mq5",
            V201 / "SolTradeFastMultiMarketV2-FPMarkets-demo.set",
            target,
            Path(temporary.name),
        )
        expert = next(Path(temporary.name).glob("*.mq5")).read_text(encoding="utf-8")
        preset = next(Path(temporary.name).glob("*.set")).read_text(encoding="utf-8")
        return result, expert, preset

    def test_10k_is_account_bound_order_disabled_and_state_isolated(self):
        result, expert, preset = self.build_target("fxify-10k")
        self.assertEqual(result["account"], 7196820)
        self.assertIn("#define REQUIRED_DEMO_LOGIN 7196820", expert)
        self.assertIn("#define V1_MAGIC 2108202610", expert)
        self.assertIn("SolTradeFastMultiMarketV2F10\\", expert)
        self.assertIn('"SFM2F10_', expert)
        self.assertIn("DryRunOnly=true", preset)
        self.assertIn("MinRewardRisk=1.20", preset)

    def test_100k_uses_different_account_magic_and_state(self):
        result, expert, preset = self.build_target("fxify-100k")
        self.assertEqual(result["account"], 7198096)
        self.assertIn("#define REQUIRED_DEMO_LOGIN 7198096", expert)
        self.assertIn("#define V1_MAGIC 2108202620", expert)
        self.assertIn("SolTradeFastMultiMarketV2F100\\", expert)
        self.assertIn('"SFM2F100_', expert)
        self.assertIn("FastMagic=2108202620", preset)

    def test_frozen_strategy_thresholds_remain_exact(self):
        for target in port.ALLOWED:
            result, expert, preset = self.build_target(target)
            self.assertEqual(result["strategy_changes"], [])
            self.assertIn("input double MinRewardRisk=1.20;", expert)
            self.assertIn("RiskPerTradePercent=0.25", preset)
            self.assertIn("MaxPortfolioRiskPercent=1.50", preset)
            self.assertIn("MaxSimultaneousTrades=6", preset)
            self.assertIn("MaxStronglyCorrelatedTrades=2", preset)
            self.assertNotIn("MinRewardRisk=1.15", preset)

    def test_wrong_source_is_refused(self):
        with tempfile.TemporaryDirectory() as temporary:
            bad = Path(temporary) / "bad.mq5"
            bad.write_text("not approved", encoding="utf-8")
            with self.assertRaisesRegex(ValueError, "approved release"):
                port.build(
                    bad,
                    V201 / "SolTradeFastMultiMarketV2-FPMarkets-demo.set",
                    "fxify-10k",
                    Path(temporary) / "out",
                )

    def test_watchdog_uses_one_fully_configured_process_and_never_reattaches(self):
        watchdog = (ROOT / "ops" / "forexvps" / "Watch-SolTrade.ps1").read_text(
            encoding="utf-8"
        )
        self.assertIn('"/login:$($instance.account)"', watchdog)
        self.assertIn('"/config:$startup"', watchdog)
        self.assertIn("RUNTIME_STALE_EXISTING_PROCESS_FAIL_CLOSED", watchdog)
        self.assertNotIn("EA_REATTACH_REQUESTED_RUNTIME_STALE", watchdog)
        self.assertNotIn("deferredFxifyAttach", watchdog)

        for name in ("fxify-10k.ini", "fxify-100k.ini"):
            startup = (ROOT / "ops" / "forexvps" / "runtime" / name).read_text(
                encoding="utf-8"
            )
            # The user has since manually activated both challenge terminals;
            # watchdog recovery must preserve that explicit runtime state.
            self.assertIn("AllowLiveTrading=1", startup)
            self.assertIn("Enabled=1", startup)
            self.assertNotRegex(startup, r"(?m)^Account=")


if __name__ == "__main__":
    unittest.main()
