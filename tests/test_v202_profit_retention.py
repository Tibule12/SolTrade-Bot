from datetime import datetime, timedelta
import unittest

from tools.replay_v202_profit_retention import candidate_floor, delayed_failure_trigger


class ProfitRetentionCandidateTests(unittest.TestCase):
    def test_no_change_before_trade_proves_half_r(self) -> None:
        self.assertEqual(candidate_floor(0.49999), -1.0)

    def test_monotonic_profit_bands(self) -> None:
        values = [candidate_floor(x) for x in (0.50, 0.74, 0.75, 0.99, 1.0, 1.5, 2.0)]
        self.assertEqual(values, sorted(values))
        self.assertEqual(candidate_floor(0.50), 0.20)
        self.assertEqual(candidate_floor(0.75), 0.35)
        self.assertEqual(candidate_floor(1.00), 0.60)
        self.assertEqual(candidate_floor(2.00), 1.20)

    def test_delayed_failure_requires_age_loss_low_mfe_and_sixty_seconds(self) -> None:
        entry = "2026.09.04 13:00:00"
        observations = [
            ("2026.09.04 13:14:50", -0.50),
            ("2026.09.04 13:15:00", -0.36),
            ("2026.09.04 13:15:50", -0.45),
            ("2026.09.04 13:16:00", -0.44),
        ]
        self.assertEqual(delayed_failure_trigger(entry, observations), ("2026.09.04 13:16:00", -0.44))

    def test_delayed_failure_timer_resets_on_recovery(self) -> None:
        entry = "2026.09.04 13:00:00"
        observations = [
            ("2026.09.04 13:15:00", -0.36),
            ("2026.09.04 13:15:50", -0.20),
            ("2026.09.04 13:16:00", -0.40),
            ("2026.09.04 13:16:50", -0.45),
            ("2026.09.04 13:17:00", -0.46),
        ]
        self.assertEqual(delayed_failure_trigger(entry, observations), ("2026.09.04 13:17:00", -0.46))

    def test_delayed_failure_never_fires_after_point_fifteen_r_mfe(self) -> None:
        entry = "2026.09.04 13:00:00"
        observations = [
            ("2026.09.04 13:05:00", 0.15),
            ("2026.09.04 13:15:00", -0.40),
            ("2026.09.04 13:17:00", -0.50),
        ]
        self.assertIsNone(delayed_failure_trigger(entry, observations))


if __name__ == "__main__":
    unittest.main()
