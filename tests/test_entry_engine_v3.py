import csv
import tempfile
import unittest
from pathlib import Path

import numpy as np

from tools.entry_engine_v3.build_dataset import FEATURE_NAMES, RATCHETS, Source, build_episodes, whole_trade_ratchet
from tools.entry_engine_v3.common import utc_seconds
from tools.entry_engine_v3.state_machine import Estimate, State, TransitionMachine, ORDER_CAPABILITY


def feature_row(stamp: str, symbol: str = "EURUSD") -> dict[str, str]:
    state = "available=true;open=1;high=1.1;low=.9;close=1.05;atr14=.01;trend=1;structure=1;return_3bar=.01;vol_ratio=1;tick_volume=100"
    return {"observation_utc": stamp, "symbol": symbol, "completed_bars_only": "true", "order_capability": "false",
        "m1_completed_state": state, "m5_completed_state": state, "m15_completed_state": state, "h1_completed_state": state,
        "mid_change_30s": ".01", "rate_5s": "2", "rate_30s": "1", "quote_pressure_5s": "2"}


class EntryEngineV3Tests(unittest.TestCase):
    def test_utc_parser_is_timezone_independent(self):
        self.assertEqual(utc_seconds("2026.09.16 04:16:07"), 1789532167)
        self.assertEqual(utc_seconds("1789532167000"), 1789532167)

    def test_wait_episode_and_four_hour_independence(self):
        with tempfile.TemporaryDirectory() as name:
            folder = Path(name) / "features"; folder.mkdir()
            rows = [feature_row("2026.09.16 04:00:00"), feature_row("2026.09.16 04:00:15"),
                    feature_row("2026.09.16 04:16:00"), feature_row("2026.09.16 08:00:00")]
            with (folder / "x-features.csv").open("w", newline="") as f:
                writer = csv.DictWriter(f, fieldnames=list(rows[0])); writer.writeheader(); writer.writerows(rows)
            source = Source(Path(name))
            try: episodes = build_episodes(source)
            finally: source.close()
        self.assertEqual(len(episodes), 2)
        self.assertEqual(len(episodes[0].observations), 2)
        self.assertEqual(episodes[1].detected - episodes[0].detected, 4 * 3600)

    def test_whole_trade_guarantee_is_monotonic_and_bank1_unchanged(self):
        path = np.asarray([0, .5, 1.0, 2.0, 4.0, 2.0, .4])
        structural, _ = whole_trade_ratchet(path, ())
        balanced, guarantee = whole_trade_ratchet(path, RATCHETS["balanced"])
        self.assertAlmostEqual(structural, .7)
        self.assertEqual(balanced, guarantee)
        self.assertEqual(guarantee, .75)

    def test_ratchet_does_not_reenter_after_structural_stop(self):
        path=np.asarray([0,1.0,-1.0,8.0])
        result,guarantee=whole_trade_ratchet(path,RATCHETS["balanced"])
        self.assertEqual(result,0.0)
        self.assertEqual(guarantee,0.0)

    def test_model_manifest_has_no_identity_or_future_fields(self):
        forbidden = {"symbol", "direction", "mfe_r", "mae_r", "bank1", "full_loss", "terminal_r",
                     "buy_score", "sell_score", "admission_score", "no_trade_score"}
        self.assertFalse(forbidden.intersection(FEATURE_NAMES))
        self.assertIn("current_r_from_detection", FEATURE_NAMES)
        self.assertIn("m5_trend_age_seconds", FEATURE_NAMES)
        self.assertIn("m5_impulse_displacement_atr_aligned", FEATURE_NAMES)
        self.assertIn("remaining_room_m15_r", FEATURE_NAMES)
        self.assertIn("bid_change_from_detection_atr_aligned", FEATURE_NAMES)

    def test_transition_state_machine_waits_then_enters_or_abandons(self):
        machine=TransitionMachine(100,1000,.1,.45,.35,.05)
        self.assertEqual(machine.detect(100),State.WAIT_FOR_TRANSITION)
        weak=Estimate("LONG",.05,.40,.50,.01)
        self.assertEqual(machine.observe(200,weak),State.WAIT_FOR_TRANSITION)
        strong=Estimate("LONG",.25,.30,.55,.10)
        self.assertEqual(machine.observe(300,strong),State.ENTRY_TRIGGERED)
        expired=TransitionMachine(100,1000,.1,.45,.35,.05);expired.detect(100)
        self.assertEqual(expired.expire(1000),State.OPPORTUNITY_ABANDONED)
        self.assertFalse(ORDER_CAPABILITY)


if __name__ == "__main__": unittest.main()
