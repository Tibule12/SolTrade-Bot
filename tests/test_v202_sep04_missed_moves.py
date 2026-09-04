from datetime import datetime
import unittest

from tools.audit_v202_sep04_missed_moves import observed_path


class MissedMoveAuditTests(unittest.TestCase):
    def test_buy_counts_half_r_before_stop(self) -> None:
        path = [
            (datetime(2026, 9, 4, 1, 0, 10), 100.6, 100.7),
            (datetime(2026, 9, 4, 1, 0, 20), 98.9, 99.0),
        ]
        result = observed_path("BUY", 100.0, 1.0, path)
        self.assertTrue(result["reached_0_5r_before_stop"])
        self.assertEqual(result["observed_stop_utc"], "2026.09.04 01:00:20")

    def test_sell_stops_before_later_profit(self) -> None:
        path = [
            (datetime(2026, 9, 4, 1, 0, 10), 101.0, 101.1),
            (datetime(2026, 9, 4, 1, 0, 20), 98.0, 98.1),
        ]
        result = observed_path("SELL", 100.0, 1.0, path)
        self.assertFalse(result["reached_0_5r_before_stop"])
        self.assertEqual(result["observed_stop_utc"], "2026.09.04 01:00:10")


if __name__ == "__main__":
    unittest.main()
