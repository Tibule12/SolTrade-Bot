import unittest

from tools.calibrate_v202_admission_walk_forward import (
    Example,
    fit_logistic,
    metrics,
    select_threshold,
    sigmoid,
    wilson_lower,
)


class AdmissionWalkForwardTests(unittest.TestCase):
    def example(self, index: int, won: bool) -> Example:
        return Example(
            day="2026.08.26",
            source="TEST",
            key=str(index),
            score=70.0 if won else 55.0,
            room_r=1.2 if won else 0.2,
            spread_atr=2.0 if won else 10.0,
            drift_atr=0.1,
            impulse_atr=0.5,
            session_asia=0.0,
            session_london=0.0,
            session_overlap=1.0,
            net_r=0.5 if won else -1.0,
        )

    def test_sigmoid_is_bounded(self) -> None:
        self.assertGreater(sigmoid(1000), 0.999)
        self.assertLess(sigmoid(-1000), 0.001)

    def test_wilson_lower_penalizes_small_samples(self) -> None:
        self.assertLess(wilson_lower(3, 3), wilson_lower(30, 30))

    def test_logistic_model_separates_obvious_fixture(self) -> None:
        examples = [self.example(i, i < 15) for i in range(30)]
        model = fit_logistic(examples)
        threshold = select_threshold(examples, model)
        result = metrics(examples, model, threshold)
        self.assertGreaterEqual(result["win_rate"], 0.90)
        self.assertGreater(result["mean_net_r"], 0)


if __name__ == "__main__":
    unittest.main()
