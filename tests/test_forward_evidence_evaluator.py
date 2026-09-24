import math
import json
import os
import shutil
import subprocess
import unittest
from pathlib import Path

from tools.forward_evidence.evaluator import (
    CANDIDATE_IDS, ORDER_CAPABILITY, candidate_summary, entry_quality,
    max_drawdown, quality_calibration, sequence_status, validate_right_censored,
)

ROOT = Path(__file__).resolve().parents[1]
PS = ROOT / "ops/forexvps/Run-V3-Forward-Evidence-Evaluator.ps1"
PWSH = os.environ.get("SOLTRADE_PWSH") or shutil.which("pwsh") or shutil.which("powershell")


def row(**updates):
    base = {
        "outcome_status": "TERMINAL", "terminal_reason": "INITIAL_STRUCTURAL_STOP",
        "candidate_id": CANDIDATE_IDS[0], "candidate_fired": True,
        "baseline_final_r": -1.0, "candidate_final_r": -0.4,
        "entry_utc": 1_789_000_000, "symbol": "EURUSD.r", "session": "LONDON",
        "recovered_to_breakeven": False, "reached_plus_1_after_exit": False,
        "reached_plus_2_after_exit": False, "reached_plus_3_after_exit": False,
        "reached_plus_5_after_exit": False,
    }
    base.update(updates)
    return base


class ForwardEvidenceTests(unittest.TestCase):
    def test_loss_avoidance_and_severity(self):
        summary = candidate_summary([row(), row(candidate_fired=False, candidate_final_r=-1.0)], CANDIDATE_IDS[0])
        self.assertEqual(summary["eligible_triggered_positions"], 2)
        self.assertEqual(summary["full_minus_1_losses_avoided"], 1)
        self.assertEqual(summary["full_minus_1_losses_not_avoided"], 1)
        self.assertAlmostEqual(summary["total_r_saved_vs_baseline"], 0.6)
        self.assertAlmostEqual(summary["average_losing_r_with_invalidation"], -0.7)

    def test_interrupted_monster_winner_is_loss_not_saving(self):
        winning = row(
            terminal_reason="RUNNER_STRUCTURAL_STOP", baseline_final_r=3.2,
            candidate_final_r=-0.4, recovered_to_breakeven=True,
            reached_plus_1_after_exit=True, reached_plus_2_after_exit=True,
            reached_plus_3_after_exit=True,
        )
        summary = candidate_summary([winning], CANDIDATE_IDS[0])
        self.assertAlmostEqual(summary["total_r_saved_vs_baseline"], -3.6)
        self.assertEqual(summary["interrupted_bank1_trades"], 1)
        self.assertEqual(summary["interrupted_plus_3_trades"], 1)

    def test_right_censored_rows_cannot_be_known_results(self):
        clean = {"outcome_status": "RIGHT_CENSORED", "opportunity_id": "a", "baseline_final_r_known": "false", "aftermath_complete": "false", "baseline_final_r": ""}
        self.assertEqual(validate_right_censored([clean]), [])
        dirty = dict(clean, baseline_final_r_known="true", baseline_final_r="0")
        self.assertEqual(len(validate_right_censored([dirty])), 2)

    def test_censored_rows_never_enter_aggregate_payoffs(self):
        censored = row(outcome_status="RIGHT_CENSORED", baseline_final_r=999, candidate_final_r=999)
        summary = candidate_summary([row(), censored], CANDIDATE_IDS[0])
        self.assertEqual(summary["eligible_triggered_positions"], 1)
        self.assertAlmostEqual(summary["baseline_total_net_r"], -1.0)

    def test_fractional_loss_savings_and_interruption_offset(self):
        summary = candidate_summary([
            row(baseline_final_r=-1.02124703, candidate_final_r=-0.41336189),
            row(baseline_final_r=3.12345678, candidate_final_r=-0.41336189,
                terminal_reason="RUNNER_STRUCTURAL_STOP"),
        ], CANDIDATE_IDS[0])
        self.assertAlmostEqual(summary["total_r_saved_vs_baseline"], -2.92893353)

    @unittest.skipUnless(PWSH, "Set SOLTRADE_PWSH to run the actual scheduled PowerShell calculations")
    def test_actual_powershell_regressions(self):
        result = subprocess.run([
            PWSH, "-NoProfile", "-File", str(ROOT / "tests/Test-ForwardEvidenceEvaluator.ps1"),
            "-EvaluatorPath", str(PS), "-ObservationCount", "1000",
        ], check=True, capture_output=True, text=True, timeout=90)
        receipt = json.loads(result.stdout)
        self.assertEqual(receipt["status"], "PASS")
        self.assertGreaterEqual(receipt["tests_passed"], 31)
        self.assertEqual(receipt["benchmark"]["comparisons"], 1000)
        self.assertFalse(receipt["production_paths_read"])

    @unittest.skipUnless(PWSH, "Set SOLTRADE_PWSH for deployment XML regression checks")
    def test_task_verification_allows_only_intended_settings(self):
        result = subprocess.run([
            PWSH, "-NoProfile", "-File", str(ROOT / "tests/Test-EvaluatorTaskXml.ps1"),
        ], check=True, capture_output=True, text=True, timeout=30)
        receipt = json.loads(result.stdout)
        self.assertEqual(receipt["status"], "PASS")
        self.assertEqual(receipt["checks"], 6)

    def test_drawdown_and_robustness_are_chronological(self):
        self.assertEqual(max_drawdown([1.0, -2.0, 0.5, -1.0]), 2.5)

    def test_quality_formula_and_frozen_bands(self):
        q = entry_quality(0.10)
        self.assertAlmostEqual(q, 1 / (1 + math.exp(-0.2)))
        bands = quality_calibration([row(entry_quality=q, baseline_plus_2=False, baseline_plus_3=False, baseline_plus_5=False, bank1_reached=False)])
        self.assertEqual((bands[0]["quality_low"], bands[0]["quality_high"]), (0.50, 0.55))

    def test_contamination_is_sticky(self):
        first = sequence_status(None, ["tracker source hash changed"])
        self.assertEqual(first["status"], "EVIDENCE_CONTAMINATED")
        again = sequence_status(first, [])
        self.assertEqual(again["status"], "EVIDENCE_CONTAMINATED")

    def test_scheduled_source_is_observation_only(self):
        self.assertFalse(ORDER_CAPABILITY)
        text = PS.read_text()
        self.assertIn("EVIDENCE_CONTAMINATED", text)
        self.assertIn("RIGHT_CENSORED", text)
        executable = "\n".join(
            line for line in text.splitlines() if "$patterns=" not in line
        )
        for forbidden in ("OrderSend(", "CTrade", "TRADE_ACTION_", "PositionClose(", "PositionModify(", "OrderDelete("):
            self.assertNotIn(forbidden, executable)


if __name__ == "__main__":
    unittest.main()
