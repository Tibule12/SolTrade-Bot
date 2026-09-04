from datetime import datetime, timedelta
import unittest

from tools.replay_v202_intelligence_candidates import (
    Observation,
    Trade,
    calibration_status,
    current_net_floor,
    graduated_net_floor,
    replay_trade,
)


def sample_trade() -> Trade:
    return Trade(
        day="2026.09.02",
        account="fp",
        ticket="1",
        market="GBPJPY",
        symbol="GBPJPY.r",
        direction="SELL",
        entry_utc="2026.09.02 07:00:00",
        exit_utc="2026.09.02 08:00:00",
        fill=100.0,
        stop=101.0,
        initial_risk=250.0,
        original_net_r=-1.0,
        exit_class="INITIAL_STRUCTURAL_STOP_EXIT",
        admission_score=64.0,
        admission_state_key="abc",
    )


def observation(minute: int, current_r: float, candidate_direction: str = "BUY") -> Observation:
    base = datetime(2026, 9, 2, 7, 0, 0) + timedelta(minutes=minute)
    trade = sample_trade()
    close = trade.fill + trade.direction_number * current_r * trade.initial_distance
    return Observation(
        utc=base.strftime("%Y.%m.%d %H:%M:%S"),
        close_price=close,
        candidate_direction=candidate_direction,
        trend_m5=0.25,
        trend_m15=-0.50,
    )


class IntelligenceCandidateTests(unittest.TestCase):
    def test_graduated_floor_changes_only_proven_profit_bands(self) -> None:
        self.assertEqual(current_net_floor(0.74), graduated_net_floor(0.74))
        self.assertEqual(graduated_net_floor(0.74), 0.10)
        self.assertEqual(current_net_floor(0.90), 0.10)
        self.assertEqual(graduated_net_floor(0.90), 0.25)
        self.assertAlmostEqual(current_net_floor(1.10), 0.35)
        self.assertEqual(graduated_net_floor(1.10), 0.40)

    def test_delayed_failure_requires_age_mfe_loss_and_two_minutes(self) -> None:
        trade = sample_trade()
        path = [
            observation(1, -0.10),
            observation(5, -0.40),
            observation(6, -0.45),
        ]
        result = replay_trade(trade, path, graduated=True)
        self.assertEqual(result["status"], "DELAYED_EARLY_FAILURE_EXIT")
        self.assertEqual(result["exit_utc"], "2026.09.02 07:06:00")
        self.assertEqual(result["modeled_r"], -0.45)

    def test_delayed_failure_does_not_cut_a_recovering_trade(self) -> None:
        trade = sample_trade()
        path = [
            observation(5, -0.40),
            observation(6, -0.05),
            observation(7, 0.60, candidate_direction="SELL"),
            observation(8, 0.05, candidate_direction="SELL"),
        ]
        result = replay_trade(trade, path, graduated=True)
        self.assertEqual(result["status"], "PROTECTED_STOP")
        self.assertEqual(result["modeled_r"], 0.10)

    def test_initial_spread_or_early_adverse_move_cannot_trigger_failure(self) -> None:
        trade = sample_trade()
        path = [observation(0, -0.05), observation(1, -0.40), observation(2, -0.45)]
        result = replay_trade(trade, path, graduated=True)
        self.assertNotEqual(result["status"], "DELAYED_EARLY_FAILURE_EXIT")

    def test_calibration_fails_closed_on_tiny_sample(self) -> None:
        status = calibration_status([sample_trade()])
        self.assertEqual(status["status"], "INSUFFICIENT_SAMPLE_FAIL_CLOSED")
        self.assertFalse(status["live_admission_change_authorized"])


if __name__ == "__main__":
    unittest.main()
