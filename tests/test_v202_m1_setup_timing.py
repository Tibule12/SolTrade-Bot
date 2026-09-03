import unittest
from datetime import datetime, timedelta

from tools.audit_v202_m1_setup_timing import decisions, feature_set


class V202M1SetupTimingTests(unittest.TestCase):
    def _bars(self, entry):
        start = entry.replace(second=0) - timedelta(minutes=180)
        bars = []
        price = 100.0
        for index in range(211):
            opened = price
            closed = opened + (0.04 if index % 3 else -0.01)
            bars.append({
                "time": start + timedelta(minutes=index),
                "open": opened,
                "high": max(opened, closed) + 0.02,
                "low": min(opened, closed) - 0.02,
                "close": closed,
            })
            price = closed
        return bars

    def test_feature_cutoff_ignores_current_and_future_bars(self):
        entry = datetime(2026, 9, 3, 10, 0, 30)
        bars = self._bars(entry)
        baseline = feature_set(bars, entry, 1, "STRUCTURE_INSIDE")
        for bar in bars:
            if bar["time"] >= entry.replace(second=0):
                bar.update(open=1.0, high=10000.0, low=-10000.0, close=9999.0)
        changed_future = feature_set(bars, entry, 1, "STRUCTURE_INSIDE")
        self.assertEqual(baseline, changed_future)

    def test_setup_family_rules_are_distinct(self):
        base = {
            "trend_m1": 1.0,
            "path_efficiency_m1": 0.5,
            "last_bar_directional": False,
            "three_bar_directional": False,
            "reclaim_confirmed": False,
            "breakout_retained": False,
        }
        self.assertFalse(decisions({**base, "family": "CONTINUATION"})["SETUP_FAMILY_TIMING_V1"])
        self.assertTrue(decisions({**base, "family": "CONTINUATION", "three_bar_directional": True})["SETUP_FAMILY_TIMING_V1"])
        self.assertTrue(decisions({**base, "family": "PULLBACK_REVERSAL", "reclaim_confirmed": True})["SETUP_FAMILY_TIMING_V1"])
        self.assertTrue(decisions({**base, "family": "BREAKOUT", "breakout_retained": True})["SETUP_FAMILY_TIMING_V1"])


if __name__ == "__main__":
    unittest.main()
