import sys
import unittest
from datetime import datetime, timedelta
from pathlib import Path
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "tools"))
from analyze_gold_weekend_expanded import evaluate, signals, entry_indices, session_endpoint
from measure_gold_precontinuation import measure


class GoldWeekendExpandedTests(unittest.TestCase):
    def bars(self, count=241, start=datetime(2026, 10, 5, 1)):
        return [(start+timedelta(minutes=i), 100.0, 100.0, 100.0, 100.0, .1) for i in range(count)]

    def test_m1_stays_primary_when_day_disagrees(self):
        friday = self.bars(240, datetime(2026, 10, 2, 20))
        friday[0] = (friday[0][0], 110.0, 110.0, 110.0, 110.0, .1)
        friday[-1] = (friday[-1][0], 99.0, 101.0, 99.0, 100.0, .1)
        found, _ = signals(friday, 20.0)
        self.assertEqual(found["M1"], "BUY")
        self.assertEqual(found["FRIDAY"], "SELL")

    def test_same_bar_threshold_is_ambiguous(self):
        monday = self.bars()
        monday[1] = (monday[1][0], 100.0, 106.0, 94.0, 100.0, .1)
        self.assertEqual(evaluate(monday, "BUY", 0)["barrier_5"], "AMBIGUOUS_SAME_BAR")

    def test_missing_four_hour_path_is_censored(self):
        monday = self.bars(120)
        result = evaluate(monday, "BUY", 0)
        self.assertEqual(result["barrier_5"], "CENSORED")
        self.assertIsNone(result["return_240m"])

    def test_later_entry_uses_fresh_bar(self):
        monday = self.bars()
        selected = entry_indices(monday, "BUY")
        self.assertEqual(selected["REOPEN"], 0)
        self.assertEqual(selected["AFTER_15M"], 15)
        self.assertEqual(selected["AFTER_30M"], 30)

    def test_monday_new_york_close_can_require_tuesday_broker_bars(self):
        path = self.bars(27*60)
        monday_last = next(i for i, b in enumerate(path) if b[0].date() > path[0][0].date())-1
        result = evaluate(path, "BUY", 0, monday_last)
        self.assertIsNotNone(result["return_LONDON"])
        self.assertIsNotNone(result["return_NY"])
        self.assertIsNotNone(result["return_FULL_MONDAY"])

    def test_session_close_never_uses_stale_or_future_quote(self):
        bars = self.bars(2)
        target = bars[-1][0]+timedelta(minutes=10)
        self.assertIsNone(session_endpoint(bars,0,target))
        self.assertEqual(session_endpoint(bars,0,bars[-1][0]),1)

    def test_exporter_has_no_order_api(self):
        source = (Path(__file__).resolve().parents[1] / "tools/mql/SolTradeGoldWeekendReadOnly.mq5").read_text()
        for token in ("OrderSend(", "OrderSendAsync(", "CTrade", "PositionClose(", "#include <Trade"):
            self.assertNotIn(token, source)

    def test_precontinuation_mae_excludes_unknown_boundary_bar_order(self):
        monday = self.bars(3)
        monday[1] = (monday[1][0], 100, 100, 98, 100, .1)
        monday[2] = (monday[2][0], 100, 106, 90, 100, .1)
        receipt = {"monday":"2026-10-05", "signals":{"M1":"BUY"},
                   "paths":{"BUY":{"REOPEN":{"entry_price_estimate":100.1,
                    "barrier_5":"FAVORABLE_FIRST","barrier_10":"NEITHER","barrier_20":"NEITHER"}}}}
        with patch("measure_gold_precontinuation.load",return_value=({monday[0][0].date():monday},{},{})):
            result = measure(Path("unused"),[receipt])
        self.assertAlmostEqual(result["5"]["median_prior_adverse_usd"],2.1)


if __name__ == "__main__":
    unittest.main()
