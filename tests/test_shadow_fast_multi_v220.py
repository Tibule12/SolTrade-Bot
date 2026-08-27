import importlib.util
import sys
import unittest
from pathlib import Path


MODULE_PATH = Path(__file__).parents[1] / "tools" / "shadow_fast_multi_v220.py"
SPEC = importlib.util.spec_from_file_location("shadow_fast_multi_v220", MODULE_PATH)
shadow = importlib.util.module_from_spec(SPEC)
assert SPEC.loader
sys.modules[SPEC.name] = shadow
SPEC.loader.exec_module(shadow)


def example_row(**overrides):
    row = {
        "utc": "2026.08.27 08:00:00",
        "sast": "2026.08.27 10:00:00",
        "scan_sequence": "1",
        "intended_market": "EURUSD",
        "resolved_broker_symbol": "EURUSD.r",
        "candidate_direction": "BUY",
        "decision": "NO_TRADE",
        "score": "90",
        "buy_score": "90",
        "sell_score": "40",
        "no_trade_score": "20",
        "tick_state": "FRESH",
        "raw_spread": "0.00002",
        "spread_points": "2",
        "spread_median_ratio": "1.0",
        "spread_baseline_ready": "true",
        "spread_filter_result": "PASS",
        "spread_to_m5_atr_percent": "2.0",
        "movement_to_spread": "20",
        "directional_core_qualified": "true",
        "directional_persistence_count": "3",
        "directional_persistence_seconds": "30",
        "entry_drift_m5_atr": "0.2",
        "m5_confirmed": "true",
        "m15_confirmed": "true",
        "m5_swing_extension_atr": "0.5",
        "m15_swing_extension_atr": "0.5",
        "m15_invalidation_swing": "1.0995",
        "confirmation_timing": "consumed=0.10",
        "extension_state": "impulse_atr=0.8;breakout_atr=0.1",
        "absolute_admission_components": (
            "remaining_room=10;cost_penalty=3;extension_penalty=0;"
            "conflict_penalty=0;final=70;trigger=true;range_chop=false;"
            "opposing_structure=true"
        ),
        "entry": "1.1000",
        "stop": "1.0990",
        "stop_distance": "0.0010",
        "reward_r": "0.8",
        "available_move": "0.00085",
        "expected_cost_move": "0.00005",
        "expected_net_move": "0.00080",
        "cost_multiple": "17",
        "primary_rejection_reason": "OPPOSING_STRUCTURE_TOO_CLOSE_AFTER_COSTS",
        "eligible": "false",
        "order_attempt_status": "NOT_ATTEMPTED",
        "setup_key": "1",
    }
    row.update(overrides)
    return row


class ShadowAuditTests(unittest.TestCase):
    def test_requested_reward_room_thresholds_are_complete(self):
        self.assertEqual(shadow.RR_THRESHOLDS, (1.00, 1.10, 1.15, 1.20, 1.25, 1.35, 1.50))

    def test_atr_uses_price_units_for_fx(self):
        observation = shadow.Observation.from_row(example_row())
        self.assertAlmostEqual(observation.atr5, 0.001)

    def test_min_rr_ablation_does_not_change_live_decision(self):
        observation = shadow.Observation.from_row(example_row())
        self.assertEqual(shadow.evaluate(observation), "REJECTED:min_reward_r")
        self.assertEqual(shadow.evaluate(observation, {"min_reward_r"}), "ELIGIBLE")
        self.assertEqual(observation.row["eligible"], "false")

    def test_opposing_level_is_directionally_above_buy_entry(self):
        observation = shadow.Observation.from_row(example_row())
        output = shadow.candidate_row(observation)
        self.assertGreater(output["nearest_opposing_structure"], output["entry_candidate_price"])

    def test_conflict_ablation_removes_score_penalty_but_keeps_other_gates(self):
        row = example_row(
            reward_r="1.5",
            expected_net_move="0.0015",
            available_move="0.00155",
            absolute_admission_components=(
                "remaining_room=15;cost_penalty=3;extension_penalty=0;"
                "conflict_penalty=100;final=-25;trigger=true;range_chop=false;"
                "opposing_structure=true"
            ),
            primary_rejection_reason="M5_M15_DIRECTIONAL_CONFLICT",
            directional_core_qualified="false",
            directional_persistence_count="0",
            directional_persistence_seconds="0",
        )
        observation = shadow.Observation.from_row(row)
        result = shadow.evaluate(observation, {"m5_m15_conflict"})
        self.assertTrue(result.startswith("REJECTED:") or result.startswith("UNKNOWN:"))
        self.assertNotEqual(result, "ELIGIBLE")  # persistence/core causality is not invented

    def test_v6_structure_metadata_is_preserved(self):
        observation = shadow.Observation.from_row(example_row(
            stop_anchor_timeframe="M5",
            stop_anchor_time="2026.08.27 07:55:00",
            stop_anchor_age_seconds="300",
            opposing_structure_timeframe="M15",
            opposing_structure_time="2026.08.27 07:30:00",
            opposing_structure_age_seconds="1800",
            opposing_reaction_count="3",
            initial_clean_room_required_r="1.20",
        ))
        output = shadow.candidate_row(observation)
        self.assertEqual(output["stop_anchor_timeframe"], "M5")
        self.assertEqual(output["opposing_structure_timeframe"], "M15")
        self.assertEqual(output["required_minimum_reward_r"], 1.20)


if __name__ == "__main__":
    unittest.main()
