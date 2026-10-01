import csv
import tempfile
import unittest
from pathlib import Path

from tools.three_account_score_audit import analyze, correlation, label, load_trades, ranks


class ScoreAuditTest(unittest.TestCase):
    def test_fixed_bins_and_tied_rank_correlation(self):
        self.assertEqual(label(60), "60-62.5")
        self.assertEqual(label(62.5), "62.5-65")
        self.assertEqual(label(77.5), "77.5+")
        self.assertEqual(ranks([3, 1, 1, 2]), [4, 1.5, 1.5, 3])
        self.assertAlmostEqual(correlation([1, 2, 3], [3, 2, 1]), -1)

    def test_entry_exit_pairing_and_confirmed_bank(self):
        columns = ["schema", "utc", "event", "ticket", "symbol", "direction", "entry", "stop", "buy_case", "sell_case", "no_trade_case", "regime", "m1", "m5", "m15", "h1", "session", "previous_session", "levels", "available_move", "expected_cost_move", "expected_net_move", "spread", "setup_key", "detail"]
        base = dict.fromkeys(columns, "")
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "events.csv"
            rows = []
            rows.append(dict(base, utc="2026.09.14 10:00:00", event="ENTRY", ticket="123", symbol="EURUSD", direction="BUY", entry="1.1002", stop="1.0992", buy_case="score=70.00;M1=BULL_TREND", sell_case="score=45.00;M1=BULL_TREND", no_trade_case="score=12.00;admission_score=68.00;conflict=false", m1="BULL_TREND", m5="BULL_TREND", m15="RANGE_CHOP", h1="BEAR_TREND"))
            rows.append(dict(base, utc="2026.09.14 10:10:00", event="PARTIAL_BANK_1R", ticket="123"))
            rows.append(dict(base, utc="2026.09.14 11:00:00", event="EXIT", ticket="0", detail="position_id=123;final_total_r=0.50;net=50.00;exit_class=RUNNER_STRUCTURAL_EXIT;RUNNER_PEAK_R=2.5"))
            rows.append(dict(base, utc="2026.09.14 11:10:00", event="EXIT", ticket="0", detail="position_id=missing;final_total_r=-1;net=-100"))
            with path.open("w", newline="") as handle:
                writer = csv.DictWriter(handle, columns)
                writer.writeheader()
                writer.writerows(rows)
            trades, coverage = load_trades(path)
            self.assertEqual(len(trades), 1)
            self.assertEqual(coverage["unmatched_exit_position_ids"], ["missing"])
            self.assertTrue(trades[0]["bank1_confirmed"])
            self.assertEqual(trades[0]["no_trade_score"], 12)
            self.assertEqual(trades[0]["admission_score"], 68)
            self.assertEqual(trades[0]["final_r"], 0.5)
            result = analyze(trades, coverage)["cohorts"]["frozen_fp_manager_from_2026_09_13"]
            self.assertEqual(result["summary"]["confirmed_bank1r"], 1)
            self.assertEqual(result["timeframe_state"]["h1"]["OPPOSES"]["n"], 1)


if __name__ == "__main__":
    unittest.main()
