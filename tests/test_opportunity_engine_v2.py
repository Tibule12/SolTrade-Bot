#!/usr/bin/env python3
from __future__ import annotations

import sys
import unittest
import csv
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))

from opportunity_engine_v2_common import aggregate, structural_stop  # noqa: E402
from train_opportunity_engine_v2 import decision, directional  # noqa: E402


class OpportunityEngineV2Tests(unittest.TestCase):
    def test_partial_higher_timeframe_bucket_is_excluded(self) -> None:
        bars = [{"epoch": float(i * 60), "open": 100+i, "high": 101+i, "low": 99+i, "close": 100.5+i} for i in range(14)]
        complete = aggregate(bars, 5, 14 * 60)
        self.assertEqual([0.0, 300.0], [x["epoch"] for x in complete])

    def test_structural_stop_keeps_volatility_floor(self) -> None:
        m5 = [{"high": 101.0, "low": 99.0}] * 10
        m15 = [{"high": 102.0, "low": 98.0}] * 8
        long_stop, long_distance, _ = structural_stop(100.0, 1, .01, m5, m15, 2.0, 4.0, 1.0)
        short_stop, short_distance, _ = structural_stop(100.0, -1, .01, m5, m15, 2.0, 4.0, 1.0)
        self.assertGreaterEqual(long_distance, 2.3)
        self.assertGreaterEqual(short_distance, 2.3)
        self.assertLess(long_stop, 100.0)
        self.assertGreater(short_stop, 100.0)

    def test_directional_transform_mirrors_long_and_short(self) -> None:
        row = {name: "0" for name in (
            "event_direction trend_m1 trend_m5 trend_m15 trend_h1 path_efficiency_m5 path_efficiency_change impulse_m5_atr latest_impulse_direction impulse_age_m5 impulse_displacement_m5_atr recent_momentum_m5_atr acceleration_m5_atr volatility_expansion_m5 m1_body_atr m1_body_fraction m1_lower_wick_body m1_upper_wick_body up_close_streak down_close_streak breakout_up breakout_down failed_breakout_up failed_breakout_down bull_structure bear_structure pullback_resume_up pullback_resume_down pullback_depth_long pullback_depth_short pullback_progress_long pullback_progress_short breakout_retest_up breakout_retest_down opposing_pressure_signed_m1 rejection_up rejection_down range_location distance_high_m5_atr distance_low_m5_atr session_location previous_day_location long_room_r short_room_r long_stop_m1_atr short_stop_m1_atr long_stop_m5_atr short_stop_m5_atr long_invalidation_distance_m5_atr short_invalidation_distance_m5_atr spread_m1_atr cost_long_r cost_short_r compression_ratio_m1"
        ).split()}
        row.update({"event_direction":"1", "trend_m5":"2", "m1_body_atr":".4", "range_location":".8",
                    "long_room_r":"3", "short_room_r":"1", "long_stop_m1_atr":"4", "short_stop_m1_atr":"5",
                    "long_stop_m5_atr":"1.2", "short_stop_m5_atr":"1.3"})
        long, short = directional(row, 1), directional(row, -1)
        self.assertEqual(2.0, long["trend_m5_aligned"])
        self.assertEqual(-2.0, short["trend_m5_aligned"])
        self.assertAlmostEqual(.2, short["directional_range_location"])
        self.assertEqual(3.0, long["room_r"])
        self.assertEqual(1.0, short["room_r"])

    def test_enter_requires_direction_and_no_trade_separation(self) -> None:
        self.assertEqual("LONG", decision(.75, .30, .55, .12)[0])
        self.assertEqual("WAIT", decision(.60, .56, .55, .12)[0])
        self.assertEqual("REJECT", decision(.30, .25, .55, .12)[0])

    def test_development_trainer_has_no_holdout_input(self) -> None:
        text = (ROOT / "tools/train_opportunity_engine_v2.py").read_text()
        for token in ("fp-m1-forward-gate", "all-three-live-damage", "20260908", "20260915_GER40"):
            self.assertNotIn(token, text)

    def test_episode_windows_do_not_overlap_labels(self) -> None:
        from build_opportunity_engine_v2_universe import EPISODE_COOLDOWN, HORIZON
        self.assertGreaterEqual(EPISODE_COOLDOWN, HORIZON)

    def test_required_raw_context_is_explicit(self) -> None:
        text = (ROOT / "tools/opportunity_engine_v2_common.py").read_text()
        for name in ("latest_impulse", "impulse_displacement_m5_atr", "pullback_depth_long",
                     "pullback_progress_long", "breakout_retest_up", "opposing_pressure_signed_m1"):
            self.assertIn(name, text)

    def test_persisted_episodes_are_independent_and_pre_holdout(self) -> None:
        path = ROOT / "reports/fast-multi-market-v2/opportunity-engine-v2-raw-rebuild-20260915/opportunities.csv"
        last: dict[str, int] = {}
        cutoff = int(datetime(2026, 9, 8, tzinfo=timezone.utc).timestamp())
        with path.open(newline="", encoding="utf-8") as handle:
            for row in csv.DictReader(handle):
                stamp = int(datetime.strptime(row["causal_entry_utc"], "%Y.%m.%d %H:%M:%S").replace(tzinfo=timezone.utc).timestamp())
                self.assertLess(stamp, cutoff)
                if row["symbol"] in last:
                    self.assertGreaterEqual(stamp - last[row["symbol"]], 4 * 3600)
                last[row["symbol"]] = stamp
                for field in ("structure_context", "expiry_utc", "long_invalidation", "short_invalidation",
                              "long_primary_label", "short_primary_label"):
                    self.assertIn(field, row)


if __name__ == "__main__":
    unittest.main()
