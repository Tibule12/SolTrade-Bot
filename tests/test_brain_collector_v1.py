import csv
import pathlib
import re
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[1]
SOURCE = ROOT / "tools/mql/brain-collector-v1/SolTradeBrainCollectorV1.mq5"


class BrainCollectorV1Tests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.text = SOURCE.read_text(encoding="utf-8")

    def test_no_order_capability(self):
        forbidden = [
            r"#include\s*<Trade/",
            r"\bCTrade\b",
            r"\bOrderSend(?:Async)?\s*\(",
            r"\bMqlTradeRequest\b",
            r"\bTRADE_ACTION_",
            r"\bPositionClose\s*\(",
            r"\bPositionModify\s*\(",
            r"\bOrderDelete\s*\(",
        ]
        for pattern in forbidden:
            self.assertIsNone(re.search(pattern, self.text), pattern)
        self.assertIn("const bool ORDER_CAPABILITY=false;", self.text)
        self.assertIn("if(MQLInfoInteger(MQL_TRADE_ALLOWED) || TerminalInfoInteger(TERMINAL_TRADE_ALLOWED))", self.text)

    def test_completed_bars_only(self):
        self.assertRegex(self.text, r"CopyRates\(symbol,tf,1,16,r\)")
        self.assertNotRegex(self.text, r"CopyRates\([^\n]*,0,")
        self.assertIn('"completed_bars_only","order_capability"', self.text)

    def test_future_data_not_used_for_features(self):
        self.assertNotIn("HistorySelect", self.text)
        self.assertNotIn("CopyTicksRange", self.text)
        self.assertIn("CopyTicks(Symbols[s],ticks,COPY_TICKS_ALL", self.text)

    def test_restart_state_is_durable(self):
        self.assertIn('"status\\\\state.csv"', self.text)
        self.assertIn('"status\\\\restart-count.txt"', self.text)
        self.assertIn("LoadState();", self.text)
        self.assertIn("SaveState();", self.text)
        self.assertIn("ReconcileTickTails();", self.text)
        self.assertIn("ReconcileTickFile(s,now-3600);", self.text)
        self.assertIn("if(sequence>max_sequence)max_sequence=sequence;", self.text)

    def test_new_information_families_are_present(self):
        required = [
            "tick_time_utc_msc", "spread_points", "quote_direction", "trade_direction",
            "rate_1s", "rate_5s", "rate_30s", "quote_pressure_5s",
            "quote_acceleration", "tick_volume_real", "correlated_return_mean",
            "scheduled_event_present", "spread_cash_per_lot_estimate",
            "m1_completed_state", "m5_completed_state", "m15_completed_state",
            "h1_completed_state",
        ]
        for field in required:
            self.assertIn(f'"{field}"', self.text)


if __name__ == "__main__":
    unittest.main()
