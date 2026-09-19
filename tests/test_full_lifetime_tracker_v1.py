import json
import re
import unittest
from pathlib import Path

from tools.entry_engine_v3.full_lifetime import FROZEN_CANDIDATES, LifetimePosition, ORDER_CAPABILITY


ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "tools/mql/full-lifetime-tracker-v1/SolTradeFullLifetimeTrackerV1.mq5"
MODEL = ROOT / "reports/fast-multi-market-v2/full-lifetime-causal-tracking-20260919/frozen-tracking-model.json"
FOUR_HOURS = 4 * 60 * 60


class FullLifetimeTrackerTests(unittest.TestCase):
    def test_negative_r_alone_never_invalidates(self):
        position = LifetimePosition(entry_utc=1_000)
        position.observe(-0.80, 0.10, now=1_100)
        self.assertFalse(position.paths["FROZEN_V3_DIAGNOSTIC"].invalidated)

    def test_frozen_diagnostic_requires_both_conditions(self):
        position = LifetimePosition(entry_utc=1_000)
        position.observe(-0.39, -0.90, now=1_100)
        self.assertFalse(position.paths["FROZEN_V3_DIAGNOSTIC"].invalidated)
        position.observe(-0.40, -0.25, now=1_200)
        self.assertTrue(position.paths["FROZEN_V3_DIAGNOSTIC"].invalidated)
        self.assertEqual(position.paths["FROZEN_V3_DIAGNOSTIC"].exit_r, -0.40)

    def test_triggered_trade_remains_active_beyond_four_hours(self):
        position = LifetimePosition(entry_utc=1_000)
        position.observe(0.20, 0.10, now=1_000 + FOUR_HOURS + 60)
        self.assertTrue(position.active)
        self.assertEqual(position.outcome_status, "OPEN")

    def test_bank1_runner_remains_active_beyond_four_hours(self):
        position = LifetimePosition(entry_utc=1_000)
        position.observe(1.05, 0.10, now=2_000)
        position.observe(0.40, 0.10, now=1_000 + FOUR_HOURS + 600)
        self.assertTrue(position.active)
        self.assertTrue(position.bank1_reached)
        self.assertEqual(position.bank_count, 1)

    def test_overnight_restart_restores_complete_open_state(self):
        position = LifetimePosition(entry_utc=1_000)
        position.observe(-0.45, -0.30, now=1_500)
        position.observe(1.20, 0.10, now=2_000)
        position.advance_runner_stop(0.35)
        restored = LifetimePosition.from_state(json.loads(json.dumps(position.to_state())))
        restored.observe(0.60, 0.10, now=1_000 + 86_400)
        self.assertTrue(restored.active)
        self.assertTrue(restored.bank1_reached)
        self.assertEqual(restored.runner_stop_r, 0.35)
        self.assertEqual(restored.runner_trail_updates, 1)
        self.assertTrue(restored.paths["FROZEN_V3_DIAGNOSTIC"].recovered_to_breakeven)

    def test_stale_market_freezes_evaluation_and_cutoff(self):
        position = LifetimePosition(entry_utc=1_000)
        position.observe(-2.0, -1.0, now=100_000, fresh_quote=False)
        position.evaluate_research_cutoff(100_000, 3_600, fresh_quote=False)
        self.assertTrue(position.active)
        self.assertFalse(position.structural_stop_reached)
        self.assertFalse(position.paths["FROZEN_V3_DIAGNOSTIC"].invalidated)

    def test_invalidation_aftermath_continues_beyond_four_hours(self):
        position = LifetimePosition(entry_utc=1_000)
        position.observe(-0.50, -0.40, now=2_000, expanding_pullback=True)
        position.observe(0.0, 0.0, now=1_000 + FOUR_HOURS + 10)
        position.observe(1.0, 0.0, now=1_000 + FOUR_HOURS + 20)
        position.observe(2.0, 0.0, now=1_000 + FOUR_HOURS + 30)
        position.observe(3.0, 0.0, now=1_000 + FOUR_HOURS + 40)
        position.observe(5.0, 0.0, now=1_000 + FOUR_HOURS + 50)
        path = position.paths["FROZEN_V3_DIAGNOSTIC"]
        self.assertTrue(position.active)
        self.assertTrue(path.recovered_to_breakeven)
        self.assertTrue(path.reached_bank1 and path.reached_plus_2 and path.reached_plus_3 and path.reached_plus_5)

    def test_forced_research_cutoff_is_right_censored(self):
        position = LifetimePosition(entry_utc=1_000)
        position.observe(0.25, 0.0, now=2_000)
        position.evaluate_research_cutoff(1_000 + 86_400, 86_400, fresh_quote=True)
        self.assertFalse(position.active)
        self.assertEqual(position.outcome_status, "RIGHT_CENSORED")
        self.assertEqual(position.terminal_reason, "RESEARCH_SAFETY_HORIZON")
        self.assertIsNone(position.baseline_final_r(0.25))

    def test_bank_occurs_once_and_preserves_runner_math(self):
        position = LifetimePosition(entry_utc=1_000)
        position.observe(1.0, 0.0, now=2_000)
        position.observe(2.0, 0.0, now=3_000)
        position.observe(-1.0, 0.0, now=4_000)
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

    def test_mql_lifetime_semantics_and_zero_order_api(self):
        text = SOURCE.read_text()
        self.assertFalse(ORDER_CAPABILITY)
        self.assertIn("const bool ORDER_CAPABILITY=false", text)
        self.assertIn("#define EPISODE_INDEPENDENCE_SECONDS 14400", text)
        self.assertIn("ResearchSafetyHorizonDays=0", text)
        self.assertIn('rightCensored?"RIGHT_CENSORED"', text)
        self.assertIn("UpdateRunnerStructuralStop", text)
        self.assertIn("FeatureWindowReady", text)
        self.assertNotIn("PositionExpiry", text)
        self.assertNotIn("FOUR_HOUR_EXPIRY", text)
        for pattern in (
            r"#include\s*<Trade/", r"\bCTrade\b", r"\bOrderSend(?:Async)?\s*\(",
            r"\bMqlTradeRequest\b", r"\bTRADE_ACTION_", r"\bPositionClose\s*\(",
            r"\bPositionModify\s*\(", r"\bOrderDelete\s*\(",
        ):
            self.assertIsNone(re.search(pattern, text), pattern)


if __name__ == "__main__":
    unittest.main()
