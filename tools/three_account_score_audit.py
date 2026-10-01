#!/usr/bin/env python3
"""Describe recorded FP entry scores against completed EA outcomes; never trade."""

import argparse
import csv
import json
import math
import re
import statistics
from collections import Counter, defaultdict
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DEFAULT_EVIDENCE = ROOT / "reports/fast-multi-market-v2/full-live-audit-20260930/evidence/fp-evidence.csv"
DEFAULT_OUTPUT = ROOT / "reports/fast-multi-market-v2/three-account-replay-20261001"
SCORE_BOUNDS = (60, 62.5, 65, 67.5, 70, 72.5, 75, 77.5)


def fields(text):
    return dict(re.findall(r"(?:^|;)([A-Za-z_][A-Za-z_0-9]*)=([^;]*)", text or ""))


def number(value):
    try:
        return float(value)
    except (TypeError, ValueError):
        return None


def label(score):
    if score is None:
        return "MISSING"
    if score < SCORE_BOUNDS[0]:
        return "<60"
    for lo, hi in zip(SCORE_BOUNDS, SCORE_BOUNDS[1:]):
        if lo <= score < hi:
            return f"{lo:g}-{hi:g}"
    return "77.5+"


def ranks(values):
    order = sorted(range(len(values)), key=values.__getitem__)
    answer = [0.0] * len(values)
    for start in range(len(values)):
        if start and values[order[start]] == values[order[start - 1]]:
            continue
        end = start + 1
        while end < len(values) and values[order[end]] == values[order[start]]:
            end += 1
        for i in range(start, end):
            answer[order[i]] = (start + end - 1) / 2 + 1
    return answer


def correlation(xs, ys):
    if len(xs) < 3:
        return None
    mx, my = statistics.mean(xs), statistics.mean(ys)
    numerator = sum((x - mx) * (y - my) for x, y in zip(xs, ys))
    denominator = math.sqrt(sum((x - mx) ** 2 for x in xs) * sum((y - my) ** 2 for y in ys))
    return numerator / denominator if denominator else None


def summary(rows):
    rs = [r["final_r"] for r in rows]
    return {
        "n": len(rows),
        "wins": sum(r > 0 for r in rs),
        "losses": sum(r < 0 for r in rs),
        "full_stop_losses": sum(r["exit_class"] == "INITIAL_STRUCTURAL_STOP_EXIT" for r in rows),
        "confirmed_bank1r": sum(r["bank1_confirmed"] for r in rows),
        "price_peak_2r": sum((r["peak_price_r"] or 0) >= 2 for r in rows),
        "price_peak_3r": sum((r["peak_price_r"] or 0) >= 3 for r in rows),
        "price_peak_5r": sum((r["peak_price_r"] or 0) >= 5 for r in rows),
        "average_r": statistics.mean(rs) if rs else None,
        "median_r": statistics.median(rs) if rs else None,
        "total_r": sum(rs),
        "total_cash": sum(r["net_cash"] for r in rows),
    }


def load_trades(path):
    entries = {}
    exits = []
    bank_events = set()
    with path.open(newline="") as handle:
        for row in csv.DictReader(handle):
            event = row["event"]
            if event == "ENTRY":
                entries[row["ticket"]] = row
            elif event in ("PARTIAL_BANK_1R", "PARTIAL_EXIT_DEAL"):
                bank_events.add(row["ticket"])
            elif event == "EXIT":
                exits.append(row)
    trades = []
    unmatched_exits = []
    matched = set()
    for exit_row in exits:
        detail = fields(exit_row["detail"])
        ticket = detail.get("position_id")
        entry = entries.get(ticket)
        final_r = number(detail.get("final_total_r", detail.get("PROTECTED_R")))
        net_cash = number(detail.get("net"))
        if not entry or final_r is None or net_cash is None:
            unmatched_exits.append(ticket)
            continue
        matched.add(ticket)
        nc = fields(entry["no_trade_case"])
        own = fields(entry["buy_case"] if entry["direction"] == "BUY" else entry["sell_case"])
        opposite = fields(entry["sell_case"] if entry["direction"] == "BUY" else entry["buy_case"])
        bank = detail.get("partial_banking") == "true" or ticket in bank_events
        entry_detail = fields(entry["detail"])
        try:
            source = str(path.relative_to(ROOT))
        except ValueError:
            source = str(path)
        trades.append({
            "account": "FP 7404213", "position_id": ticket, "symbol": entry["symbol"],
            "direction": entry["direction"], "entry_utc": entry["utc"],
            "exit_utc": exit_row["utc"], "entry_price": number(entry["entry"]),
            "initial_stop": number(entry["stop"]), "admission_score": number(nc.get("admission_score")),
            "initial_dollar_risk": number(entry_detail.get("initial_risk", detail.get("initial_dollar_risk"))),
            "directional_score": number(own.get("score")),
            "opposite_score": number(opposite.get("score")),
            "no_trade_score": number(nc.get("score")), "conflict": nc.get("conflict"),
            "m1": entry["m1"], "m5": entry["m5"], "m15": entry["m15"], "h1": entry["h1"],
            "final_r": final_r, "net_cash": net_cash, "exit_class": detail.get("exit_class", ""),
            "bank1_confirmed": bank, "peak_price_r": number(detail.get("RUNNER_PEAK_R")),
            "source": source,
            "baseline_evidence": "EA_EVENT_SCORE__BROKER_NET_RECONCILIATION_SEPARATE",
        })
    return sorted(trades, key=lambda r: (r["entry_utc"], r["position_id"])), {
        "entry_events": len(entries), "exit_events": len(exits), "matched_closed": len(trades),
        "unmatched_exit_position_ids": unmatched_exits,
        "entry_without_exit_position_ids": sorted(set(entries) - matched),
    }


def analyze(trades, coverage):
    cohorts = {
        "all_available_mixed_strategy_versions": trades,
        "frozen_fp_manager_from_2026_09_13": [r for r in trades if r["entry_utc"] >= "2026.09.13"],
    }
    output = {"schema": "SOLTRADE_RECORDED_SCORE_DIAGNOSTIC_V1", "coverage": coverage,
              "interpretation": "Descriptive association on actual admitted FP trades only. Neither opposite-direction fills nor rejected opportunities are represented. Price-peak thresholds do not prove executable net-cash milestones; Bank1R uses confirmed partial events.",
              "cohorts": {}}
    for name, rows in cohorts.items():
        result = {"summary": summary(rows), "score_fields": {}, "timeframe_state": {}, "no_trade_score": {}, "conflict": {}}
        for field in ("admission_score", "directional_score", "opposite_score"):
            eligible = [r for r in rows if r[field] is not None]
            by_band = defaultdict(list)
            for row in eligible:
                by_band[label(row[field])].append(row)
            xs, ys = [r[field] for r in eligible], [r["final_r"] for r in eligible]
            decile_rows = defaultdict(list)
            ordered = sorted(eligible, key=lambda r: (r[field], r["position_id"]))
            for index, row in enumerate(ordered):
                decile_rows[min(10, index * 10 // len(ordered) + 1)].append(row)
            result["score_fields"][field] = {
                "pearson_r": correlation(xs, ys),
                "spearman_r": correlation(ranks(xs), ranks(ys)) if xs else None,
                "fixed_bands": {key: summary(value) for key, value in sorted(by_band.items())},
                "rank_deciles": {str(key): {"min_score": min(r[field] for r in value),
                                             "max_score": max(r[field] for r in value),
                                             **summary(value)} for key, value in sorted(decile_rows.items())},
            }
        for field in ("m1", "m5", "m15", "h1"):
            buckets = defaultdict(list)
            for row in rows:
                state = row[field]
                if "RANGE" in state or "TRANSITION" in state:
                    agreement = "NON_DIRECTIONAL"
                elif ("BULL" in state and row["direction"] == "BUY") or ("BEAR" in state and row["direction"] == "SELL"):
                    agreement = "AGREES"
                elif "BULL" in state or "BEAR" in state:
                    agreement = "OPPOSES"
                else:
                    agreement = "UNKNOWN"
                buckets[agreement].append(row)
            result["timeframe_state"][field] = {key: summary(value) for key, value in buckets.items()}
        for field in ("no_trade_score", "conflict"):
            buckets = defaultdict(list)
            for row in rows:
                buckets[str(row[field])].append(row)
            result[field] = {key: summary(value) for key, value in sorted(buckets.items())}
        output["cohorts"][name] = result
    return output


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--evidence", type=Path, default=DEFAULT_EVIDENCE)
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT)
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    trades, coverage = load_trades(args.evidence)
    if trades:
        with (args.output / "fp-score-trades.csv").open("w", newline="") as handle:
            writer = csv.DictWriter(handle, fieldnames=list(trades[0]))
            writer.writeheader()
            writer.writerows(trades)
    (args.output / "fp-score-diagnostic.json").write_text(json.dumps(analyze(trades, coverage), indent=2) + "\n")
    print(json.dumps(coverage))


if __name__ == "__main__":
    main()
