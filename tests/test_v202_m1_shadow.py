import csv
import tempfile
import unittest
from pathlib import Path

from tools.evaluate_v202_m1_shadow import Bar, m1_entry_evidence, summarize


ROOT = Path(__file__).resolve().parents[1]
FP_PAYLOAD = ROOT / "ops/forexvps/payload/fp-demo/SolTradeFastMultiMarketV2.mq5"


def bar(minute: int, open_: float, high: float, low: float, close: float) -> Bar:
    return Bar(f"2026.09.02 10:{minute:02d}:00", open_, high, low, close)


class M1EvidenceTests(unittest.TestCase):
    def test_buy_pullback_must_reclaim_completed_pullback_high(self) -> None:
        bars = [
            bar(9, 100.1, 100.9, 100.0, 100.8),
            bar(8, 100.7, 100.7, 99.7, 100.0),
            bar(7, 100.4, 100.6, 100.2, 100.5),
            bar(6, 100.2, 100.5, 100.1, 100.4),
            bar(5, 100.0, 100.3, 99.9, 100.2),
        ]
        result = m1_entry_evidence(bars, direction=1, atr=1.0, aligned_breakout=False, breakout_anchor=0)
        self.assertTrue(result["reclaim_confirmed"])
        self.assertEqual(result["pullback_shift"], 2)
        self.assertEqual(result["shadow_evidence"], "PULLBACK_RECLAIM_CONFIRMED")

    def test_sell_pullback_without_close_below_low_is_not_confirmed(self) -> None:
        bars = [
            bar(9, 100.4, 100.5, 99.9, 100.0),
            bar(8, 99.8, 100.8, 99.7, 100.5),
            bar(7, 100.1, 100.3, 99.8, 100.0),
            bar(6, 100.3, 100.4, 100.0, 100.1),
            bar(5, 100.5, 100.6, 100.2, 100.3),
        ]
        result = m1_entry_evidence(bars, direction=-1, atr=1.0, aligned_breakout=False, breakout_anchor=0)
        self.assertFalse(result["reclaim_confirmed"])
        self.assertEqual(result["shadow_evidence"], "PULLBACK_WITHOUT_RECLAIM")

    def test_breakout_requires_two_completed_closes_beyond_anchor(self) -> None:
        one = [
            bar(9, 100.0, 101.2, 99.9, 101.0),
            bar(8, 99.7, 100.0, 99.6, 99.9),
            bar(7, 99.6, 99.9, 99.5, 99.8),
            bar(6, 99.5, 99.8, 99.4, 99.7),
            bar(5, 99.4, 99.7, 99.3, 99.6),
        ]
        two = [one[0], bar(8, 100.2, 100.9, 100.1, 100.7), *one[2:]]
        self.assertFalse(m1_entry_evidence(one, direction=1, atr=1, aligned_breakout=True, breakout_anchor=100)["breakout_retained"])
        self.assertTrue(m1_entry_evidence(two, direction=1, atr=1, aligned_breakout=True, breakout_anchor=100)["breakout_retained"])

    def test_completed_close_back_inside_marks_failed_breakout(self) -> None:
        bars = [
            bar(9, 100.8, 101.0, 99.7, 99.9),
            bar(8, 100.4, 100.9, 100.2, 100.7),
            bar(7, 100.2, 100.6, 100.1, 100.5),
            bar(6, 99.9, 100.4, 99.8, 100.3),
            bar(5, 99.8, 100.1, 99.7, 100.0),
        ]
        result = m1_entry_evidence(bars, direction=1, atr=1, aligned_breakout=True, breakout_anchor=100)
        self.assertTrue(result["breakout_failed"])
        self.assertFalse(result["shadow_would_confirm"])

    def test_m1_shadow_cannot_change_live_admission_or_order_path(self) -> None:
        source = FP_PAYLOAD.read_text(encoding="utf-8")
        score_body = source[source.index("bool ScoreSymbol"):source.index("void SortRanked")]
        gate_body = score_body[score_body.index('string complete_reason=""'):]
        order_body = source[source.index("bool OpenCandidate"):source.index("void AppendScanAudit")]
        self.assertNotIn("m1_shadow_would_confirm", gate_body)
        self.assertNotIn("m1_shadow_would_confirm", order_body)
        self.assertIn('"NONE_SHADOW_TELEMETRY_ONLY"', source)

    def test_summary_fails_closed_without_outcomes(self) -> None:
        fields = [
            "m1_shadow_evidence", "complete_admission_qualified", "live_eligible",
            "intended_market", "candidate_direction", "completed_m1_bar_time", "admission_state_key",
            "m1_shadow_would_confirm", "live_admission_unchanged", "order_influence",
        ]
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "shadow.csv"
            with path.open("w", newline="", encoding="utf-8") as handle:
                writer = csv.DictWriter(handle, fieldnames=fields)
                writer.writeheader()
                writer.writerow({
                    "m1_shadow_evidence": "PULLBACK_RECLAIM_CONFIRMED",
                    "complete_admission_qualified": "true", "live_eligible": "false",
                    "intended_market": "GBPJPY", "candidate_direction": "SELL",
                    "completed_m1_bar_time": "2026.09.02 10:09:00", "admission_state_key": "1",
                    "m1_shadow_would_confirm": "true", "live_admission_unchanged": "true",
                    "order_influence": "NONE_SHADOW_TELEMETRY_ONLY",
                })
            report = summarize(path)
        self.assertTrue(report["shadow_is_non_intervening"])
        self.assertFalse(report["safe_to_promote_to_live_gate"])


if __name__ == "__main__":
    unittest.main()
