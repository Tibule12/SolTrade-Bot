#!/usr/bin/env python3
"""Make bounded read-only FP tick requests around every frozen-manager broker entry."""

import argparse
import csv
from collections import defaultdict
from datetime import datetime, timedelta
from pathlib import Path

DEFAULT_DEALS = Path("reports/fast-multi-market-v2/three-account-replay-20261001/broker-refresh-fp/deals.csv")
DEFAULT_OUT = Path("reports/fast-multi-market-v2/three-account-replay-20261001/fp-entry-window-requests.csv")
LIFETIME_OUT = Path("reports/fast-multi-market-v2/three-account-replay-20261001/fp-baseline-lifetime-requests.csv")
CUTOFF_SERVER = datetime(2026, 9, 13, 10, 23, 58)
FORMAT = "%Y.%m.%d %H:%M:%S"


def build(deals_path, output_path, mode="entry_window"):
    groups = defaultdict(list)
    with deals_path.open(newline="") as handle:
        for row in csv.DictReader(handle):
            if row["position_id"] != "0":
                groups[row["position_id"]].append(row)
    requests = []
    for position, rows in groups.items():
        opens = [r for r in rows if r["entry"] == "0"]
        if len(opens) != 1:
            continue
        first = opens[0]
        entered = datetime.strptime(first["time_server"], FORMAT)
        if entered < CUTOFF_SERVER:
            continue
        closes = [r for r in rows if r["entry"] == "1"]
        if mode == "baseline_lifetime" and not closes:
            continue
        final = (max(datetime.strptime(r["time_server"], FORMAT) for r in closes) + timedelta(seconds=60)) if mode == "baseline_lifetime" else (entered + timedelta(minutes=5))
        requests.append({
            "case_id": ("fp-life-" if mode == "baseline_lifetime" else "fp-entry-") + position,
            "symbol": first["symbol"],
            "from": (entered - timedelta(seconds=60)).strftime(FORMAT),
            "to": final.strftime(FORMAT),
        })
    requests.sort(key=lambda r: (r["from"], r["case_id"]))
    output_path.parent.mkdir(parents=True, exist_ok=True)
    with output_path.open("w", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=["case_id", "symbol", "from", "to"])
        writer.writeheader()
        writer.writerows(requests)
    return len(requests)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--deals", type=Path, default=DEFAULT_DEALS)
    parser.add_argument("--output", type=Path, default=DEFAULT_OUT)
    parser.add_argument("--mode", choices=("entry_window", "baseline_lifetime"), default="entry_window")
    args = parser.parse_args()
    output = LIFETIME_OUT if args.mode == "baseline_lifetime" and args.output == DEFAULT_OUT else args.output
    print(build(args.deals, output, args.mode))
