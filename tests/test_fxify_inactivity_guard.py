#!/usr/bin/env python3
from __future__ import annotations

from dataclasses import replace
from datetime import datetime, timedelta
import hashlib
from pathlib import Path
import sys
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))

from fxify_inactivity_guard_model import (  # noqa: E402
    Config,
    Deal,
    Position,
    Snapshot,
    evaluate,
    latest_entry,
    manage_position,
    projected_risk,
    simulate_historical_gap,
)


BASE = datetime(2026, 2, 2, 10, 5, 1)
CONFIG = Config()


def snapshot(day: float, **kwargs) -> Snapshot:
    return Snapshot(now=BASE + timedelta(days=day), history_anchor=BASE, **kwargs)


class FXIFYInactivityGuardTests(unittest.TestCase):
    def test_01_v28_entry_resets_timer(self):
        result = evaluate(snapshot(50, deals=(Deal(BASE + timedelta(days=49), "IN", magic=2607202601),)))
        self.assertAlmostEqual(result.elapsed_days, 1.0)
        self.assertNotIn("MAINTENANCE_ENTRY_INTENT", result.events)

    def test_02_guard_entry_resets_timer(self):
        result = evaluate(snapshot(51, deals=(Deal(BASE + timedelta(days=50), "IN", magic=CONFIG.guard_magic),)))
        self.assertAlmostEqual(result.elapsed_days, 1.0)

    def test_03_day_45_alert(self):
        self.assertIn("DAY_45_WARNING", evaluate(snapshot(45)).events)

    def test_04_no_trade_before_day_50(self):
        self.assertFalse(evaluate(snapshot(49.999)).maintenance_intent)

    def test_05_exactly_one_safe_day_50_intent(self):
        result = evaluate(snapshot(50))
        self.assertEqual(result.events.count("MAINTENANCE_ENTRY_INTENT"), 1)
        executed = [Deal(BASE + timedelta(days=50), "IN", magic=CONFIG.guard_magic)] if result.maintenance_intent else []
        self.assertEqual(len(executed), 1)
        after_fill = evaluate(snapshot(50.001, deals=tuple(executed), guard_position_active=True))
        self.assertFalse(after_fill.maintenance_intent)

    def test_06_restart_history_prevents_duplicate(self):
        deals = (Deal(BASE + timedelta(days=50), "IN", magic=CONFIG.guard_magic),)
        restarted = evaluate(snapshot(50.01, deals=deals))
        self.assertFalse(restarted.maintenance_intent)

    def test_07_weekend_closed_market(self):
        self.assertEqual(evaluate(snapshot(50, market_open=False)).blocker, "MARKET_CLOSED_OR_NOT_TRADEABLE")

    def test_08_excessive_spread(self):
        self.assertEqual(evaluate(snapshot(50, spread_pips=2.0)).blocker, "EXCESSIVE_SPREAD")

    def test_09_read_only_account(self):
        self.assertEqual(evaluate(snapshot(50, account_trade_allowed=False)).blocker, "ACCOUNT_READ_ONLY_OR_TRADE_DISABLED")

    def test_10_algo_trading_disabled(self):
        self.assertEqual(evaluate(snapshot(50, terminal_trade_allowed=False)).blocker, "ALGO_TRADING_DISABLED")

    def test_11_order_rejection_retry(self):
        first = evaluate(snapshot(50, previous_request_rejected=True))
        self.assertIn("RETRY_AFTER_REJECTION", first.events)
        waiting = evaluate(snapshot(50, last_attempt=BASE + timedelta(days=50) - timedelta(minutes=5)))
        self.assertEqual(waiting.blocker, "RETRY_INTERVAL")
        retry = evaluate(snapshot(50, last_attempt=BASE + timedelta(days=50) - timedelta(minutes=16)))
        self.assertTrue(retry.maintenance_intent)

    def test_12_existing_guard_position_blocks_duplicate(self):
        self.assertEqual(evaluate(snapshot(50, guard_position_active=True)).blocker, "GUARD_POSITION_ACTIVE")

    def test_13_incorrect_symbol_specifications(self):
        self.assertEqual(evaluate(snapshot(50, symbol_specs_valid=False)).blocker, "INVALID_SYMBOL_SPECIFICATIONS")

    def test_14_insufficient_margin(self):
        self.assertEqual(evaluate(snapshot(50, free_margin=380.0)).blocker, "INSUFFICIENT_MARGIN")

    def test_15_daily_loss_safety_buffer(self):
        self.assertEqual(evaluate(snapshot(50, equity=9_650.0)).blocker, "DAILY_LOSS_SAFETY_BUFFER")

    def test_16_maximum_loss_safety_buffer(self):
        result = evaluate(snapshot(50, equity=9_240.0, boundary_balance=9_000.0))
        self.assertEqual(result.blocker, "MAXIMUM_LOSS_SAFETY_BUFFER")

    def test_17_all_cost_components_in_projected_risk(self):
        risk, components = projected_risk(snapshot(50), CONFIG)
        self.assertEqual(set(components), {"stop", "spread", "slippage", "commission"})
        self.assertAlmostEqual(risk, 1.22)

    def test_18_day_55_critical_alert(self):
        self.assertIn("DAY_55_CRITICAL", evaluate(snapshot(55, market_open=False)).events)

    def test_19_partial_fills_are_entries_and_prevent_duplicate(self):
        deals = (
            Deal(BASE + timedelta(days=50), "IN", magic=CONFIG.guard_magic, volume=0.006),
            Deal(BASE + timedelta(days=50, seconds=1), "IN", magic=CONFIG.guard_magic, volume=0.004),
        )
        self.assertEqual(latest_entry(deals), deals[1])
        self.assertFalse(evaluate(snapshot(50.01, deals=deals, guard_position_active=True)).maintenance_intent)

    def test_20_netting_and_hedging_handling(self):
        for mode in ("NETTING", "HEDGING"):
            self.assertTrue(evaluate(snapshot(50, margin_mode=mode)).maintenance_intent)
            self.assertEqual(
                evaluate(snapshot(50, margin_mode=mode, symbol_position_active=True)).blocker,
                "SYMBOL_POSITION_CONFLICT",
            )

    def test_21_maximum_holding_time_exit(self):
        position = Position(BASE, stop_present=True)
        self.assertEqual(manage_position(BASE + timedelta(minutes=60), position), "CLOSE_MAXIMUM_HOLDING_TIME")

    def test_22_server_side_stop_required(self):
        position = Position(BASE, stop_present=False)
        self.assertEqual(manage_position(BASE + timedelta(minutes=1), position), "EMERGENCY_CLOSE_MISSING_STOP")

    def test_23_v28_and_production_unchanged(self):
        production = ROOT / "MQL5/Experts/SolTradeBot.mq5"
        self.assertEqual(
            hashlib.sha256(production.read_bytes()).hexdigest(),
            "261a9cfe1c1e8d84e2a2a468ac4d0775086b21c89824b117e5127697fd03ced3",
        )

    def test_24_historical_gap_is_interrupted_before_60_days(self):
        rows = simulate_historical_gap()
        self.assertIn("DAY_45_WARNING", rows[0]["decision_events"])
        self.assertIn("MAINTENANCE_ENTRY_INTENT", rows[1]["decision_events"])
        self.assertEqual(rows[2]["event"], "GUARD_ENTRY_EXECUTED")
        self.assertEqual(rows[-1]["inactivity_breach"], "NO")
        self.assertLess(float(rows[-1]["elapsed_days_before_event"]), 60.0)

    def test_25_inout_resets_but_out_does_not(self):
        out = Deal(BASE + timedelta(days=49), "OUT", magic=2607202601)
        inout = Deal(BASE + timedelta(days=48), "INOUT", magic=2607202601)
        result = evaluate(snapshot(50, deals=(inout, out)))
        self.assertAlmostEqual(result.elapsed_days, 2.0)
        self.assertFalse(result.maintenance_intent)

    def test_26_terminal_disconnection_blocks_entry(self):
        self.assertEqual(evaluate(snapshot(50, connected=False)).blocker, "TERMINAL_DISCONNECTED")

    def test_27_active_guard_order_blocks_entry(self):
        self.assertEqual(evaluate(snapshot(50, guard_order_active=True)).blocker, "GUARD_ORDER_ACTIVE")

    def test_28_invalid_tick_blocks_entry(self):
        self.assertEqual(evaluate(snapshot(50, tick_valid=False)).blocker, "INVALID_MARKET_DATA")

    def test_29_broker_adjusted_stop_risk_is_capped(self):
        result = evaluate(snapshot(50, stop_pip_value=0.12))
        self.assertEqual(result.blocker, "STOP_RISK_TOO_HIGH")


if __name__ == "__main__":
    unittest.main(verbosity=2)
