import csv
import tempfile
import unittest
from decimal import Decimal
from pathlib import Path

from tools.three_account_fxify_events import (
    AUDIT,
    BASELINE,
    PAUSE,
    average_ranks,
    build,
    load_trades,
    pearson,
    reconcile_account,
    score_band,
    score_diagnostic,
)


class FXIFYEventDiagnosticTest(unittest.TestCase):
    def write_events(self, path, rows):
        columns = (
            "utc", "event", "ticket", "symbol", "direction", "buy_case",
            "sell_case", "no_trade_case", "detail",
        )
        with path.open("w", newline="", encoding="utf-8") as handle:
            writer = csv.DictWriter(handle, fieldnames=columns)
            writer.writeheader()
            writer.writerows(rows)

    def test_exit_position_id_and_recorded_score_only(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "events.csv"
            self.write_events(path, [
                {
                    "utc": "2026.09.14 10:00:00", "event": "ENTRY", "ticket": "123",
                    "symbol": "EURUSD.r", "direction": "BUY", "buy_case": "score=72.3",
                    "sell_case": "score=41.2", "no_trade_case": "score=12;admission_score=64.12",
                    "detail": "initial_risk=100.00;admission_score=64.1234",
                },
                {
                    "utc": "2026.09.14 11:00:00", "event": "EXIT", "ticket": "0",
                    "symbol": "EURUSD.r", "direction": "BUY", "buy_case": "", "sell_case": "",
                    "no_trade_case": "", "detail": "position_id=123;net=-50.00;banked_cash=-25.00;"
                    "partial_banking=false;exit_class=INITIAL_STRUCTURAL_STOP_EXIT;RUNNER_PEAK_R=0.75",
                },
            ])
            trades, coverage = load_trades(path, "7196820")
            self.assertEqual(coverage["matched_closed_positions"], 1)
            trade = trades[0]
            self.assertEqual(trade["position_id"], "123")
            self.assertEqual(trade["admission_score"], Decimal("64.1234"))
            self.assertEqual(trade["admission_score_source"], "ENTRY.detail")
            self.assertEqual(trade["net_r"], Decimal("-0.5"))
            self.assertFalse(trade["bank1_confirmed"])
            self.assertEqual(score_band(trade["admission_score"]), "62.5-65")
            self.assertIsNone(score_diagnostic(trades)["admission_score"]["pearson_score_vs_realized_net_r"])

    def test_missing_score_is_omitted_from_correlations_and_unmatched_exit_fails(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "events.csv"
            self.write_events(path, [
                {
                    "utc": "2026.09.14 10:00:00", "event": "ENTRY", "ticket": "1",
                    "symbol": "XAUUSD.r", "direction": "SELL", "buy_case": "score=20",
                    "sell_case": "score=70", "no_trade_case": "score=12",
                    "detail": "initial_risk=10",
                },
                {
                    "utc": "2026.09.14 11:00:00", "event": "EXIT", "ticket": "0",
                    "symbol": "XAUUSD.r", "direction": "SELL", "buy_case": "", "sell_case": "",
                    "no_trade_case": "", "detail": "position_id=1;net=5",
                },
            ])
            trades, _ = load_trades(path, "7198096")
            self.assertIsNone(trades[0]["admission_score"])
            self.assertEqual(score_diagnostic(trades)["admission_score"]["missing_n"], 1)
            self.write_events(path, [
                {
                    "utc": "2026.09.14 11:00:00", "event": "EXIT", "ticket": "0",
                    "symbol": "XAUUSD.r", "direction": "SELL", "buy_case": "", "sell_case": "",
                    "no_trade_case": "", "detail": "position_id=1;net=5",
                },
            ])
            with self.assertRaisesRegex(ValueError, "unmatched events"):
                load_trades(path, "7198096")

    def test_balance_bridge_posts_after_flat_anchor_and_marks_inception_unknown(self):
        trades = [
            {"position_id": "old", "entry_utc": "2026.09.01 09:00:00", "exit_utc": "2026.09.01 10:00:00", "net_usd": Decimal("2.00"), "symbol": "EURUSD.r", "bank1_confirmed": False},
            {"position_id": "new", "entry_utc": "2026.09.14 09:00:00", "exit_utc": "2026.09.14 10:00:00", "net_usd": Decimal("-50.00"), "symbol": "EURUSD.r", "bank1_confirmed": False},
        ]
        rec, path = reconcile_account(
            "fxify-10k", trades,
            {"account": 7196820, "equity": 10010.0, "positions": 0, "orders": 0},
            {"login": "7196820", "equity": "9960.00", "positions": "0", "orders": "0", "timestamp_utc": "2026.09.16 02:56:25"},
            "2026.09.13 07:23:58",
        )
        self.assertEqual(rec["post_baseline_recorded_net_usd"], "-50.00")
        self.assertEqual(rec["pause_reconciliation_gap_usd"], "0.00")
        self.assertEqual(rec["inception_arithmetic_gap_usd"], "8.00")
        self.assertIn("INCOMPLETE_HISTORY", rec["inception_status"])
        self.assertEqual(path[0]["balance_after_exit_usd"], "9960.00")
        self.assertAlmostEqual(pearson([1, 2, 3], [3, 2, 1]), -1.0)
        self.assertEqual(average_ranks([3, 1, 1, 2]), [4, 1.5, 1.5, 3])

    def test_preserved_fxify_anchors_and_score_coverage(self):
        evidence = {
            "fxify-10k": AUDIT / "fxify-10k-evidence.csv",
            "fxify-100k": AUDIT / "fxify-100k-evidence.csv",
        }
        report, trades, paths = build(evidence, BASELINE, PAUSE)
        expected = {
            "fxify-10k": ("-336.99", "-379.17", "9660.24", "-2.77"),
            "fxify-100k": ("-3594.40", "-3915.76", "96405.60", "0.00"),
        }
        for account_id, (all_net, post_net, paused, prior_gap) in expected.items():
            data = report["accounts"][account_id]
            rec = data["reconciliation"]
            self.assertEqual(len(trades[account_id]), 22)
            self.assertEqual(len(paths[account_id]), 4)
            self.assertEqual(data["coverage"]["entry_detail_admission_scores"], 22)
            self.assertEqual(data["cohorts"]["all_recorded_mixed_managers"]["summary"]["net_usd"], all_net)
            self.assertEqual(rec["post_baseline_recorded_net_usd"], post_net)
            self.assertEqual(rec["pause_flat_equity_usd"], paused)
            self.assertEqual(rec["inception_arithmetic_gap_usd"], prior_gap)
            self.assertTrue(rec["exact_ea_event_to_runtime_reconciliation"])


if __name__ == "__main__":
    unittest.main()
