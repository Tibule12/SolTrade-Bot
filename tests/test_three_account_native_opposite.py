import csv
import importlib.util
import tempfile
import unittest
from datetime import datetime
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
MODULE_PATH = ROOT / 'tools/three_account_native_opposite.py'
SPEC = importlib.util.spec_from_file_location('three_account_native_opposite', MODULE_PATH)
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


class NativeOppositeGeometryTests(unittest.TestCase):
    @staticmethod
    def bars():
        return [
            {'open': 100.0 + i * 0.02, 'high': 100.5 + i * 0.02,
             'low': 99.5 + i * 0.02, 'close': 100.0 + i * 0.02}
            for i in range(20)
        ]

    def test_native_buy_uses_maximum_of_completed_low_extremes(self):
        m5 = self.bars()
        m15 = self.bars()
        m5[4]['low'] = 98.0
        m15[4]['low'] = 97.0
        result = MODULE.native_stop(m5, m15, 'BUY', 101.0, 0.1, 0.01, 0, 0)
        self.assertEqual(result['swing_m5'], 98.0)
        self.assertEqual(result['swing_m15'], 97.0)
        self.assertEqual(result['selected_invalidation'], 98.0)
        self.assertEqual(result['stop_unrounded'], 101.0 - result['initial_distance'])

    def test_native_sell_uses_minimum_of_completed_high_extremes(self):
        m5 = self.bars()
        m15 = self.bars()
        m5[2]['high'] = 103.0
        m15[2]['high'] = 104.0
        result = MODULE.native_stop(m5, m15, 'SELL', 100.0, 0.1, 0.01, 0, 0)
        self.assertEqual(result['swing_m5'], 103.0)
        self.assertEqual(result['swing_m15'], 104.0)
        self.assertEqual(result['selected_invalidation'], 103.0)
        self.assertEqual(result['stop_unrounded'], 100.0 + result['initial_distance'])

    def test_broker_floor_is_distinct_from_volatility_and_structure(self):
        m5 = self.bars()
        m15 = self.bars()
        result = MODULE.native_stop(m5, m15, 'BUY', 101.0, 0.01, 0.01, 1000, 0)
        self.assertTrue(result['broker_floor_binding_using_current_metadata'])
        self.assertEqual(result['broker_floor_using_current_metadata'], 10.02)
        self.assertEqual(result['initial_distance'], 10.02)

    def test_requires_complete_history_and_direction(self):
        with self.assertRaises(ValueError):
            MODULE.native_stop(self.bars()[:10], self.bars(), 'BUY', 101.0, 0.1, 0.01, 0, 0)
        with self.assertRaises(ValueError):
            MODULE.native_stop(self.bars(), self.bars(), 'FLIP', 101.0, 0.1, 0.01, 0, 0)

    def test_request_contains_all_frozen_fp_quote_cases(self):
        with tempfile.TemporaryDirectory() as folder:
            path = MODULE.prepare_requests(Path(folder))
            with path.open(newline='') as stream:
                requests = list(csv.DictReader(stream))
            self.assertEqual(len(requests), 29)
            self.assertEqual(len({row['case_id'] for row in requests}), 29)
            self.assertTrue(all(row['entry_server'].startswith('2026.') for row in requests))

    def test_readonly_probe_contains_no_trade_api(self):
        source = (ROOT / 'tools/mql/SolTradeFPReadOnlyNativeStopBars.mq5').read_text()
        for token in ('OrderSend(', 'OrderSendAsync(', 'CTrade', '#include <Trade', '.Buy(', '.Sell(', 'PositionClose('):
            self.assertNotIn(token, source)
        self.assertIn('ACCOUNT_LOGIN)!=7404213', source)
        self.assertIn('v202-validation-terminal', source)

    def test_live_fourteen_losses_use_reconstructed_native_not_mirrored_stops(self):
        path = ROOT / 'reports/fast-multi-market-v2/three-account-replay-completion-20261001/native-opposite/native-opposite-stops.csv'
        if not path.exists():
            self.skipTest('live read-only broker evidence not present')
        with path.open(newline='') as stream:
            all_rows = list(csv.DictReader(stream))
        losses = [row for row in all_rows if row['is_fourteen_stop_loss'] == 'true']
        self.assertEqual(len(all_rows), 29)
        self.assertEqual(len(losses), 14)
        for row in losses:
            self.assertEqual(row['actual_stop_reconstruction_status'], 'MATCHES_BROKER_OPENING_ORDER')
            self.assertEqual(row['actual_stop_difference_ticks'], '0.0')
            self.assertEqual(row['quote_status'], 'EXACT_PRODUCTION_FILL_SIDE_QUOTE')
            self.assertEqual(row['bar_source'], 'COPY_TICKS_RANGE_BID_AGGREGATION')
            self.assertEqual(row['native_opposite_status'], 'NATIVE_STRUCTURE_RECONSTRUCTED_HISTORICAL_BROKER_FLOOR_UNVERIFIED')
            self.assertNotEqual(row['native_opposite_stop'], '')

    def test_live_opposite_entry_uses_correct_executable_quote_side(self):
        path = ROOT / 'reports/fast-multi-market-v2/three-account-replay-completion-20261001/native-opposite/native-opposite-stops.csv'
        if not path.exists():
            self.skipTest('live read-only broker evidence not present')
        with path.open(newline='') as stream:
            rows = list(csv.DictReader(stream))
        for row in rows:
            if not row['native_opposite_entry']:
                continue
            expected = row['entry_ask'] if row['opposite_direction'] == 'BUY' else row['entry_bid']
            self.assertAlmostEqual(float(row['native_opposite_entry']), float(expected), places=8)
            entry_server = MODULE.broker_entry_ms(row['entry_utc']) // 1000
            self.assertLessEqual(int(row['completed_m5_open_server_epoch']) + 300, entry_server)
            self.assertLessEqual(int(row['completed_m15_open_server_epoch']) + 900, entry_server)
            self.assertEqual(row['historical_broker_floor_available'], 'false')
            self.assertEqual(row['exact_native_stop_price'], 'false')


if __name__ == '__main__':
    unittest.main()
