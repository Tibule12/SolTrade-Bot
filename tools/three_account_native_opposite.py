#!/usr/bin/env python3
"""Reconstruct frozen native FP opposite-stop geometry from causal completed bars.

This module never substitutes mirrored distance for an unavailable native stop.
Historical broker stop/freeze levels are not supplied by MT5 history APIs, so
the provenance and exactness status remain explicit in each output row.
"""

import argparse
import csv
import gzip
import hashlib
import json
import shutil
from collections import defaultdict
from datetime import datetime, timedelta
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / 'ops/forexvps/releases/fp-adaptive-payoff-v1-bank1r-giveback-20260912/SolTradeFastMultiMarketV2.mq5'
PREVIOUS = ROOT / 'reports/fast-multi-market-v2/three-account-replay-20261001'
DEFAULT_OUTPUT = ROOT / 'reports/fast-multi-market-v2/three-account-replay-completion-20261001/native-opposite'


def rows(path):
    with path.open(newline='') as stream:
        return list(csv.DictReader(stream))


def sha256(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def broker_entry_ms(utc_text):
    parsed = datetime.fromisoformat(utc_text.replace('Z', '+00:00'))
    return int(parsed.timestamp() * 1000) + 3 * 3600 * 1000


def prepare_requests(output=DEFAULT_OUTPUT):
    output.mkdir(parents=True, exist_ok=True)
    selected = {row['case_id'].removeprefix('fp-entry-') for row in rows(PREVIOUS / 'fp-entry-window-requests.csv')}
    positions = [row for row in rows(PREVIOUS / 'fp-broker-position-ledger.csv') if row['position_id'] in selected]
    positions.sort(key=lambda row: row['entry_utc'])
    assert len(positions) == len(selected) == 29, 'Expected frozen 29 FP quote-path positions'
    request = output / 'native-stop-requests.csv'
    with request.open('w', newline='') as stream:
        writer = csv.writer(stream)
        writer.writerow(['case_id', 'symbol', 'entry_server', 'ignored'])
        for row in positions:
            entry = datetime.fromisoformat(row['entry_utc']) + timedelta(hours=3)
            writer.writerow([row['position_id'], row['symbol'], entry.strftime('%Y.%m.%d %H:%M:%S'), ''])
    prehistory = output / 'prehistory-tick-requests.csv'
    with prehistory.open('w', newline='') as stream:
        writer = csv.writer(stream)
        writer.writerow(['case_id', 'symbol', 'from', 'to'])
        for row in positions:
            entry = datetime.fromisoformat(row['entry_utc']) + timedelta(hours=3)
            lookback = timedelta(hours=80 if entry.weekday() == 0 and entry.hour < 8 else 6)
            writer.writerow([f'fp-prebar-{row["position_id"]}', row['symbol'],
                             (entry - lookback).strftime('%Y.%m.%d %H:%M:%S'),
                             entry.strftime('%Y.%m.%d %H:%M:%S')])
    return request


def aggregate_tick_bars(output=DEFAULT_OUTPUT, paths=None):
    """Retain broker tick evidence and derive only bars completed before entry."""
    from audit_fp_all_symbols import PATHS

    output.mkdir(parents=True, exist_ok=True)
    paths = Path(paths or PATHS)
    raw_folder = output / 'prehistory-ticks'
    raw_folder.mkdir(exist_ok=True)
    coverage_path = output / 'prehistory-export/path-coverage-native-prehistory-20261001.csv'
    coverage = {row['case_id']: row for row in rows(coverage_path)}
    selected = {row['case_id'].removeprefix('fp-entry-') for row in rows(PREVIOUS / 'fp-entry-window-requests.csv')}
    positions = [row for row in rows(PREVIOUS / 'fp-broker-position-ledger.csv') if row['position_id'] in selected]
    all_bars = []
    receipts = []
    for position in sorted(positions, key=lambda item: item['entry_utc']):
        pid = position['position_id']
        case = f'fp-prebar-{pid}'
        original = paths / f'ticks-{case}.csv'
        archived = raw_folder / f'ticks-{case}.csv.gz'
        if not original.exists():
            receipts.append({'position_id': pid, 'status': 'UNRESOLVED_BROKER_TICKS_MISSING', 'ticks': 0})
            continue
        with original.open('rb') as source, gzip.open(archived, 'wb', compresslevel=6) as target:
            shutil.copyfileobj(source, target)
        entry_ms = broker_entry_ms(position['entry_utc'])
        tick_count = 0
        previous_ms = -1
        timestamps_ok = True
        by_frame = {5: {}, 15: {}}
        with original.open(newline='') as stream:
            for row in csv.DictReader(stream):
                timestamp = int(row['time_msc'])
                if timestamp < previous_ms:
                    timestamps_ok = False
                previous_ms = timestamp
                if timestamp >= entry_ms:
                    continue
                bid = float(row['bid'])
                ask = float(row['ask'])
                if bid <= 0 or ask < bid:
                    continue
                tick_count += 1
                for minutes in (5, 15):
                    duration = minutes * 60 * 1000
                    bucket = timestamp // duration * duration
                    containing = entry_ms // duration * duration
                    if bucket >= containing:
                        continue
                    record = by_frame[minutes].get(bucket)
                    if record is None:
                        by_frame[minutes][bucket] = {
                            'open': bid, 'high': bid, 'low': bid, 'close': bid,
                            'ticks': 1, 'first_tick_msc': timestamp, 'last_tick_msc': timestamp,
                        }
                    else:
                        record['high'] = max(record['high'], bid)
                        record['low'] = min(record['low'], bid)
                        record['close'] = bid
                        record['ticks'] += 1
                        record['last_tick_msc'] = timestamp
        case_coverage = coverage.get(case, {})
        for minutes in (5, 15):
            selected_buckets = sorted(by_frame[minutes], reverse=True)[:20]
            for shift, bucket in enumerate(selected_buckets, start=1):
                bar = by_frame[minutes][bucket]
                all_bars.append({
                    'case_id': pid, 'symbol': position['symbol'], 'timeframe_minutes': minutes,
                    'completed_shift': shift, 'bar_open_server_epoch': bucket // 1000,
                    'open': bar['open'], 'high': bar['high'], 'low': bar['low'], 'close': bar['close'],
                    'tick_volume': bar['ticks'], 'first_tick_msc': bar['first_tick_msc'],
                    'last_tick_msc': bar['last_tick_msc'],
                })
        receipts.append({
            'position_id': pid,
            'status': 'BROKER_TICK_BARS_RECONSTRUCTED' if case_coverage.get('error') == '0' and timestamps_ok else 'UNRESOLVED_TICK_COVERAGE',
            'ticks': tick_count,
            'm5_completed_bars': len(by_frame[5]),
            'm15_completed_bars': len(by_frame[15]),
            'entry_server_msc': entry_ms,
            'archive_sha256': sha256(archived),
            'archive': str(archived.relative_to(ROOT)),
            'last_raw_tick_server_msc': previous_ms,
            'timestamps_nondecreasing': timestamps_ok,
        })
    bar_path = output / 'native-stop-bars-from-broker-ticks.csv'
    with bar_path.open('w', newline='') as stream:
        writer = csv.DictWriter(stream, fieldnames=list(all_bars[0]))
        writer.writeheader();writer.writerows(all_bars)
    receipt_path = output / 'native-stop-broker-tick-coverage.json'
    receipt_path.write_text(json.dumps(receipts, indent=2) + '\n')
    return {'positions': len(receipts), 'bars': len(all_bars), 'bar_path': str(bar_path),
            'coverage_path': str(receipt_path)}


def true_range(current, previous):
    return max(current['high'] - current['low'],
               abs(current['high'] - previous['close']),
               abs(current['low'] - previous['close']))


def average_range(bars, start, count):
    # bars[0] is the last bar fully completed before hypothetical execution.
    return sum(true_range(bars[i], bars[i + 1]) for i in range(start, start + count)) / count


def native_stop(bars5, bars15, direction, entry, spread, point, stop_level, freeze_level):
    """Exact ScoreSymbol stop geometry except for historical symbol metadata provenance."""
    if len(bars5) < 17 or len(bars15) < 15:
        raise ValueError('insufficient completed M5/M15 bars')
    if point <= 0 or spread < 0:
        raise ValueError('invalid quote or point')
    atr5 = average_range(bars5, 0, 14)
    atr15 = average_range(bars15, 0, 14)
    if atr5 <= 0 or atr15 <= 0:
        raise ValueError('invalid ATR')
    if direction == 'BUY':
        swing5 = min(bar['low'] for bar in bars5[:8])
        swing15 = min(bar['low'] for bar in bars15[:6])
        invalidation = max(swing5, swing15)
        structural_distance = entry - invalidation
        stop_sign = -1
    elif direction == 'SELL':
        swing5 = max(bar['high'] for bar in bars5[:8])
        swing15 = max(bar['high'] for bar in bars15[:6])
        invalidation = min(swing5, swing15)
        structural_distance = invalidation - entry
        stop_sign = +1
    else:
        raise ValueError('direction must be BUY or SELL')
    volatility_expansion = average_range(bars5, 0, 4) / max(average_range(bars5, 4, 12), point)
    expansion_buffer = (0.18 + 0.22 * max(0.0, min(volatility_expansion - 1.0, 1.5))) * atr5 + 2 * spread
    raw_distance = structural_distance + expansion_buffer
    volatility_floor = max(1.15 * atr5, 0.55 * atr15)
    broker_floor = max(stop_level, freeze_level) * point + 2 * point
    distance = max(raw_distance, volatility_floor, broker_floor)
    return {
        'direction': direction,
        'entry': entry,
        'swing_m5': swing5,
        'swing_m15': swing15,
        'selected_invalidation': invalidation,
        'atr_m5': atr5,
        'atr_m15': atr15,
        'volatility_expansion': volatility_expansion,
        'expansion_buffer': expansion_buffer,
        'structural_distance_before_buffer': structural_distance,
        'raw_distance': raw_distance,
        'volatility_floor': volatility_floor,
        'broker_floor_using_current_metadata': broker_floor,
        'broker_floor_binding_using_current_metadata': broker_floor > max(raw_distance, volatility_floor),
        'initial_distance': distance,
        'stop_unrounded': entry + stop_sign * distance,
    }


def tick_normalize(price, tick_size, digits):
    if tick_size <= 0:
        return round(price, digits)
    # MQL MathRound on positive prices is half-up, not Python's ties-to-even.
    return round(int(price / tick_size + 0.5) * tick_size, digits)


def find_entry_quote(position_id, entry_ms):
    path = PREVIOUS / 'fp-entry-window-ticks' / f'ticks-fp-entry-{position_id}.csv'
    if not path.exists():
        return None, None
    selected = None
    with path.open(newline='') as stream:
        for row in csv.DictReader(stream):
            timestamp = int(row['time_msc'])
            if timestamp > entry_ms:
                break
            if timestamp >= entry_ms - 2000:
                selected = (timestamp, float(row['bid']), float(row['ask']))
    return selected, path


def index_opening_stops(order_rows, deal_rows):
    orders = {row['ticket']: row for row in order_rows}
    result = {}
    for deal in deal_rows:
        if deal['entry'] != '0' or not deal['position_id']:
            continue
        order = orders.get(deal['order'])
        if order and float(order['sl']) > 0:
            result[deal['position_id']] = float(order['sl'])
    return result


def calculate(output=DEFAULT_OUTPUT, export_dir=None):
    output.mkdir(parents=True, exist_ok=True)
    export_dir = Path(export_dir or output / 'bar-export')
    suffix = '-fp-20261001'
    coverage_path = export_dir / f'native-stop-coverage{suffix}.csv'
    bar_path = export_dir / f'native-stop-bars{suffix}.csv'
    spec_path = export_dir / f'native-stop-specifications{suffix}.csv'
    status_path = export_dir / f'native-stop-status{suffix}.csv'
    status_rows = rows(status_path)
    if len(status_rows) != 1 or status_rows[0]['status'] != 'COMPLETE' or status_rows[0]['account'] != '7404213':
        raise ValueError('Read-only FP bar export is not complete')
    coverage = {(row['case_id'], int(row['timeframe_minutes'])): row for row in rows(coverage_path)}
    specs = {row['case_id']: row for row in rows(spec_path)}
    broker_tick_bar_path = output / 'native-stop-bars-from-broker-ticks.csv'
    broker_tick_receipt_path = output / 'native-stop-broker-tick-coverage.json'
    if not broker_tick_bar_path.exists() or not broker_tick_receipt_path.exists():
        raise ValueError('Causal broker-tick bar reconstruction is required; stale terminal bar cache is rejected')
    tick_receipts = {row['position_id']: row for row in json.loads(broker_tick_receipt_path.read_text())}
    bars = defaultdict(list)
    for row in rows(broker_tick_bar_path):
        bars[(row['case_id'], int(row['timeframe_minutes']))].append({
            'time': int(row['bar_open_server_epoch']),
            'shift': int(row['completed_shift']),
            'open': float(row['open']), 'high': float(row['high']),
            'low': float(row['low']), 'close': float(row['close']),
        })
    for group in bars.values():
        group.sort(key=lambda item: item['shift'])
    selections = {row['case_id'].removeprefix('fp-entry-') for row in rows(PREVIOUS / 'fp-entry-window-requests.csv')}
    positions = [row for row in rows(PREVIOUS / 'fp-broker-position-ledger.csv') if row['position_id'] in selections]
    actual_stops = index_opening_stops(rows(PREVIOUS / 'broker-refresh-fp/orders.csv'), rows(PREVIOUS / 'broker-refresh-fp/deals.csv'))
    score_rows = {row['position_id']: row for row in rows(PREVIOUS / 'fp-score-trades.csv')}
    loss_ids = {row['position_id'] for row in rows(PREVIOUS / 'per-loss-attribution.csv')
                if row['account'] == 'FP 7404213' and row['manager_cohort'] == 'FROZEN_BANK1R_FROM_SEP13'
                and row['observed_exit_class'] == 'INITIAL_STRUCTURAL_STOP_EXIT'}
    fieldnames = [
        'account', 'position_id', 'symbol', 'entry_utc', 'actual_direction', 'opposite_direction',
        'is_fourteen_stop_loss', 'actual_fill_price', 'actual_initial_stop', 'entry_quote_server_msc',
        'entry_quote_lag_ms', 'entry_bid', 'entry_ask', 'spread', 'completed_m5_open_server_epoch',
        'completed_m15_open_server_epoch', 'bar_status', 'quote_status', 'actual_stop_reconstruction_status',
        'actual_stop_reconstructed', 'actual_stop_difference_ticks', 'native_opposite_status',
        'native_opposite_entry', 'native_opposite_stop', 'native_opposite_initial_distance',
        'native_opposite_m5_swing', 'native_opposite_m15_swing', 'native_opposite_selected_invalidation',
        'native_opposite_m5_atr', 'native_opposite_m15_atr', 'native_opposite_volatility_expansion',
        'native_opposite_expansion_buffer', 'native_opposite_volatility_floor',
        'native_opposite_broker_floor_using_current_metadata', 'broker_floor_binding_using_current_metadata',
        'historical_broker_floor_available', 'exact_native_stop_price', 'bar_source',
        'causal_tick_coverage_status', 'unresolved_reason',
    ]
    results = []
    for position in sorted(positions, key=lambda item: item['entry_utc']):
        pid = position['position_id']
        entry_ms = broker_entry_ms(position['entry_utc'])
        quote, _ = find_entry_quote(pid, entry_ms)
        actual_dir = position['direction']
        opposite_dir = 'SELL' if actual_dir == 'BUY' else 'BUY'
        spec = specs.get(pid)
        c5, c15 = coverage.get((pid, 5)), coverage.get((pid, 15))
        bars5, bars15 = bars.get((pid, 5), []), bars.get((pid, 15), [])
        tick_receipt = tick_receipts.get(pid, {})
        bar_good = bool(tick_receipt.get('status') == 'BROKER_TICK_BARS_RECONSTRUCTED'
                        and len(bars5) >= 18 and len(bars15) >= 18
                        and bars5[0]['time'] + 300 <= entry_ms // 1000
                        and bars15[0]['time'] + 900 <= entry_ms // 1000)
        row = {key: '' for key in fieldnames}
        row.update(account='FP 7404213', position_id=pid, symbol=position['symbol'],
                   entry_utc=position['entry_utc'], actual_direction=actual_dir,
                   opposite_direction=opposite_dir, is_fourteen_stop_loss=str(pid in loss_ids).lower(),
                   actual_fill_price=position['entry_price'], actual_initial_stop=actual_stops.get(pid, ''),
                   completed_m5_open_server_epoch=bars5[0]['time'] if bars5 else '',
                   completed_m15_open_server_epoch=bars15[0]['time'] if bars15 else '',
                   bar_status='CAUSAL_TICK_AGGREGATED_COMPLETED_BARS' if bar_good else 'UNRESOLVED_COMPLETED_BARS',
                   quote_status='UNRESOLVED_ENTRY_QUOTE',
                   historical_broker_floor_available='false', exact_native_stop_price='false',
                   bar_source='COPY_TICKS_RANGE_BID_AGGREGATION',
                   causal_tick_coverage_status=tick_receipt.get('status', 'MISSING'))
        problems = []
        if not bar_good:
            problems.append('M5_OR_M15_COMPLETED_BARS_MISSING_OR_NONCAUSAL')
        if quote:
            timestamp, bid, ask = quote
            row.update(entry_quote_server_msc=timestamp, entry_quote_lag_ms=entry_ms - timestamp,
                       entry_bid=bid, entry_ask=ask, spread=ask - bid)
            production_quote = ask if actual_dir == 'BUY' else bid
            point = float(spec['point']) if spec else 0.0
            if point and abs(production_quote - float(position['entry_price'])) <= point / 10:
                row['quote_status'] = 'EXACT_PRODUCTION_FILL_SIDE_QUOTE'
            else:
                row['quote_status'] = 'ENTRY_QUOTE_DOES_NOT_MATCH_PRODUCTION_FILL'
                problems.append('EXECUTABLE_QUOTE_NOT_EQUAL_TO_BROKER_FILL')
        else:
            problems.append('NO_CAUSAL_QUOTE_WITHIN_TWO_SECONDS')
        if not spec:
            problems.append('SYMBOL_SPECIFICATION_MISSING')
        if pid not in actual_stops:
            problems.append('ORIGINAL_OPENING_ORDER_STOP_MISSING')
        if bar_good and quote and spec:
            point = float(spec['point'])
            tick_size = float(spec['tick_size'])
            digits = int(spec['digits'])
            stops = int(spec['stops_level_points'])
            freeze = int(spec['freeze_level_points'])
            spread = quote[2] - quote[1]
            original = native_stop(bars5, bars15, actual_dir, float(position['entry_price']), spread,
                                   point, stops, freeze)
            original_stop = tick_normalize(original['stop_unrounded'], tick_size, digits)
            row['actual_stop_reconstructed'] = original_stop
            if pid in actual_stops and tick_size:
                difference = abs(actual_stops[pid] - original_stop) / tick_size
                row['actual_stop_difference_ticks'] = round(difference, 6)
                if difference <= 0.01:
                    row['actual_stop_reconstruction_status'] = 'MATCHES_BROKER_OPENING_ORDER'
                else:
                    row['actual_stop_reconstruction_status'] = 'DOES_NOT_MATCH_BROKER_OPENING_ORDER'
                    problems.append('FROZEN_FORMULA_DOES_NOT_RECONCILE_ACTUAL_STOP')
            opposite_entry = quote[2] if opposite_dir == 'BUY' else quote[1]
            opposite = native_stop(bars5, bars15, opposite_dir, opposite_entry, spread,
                                   point, stops, freeze)
            opposite_stop = tick_normalize(opposite['stop_unrounded'], tick_size, digits)
            row.update(native_opposite_entry=opposite_entry, native_opposite_stop=opposite_stop,
                       native_opposite_initial_distance=abs(opposite_entry - opposite_stop),
                       native_opposite_m5_swing=opposite['swing_m5'],
                       native_opposite_m15_swing=opposite['swing_m15'],
                       native_opposite_selected_invalidation=opposite['selected_invalidation'],
                       native_opposite_m5_atr=opposite['atr_m5'],
                       native_opposite_m15_atr=opposite['atr_m15'],
                       native_opposite_volatility_expansion=opposite['volatility_expansion'],
                       native_opposite_expansion_buffer=opposite['expansion_buffer'],
                       native_opposite_volatility_floor=opposite['volatility_floor'],
                       native_opposite_broker_floor_using_current_metadata=opposite['broker_floor_using_current_metadata'],
                       broker_floor_binding_using_current_metadata=str(opposite['broker_floor_binding_using_current_metadata']).lower())
            if row['quote_status'] == 'EXACT_PRODUCTION_FILL_SIDE_QUOTE' and row['actual_stop_reconstruction_status'] == 'MATCHES_BROKER_OPENING_ORDER':
                row['native_opposite_status'] = 'NATIVE_STRUCTURE_RECONSTRUCTED_HISTORICAL_BROKER_FLOOR_UNVERIFIED'
            else:
                row['native_opposite_status'] = 'NATIVE_STRUCTURE_DIAGNOSTIC_ONLY'
            if opposite['broker_floor_binding_using_current_metadata']:
                problems.append('CURRENT_BROKER_STOP_OR_FREEZE_FLOOR_BINDS_AND_HISTORICAL_VALUE_UNKNOWN')
        else:
            row['native_opposite_status'] = 'UNRESOLVED_NATIVE_OPPOSITE_STRUCTURE'
        # The historical stops/freeze level is not in deal/order history. Never
        # mark a stop as exact solely because today's symbol metadata is known.
        problems.append('HISTORICAL_BROKER_STOP_AND_FREEZE_LEVELS_NOT_RECORDED')
        row['unresolved_reason'] = ';'.join(dict.fromkeys(problems))
        results.append(row)
    assert len(results) == 29 and sum(row['is_fourteen_stop_loss'] == 'true' for row in results) == 14
    out_csv = output / 'native-opposite-stops.csv'
    with out_csv.open('w', newline='') as stream:
        writer = csv.DictWriter(stream, fieldnames=fieldnames)
        writer.writeheader(); writer.writerows(results)
    summary = {
        'schema': 'FP_NATIVE_OPPOSITE_STOP_RECONSTRUCTION_V1',
        'account': 7404213,
        'position_count': len(results),
        'fourteen_initial_stop_loss_count': 14,
        'native_structure_reconstructed_count': sum(row['native_opposite_status'].startswith('NATIVE_STRUCTURE_RECONSTRUCTED') for row in results),
        'native_structure_unresolved_count': sum(row['native_opposite_status'] == 'UNRESOLVED_NATIVE_OPPOSITE_STRUCTURE' for row in results),
        'actual_stop_reconciled_count': sum(row['actual_stop_reconstruction_status'] == 'MATCHES_BROKER_OPENING_ORDER' for row in results),
        'exact_native_stop_price_count': 0,
        'historical_broker_floor_provenance': 'Unavailable in historical MT5 deal/order data; current metadata is marked as current, never historical.',
        'frozen_source_sha256': sha256(SOURCE),
        'input_sha256': {str(path.relative_to(ROOT)): sha256(path) for path in
                         (bar_path, coverage_path, spec_path, status_path, broker_tick_bar_path, broker_tick_receipt_path)},
        'out_csv': str(out_csv.relative_to(ROOT)),
    }
    (output / 'native-opposite-summary.json').write_text(json.dumps(summary, indent=2) + '\n')
    return summary


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('mode', choices=['prepare', 'aggregate', 'calculate'])
    parser.add_argument('--output', type=Path, default=DEFAULT_OUTPUT)
    parser.add_argument('--export-dir', type=Path)
    parser.add_argument('--paths', type=Path)
    args = parser.parse_args()
    if args.mode == 'prepare':
        print(prepare_requests(args.output))
    elif args.mode == 'aggregate':
        print(json.dumps(aggregate_tick_bars(args.output, args.paths), indent=2))
    else:
        print(json.dumps(calculate(args.output, args.export_dir), indent=2))
