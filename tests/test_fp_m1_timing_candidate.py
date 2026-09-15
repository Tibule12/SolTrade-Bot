import csv
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "ops/forexvps/releases/fp-m1-timing-v1-candidate-20260915/SolTradeFastMultiMarketV2.mq5"
BASE = ROOT / "ops/forexvps/releases/fp-adaptive-payoff-v1-bank1r-giveback-20260912/SolTradeFastMultiMarketV2.mq5"
FEATURES = ROOT / "reports/fast-multi-market-v2/fp-m1-forward-gate-20260915/trade-features.csv"


class FPM1TimingCandidateTests(unittest.TestCase):
    def test_gate_is_before_persistence_and_has_explicit_reason(self):
        text = SOURCE.read_text()
        reason = 'else if(!m1_timing_ready) complete_reason="M1_SETUP_TIMING_NOT_READY";'
        self.assertIn(reason, text)
        self.assertLess(text.index(reason), text.index("out.complete_admission_qualified=(complete_reason==\"\")"))

    def test_entry_risk_and_manager_inputs_are_unchanged(self):
        original = BASE.read_text().splitlines()
        candidate = SOURCE.read_text().splitlines()
        original_inputs = [line for line in original if line.lstrip().startswith("input ")]
        candidate_inputs = [line for line in candidate if line.lstrip().startswith("input ")]
        self.assertEqual(original_inputs, candidate_inputs)
        for literal in ("ProfitBankTriggerR=1.00", "ProfitBankFraction=0.50", "RiskPerTradePercent=1.00", "MaxAggregateRiskPercent=1.50"):
            self.assertEqual(literal in "\n".join(original), literal in "\n".join(candidate))

    def test_latest_four_fp_losses_are_rejected_by_locked_rule(self):
        with FEATURES.open(newline="", encoding="utf-8") as handle:
            rows = list(csv.DictReader(handle))
        latest = [row for row in rows if row["case"].startswith(("20260914", "20260915"))]
        self.assertEqual(len(latest), 4)
        self.assertTrue(all(row["SETUP_FAMILY_TIMING_V1"] == "False" for row in latest))


if __name__ == "__main__":
    unittest.main()
