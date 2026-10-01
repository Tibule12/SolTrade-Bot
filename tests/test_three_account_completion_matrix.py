import csv
import unittest

from tools.three_account_completion.matrix import OUT, build


class CompletionMatrixTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.summary = build()
        with (OUT / "account-arm-completion-matrix.csv").open(newline="") as stream:
            cls.rows = list(csv.DictReader(stream))

    def test_all_original_arms_retained_and_no_counterfactual_cash_fabricated(self):
        self.assertEqual(len(self.rows), 73)
        self.assertEqual(self.summary["counterfactual_arms_with_exact_final_balance"], 0)
        for row in self.rows:
            if row["arm"] in ("BASELINE_REPLAY", "PRODUCTION_SCORE_NORMAL__FROZEN_MANAGER_COHORT"):
                continue
            self.assertEqual(row["broker_exact_final_balance"], "")
            self.assertEqual(row["modelled_final_balance"], "")
            self.assertEqual(row["net_cash"], "")
            self.assertEqual(row["net_r"], "")
            self.assertEqual(row["exact_replay_trades"], "0")

    def test_fxify_baseline_uses_four_trade_bridge_not_all_september_events(self):
        for account in ("FXIFY 7196820", "FXIFY 7198096"):
            row = next(r for r in self.rows if r["account"] == account and r["arm"] == "BASELINE_REPLAY")
            self.assertEqual(row["eligible_trades"], "4")
            self.assertEqual(row["unresolved_trades"], "4")
            self.assertEqual(row["exact_replay_trades"], "0")
            self.assertEqual(row["broker_exact_final_balance"], "")

    def test_all_opportunity_coverage_denominator_is_not_invented(self):
        for row in self.rows:
            if row["account"] == "FP 7404213" and "ALL_OPPORTUNITIES" in row["arm"]:
                self.assertEqual(row["exact_coverage_pct"], "")
                self.assertIn("DENOMINATOR_UNKNOWN", row["eligibility_basis"])


if __name__ == "__main__":
    unittest.main()
