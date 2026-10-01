"""Synthetic tests for strict, orderless alternative account-path replay."""

from __future__ import annotations

import unittest
from decimal import Decimal as D

from tools.three_account_completion import (
    ARM_MATRIX_COLUMNS, CloseFill, CoverageCase, EntryFill, RiskPolicy,
    TradePath, classify_arm_coverage, replay_filled_arm,
)


def policy(**overrides: object) -> RiskPolicy:
    values = dict(
        opening_balance=D("10000"), risk_fraction=D("0.01"),
        max_portfolio_risk_fraction=D("0.03"), max_simultaneous_positions=3,
        max_positions_per_theme=2, minimum_lot=D("0.1"),
        maximum_lot=D("10"), lot_step=D("0.1"), margin_per_lot=D("100"),
    )
    values.update(overrides)
    return RiskPolicy(**values)


def path(
    trade_id: str, start: int, *, status: str = "COMPLETE", grade: str = "BROKER_EXECUTION",
    direction: str = "BUY", symbol: str = "XAUUSD", theme: str = "METAL",
    entry_price: str = "100", stop: str = "90", exit_price: str = "90",
    exit_kind: str = "INITIAL_STOP", bank: bool = False,
    reason: str = "", risk_per_lot: str = "100",
) -> TradePath:
    if status != "COMPLETE":
        return TradePath("FP", "INVERSE", trade_id, symbol, theme, True, status,
                         reason or "Missing broker quotes after export end")
    entry = EntryFill(
        start, D(entry_price), D(stop), direction, D("10"), D(risk_per_lot),
        D("-2"), D("0"), f"entry-{trade_id}", grade,
        "NATIVE_OPPOSITE_STRUCTURE" if grade == "QUOTE_FILL_MODEL" else "RECORDED_PRODUCTION_STOP",
    )
    closes = ()
    if bank:
        closes += (CloseFill(start + 1000, D("110"), "BANK1R", D("-1"), D("0"), D("0"),
                             f"bank-{trade_id}", grade),)
    closes += (CloseFill(start + 2000, D(exit_price), "RUNNER_STOP" if bank else exit_kind,
                         D("-1"), D("-0.5"), D("0"), f"exit-{trade_id}", grade),)
    return TradePath("FP", "INVERSE", trade_id, symbol, theme, True, status, reason,
                     entry, closes, exit_price == "120", False)


class CompletionReplayTests(unittest.TestCase):
    def test_one_time_bank_runner_and_cash_costs_reconcile(self) -> None:
        row = path("A", 1000, bank=True, exit_price="120")
        out = replay_filled_arm("FP", "INVERSE", [row], policy())
        # Entry -2; half-bank 50-0.5; runner 100-0.75.
        self.assertEqual(out.broker_exact_final_balance, D("10146.75"))
        self.assertEqual(out.net_cash, D("146.75"))
        self.assertEqual(out.net_r, D("1.4675"))
        self.assertEqual((out.wins, out.bank1r, out.plus_3r), (1, 1, 1))
        self.assertEqual(out.exact_coverage_pct, D("100"))
        self.assertIsNone(out.modelled_final_balance)

    def test_quote_fill_model_never_claims_exact_broker_balance(self) -> None:
        row = path("A", 1000, grade="QUOTE_FILL_MODEL", exit_price="90")
        out = replay_filled_arm("FP", "INVERSE", [row], policy())
        self.assertIsNone(out.broker_exact_final_balance)
        self.assertEqual(out.modelled_final_balance, D("9896.5"))
        self.assertEqual(out.exact_replay_trades, 0)
        self.assertEqual(out.modelled_complete_trades, 1)
        self.assertEqual(out.status, "CONDITIONAL_ACCOUNT_MODEL_ONLY")
        self.assertIn("HISTORICAL_MARGIN_REQUIREMENT_UNAVAILABLE", replay_filled_arm(
            "FP", "INVERSE", [row], policy(margin_per_lot=None),
        ).missing_evidence)

    def test_one_censored_trade_nulls_entire_downstream_final_path(self) -> None:
        rows = [path("A", 1000, exit_price="120"),
                path("B", 3000, status="RIGHT_CENSORED", reason="ticks end at 24h"),
                path("C", 4000, symbol="US100", theme="INDEX")]
        out = replay_filled_arm("FP", "INVERSE", rows, policy())
        self.assertEqual((out.eligible_trades, out.exact_replay_trades,
                          out.censored_trades, out.unresolved_trades), (3, 2, 1, 0))
        self.assertIsNone(out.broker_exact_final_balance)
        self.assertIsNone(out.modelled_final_balance)
        self.assertIsNone(out.net_cash)
        self.assertEqual(out.first_ambiguity_trade, "B")
        self.assertEqual(out.missing_evidence, ("B:ticks end at 24h",))
        self.assertEqual(out.as_csv_row()["net_cash"], "")

    def test_unresolved_native_stop_never_treated_as_mirrored_or_zero(self) -> None:
        row = path("A", 1000, status="UNRESOLVED_NATIVE_STOP",
                   reason="historical freeze level absent")
        out = replay_filled_arm("FP", "INVERSE", [row], policy())
        self.assertEqual(out.unresolved_trades, 1)
        self.assertEqual(out.exact_coverage_pct, D("0"))
        self.assertIsNone(out.broker_exact_final_balance)
        self.assertIn("A:historical freeze level absent", out.missing_evidence)
        bad = path("A", 1000, grade="QUOTE_FILL_MODEL")
        assert bad.entry
        from dataclasses import replace
        with self.assertRaisesRegex(ValueError, "native or recorded"):
            replay_filled_arm("FP", "INVERSE", [replace(
                bad, entry=replace(bad.entry, stop_basis="MIRRORED_DISTANCE"),
            )], policy())

    def test_portfolio_cap_and_lot_size_change_with_realized_balance(self) -> None:
        rows = [
            path("A", 1000, symbol="XAUUSD", theme="METAL", exit_price="220"),
            path("B", 4000, symbol="US100", theme="INDEX", entry_price="100", stop="90",
                 exit_price="90"),
        ]
        out = replay_filled_arm("FP", "INVERSE", rows, policy())
        # First winner raises balance; next risk budget yields 1.1 lots, so its
        # full-stop loss is larger than with fixed historical lot size.
        self.assertEqual(out.net_cash, D("1082.65"))
        self.assertEqual(out.broker_exact_final_balance, D("11082.65"))
        self.assertEqual(out.max_realized_balance_dd, D("113.85"))
        capped = replay_filled_arm("FP", "INVERSE", [
            path("A", 1000, bank=True, exit_price="120"),
            path("B", 1500, symbol="US100", theme="INDEX"),
        ], policy(max_simultaneous_positions=1))
        self.assertIn("B:POSITION_OR_THEME_CAP_REJECTED", capped.missing_evidence)
        self.assertEqual(capped.broker_exact_final_balance, None)
        self.assertEqual(capped.modelled_final_balance, D("10146.75"))

    def test_banked_runner_can_last_beyond_four_hours_without_expiry(self) -> None:
        row = path("A", 1000, bank=True, exit_price="120")
        from dataclasses import replace
        closes = (row.closes[0], replace(row.closes[1], time_msc=1000 + 6 * 60 * 60 * 1000))
        out = replay_filled_arm("FP", "INVERSE", [replace(row, closes=closes)], policy())
        self.assertEqual(out.bank1r, 1)
        self.assertEqual(out.broker_exact_final_balance, D("10146.75"))

    def test_duplicate_bank_or_broken_stop_is_rejected(self) -> None:
        row = path("A", 1000, bank=True, exit_price="120")
        from dataclasses import replace
        with self.assertRaisesRegex(ValueError, "at most one"):
            replay_filled_arm("FP", "INVERSE", [replace(
                row, closes=(row.closes[0], replace(row.closes[0], time_msc=2500), row.closes[1]),
            )], policy())
        assert row.entry
        with self.assertRaisesRegex(ValueError, "Stop must be adverse"):
            replay_filled_arm("FP", "INVERSE", [replace(
                row, entry=replace(row.entry, stop_price=D("110")),
            )], policy())

    def test_same_millisecond_entry_close_requires_broker_ordering(self) -> None:
        rows = [path("A", 1000), path("B", 3000, symbol="US100", theme="INDEX")]
        with self.assertRaisesRegex(ValueError, "same-millisecond"):
            replay_filled_arm("FP", "INVERSE", rows, policy())

    def test_coverage_schema_and_account_isolation(self) -> None:
        cases = [
            CoverageCase("1", True, "COMPLETE", "BROKER_EXECUTION", ""),
            CoverageCase("2", True, "COMPLETE", "QUOTE_FILL_MODEL", ""),
            CoverageCase("3", True, "RIGHT_CENSORED", None, "market history end"),
            CoverageCase("4", True, "UNRESOLVED_COST", None, "old swap terms unavailable"),
            CoverageCase("5", False, "NOT_ELIGIBLE", None, ""),
        ]
        self.assertEqual(classify_arm_coverage(cases)[:6], (4, 1, 1, 1, 1, D("25")))
        self.assertEqual(len(ARM_MATRIX_COLUMNS), 24)
        with self.assertRaisesRegex(ValueError, "account"):
            replay_filled_arm("FXIFY", "INVERSE", [path("A", 1000)], policy())


if __name__ == "__main__":
    unittest.main()
