#!/usr/bin/env python3
"""Deterministic policy regressions for Fast Multi-Market V2."""

import unittest
from pathlib import Path
from tempfile import TemporaryDirectory


def spread_filter(median_spread, current_spread, samples, minimum_samples=100, maximum_ratio=1.75):
    baseline_ready = samples >= minimum_samples and median_spread > 0 and current_spread > 0
    ratio = current_spread / median_spread if baseline_ready else 0.0
    return baseline_ready, ratio, baseline_ready and ratio <= maximum_ratio


def eligible(score, opposite, no_trade, median_spread, current_spread, spread_samples,
             movement_spread, net_move, cost_multiple, reward_r=1.25):
    _, _, spread_ok = spread_filter(median_spread, current_spread, spread_samples)
    return (
        spread_ok
        and movement_spread >= 5.0
        and net_move > 0.0
        and cost_multiple >= 3.0
        and reward_r >= 1.25
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


def structural_stop(direction, entry, m5_swing, m15_swing, expansion_buffer,
                    atr5, atr15, broker_minimum):
    invalidation = max(m5_swing, m15_swing) if direction == 1 else min(m5_swing, m15_swing)
    raw_distance = entry - invalidation + expansion_buffer if direction == 1 else invalidation - entry + expansion_buffer
    return max(raw_distance, 1.15 * atr5, 0.55 * atr15, broker_minimum), invalidation


def estimated_round_trip_commission(deal_commissions, fallback=6.0):
    observations = [(abs(commission + fee), volume)
                    for commission, fee, volume in deal_commissions if volume > 0]
    if not observations:
        return fallback
    return 2.0 * sum(cost / volume for cost, volume in observations) / len(observations)


def reconciliation_safe(positions, pending_orders):
    if any(order["magic"] == 2108202601 for order in pending_orders):
        return False, "AMBIGUOUS_PENDING_FAST_MULTI_ORDER"
    seen = set()
    for position in positions:
        if position["magic"] != 2108202601:
            continue
        if position["symbol"] in seen:
            return False, "DUPLICATE_FAST_MULTI_POSITION"
        seen.add(position["symbol"])
        if not position["known_symbol"]:
            return False, "UNRESOLVED_OPEN_POSITION_SYMBOL"
        if position["stop"] <= 0:
            return False, "OPEN_POSITION_WITHOUT_BROKER_STOP"
        if not position["persistent_state"]:
            return False, "PERSISTENT_STATE_UNRECOVERABLE"
    return True, "BROKER_RECONCILIATION_PASS"


class HistoryWarmup:
    """Deterministic reference for the MQL5 post-recovery history interlock."""

    def __init__(self, started_at=0, minimum_seconds=30, stable_scans=3):
        self.started_at = started_at
        self.minimum_seconds = minimum_seconds
        self.required_stable_scans = stable_scans
        self.fingerprint = None
        self.stable_scans = 0
        self.ready = False
        self.bar_times = None

    def observe(self, fingerprint, timestamp, bar_times=(60, 300, 900, 3600)):
        normal_progression = (
            self.ready
            and self.bar_times is not None
            and any(current > previous for previous, current in zip(self.bar_times, bar_times))
            and all(
                current >= previous and current - previous in (0, period)
                for previous, current, period in zip(self.bar_times, bar_times, (60, 300, 900, 3600))
            )
        )
        if fingerprint == self.fingerprint or normal_progression:
            self.stable_scans += 1
        else:
            self.fingerprint = fingerprint
            self.stable_scans = 1
            self.ready = False
        self.bar_times = bar_times
        self.ready = (
            self.stable_scans >= self.required_stable_scans
            and timestamp - self.started_at >= self.minimum_seconds
        )
        return self.ready


class DirectionalPersistence:
    """Reference for completed-M5 entry confirmation and restart state."""

    def __init__(self, state=None):
        self.bar, self.direction, self.count = state or (None, 0, 0)

    def observe(self, bar, direction, qualified):
        if self.bar == bar:
            return self.count if qualified and self.direction == direction else 0
        consecutive = self.bar is not None and bar - self.bar == 300 and self.direction == direction
        self.count = self.count + 1 if qualified and consecutive else (1 if qualified else 0)
        self.bar = bar
        self.direction = direction if qualified else 0
        return self.count

    def state(self):
        return self.bar, self.direction, self.count


class SoftExitPersistence:
    """Reference for persistent non-structural thesis deterioration."""

    def __init__(self, state=None):
        self.bar, self.count = state or (None, 0)

    def observe(self, bar, soft_bad=False, structural_reversal=False):
        if structural_reversal:
            return "EXIT"
        if self.bar != bar:
            consecutive = self.bar is not None and bar - self.bar == 300
            self.count = self.count + 1 if soft_bad and consecutive else (1 if soft_bad else 0)
            self.bar = bar
        if self.count >= 2:
            return "EXIT"
        return "PENDING" if self.count == 1 else "HOLD"

    def state(self):
        return self.bar, self.count


class FastMultiV2PolicyTests(unittest.TestCase):
    def test_first_directional_m5_state_is_blocked(self):
        persistence = DirectionalPersistence()
        self.assertEqual(persistence.observe(1_000, -1, True), 1)

    def test_two_consecutive_directional_m5_states_permit_entry(self):
        persistence = DirectionalPersistence()
        persistence.observe(1_000, -1, True)
        self.assertEqual(persistence.observe(1_300, -1, True), 2)

    def test_direction_change_or_missing_core_resets_entry_confirmation(self):
        persistence = DirectionalPersistence()
        persistence.observe(1_000, -1, True)
        self.assertEqual(persistence.observe(1_300, 1, True), 1)
        self.assertEqual(persistence.observe(1_600, 1, False), 0)

    def test_repeated_scans_in_same_m5_bar_do_not_increment_entry_confirmation(self):
        persistence = DirectionalPersistence()
        self.assertEqual(persistence.observe(1_000, 1, True), 1)
        self.assertEqual(persistence.observe(1_000, 1, True), 1)

    def test_entry_confirmation_survives_restart(self):
        before = DirectionalPersistence()
        before.observe(1_000, 1, True)
        after = DirectionalPersistence(before.state())
        self.assertEqual(after.observe(1_300, 1, True), 2)

    def test_hard_structural_reversal_exits_immediately(self):
        persistence = SoftExitPersistence()
        self.assertEqual(persistence.observe(1_000, structural_reversal=True), "EXIT")

    def test_one_soft_bad_bar_is_pending_and_second_exits(self):
        persistence = SoftExitPersistence()
        self.assertEqual(persistence.observe(1_000, soft_bad=True), "PENDING")
        self.assertEqual(persistence.observe(1_300, soft_bad=True), "EXIT")

    def test_repeated_scans_do_not_accelerate_soft_exit(self):
        persistence = SoftExitPersistence()
        self.assertEqual(persistence.observe(1_000, soft_bad=True), "PENDING")
        self.assertEqual(persistence.observe(1_000, soft_bad=True), "PENDING")

    def test_soft_exit_recovery_resets_and_survives_restart(self):
        before = SoftExitPersistence()
        before.observe(1_000, soft_bad=True)
        after = SoftExitPersistence(before.state())
        self.assertEqual(after.observe(1_300, soft_bad=False), "HOLD")
        self.assertEqual(after.observe(1_600, soft_bad=True), "PENDING")

    def test_no_trade_overrides_moderate_direction(self):
        self.assertFalse(eligible(72, 50, 68, 1.0, 1.0, 100, 20, 2, 4))

    def test_direction_must_dominate_opposite(self):
        self.assertFalse(eligible(75, 66, 30, 1.0, 1.0, 100, 20, 2, 4))

    def test_abnormal_spread_rejected(self):
        self.assertFalse(eligible(90, 30, 20, 1.0, 1.751, 100, 20, 2, 4))

    def test_normal_symbol_relative_spread_passes_even_above_legacy_atr_ratio(self):
        self.assertTrue(eligible(90, 30, 20, 1.0, 1.0, 100, 20, 2, 4))

    def test_spread_ratio_boundary_and_missing_baseline(self):
        self.assertTrue(spread_filter(1.0, 1.75, 100)[2])
        self.assertFalse(spread_filter(1.0, 1.750001, 100)[2])
        self.assertFalse(spread_filter(1.0, 1.0, 99)[2])

    def test_insufficient_net_move_rejected(self):
        self.assertFalse(eligible(90, 30, 20, 1.0, 1.0, 100, 20, 0, 4))
        self.assertFalse(eligible(90, 30, 20, 1.0, 1.0, 100, 20, 2, 2.99))

    def test_clean_candidate_accepted(self):
        self.assertTrue(eligible(82, 55, 42, 1.0, 1.1, 100, 12, 3, 4))

    def test_reward_threshold_remains_one_point_two_five(self):
        self.assertFalse(eligible(90, 30, 20, 1.0, 1.0, 100, 20, 2, 4, reward_r=1.249999))
        self.assertTrue(eligible(90, 30, 20, 1.0, 1.0, 100, 20, 2, 4, reward_r=1.25))

    def test_nearest_confirmed_structure_is_selected(self):
        buy_distance, buy_invalidation = structural_stop(1, 1.1050, 1.1000, 1.1020, 0.0002,
                                                         0.0010, 0.0020, 0.0003)
        sell_distance, sell_invalidation = structural_stop(-1, 1.1000, 1.1050, 1.1030, 0.0002,
                                                            0.0010, 0.0020, 0.0003)
        self.assertEqual(buy_invalidation, 1.1020)
        self.assertEqual(sell_invalidation, 1.1030)
        self.assertAlmostEqual(buy_distance, 0.0032)
        self.assertAlmostEqual(sell_distance, 0.0032)

    def test_atr_and_broker_stop_floors_are_preserved(self):
        distance, _ = structural_stop(1, 1.1050, 1.1048, 1.1049, 0.0,
                                      0.0010, 0.0030, 0.0020)
        self.assertAlmostEqual(distance, 0.0020)

    def test_broker_confirmed_zero_commission_is_not_replaced_by_fallback(self):
        self.assertEqual(estimated_round_trip_commission([(0.0, 0.0, 9.82), (0.0, 0.0, 9.82)]), 0.0)
        self.assertEqual(estimated_round_trip_commission([]), 6.0)

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

    def test_restart_reconciliation_accepts_one_persisted_stopped_position(self):
        positions = [{"magic": 2108202601, "symbol": "EURUSD.r", "known_symbol": True,
                      "stop": 1.08, "persistent_state": True}]
        self.assertEqual(reconciliation_safe(positions, []), (True, "BROKER_RECONCILIATION_PASS"))

    def test_restart_reconciliation_rejects_duplicate_position(self):
        position = {"magic": 2108202601, "symbol": "EURUSD.r", "known_symbol": True,
                    "stop": 1.08, "persistent_state": True}
        safe, reason = reconciliation_safe([position, position.copy()], [])
        self.assertFalse(safe)
        self.assertEqual(reason, "DUPLICATE_FAST_MULTI_POSITION")

    def test_restart_reconciliation_rejects_pending_order(self):
        safe, reason = reconciliation_safe([], [{"magic": 2108202601}])
        self.assertFalse(safe)
        self.assertEqual(reason, "AMBIGUOUS_PENDING_FAST_MULTI_ORDER")

    def test_restart_reconciliation_rejects_missing_stop_or_state(self):
        base = {"magic": 2108202601, "symbol": "EURUSD.r", "known_symbol": True,
                "stop": 1.08, "persistent_state": True}
        no_stop = dict(base, stop=0)
        no_state = dict(base, persistent_state=False)
        self.assertFalse(reconciliation_safe([no_stop], [])[0])
        self.assertFalse(reconciliation_safe([no_state], [])[0])

    def test_append_only_scan_history_survives_subsequent_scans(self):
        with TemporaryDirectory() as directory:
            audit = Path(directory) / "scan-history.csv"
            with audit.open("a", encoding="utf-8") as stream:
                stream.write("scan,symbol,reason\n")
                stream.write("1,EURUSD.r,ABNORMAL_SPREAD\n")
            first_size = audit.stat().st_size
            with audit.open("a", encoding="utf-8") as stream:
                stream.write("2,EURUSD.r,QUALIFIED_CONTEXT_COST_STRUCTURE\n")
            self.assertGreater(audit.stat().st_size, first_size)
            self.assertEqual(len(audit.read_text(encoding="utf-8").splitlines()), 3)

    def test_post_update_first_scan_cannot_trade(self):
        warmup = HistoryWarmup(started_at=0)
        self.assertFalse(warmup.observe("incomplete-history", 0))

    def test_history_rebuild_resets_warmup(self):
        warmup = HistoryWarmup(started_at=0)
        self.assertFalse(warmup.observe("incomplete-history", 0))
        self.assertFalse(warmup.observe("rebuilt-history", 1))
        self.assertFalse(warmup.observe("rebuilt-history", 11))
        self.assertFalse(warmup.observe("rebuilt-history", 21))
        self.assertTrue(warmup.observe("rebuilt-history", 31))

    def test_expected_completed_bar_advance_keeps_ready_symbol_live(self):
        warmup = HistoryWarmup(started_at=0)
        for timestamp in (0, 10, 20, 30):
            warmup.observe("stable-bar-set", timestamp)
        self.assertTrue(warmup.ready)
        self.assertTrue(warmup.observe("new-completed-bar-set", 40, (120, 300, 900, 3600)))

    def test_same_timestamp_history_rewrite_relocks_ready_symbol(self):
        warmup = HistoryWarmup(started_at=0)
        for timestamp in (0, 10, 20, 30):
            warmup.observe("stable-bar-set", timestamp)
        self.assertFalse(warmup.observe("rewritten-bar-values", 40, (60, 300, 900, 3600)))

    def test_skipped_completed_bar_relocks_ready_symbol(self):
        warmup = HistoryWarmup(started_at=0)
        for timestamp in (0, 10, 20, 30):
            warmup.observe("stable-bar-set", timestamp)
        self.assertFalse(warmup.observe("skipped-bar-set", 40, (180, 300, 900, 3600)))


if __name__ == "__main__":
    unittest.main()
