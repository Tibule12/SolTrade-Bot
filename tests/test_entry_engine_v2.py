#!/usr/bin/env python3
"""Regression checks for the orderless ENTRY_ENGINE_V2 research pipeline."""
from __future__ import annotations

import sys
import unittest
from datetime import datetime, timedelta, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))

from build_entry_engine_v2_dataset import touch  # noqa: E402
from entry_engine_v2_common import FEATURES, bar_features  # noqa: E402


class EntryEngineV2Tests(unittest.TestCase):
    def test_requested_causal_feature_families_are_present(self) -> None:
        required = {
            "impulse_age_minutes", "impulse_age_m5_bars", "seconds_since_structural_break",
            "impulse_distance_m5_atr", "range_location", "expected_move_consumed_fraction",
            "m5_favorable_room_r", "m15_favorable_room_r", "session_room_r", "previous_day_room_r",
            "m1_displacement_5m_atr", "m1_acceleration_atr", "m1_body_fraction",
            "m1_directional_close_streak", "pullback_depth_m1_atr", "pullback_expanding",
            "pullback_resumption", "m1_direction", "m5_direction", "m15_direction", "h1_direction",
            "opposing_score", "opposing_score_rate_5m", "opposing_breakout", "score_dominance",
            "stop_m1_atr", "stop_m5_atr", "stop_inside_m1_noise", "confirmation_move_m5_atr",
            "cost_r", "cost_multiple", "broker_execution_cost_room_fraction", "entry_drift_m5_atr",
        }
        self.assertFalse(required - set(FEATURES))
        self.assertFalse({"mfe_r", "mae_r", "primary_label", "resolved_payoff_r"} & set(FEATURES))

    def test_forming_entry_minute_cannot_change_features(self) -> None:
        start = datetime(2026, 1, 1, tzinfo=timezone.utc)
        bars = []
        price = 100.0
        for index in range(400):
            opened = start + timedelta(minutes=index)
            close = price + (0.08 if index % 3 else -0.04)
            bars.append({"epoch": opened.timestamp(), "open": price, "high": max(price, close)+0.03,
                         "low": min(price, close)-0.03, "close": close})
            price = close
        at = (start + timedelta(minutes=399, seconds=30)).strftime("%Y.%m.%d %H:%M:%S")
        original = bar_features(bars, at, price, 1)
        bars[-1] = {"epoch": bars[-1]["epoch"], "open": -1000.0, "high": 9000.0,
                    "low": -9000.0, "close": 5000.0}
        self.assertEqual(original, bar_features(bars, at, price, 1))

    def test_partial_higher_timeframe_bucket_cannot_change_features(self) -> None:
        start = datetime(2026, 1, 1, tzinfo=timezone.utc)
        bars = []
        price = 100.0
        for index in range(405):
            opened = start + timedelta(minutes=index)
            close = price + (0.05 if index % 2 else -0.02)
            bars.append({"epoch": opened.timestamp(), "open": price, "high": max(price, close)+0.02,
                         "low": min(price, close)-0.02, "close": close})
            price = close
        at = (start + timedelta(minutes=404, seconds=30)).strftime("%Y.%m.%d %H:%M:%S")
        original = bar_features(bars, at, price, -1)
        # Minutes 400-403 are completed M1 bars, but their M5 bucket closes at
        # minute 405 and must not affect M5/M15-derived features.
        for index in range(400, 404):
            bars[index] = {"epoch": bars[index]["epoch"], "open": -1000.0, "high": 9000.0,
                           "low": -9000.0, "close": 5000.0}
        changed = bar_features(bars, at, price, -1)
        higher_timeframe = ("m5_displacement_15m_atr", "m5_acceleration_atr",
                            "seconds_since_structural_break", "impulse_age_m5_bars")
        self.assertEqual({k: original[k] for k in higher_timeframe},
                         {k: changed[k] for k in higher_timeframe})

    def test_outcome_targets_stop_accumulating_before_stop(self) -> None:
        record = {"samples": 0, "mfe_r": 0.0, "mae_r": 0.0, "mfe_before_stop_r": 0.0,
                  "mae_before_stop_r": 0.0, "maximum_continuation_after_plus_1_r": 0.0,
                  "maximum_tradable_continuation_after_plus_1_r": 0.0}
        for name in ("plus_0_5", "plus_1", "minus_0_5", "minus_1", "plus_2", "plus_3", "plus_5"):
            record["time_" + name] = None
        touch(record, "2026.01.01 00:01:00", 1.2)
        touch(record, "2026.01.01 00:02:00", -1.1)
        touch(record, "2026.01.01 00:03:00", 3.0)
        self.assertEqual("2026.01.01 00:01:00", record["time_plus_1"])
        self.assertEqual("2026.01.01 00:02:00", record["time_minus_1"])
        self.assertEqual(1.2, record["maximum_tradable_continuation_after_plus_1_r"])
        self.assertEqual(3.0, record["maximum_continuation_after_plus_1_r"])

    def test_development_trainer_has_no_holdout_input(self) -> None:
        text = (ROOT / "tools/train_entry_engine_v2_development.py").read_text()
        self.assertNotIn("fp-m1-forward-gate", text)
        self.assertNotIn("20260908", text)
        self.assertNotIn("all-three-live-damage", text)


if __name__ == "__main__":
    unittest.main()
