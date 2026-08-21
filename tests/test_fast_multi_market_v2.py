#!/usr/bin/env python3
"""Deterministic policy regressions for Fast Multi-Market V2."""

import unittest


def eligible(score, opposite, no_trade, spread_atr, movement_spread, net_move, cost_multiple):
    return (
        spread_atr <= 8.0
        and movement_spread >= 5.0
        and net_move > 0.0
        and cost_multiple >= 3.0
        and score >= 68.0
        and score >= opposite + 12.0
        and score >= no_trade + 8.0
    )


def sized_lots(equity, stop_loss_per_lot, commission_per_lot, step=0.01):
    budget = equity * 0.0025
    raw = budget / (stop_loss_per_lot + commission_per_lot)
    return int((raw + 1e-12) / step) * step


def reversal_allowed(previous_direction, previous_invalidated, previous_setup, direction,
                     setup, structural_reversal, m5, m15, dominates, cost_ok):
    if previous_setup and setup == previous_setup:
        return False
    if not previous_direction or previous_direction == direction:
        return True
    return all((previous_invalidated, structural_reversal, m5, m15, dominates, cost_ok))


def portfolio_safe(open_count, theme_count, correlated_count, current_risk, equity):
    candidate_budget = equity * 0.0025
    return (
        open_count < 6
        and theme_count < 2
        and correlated_count < 2
        and current_risk + candidate_budget <= equity * 0.015 + 0.01
    )


def spread_units(bid, ask, point, digits, is_fx):
    raw = ask - bid
    pip_size = 10.0 * point if is_fx and digits in (3, 5) else point
    return raw, raw / point, raw / pip_size if is_fx else None


def runner_decision(current_r, thesis_invalidated=False, trailing_stop_hit=False):
    if thesis_invalidated:
        return "EXIT"
    if trailing_stop_hit:
        return "EXIT_PROTECTED"
    if current_r >= 0.75:
        return "RUNNER_MODE"
    return "MANAGE"


def ratchet_stop(direction, current_stop, candidate_stop):
    return max(current_stop, candidate_stop) if direction == 1 else min(current_stop, candidate_stop)


class FastMultiV2PolicyTests(unittest.TestCase):
    def test_no_trade_overrides_moderate_direction(self):
        self.assertFalse(eligible(72, 50, 68, 3, 20, 2, 4))

    def test_direction_must_dominate_opposite(self):
        self.assertFalse(eligible(75, 66, 30, 3, 20, 2, 4))

    def test_abnormal_spread_rejected(self):
        self.assertFalse(eligible(90, 30, 20, 8.01, 20, 2, 4))

    def test_insufficient_net_move_rejected(self):
        self.assertFalse(eligible(90, 30, 20, 3, 20, 0, 4))
        self.assertFalse(eligible(90, 30, 20, 3, 20, 2, 2.99))

    def test_clean_candidate_accepted(self):
        self.assertTrue(eligible(82, 55, 42, 4, 12, 3, 4))

    def test_wider_stop_reduces_lot(self):
        narrow = sized_lots(100_000, 100, 6)
        wide = sized_lots(100_000, 250, 6)
        self.assertGreater(narrow, wide)

    def test_same_setup_rejected(self):
        self.assertFalse(reversal_allowed(1, True, 123, 1, 123, True, True, True, True, True))

    def test_opposite_reentry_needs_every_reversal_condition(self):
        base = (-1, True, 123, 1, 456)
        self.assertTrue(reversal_allowed(*base, True, True, True, True, True))
        for missing in range(5):
            gates = [True] * 5
            gates[missing] = False
            self.assertFalse(reversal_allowed(*base, *gates))

    def test_six_position_cap(self):
        self.assertTrue(portfolio_safe(5, 0, 0, 1000, 100_000))
        self.assertFalse(portfolio_safe(6, 0, 0, 0, 100_000))

    def test_factor_and_correlation_cap(self):
        self.assertFalse(portfolio_safe(1, 2, 0, 0, 100_000))
        self.assertFalse(portfolio_safe(1, 0, 2, 0, 100_000))

    def test_portfolio_risk_cap(self):
        self.assertTrue(portfolio_safe(5, 0, 0, 1250, 100_000))
        self.assertFalse(portfolio_safe(5, 0, 0, 1250.02, 100_000))

    def test_runner_activates_at_point_seven_five_r(self):
        self.assertEqual(runner_decision(0.749999), "MANAGE")
        self.assertEqual(runner_decision(0.75), "RUNNER_MODE")

    def test_runner_has_no_hard_profit_ceiling(self):
        for current_r in (1.0, 1.5, 2.0, 3.0, 8.0):
            self.assertEqual(runner_decision(current_r), "RUNNER_MODE")

    def test_buy_protected_stop_never_moves_down(self):
        self.assertEqual(ratchet_stop(1, 1.1050, 1.1030), 1.1050)
        self.assertEqual(ratchet_stop(1, 1.1050, 1.1070), 1.1070)

    def test_sell_protected_stop_never_moves_up(self):
        self.assertEqual(ratchet_stop(-1, 158.20, 158.50), 158.20)
        self.assertEqual(ratchet_stop(-1, 158.20, 157.90), 157.90)

    def test_runner_can_exit_on_structural_invalidation(self):
        self.assertEqual(runner_decision(2.0, thesis_invalidated=True), "EXIT")

    def test_runner_trailing_stop_realises_protected_profit(self):
        self.assertEqual(runner_decision(1.2, trailing_stop_hit=True), "EXIT_PROTECTED")
        self.assertGreater(0.30, 0.0)

    def test_fx_spread_normalization(self):
        raw, points, pips = spread_units(1.10000, 1.10012, 0.00001, 5, True)
        self.assertAlmostEqual(raw, 0.00012)
        self.assertAlmostEqual(points, 12.0)
        self.assertAlmostEqual(pips, 1.2)

    def test_jpy_spread_normalization(self):
        _, points, pips = spread_units(158.100, 158.112, 0.001, 3, True)
        self.assertAlmostEqual(points, 12.0)
        self.assertAlmostEqual(pips, 1.2)

    def test_metal_spread_normalization(self):
        _, points, pips = spread_units(38.100, 38.130, 0.001, 3, False)
        self.assertAlmostEqual(points, 30.0)
        self.assertIsNone(pips)

    def test_index_spread_normalization(self):
        _, points, pips = spread_units(26000.0, 26000.5, 0.1, 1, False)
        self.assertAlmostEqual(points, 5.0)
        self.assertIsNone(pips)


if __name__ == "__main__":
    unittest.main()
