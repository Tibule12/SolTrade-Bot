import hashlib
import json
import re
import sys
import unittest
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import build

SOURCE = HERE / "SolTradeFastMultiMarketV2.mq5"


class GivebackRepairTests(unittest.TestCase):
    def setUp(self):
        self.source = SOURCE.read_text()
        self.base = build.BASE.read_text()

    def body(self, text, name):
        a, b = build.function_span(text, name)
        return text[a:b]

    def test_identity_scope_and_frozen_inputs(self):
        manifest = json.loads((HERE / "manifest.json").read_text())
        self.assertEqual(hashlib.sha256(SOURCE.read_bytes()).hexdigest(), manifest["source_sha256"])
        self.assertEqual(re.findall(r"^input .*?;", self.source, re.M), re.findall(r"^input .*?;", self.base, re.M))
        self.assertEqual(manifest["fxify_forbidden"], [7196820, 7198096])
        self.assertIn("#define REQUIRED_DEMO_LOGIN 7404213", self.source)
        self.assertIn("ADAPTIVE_PAYOFF_V1_BANK1R_GIVEBACK", self.body(self.source, "WriteRuntimeStatus"))

    def test_entries_sizing_stops_bank_and_runner_unchanged(self):
        for name in (
            "ScoreSymbol", "EntryQuoteStillValid", "CalculateLots", "NearestOpposingSwing",
            "CandidatePortfolioSafe", "OpenCandidate", "VerifyOrderOwnership", "InitializeOwnership",
            "StrongCorrelationCount", "FPBankTarget", "FPReadBankLedger", "FPTryBank",
        ):
            self.assertEqual(self.body(self.source, name), self.body(self.base, name), name)
        self.assertIn("if(bank_trigger_r<1.0", self.body(self.source, "FPTryBank"))
        self.assertIn("0.50*original", self.body(self.source, "FPBankTarget"))
        self.assertIn("RiskPerTradePercent!=1.00", self.body(self.source, "OnInit"))
        self.assertIn("MaxPortfolioRiskPercent!=1.50", self.body(self.source, "OnInit"))

    def test_explicit_durable_giveback_state_and_exit(self):
        manager = self.body(self.source, "ManageFastPositions")
        self.assertIn("AP_STATE_PRE_BANK_GIVEBACK 4", self.source)
        self.assertIn('return "PRE_BANK_GIVEBACK"', self.body(self.source, "APStateName"))
        self.assertIn('return "PRE_BANK_GIVEBACK_FAILED"', self.body(self.source, "APExitName"))
        self.assertIn("state==AP_STATE_PRE_BANK_PROFIT && current_r<0.0", manager)
        self.assertIn("state==AP_STATE_PRE_BANK_GIVEBACK && current_r>=0.0", manager)
        self.assertIn("state==AP_STATE_PRE_BANK_GIVEBACK && current_r<=-0.50 && pre_bank_causal_failure", manager)
        self.assertIn("score.direction==-direction && opposite_structure", manager)
        self.assertIn("opposite_score>=held_score+MinDirectionalDominance", manager)
        self.assertIn("structural_deterioration || pre_bank_opposing_failure", manager)
        self.assertIn("original_structural_sl_retained=true", manager)

    def test_no_blind_negative_or_half_risk_exit(self):
        manager = self.body(self.source, "ManageFastPositions")
        self.assertNotIn("state==AP_STATE_PRE_BANK_GIVEBACK && current_r<0.0 &&", manager)
        damage = "state==AP_STATE_PRE_BANK_GIVEBACK && current_r<=-0.50 && pre_bank_causal_failure"
        self.assertEqual(manager.count(damage), 1)
        self.assertIn("soft_bad_bars>=2 && state!=AP_STATE_PRE_BANK_GIVEBACK", manager)
        self.assertNotIn("MinimumProtectedR(", manager)
        self.assertNotIn("ReachedApproximateR(", manager)

    def test_live_xau_regression_and_recovery_paths(self):
        HEALTHY, PRE_BANK, RUNNER, GIVEBACK = 1, 2, 3, 4

        def step(state, peak, current, bank_r, causal=False, hard=False):
            if hard:
                return state, "THESIS_INVALIDATION"
            if state == HEALTHY and peak >= 0.50:
                state = PRE_BANK
            if state == PRE_BANK and current < 0:
                state = GIVEBACK
            if state == GIVEBACK and current >= 0:
                state = PRE_BANK
            if bank_r >= 1.0:
                return RUNNER, "PARTIAL_BANK_1R"
            if state == GIVEBACK and current <= -0.50 and causal:
                return state, "PRE_BANK_GIVEBACK_FAILED"
            return state, None

        state, action = step(HEALTHY, 0.56825, 0.56825, 0.56825)
        self.assertEqual((state, action), (PRE_BANK, None))
        state, action = step(state, 0.56825, -0.11647, -0.11647)
        self.assertEqual((state, action), (GIVEBACK, None))
        state, action = step(state, 0.56825, -0.50445, -0.50445, causal=False)
        self.assertEqual((state, action), (GIVEBACK, None))
        state, action = step(state, 0.56825, -0.65579, -0.65579, causal=True)
        self.assertEqual((state, action), (GIVEBACK, "PRE_BANK_GIVEBACK_FAILED"))

        state, action = step(GIVEBACK, 0.70, 0.10, 0.10)
        self.assertEqual((state, action), (PRE_BANK, None))
        state, action = step(GIVEBACK, 1.05, 1.01, 1.00)
        self.assertEqual((state, action), (RUNNER, "PARTIAL_BANK_1R"))


if __name__ == "__main__":
    unittest.main(verbosity=2)
