import json
import re
import unittest
from pathlib import Path

from tools.entry_engine_v3.full_lifetime import FROZEN_CANDIDATES, LifetimePosition, ORDER_CAPABILITY


ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "tools/mql/full-lifetime-tracker-v1/SolTradeFullLifetimeTrackerV1.mq5"
MODEL = ROOT / "reports/fast-multi-market-v2/full-lifetime-causal-tracking-20260919/frozen-tracking-model.json"


class FullLifetimeTrackerTests(unittest.TestCase):
    def test_negative_r_alone_never_invalidates(self):
        position = LifetimePosition()
        position.observe(-0.80, 0.10)
        self.assertFalse(position.paths["FROZEN_V3_DIAGNOSTIC"].invalidated)

    def test_frozen_diagnostic_requires_both_conditions(self):
        position = LifetimePosition()
        position.observe(-0.39, -0.90)
        self.assertFalse(position.paths["FROZEN_V3_DIAGNOSTIC"].invalidated)
        position.observe(-0.40, -0.25)
        self.assertTrue(position.paths["FROZEN_V3_DIAGNOSTIC"].invalidated)
        self.assertEqual(position.paths["FROZEN_V3_DIAGNOSTIC"].exit_r, -0.40)

    def test_aftermath_keeps_recording_recovery_and_tail(self):
        position = LifetimePosition()
        position.observe(-0.50, -0.40, expanding_pullback=True)
        for value in (-1.0, 0.0, 1.0, 2.0, 3.0, 5.0):
            position.observe(value, 0.0)
        path = position.paths["FROZEN_V3_DIAGNOSTIC"]
        self.assertTrue(path.continued_to_minus_1)
        self.assertTrue(path.recovered_to_breakeven)
        self.assertTrue(path.reached_bank1 and path.reached_plus_2 and path.reached_plus_3 and path.reached_plus_5)

    def test_bank_occurs_once_and_preserves_runner_math(self):
        position = LifetimePosition()
        position.observe(1.0, 0.0)
        position.observe(2.0, 0.0)
        position.observe(-1.0, 0.0)
        self.assertEqual(position.bank_count, 1)
        self.assertEqual(position.baseline_final_r(-1.0), 0.0)

    def test_model_and_candidates_are_frozen(self):
        payload = json.loads(MODEL.read_text())
        self.assertEqual(payload["configuration"]["family"], "TRANSITION_INTERACTIONS")
        self.assertEqual(payload["configuration"]["l2"], 10.0)
        self.assertEqual(payload["configuration"]["max_full_loss"], 0.45)
        self.assertEqual(len(payload["base_feature_names"]), 72)
        self.assertEqual(len(payload["model_feature_names"]), 80)
        self.assertEqual([item["id"] for item in payload["invalidation_candidates"]], [c.candidate_id for c in FROZEN_CANDIDATES])

    def test_mql_tracker_has_no_trade_api(self):
        text = SOURCE.read_text()
        self.assertIn("const bool ORDER_CAPABILITY=false", text)
        self.assertIn("completed_bars_only,order_capability", text)
        self.assertIn("bool SymbolFresh", text)
        self.assertIn("STALE_MARKET_NO_CURRENT_TICK", text)
        for pattern in (r"#include\s*<Trade/", r"\bCTrade\b", r"\bOrderSend(?:Async)?\s*\(", r"\bMqlTradeRequest\b", r"\bTRADE_ACTION_", r"\bPositionClose\s*\(", r"\bPositionModify\s*\(", r"\bOrderDelete\s*\("):
            self.assertIsNone(re.search(pattern, text), pattern)


if __name__ == "__main__":
    unittest.main()
