#!/usr/bin/env python3
"""Test whether the last Friday gold candle predicts tradable Monday moves.

Uses only completed FP demo M1 bars. The broker exports bid OHLC and bar spread,
so ask-side fills are estimates, not historical executable tick confirmations.
"""

import argparse
import csv
import json
from bisect import bisect_left
from datetime import datetime, timedelta, timezone
from pathlib import Path
from statistics import mean, median

UTC = timezone.utc
HORIZONS = (15, 60, 240)


def load_bars(path):
    bars = []
    with path.open(newline="") as stream:
        for raw in csv.DictReader(stream):
            bars.append({
                # MT5 stores broker-server wall-clock seconds. Keep the wall clock
                # naive so it is never mistaken for a verified UTC timestamp.
                "time": datetime.fromtimestamp(int(raw["server_epoch"]), UTC).replace(tzinfo=None),
                "open": float(raw["bid_open"]),
                "high": float(raw["bid_high"]),
                "low": float(raw["bid_low"]),
                "close": float(raw["bid_close"]),
                "spread": int(raw["spread_points"]) * float(raw["point"]),
                "ticks": int(raw["tick_volume"]),
            })
    if not bars or any(a["time"] >= b["time"] for a, b in zip(bars, bars[1:])):
        raise ValueError("Bars must be nonempty and strictly increasing")
    return bars


def direction(opening, closing):
    return "BUY" if closing > opening else "SELL" if closing < opening else "FLAT"


def endpoint(bars, times, begin, minutes):
    target = bars[begin]["time"] + timedelta(minutes=minutes)
    index = bisect_left(times, target, begin)
    if index >= len(bars) or bars[index]["time"] > target + timedelta(minutes=2):
        return None
    return index


def first_barrier(bars, start, end, side, entry, dollars=10.0):
    for bar in bars[start:end + 1]:
        if side == "BUY":
            win = bar["high"] - entry >= dollars
            loss = bar["low"] - entry <= -dollars
        else:
            win = entry - (bar["low"] + bar["spread"]) >= dollars
            loss = entry - (bar["high"] + bar["spread"]) <= -dollars
        if win and loss:
            return "AMBIGUOUS_SAME_BAR"
        if win:
            return "PLUS_10_FIRST"
        if loss:
            return "MINUS_10_FIRST"
    return "NEITHER"


def analyze(bars):
    times = [bar["time"] for bar in bars]
    rows = []
    for i in range(len(bars) - 1):
        friday, monday = bars[i], bars[i + 1]
        hours = (monday["time"] - friday["time"]).total_seconds() / 3600
        if not (40 <= hours <= 80 and friday["time"].weekday() == 4 and monday["time"].weekday() == 0):
            continue
        day_start = i
        while day_start > 0 and bars[day_start - 1]["time"].date() == friday["time"].date():
            day_start -= 1
        hour_start = bisect_left(times, friday["time"] - timedelta(minutes=59), day_start, i + 1)
        if i - hour_start + 1 < 45:
            continue
        ends = {str(minutes): endpoint(bars, times, i + 1, minutes) for minutes in HORIZONS}
        if ends["240"] is None:
            continue
        buy_entry = monday["open"] + monday["spread"]
        sell_entry = monday["open"]
        window = bars[i + 1:ends["240"] + 1]
        buy_mfe = max(bar["high"] - buy_entry for bar in window)
        buy_mae = min(bar["low"] - buy_entry for bar in window)
        sell_mfe = max(sell_entry - (bar["low"] + bar["spread"]) for bar in window)
        sell_mae = min(sell_entry - (bar["high"] + bar["spread"]) for bar in window)
        row = {
            "friday_server_date": friday["time"].date().isoformat(),
            "last_friday_bar_server": friday["time"].isoformat(),
            "first_monday_bar_server": monday["time"].isoformat(),
            "closed_m1_direction": direction(friday["open"], friday["close"]),
            "closed_h1_direction": direction(bars[hour_start]["open"], friday["close"]),
            "closed_friday_direction": direction(bars[day_start]["open"], friday["close"]),
            "friday_close_bid": friday["close"],
            "monday_open_bid": monday["open"],
            "monday_open_spread_estimate": monday["spread"],
            "weekend_gap_bid": monday["open"] - friday["close"],
            "buy_mfe_4h": buy_mfe,
            "buy_mae_4h": buy_mae,
            "sell_mfe_4h": sell_mfe,
            "sell_mae_4h": sell_mae,
            "buy_first_10_barrier_4h": first_barrier(bars, i + 1, ends["240"], "BUY", buy_entry),
            "sell_first_10_barrier_4h": first_barrier(bars, i + 1, ends["240"], "SELL", sell_entry),
            "buy_10k_budget_touched_4h": buy_mae <= -0.4,
            "buy_100k_budget_touched_4h": buy_mae <= -4.0,
            "sell_10k_budget_touched_4h": sell_mae <= -0.4,
            "sell_100k_budget_touched_4h": sell_mae <= -4.0,
        }
        for minutes in HORIZONS:
            end = ends[str(minutes)]
            row[f"buy_net_{minutes}m"] = None if end is None else bars[end]["close"] - buy_entry
            row[f"sell_net_{minutes}m"] = None if end is None else sell_entry - (bars[end]["close"] + bars[end]["spread"])
        rows.append(row)
    return rows


def group_summary(rows, signal, side):
    label = side.lower()
    chosen = [row for row in rows if signal == "ALL" or row[signal] == side]
    returns = {str(h): [row[f"{label}_net_{h}m"] for row in chosen if row[f"{label}_net_{h}m"] is not None] for h in HORIZONS}
    barriers = [row[f"{label}_first_10_barrier_4h"] for row in chosen]
    gaps = [row["weekend_gap_bid"] for row in chosen]
    return {
        "n": len(chosen),
        "side": side,
        "same_side_weekend_gap_count": sum((x > 0) if side == "BUY" else (x < 0) for x in gaps),
        "net_win_count": {h: sum(x > 0 for x in values) for h, values in returns.items()},
        "net_mean_usd_per_ounce": {h: round(mean(values), 4) if values else None for h, values in returns.items()},
        "net_median_usd_per_ounce": {h: round(median(values), 4) if values else None for h, values in returns.items()},
        "plus_10_before_minus_10": barriers.count("PLUS_10_FIRST"),
        "minus_10_before_plus_10": barriers.count("MINUS_10_FIRST"),
        "ambiguous_same_bar": barriers.count("AMBIGUOUS_SAME_BAR"),
        "neither_10_barrier": barriers.count("NEITHER"),
        "nominal_10k_daily_budget_move_touched": sum(row[f"{label}_10k_budget_touched_4h"] for row in chosen),
        "nominal_100k_daily_budget_move_touched": sum(row[f"{label}_100k_budget_touched_4h"] for row in chosen),
    }


def main(input_path, output_dir):
    output_dir.mkdir(parents=True, exist_ok=True)
    bars = load_bars(input_path)
    rows = analyze(bars)
    if not rows:
        raise RuntimeError("No complete weekend close/reopen pairs in broker data")
    with (output_dir / "weekends.csv").open("w", newline="") as stream:
        writer = csv.DictWriter(stream, fieldnames=list(rows[0]))
        writer.writeheader()
        writer.writerows(rows)
    latest = bars[-1]
    latest_day = latest["time"].date()
    first = next(bar for bar in bars if bar["time"].date() == latest_day)
    hour_start = bisect_left([bar["time"] for bar in bars], latest["time"] - timedelta(minutes=59))
    summary = {
        "data_source": "FPMarketsSC-Demo XAUUSD.r M1 bid bars; spread is per-bar estimate, not exact fill",
        "broker_history_rows": len(bars),
        "broker_history_start_server": bars[0]["time"].isoformat(),
        "broker_history_end_server": latest["time"].isoformat(),
        "complete_weekend_pairs": len(rows),
        "signals": {
            signal: {side: group_summary(rows, signal, side) for side in ("BUY", "SELL")}
            for signal in ("ALL", "closed_m1_direction", "closed_h1_direction", "closed_friday_direction")
        },
        "latest_friday": {
            "server_date": latest_day.isoformat(),
            "last_bar_server": latest["time"].isoformat(),
            "last_m1": direction(latest["open"], latest["close"]),
            "last_h1": direction(bars[hour_start]["open"], latest["close"]),
            "friday_session": direction(first["open"], latest["close"]),
            "closing_bid": latest["close"],
            "next_reopen_observed": False,
        },
    }
    (output_dir / "summary.json").write_text(json.dumps(summary, indent=2) + "\n")
    return summary


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("input", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    print(json.dumps(main(args.input, args.output), indent=2))
