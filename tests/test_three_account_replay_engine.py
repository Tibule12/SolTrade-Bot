"""Synthetic causal/accounting checks for the read-only three-account engine."""

from __future__ import annotations

import csv
import tempfile
import unittest
from decimal import Decimal as D
from pathlib import Path

from tools.three_account_replay import (
    CashReplacement, Deal, EquitySample, RiskMark, read_native_deals,
    replay_account_path, replay_cash_counterfactual,
)


def deal(ticket: int, time: int, pid: str = "0", *, symbol: str = "",
         entry: int = 0, type: int = 2, volume: str = "0", price: str = "0",
         profit: str = "0", commission: str = "0", swap: str = "0",
         fee: str = "0") -> Deal:
    return Deal(str(ticket), pid, time, symbol, entry, type, D(volume), D(price),
                D(profit), D(commission), D(swap), D(fee))


class AccountReplayTests(unittest.TestCase):
    def test_interleaved_partial_closes_preserve_all_cash_components_and_risk(self) -> None:
        rows = [
            deal(1, 1000, profit="1000"),
            deal(2, 2000, "A", symbol="XAUUSD", type=0, volume="1", price="100", commission="-2"),
            deal(3, 2100, "B", symbol="EURUSD", type=1, volume="0.5", price="1.1", commission="-1"),
            deal(4, 3000, "A", symbol="XAUUSD", entry=1, type=1, volume="0.4", price="102",
                 profit="60", commission="-0.5", swap="-0.25", fee="-0.1"),
            deal(5, 3300, "B", symbol="EURUSD", entry=1, type=0, volume="0.5", price="1.2",
                 profit="-30", commission="-0.5"),
            deal(6, 3400, "A", symbol="XAUUSD", entry=1, type=1, volume="0.6", price="101",
                 profit="-10", commission="-0.5", swap="-0.25", fee="-0.1"),
        ]
        sample = EquitySample(3200, D("1040"), D("1056.15"), "observed-equity")
        result = replay_account_path(
            rows, opening_balance="0", opening_flat_confirmed=True,
            risk_by_entry_ticket={"2": "100", "3": "50"},
            risk_marks=[RiskMark(3100, "A", D("20"), "broker-stop-snapshot")],
            equity_samples=[sample],
        )
        by_ref = {point.reference: point for point in result.points}
        self.assertEqual(by_ref["1"].balance, D("1000"))
        self.assertEqual(by_ref["2"].balance, D("998"))
        self.assertEqual(by_ref["3"].total_risk, D("150"))
        self.assertEqual(by_ref["4"].balance, D("1056.15"))
        self.assertEqual(by_ref["4"].positions[0].volume, D("0.6"))
        self.assertEqual(by_ref["4"].total_risk, D("110"))
        self.assertEqual(by_ref["observed-equity"].equity, D("1040"))
        self.assertEqual(by_ref["observed-equity"].balance_reconciliation_delta, D("0.00"))
        self.assertEqual(by_ref["observed-equity"].total_risk, D("70"))
        self.assertEqual(result.final_balance, D("1014.80"))
        self.assertEqual(result.points[-1].trade_gross_profit, D("20"))
        self.assertEqual(result.points[-1].commission, D("-4.5"))
        self.assertEqual(result.points[-1].swap, D("-0.50"))
        self.assertEqual(result.points[-1].fee, D("-0.2"))
        self.assertEqual(result.points[-1].nontrade_cashflow, D("1000"))
        self.assertEqual(result.position_status, "RECONSTRUCTED")
        self.assertEqual(result.risk_status, "FLAT_ZERO")
        self.assertIn("STOP_AND_RISK_CHANGES_BETWEEN_OBSERVATIONS", result.unresolved_dependencies)
        self.assertFalse(result.open_positions)
        self.assertFalse(result.issues)

    def test_same_millisecond_uses_ticket_order_and_entry_fee_once(self) -> None:
        rows = [
            deal(12, 1000, "P", symbol="US100", entry=1, type=1,
                 volume="1", profit="10", commission="-1"),
            deal(11, 1000, "P", symbol="US100", type=0,
                 volume="1", commission="-2"),
        ]
        result = replay_account_path(rows, opening_balance="100", opening_flat_confirmed=True)
        self.assertEqual([p.reference for p in result.points], ["11", "12"])
        self.assertEqual([p.balance for p in result.points], [D("98"), D("107")])
        self.assertEqual(result.points[-1].commission, D("-3"))
        self.assertEqual(result.position_status, "RECONSTRUCTED")

    def test_missing_entry_and_unverified_opening_do_not_fabricate_flat_book(self) -> None:
        orphan_exit = deal(2, 2000, "P", symbol="GER40", entry=1, type=0,
                           volume="1", profit="-8", swap="-1")
        result = replay_account_path([orphan_exit], opening_balance="500",
                                     opening_flat_confirmed=False)
        self.assertEqual(result.final_balance, D("491"))
        self.assertIsNone(result.points[-1].position_count)
        self.assertIsNone(result.points[-1].total_risk)
        self.assertEqual(result.position_status, "UNRESOLVED")
        self.assertIn("OPENING_POSITION_BOOK_UNVERIFIED", result.issues)
        self.assertIn("EXIT_WITHOUT_ENTRY:2", result.issues)

    def test_netting_reversal_keeps_cash_and_residual_but_censors_risk(self) -> None:
        rows = [
            deal(1, 1000, "P", symbol="XAUUSD", type=0, volume="2", price="100"),
            deal(2, 2000, "P", symbol="XAUUSD", entry=2, type=1,
                 volume="3", price="99", profit="-20", commission="-2"),
        ]
        result = replay_account_path(rows, opening_balance="1000",
                                     opening_flat_confirmed=True,
                                     risk_by_entry_ticket={"1": "100"})
        self.assertEqual(result.final_balance, D("978"))
        self.assertEqual(result.open_positions[0].direction, "SELL")
        self.assertEqual(result.open_positions[0].volume, D("1"))
        self.assertIsNone(result.points[-1].total_risk)
        self.assertIn("REVERSAL_RISK_UNRESOLVED:2", result.issues)

    def test_equity_mismatch_is_explicit_and_never_interpolated(self) -> None:
        rows = [deal(1, 1000, profit="1000")]
        result = replay_account_path(
            rows, opening_balance="0", opening_flat_confirmed=True,
            equity_samples=[EquitySample(2000, D("975"), D("999"), "terminal")],
        )
        self.assertIsNone(result.points[0].equity)
        self.assertEqual(result.points[1].equity, D("975"))
        self.assertEqual(result.points[1].balance_reconciliation_delta, D("-1"))
        self.assertIn("BALANCE_RECONCILIATION_MISMATCH:terminal", result.issues)
        self.assertIn("UNOBSERVED_INTRASAMPLE_EQUITY", result.unresolved_dependencies)

    def test_conditional_cash_change_cannot_claim_quote_or_broker_path(self) -> None:
        rows = [
            deal(1, 1000, "P", symbol="XAUUSD", type=0, volume="1", commission="-3"),
            deal(2, 2000, "P", symbol="XAUUSD", entry=1, type=1,
                 volume="1", profit="-100", swap="-2"),
        ]
        changed = replay_cash_counterfactual(
            rows, [CashReplacement("2", D("-40"), D("-1"), D("-2"), D("0"),
                                   "independent-fill-123")],
            opening_balance="1000", opening_flat_confirmed=True,
        )
        self.assertEqual(changed.final_balance, D("954"))
        self.assertEqual(changed.scenario_status, "CONDITIONAL_ACCOUNTING_ONLY")
        self.assertEqual(changed.changed_tickets, ("2",))
        self.assertEqual(changed.replacement_evidence, (("2", "independent-fill-123"),))
        self.assertEqual(changed.equity_status, "UNOBSERVED_COUNTERFACTUAL")
        self.assertIn("ALTERNATIVE_EXIT_FILL_REQUIRES_BID_ASK_PATH", changed.unresolved_dependencies)
        with self.assertRaisesRegex(ValueError, "evidence reference"):
            replay_cash_counterfactual(rows, [CashReplacement("2", D("0"), D("0"), D("0"), D("0"), "")],
                                       opening_balance=1000, opening_flat_confirmed=True)

    def test_account_replays_are_isolated(self) -> None:
        deposits = {"FP": "100000", "F10": "10000", "F100": "100000"}
        losses = {"FP": "-900", "F10": "-250", "F100": "-1700"}
        paths = {}
        for account in deposits:
            rows = [deal(1, 1000, profit=deposits[account]),
                    deal(2, 2000, "P", symbol="XAUUSD", type=0, volume="1", commission="-5"),
                    deal(3, 3000, "P", symbol="XAUUSD", entry=1, type=1,
                         volume="1", profit=losses[account], swap="-2")]
            paths[account] = replay_account_path(rows, opening_balance=0,
                                                 opening_flat_confirmed=True)
        self.assertEqual({name: path.final_balance for name, path in paths.items()},
                         {"FP": D("99093"), "F10": D("9743"), "F100": D("98293")})
        self.assertTrue(all(path.position_status == "RECONSTRUCTED" for path in paths.values()))

    def test_csv_rejects_missing_or_nonfinite_money(self) -> None:
        fields = ["ticket", "position_id", "time_server", "time_msc", "symbol", "entry", "type",
                  "volume", "price", "profit", "commission", "swap", "fee"]
        row = dict.fromkeys(fields, "0")
        row.update(ticket="1", time_msc="1000", time_server="1970.01.01 00:00:01", profit="NaN")
        with tempfile.TemporaryDirectory() as temp:
            path = Path(temp) / "deals.csv"
            with path.open("w", newline="") as handle:
                writer = csv.DictWriter(handle, fieldnames=fields)
                writer.writeheader()
                writer.writerow(row)
            with self.assertRaisesRegex(ValueError, "finite decimal"):
                read_native_deals(path, server_utc_offset_minutes=0)

    def test_broker_server_clock_needs_explicit_offset(self) -> None:
        fields = ["ticket", "position_id", "time_server", "time_msc", "symbol", "entry", "type",
                  "volume", "price", "profit", "commission", "swap", "fee"]
        row = dict.fromkeys(fields, "0")
        row.update(ticket="291239948", position_id="408708254",
                   time_server="2026.09.30 18:41:30", time_msc="1790793690430",
                   symbol="GER40", type="1", volume="18.63", price="25209.75")
        with tempfile.TemporaryDirectory() as temp:
            path = Path(temp) / "deals.csv"
            with path.open("w", newline="") as handle:
                writer = csv.DictWriter(handle, fieldnames=fields)
                writer.writeheader()
                writer.writerow(row)
            with self.assertRaises(TypeError):
                read_native_deals(path)
            parsed = read_native_deals(path, server_utc_offset_minutes=180)
        self.assertEqual(parsed[0].server_time_msc, 1790793690430)
        self.assertEqual(parsed[0].time_msc, 1790782890430)
        self.assertEqual(parsed[0].server_utc_offset_minutes, 180)


if __name__ == "__main__":
    unittest.main()
