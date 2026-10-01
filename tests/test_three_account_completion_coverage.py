"""Coverage joins must retain all unresolved inversion rows."""

from __future__ import annotations

import csv
import unittest
from pathlib import Path

from tools.three_account_completion.fp_coverage import build_coverage
from tools.three_account_completion.fp_loss_table import native_initial_boundary
from decimal import Decimal


ROOT = Path(__file__).resolve().parents[1]
REPORT = ROOT / "reports/fast-multi-market-v2/three-account-replay-completion-20261001"


def quote(pid: str = "P") -> dict[str, str]:
    return {
        "account": "FP 7404213", "position_id": pid, "symbol": "XAUUSD.r",
        "actual_direction": "SELL", "opposite_direction": "BUY",
        "actual_final_cash": "-990", "actual_final_r": "-1",
        "entry_anchor_status": "FRESH_QUOTE_WITHIN_2S", "export_error": "0",
        "24h_window_elapsed_at_export": "True",
        "opposite_mirrored_status": "PLUS_1R_QUOTE_BOUNDARY",
        "opposite_mirrored_first_observed_boundary_msc": "1000",
        "opposite_mirrored_intervening_gap_over_60s": "False",
    }


def native(pid: str = "P") -> dict[str, str]:
    return {
        "account": "FP 7404213", "position_id": pid, "symbol": "XAUUSD.r",
        "is_fourteen_stop_loss": "true", "native_opposite_status": "NATIVE_STRUCTURE_DIAGNOSTIC_ONLY",
        "historical_broker_floor_available": "false", "exact_native_stop_price": "",
        "unresolved_reason": "Historical stop/freeze level absent",
    }


class CompletionCoverageTests(unittest.TestCase):
    def test_native_boundary_does_not_accept_stale_first_post_entry_quote(self) -> None:
        status, *_ = native_initial_boundary(
            [(61_000, Decimal("101"), Decimal("101.1"))],
            entry_msc=0, end_msc=100_000,
            entry_price=Decimal("100"), stop_price=Decimal("99"),
            direction="BUY", window_complete=True,
        )
        self.assertEqual(status, "BOUNDARY_ORDER_UNRESOLVED_QUOTE_GAP")

    def test_mirrored_plus_one_does_not_become_final_profit(self) -> None:
        rows, receipt = build_coverage([quote()], [native()])
        self.assertEqual(receipt["initial_stop_loss_mirrored_quote_boundary_counts"],
                         {"PLUS_1R_QUOTE_BOUNDARY": 1})
        self.assertEqual(rows[0]["opposite_exact_status"], "UNRESOLVED_NATIVE_STOP")
        self.assertEqual(rows[0]["opposite_exact_final_cash"], "")
        self.assertEqual(rows[0]["opposite_exact_final_r"], "")

    def test_native_stop_alone_still_needs_manager_and_execution(self) -> None:
        n = native()
        n.update(native_opposite_status="NATIVE_OPPOSITE_STRUCTURE_RECONSTRUCTED",
                 historical_broker_floor_available="true", exact_native_stop_price="101.2")
        rows, receipt = build_coverage([quote()], [n])
        self.assertEqual(receipt["native_stop_exact_count"], 1)
        self.assertEqual(rows[0]["opposite_exact_status"], "UNRESOLVED_MANAGER_AND_EXECUTION")
        self.assertEqual(rows[0]["opposite_exact_final_cash"], "")

    def test_missing_entry_quote_is_broker_history_gap(self) -> None:
        q = quote()
        q["entry_anchor_status"] = "UNRESOLVED_BROKER_HISTORY_OR_STOP"
        rows, _ = build_coverage([q], [native()])
        self.assertEqual(rows[0]["opposite_exact_status"], "UNRESOLVED_BROKER_HISTORY")

    def test_24_hour_incomplete_is_right_censored_when_other_evidence_exists(self) -> None:
        q = quote()
        q["24h_window_elapsed_at_export"] = "False"
        n = native()
        n.update(native_opposite_status="NATIVE_OPPOSITE_STRUCTURE_RECONSTRUCTED",
                 historical_broker_floor_available="true", exact_native_stop_price="101.2")
        rows, _ = build_coverage([q], [n])
        self.assertEqual(rows[0]["opposite_exact_status"], "RIGHT_CENSORED")

    def test_live_receipt_retains_every_fp_row_and_fourteen_losses(self) -> None:
        quotes_path = REPORT / "fp-24h-opposite-paths.csv"
        native_path = REPORT / "native-opposite/native-opposite-stops.csv"
        if not (quotes_path.exists() and native_path.exists()):
            self.skipTest("Read-only broker exports not present in this checkout")
        with quotes_path.open(newline="", encoding="utf-8") as handle:
            q = list(csv.DictReader(handle))
        with native_path.open(newline="", encoding="utf-8") as handle:
            n = list(csv.DictReader(handle))
        rows, receipt = build_coverage(q, n)
        self.assertEqual(receipt["all_actual_entries"], 29)
        self.assertEqual(receipt["initial_stop_loss_entries"], 14)
        self.assertEqual(len(rows), 29)
        self.assertTrue(all(row["opposite_exact_final_cash"] == "" for row in rows))


if __name__ == "__main__":
    unittest.main()
