import csv
import tempfile
import unittest
from pathlib import Path

from tools.build_three_account_tick_requests import build
from tools.three_account_first_move import first_move
from tools.three_account_management_diagnostic import find_floor_hit
from tools.three_account_inversion_boundary import first_boundary
from tools.three_account_current_flow import classify
from tools.three_account_timing_matrix import choose_quote


class QuoteDiagnosticTest(unittest.TestCase):
    def test_first_move_uses_pre_entry_anchor_and_direction(self):
        quotes = [
            {"ms": 9_999, "bid": 99.9, "ask": 100.1},
            {"ms": 10_100, "bid": 99.8, "ask": 100.0},
            {"ms": 10_200, "bid": 100.0, "ask": 100.2},
        ]
        buy = first_move(quotes, 10_000, "BUY", 5)
        sell = first_move(quotes, 10_000, "SELL", 5)
        self.assertEqual(buy["first_direction"], "AGAINST_ENTRY")
        self.assertEqual(sell["first_direction"], "WITH_ENTRY")
        self.assertEqual(buy["first_move_ms"], 100)
        self.assertEqual(first_move(quotes[1:], 10_000, "BUY", 5)["status"], "NO_FRESH_ENTRY_QUOTE")

    def test_half_r_floor_and_post_bank_are_separate(self):
        quotes = [
            {"ms": 1_001, "bid": 100.5, "ask": 100.7},
            {"ms": 1_002, "bid": 100.0, "ask": 100.2},
            {"ms": 1_003, "bid": 101.0, "ask": 101.2},
            {"ms": 1_005, "bid": 99.9, "ask": 100.1},
        ]
        arm, half_hit, post_bank = find_floor_hit(quotes, 1_000, 1_006, 1_004, 1, 100, 1)
        self.assertEqual(arm, 1_001)
        self.assertEqual(half_hit[0], 1_002)
        self.assertEqual(post_bank[0], 1_005)

    def test_opposite_boundary_does_not_turn_censoring_into_profit(self):
        quotes = [
            {"ms": 2_001, "bid": 99.8, "ask": 100.0},
            {"ms": 2_002, "bid": 98.8, "ask": 99.0},
        ]
        normal = first_boundary(quotes, 2_000, 1, 100, 1, 2_002)
        inverted = first_boundary(quotes, 2_000, -1, 99.8, 1, 2_002)
        self.assertEqual(normal[0], "INITIAL_STOP_BOUNDARY")
        self.assertEqual(inverted[0], "RIGHT_CENSORED_AT_ACTUAL_EXIT")

    def test_request_builder_excludes_unclosed_and_preserves_server_clock(self):
        fields = ["position_id", "entry", "time_server", "symbol"]
        with tempfile.TemporaryDirectory() as directory:
            source, target = Path(directory) / "deals.csv", Path(directory) / "requests.csv"
            with source.open("w", newline="") as handle:
                writer = csv.DictWriter(handle, fieldnames=fields)
                writer.writeheader()
                writer.writerows([
                    dict(position_id="1", entry="0", time_server="2026.09.14 10:00:00", symbol="EURUSD"),
                    dict(position_id="1", entry="1", time_server="2026.09.14 11:00:00", symbol="EURUSD"),
                    dict(position_id="2", entry="0", time_server="2026.09.14 10:00:00", symbol="GBPUSD"),
                ])
            self.assertEqual(build(source, target, "baseline_lifetime"), 1)
            with target.open() as handle:
                row = list(csv.DictReader(handle))[0]
            self.assertEqual(row["from"], "2026.09.14 09:59:00")
            self.assertEqual(row["to"], "2026.09.14 11:01:00")

    def test_flow_uses_only_quotes_at_or_before_execution(self):
        # The large later up-tick must not change the pre-entry classification.
        rows = [{"ms": 1_000 + 500 * i, "bid": 100 - 0.1 * i,
                 "ask": 100.2 - 0.1 * i} for i in range(10)]
        before = classify(rows, 5_500)
        after = classify(rows + [{"ms": 5_501, "bid": 200, "ask": 200.2}], 5_500)
        self.assertEqual(before, after)
        self.assertEqual(before["flow"], "SHORT")
        self.assertEqual(choose_quote(rows, 5_600), None)


if __name__ == "__main__":
    unittest.main()
