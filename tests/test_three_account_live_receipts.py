import csv
import json
import re
import unittest
from datetime import datetime, timezone
from decimal import Decimal
from pathlib import Path

from tools.three_account_replay.engine import read_native_deals, replay_account_path

ROOT = Path(__file__).resolve().parents[1]
BASE = ROOT / "reports/fast-multi-market-v2/three-account-replay-20261001"


class LiveEvidenceReceiptTests(unittest.TestCase):
    def test_fresh_fp_broker_baseline_and_all_event_cash_matches(self):
        deals = read_native_deals(BASE / "broker-refresh-fp/deals.csv", server_utc_offset_minutes=180)
        replay = replay_account_path(deals, opening_balance=0, opening_flat_confirmed=True)
        self.assertEqual(len(deals), 218)
        self.assertEqual(replay.final_balance, Decimal("93712.18"))
        self.assertEqual(replay.open_positions, ())
        self.assertEqual(replay.issues, ())
        at = int(datetime(2026, 9, 30, 17, 59, tzinfo=timezone.utc).timestamp() * 1000)
        point = [p for p in replay.points if p.time_msc <= at][-1]
        self.assertEqual(point.balance, Decimal("94456.60"))
        self.assertEqual([p.position_id for p in point.positions], ["408708254"])
        receipt = json.loads((BASE / "fp-broker-reconciliation.json").read_text())
        self.assertIn("60", json.dumps(receipt))
        with (BASE / "fp-broker-position-ledger.csv").open(newline="") as handle:
            positions = list(csv.DictReader(handle))
        self.assertEqual(len(positions), 103)
        self.assertEqual(sum(p["two_close_deals"] == "True" for p in positions), 11)

    def test_tick_exports_complete_and_frozen_account_bridges(self):
        for name, expected in (("fp-entry-window-export/path-coverage-three-account-entry-windows.csv", 29),
                               ("fp-lifetime-export/path-coverage-three-account-lifetime.csv", 29)):
            with (BASE / name).open(newline="") as handle:
                coverage = list(csv.DictReader(handle))
            self.assertEqual(len(coverage), expected)
            self.assertTrue(all(row["error"] == "0" and int(row["ticks"]) > 0 for row in coverage))
        fx = json.loads((BASE / "fxify-event-diagnostic.json").read_text())
        for key, final_balance in (("fxify-10k", "9660.24"), ("fxify-100k", "96405.60")):
            account = fx["accounts"][key]
            self.assertEqual(account["coverage"]["matched_closed_positions"], 22)
            self.assertIn(final_balance, json.dumps(account["reconciliation"]))

    def test_new_research_and_broker_probe_have_no_order_api(self):
        paths = list((ROOT / "tools/three_account_replay").glob("*.py"))
        paths += list((ROOT / "tools").glob("three_account_*.py"))
        paths += [ROOT / "tools/run_three_account_baseline.py",
                  BASE / "broker-refresh-fp/SolTradeFPAllSymbolAudit.mq5"]
        forbidden = re.compile(r"\b(?:OrderSend|OrderSendAsync|PositionClose|CTrade|MqlTradeRequest)\s*\(")
        for path in paths:
            with self.subTest(path=path):
                self.assertIsNone(forbidden.search(path.read_text()), path)

    def test_incomplete_counterfactual_arms_remain_null(self):
        with (BASE / "account-arm-matrix.csv").open(newline="") as handle:
            rows = list(csv.DictReader(handle))
        self.assertEqual(len(rows), 73)
        self.assertEqual({r["account"] for r in rows},
                         {"FP 7404213", "FXIFY 7196820", "FXIFY 7198096"})
        for row in rows:
            if row["status"] == "UNRESOLVED_EXACT_ACCOUNT_PATH":
                self.assertEqual(row["net_cash"], "")
                self.assertEqual(row["net_r"], "")
                self.assertEqual(row["counterfactual_final_balance"], "")
                self.assertTrue(row["missing_for_exact_path"])

    def test_quote_gaps_are_disclosed_and_august_pilot_bridge_is_separate(self):
        quote = json.loads((BASE / "fp-quote-continuity.json").read_text())
        self.assertEqual(quote["totals"]["positions"], 29)
        self.assertEqual(quote["totals"]["ticks"], 215215)
        self.assertEqual(quote["totals"]["nonmonotonic_intervals"], 0)
        self.assertEqual(len(quote["totals"]["positions_with_gap_over_30min"]), 3)
        august = json.loads((BASE / "fxify-august-pilot-bridge.json").read_text())
        self.assertFalse(august["historical_broker_confirmation"])
        self.assertEqual(sum(Decimal(r["recorded_actual_net_usd"])
                             for r in august["closed_records"]), Decimal("-2.77"))


if __name__ == "__main__":
    unittest.main()
