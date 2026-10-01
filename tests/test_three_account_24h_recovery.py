import csv
import gzip
import tempfile
import unittest
from decimal import Decimal
from pathlib import Path

from tools.three_account_24h_recovery import evaluate_side


class TwentyFourHourQuoteRecoveryTests(unittest.TestCase):
    def path(self, rows):
        temporary = tempfile.TemporaryDirectory()
        file = Path(temporary.name) / "quotes.csv.gz"
        with gzip.open(file, "wt", newline="") as stream:
            writer = csv.writer(stream)
            writer.writerow(("time_msc", "bid", "ask"))
            writer.writerows(rows)
        self.addCleanup(temporary.cleanup)
        return file

    def test_opposite_path_continues_after_original_exit(self):
        # The original trade exited at 1_020; the opposite +1R arrives later.
        path = self.path([(999, "100", "101"), (1010, "99.8", "100.8"),
                          (1020, "99", "100"), (1030, "98", "99")])
        result = evaluate_side(path, 1000, -1, Decimal("100"), Decimal("1"), 1030)
        self.assertEqual(result["status"], "PLUS_1R_QUOTE_BOUNDARY")
        self.assertEqual(result["first_observed_boundary_msc"], 1030)

    def test_missing_market_interval_prevents_exact_boundary_order(self):
        path = self.path([(999, "100", "101"), (1010, "99.8", "100.8"),
                          (71011, "98", "99")])
        result = evaluate_side(path, 1000, -1, Decimal("100"), Decimal("1"), 72000)
        self.assertEqual(result["status"], "BOUNDARY_ORDER_UNRESOLVED_QUOTE_GAP")
        self.assertTrue(result["intervening_gap_over_60s"])

    def test_first_post_entry_quote_can_itself_be_stale(self):
        path = self.path([(999, "100", "101"), (62001, "98", "99")])
        result = evaluate_side(path, 1000, -1, Decimal("100"), Decimal("1"), 63000)
        self.assertEqual(result["status"], "BOUNDARY_ORDER_UNRESOLVED_QUOTE_GAP")


if __name__ == "__main__":
    unittest.main()
