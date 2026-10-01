import unittest
from datetime import datetime, timezone

from tools.three_account_completion.fxify_reconcile import BROKER, build
from tools.three_account_replay.engine import read_native_deals


class FxifyBrokerRecoveryTests(unittest.TestCase):
    def test_10k_broker_ledger_reconciles_all_september_ea_events(self):
        result = build()
        self.assertEqual(result["broker_deals"], 49)
        self.assertEqual(result["closed_positions"], 24)
        self.assertEqual(result["september_ea_positions_matched"], 22)
        self.assertEqual(result["ea_broker_cash_mismatch_count"], 0)
        self.assertEqual(result["broker_final_balance"], "9660.24000000")

    def test_probe_had_no_order_api_or_new_broker_deal_but_permissions_were_enabled(self):
        source = (BROKER / "SolTradeFXIFYReadOnlyHistory.mq5").read_text()
        for token in ("OrderSend(", "OrderSendAsync(", "CTrade", "PositionClose(", "PositionModify("):
            self.assertNotIn(token, source)
        deals = read_native_deals(BROKER / "deals.csv", server_utc_offset_minutes=180)
        probe_start = int(datetime(2026, 10, 1, 16, 29, tzinfo=timezone.utc).timestamp() * 1000)
        self.assertTrue(all(deal.time_msc < probe_start for deal in deals))
        result = build()
        self.assertIn("MQL_TRADE_ALLOWED=1", result["research_permission_exception"])


if __name__ == "__main__":
    unittest.main()
