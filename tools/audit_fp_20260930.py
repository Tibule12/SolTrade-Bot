#!/usr/bin/env python3
"""Read preserved FP EA evidence; never connects to MT5 or changes trading.

EXIT reports whole-position P&L, including older partials. It is deliberately
not presented as the period's account balance movement. Peak price R is also
kept distinct from net cash R and the money-based Bank1R trigger.
"""
from __future__ import annotations

import argparse
import csv
import hashlib
import json
from collections import Counter, defaultdict
from datetime import datetime, timezone
from decimal import Decimal
from pathlib import Path
from statistics import mean, median

BASE = Path(__file__).resolve().parents[1]
FROZEN_SOURCE = BASE / "ops/forexvps/releases/fp-adaptive-payoff-v1-bank1r-giveback-20260912/SolTradeFastMultiMarketV2.mq5"
FROZEN_HASH = "4d1980812f3312728d8c8258c6b8b59d4c29013f3f3832128866fbcfcab3c63e"
PRIOR_EVENTS = BASE / "reports/fast-multi-market-v2/full-live-audit-20260924/evidence/fp-events-since-last-audit.csv"


def fields(detail):
    return dict(item.split("=", 1) for item in detail.split(";") if "=" in item)


def number(value):
    if value is None or value == "":
        return None
    return float(value)


def yes(value):
    return str(value).lower() == "true"


def utc(value):
    return datetime.strptime(value, "%Y.%m.%d %H:%M:%S").replace(tzinfo=timezone.utc)


def read_events(paths):
    seen = set()
    rows = []
    for path in paths:
        with path.open(encoding="utf-8-sig", newline="") as stream:
            for line, record in enumerate(csv.DictReader(stream), 2):
                if not record.get("utc") or not record.get("event"):
                    continue
                identity = tuple(sorted(record.items()))
                if identity in seen:
                    continue
                seen.add(identity)
                record = dict(record)
                record["parsed"] = fields(record.get("detail", ""))
                record["source_path"] = str(path)
                record["source_line"] = line
                record["utc_dt"] = utc(record["utc"])
                record["position_id"] = record["parsed"].get("position_id") or record.get("ticket")
                rows.append(record)
    return sorted(rows, key=lambda row: row["utc_dt"])


def metrics(trades):
    values = [t["final_net_r"] for t in trades]
    positives = [v for v in values if v > 0]
    negatives = [v for v in values if v < 0]
    cumulative = peak = max_dd = 0.0
    for value in values:
        cumulative += value
        peak = max(peak, cumulative)
        max_dd = max(max_dd, peak - cumulative)
    by_day = defaultdict(float)
    by_symbol = defaultdict(float)
    for trade in trades:
        by_day[trade["exit_event_utc"][:10]] += trade["final_net_r"]
        by_symbol[trade["symbol"]] += trade["final_net_r"]
    total = sum(values)
    return {
        "closed_positions": len(trades),
        "positive_positions": len(positives),
        "negative_positions": len(negatives),
        "zero_positions": len(values) - len(positives) - len(negatives),
        "whole_closed_position_net_cash": float(sum((Decimal(str(t["final_net_cash"])) for t in trades), Decimal(0))),
        "whole_closed_position_net_r": total,
        "expectancy_r": mean(values) if values else None,
        "average_winner_r": mean(positives) if positives else None,
        "average_loser_r": mean(negatives) if negatives else None,
        "median_loser_r": median(negatives) if negatives else None,
        "profit_factor": sum(positives) / -sum(negatives) if negatives else None,
        "payoff_ratio": mean(positives) / -mean(negatives) if positives and negatives else None,
        "closed_position_max_drawdown_r": max_dd,
        "drawdown_definition": "Whole-position net R ordered by final EXIT event UTC, not account equity drawdown; partial realizations are not independently timed.",
        "without_best_winner_r": total - max(positives) if positives else total,
        "without_best_exit_day_r": total - max(by_day.values()) if by_day else None,
        "by_exit_day_net_r": dict(by_day),
        "by_symbol_net_r": dict(by_symbol),
        "bank1_reached": sum(t["bank1_money_trigger_reached"] for t in trades),
        "actual_partial_banked_positions": sum(t["partial_banking_confirmed"] for t in trades),
        "exit_classes": dict(Counter(t["exit_class"] for t in trades)),
    }


def analyze(events, since):
    entries = {}
    banks = defaultdict(list)
    completed = {}
    for event in events:
        pid = event["position_id"]
        if event["event"] == "ENTRY":
            entries.setdefault(pid, event)
        elif event["event"] == "PARTIAL_BANK_1R":
            banks[pid].append(event)
        elif event["event"] == "EXIT" and event["utc_dt"] > since:
            # Duplicate terminal callbacks never count as independent trades.
            completed[pid] = event
    trades = []
    anomalies = []
    for pid, event in sorted(completed.items(), key=lambda pair: pair[1]["utc_dt"]):
        data = event["parsed"]
        if data.get("final_total_cash") is None or data.get("final_total_r") is None:
            anomalies.append({"position_id": pid, "problem": "Missing final net outcome", "source_line": event["source_line"]})
            continue
        entry = entries.get(pid)
        ed = entry["parsed"] if entry else {}
        entered_before = entry is not None and entry["utc_dt"] <= since
        prior_banks = [b for b in banks[pid] if b["utc_dt"] <= since]
        net = number(data["final_total_cash"])
        risk = number(data.get("initial_dollar_risk"))
        reported_r = number(data["final_total_r"])
        banked = yes(data.get("partial_banking"))
        trade = {
            "position_id": pid,
            "symbol": event["symbol"],
            "direction": event["direction"],
            "entry_event_utc": entry["utc"] if entry else None,
            "entry_broker_time_unconverted": data.get("entry_time"),
            "exit_event_utc": event["utc"],
            "initial_dollar_risk": risk,
            "initial_price_risk": number(data.get("original_price_risk")),
            "entry_price": number(data.get("entry_price")),
            "exit_price": number(data.get("exit_price")),
            "original_volume": number(data.get("original_volume")),
            "final_net_cash": net,
            "final_net_r": reported_r,
            "recomputed_net_r": net / risk if risk else None,
            "peak_price_r": number(data.get("RUNNER_PEAK_R")),
            "peak_cash_before_commission": number(data.get("RUNNER_PEAK_DOLLARS", data.get("mfe"))),
            "mae_cash_before_commission": number(data.get("mae")),
            "total_commission_and_fees": number(data.get("commission")),
            "total_swap": number(data.get("swap")),
            "gross_cash": number(data.get("gross")),
            "bank1_money_trigger_reached": yes(data.get("reached_1r")),
            "partial_banking_confirmed": banked,
            "banked_net_cash_if_confirmed": number(data.get("banked_cash")) if banked else None,
            "runner_net_cash_if_confirmed": number(data.get("runner_cash")) if banked else None,
            "trail_updates": int(data.get("TRAIL_UPDATES", 0)),
            "exit_class": data.get("exit_class"),
            "holding_seconds": int(data.get("holding_seconds", 0)),
            "admission_score": number(ed.get("admission_score")),
            "no_trade_score": number(fields(entry.get("no_trade_case", "")).get("score")) if entry else None,
            "m1_state": entry.get("m1") if entry else None,
            "m5_state": entry.get("m5") if entry else None,
            "m15_state": entry.get("m15") if entry else None,
            "h1_state": entry.get("h1") if entry else None,
            "entry_before_audit_cutoff": entered_before,
            "entry_context_available": entry is not None,
            "partial_already_recorded_before_cutoff": bool(prior_banks),
            "allocated_banked_net_before_cutoff": number(prior_banks[-1]["parsed"].get("banked_net")) if prior_banks else None,
            "source_path": event["source_path"],
            "source_line": event["source_line"],
        }
        if trade["recomputed_net_r"] is not None and abs(trade["recomputed_net_r"] - reported_r) > 0.00003:
            anomalies.append({"position_id": pid, "problem": "Net R inconsistent with reported cash/risk beyond rounding", "reported_r": reported_r, "recomputed_r": trade["recomputed_net_r"]})
        if not banked and (trade["peak_price_r"] or 0) >= 1:
            anomalies.append({"position_id": pid, "problem": "PRICE_R_ABOVE_1_WITHOUT_BANK__NOT_PROOF_OF_MISSED_CASH_TRIGGER", "peak_price_r": trade["peak_price_r"], "source_line": event["source_line"]})
        trades.append(trade)
    period_events = [event for event in events if event["utc_dt"] > since]
    bank_records = [
        {"position_id": e["position_id"], "utc": e["utc"], "symbol": e["symbol"],
         "detail": e["parsed"], "source_path": e["source_path"], "source_line": e["source_line"]}
        for e in period_events if e["event"] == "PARTIAL_BANK_1R"
    ]
    return {
        "schema": "FP_READONLY_EVENT_AUDIT_V1",
        "exclusive_cutoff_utc": since.strftime("%Y.%m.%d %H:%M:%S"),
        "latest_event_utc": period_events[-1]["utc"] if period_events else None,
        "event_counts": dict(Counter(event["event"] for event in period_events)),
        "metrics": metrics(trades),
        "carried_positions_completed": [t["position_id"] for t in trades if t["entry_before_audit_cutoff"]],
        "confirmed_bank_events_in_period": bank_records,
        "trades": trades,
        "diagnostic_anomalies": anomalies,
        "limitations": [
            "Whole-position EXIT cash includes pre-cutoff partial realizations; it is not a cash-flow reconciliation for this interval.",
            "RUNNER_PEAK_R is price movement / original price distance. Final R is net realized cash / initial dollar risk. Do not subtract these as net monetary giveback.",
            "Cash MFE excludes commission; no net MFE or missed bank conclusion is inferred without opening-deal costs and ledger validity.",
            "Banked cash on an unbanked full-close loss is a known reporting allocation artifact and is excluded from bank totals.",
            "PARTIAL_EXIT_DEAL entry/stop fields are market-score fields, not broker execution fills.",
            "PRE_BANK_GIVEBACK_FAILED opposite_direction is a known post-mutation logging artifact.",
            "Broker timestamps in EXIT detail are not treated as UTC; event.utc is authoritative for the reported cohort.",
            "No live state is inferred from missing events; positions and balance must be read from the separately captured runtime/deal evidence.",
        ],
        "orders_sent_by_analysis": 0,
        "production_changes": False,
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--events", type=Path, required=True)
    parser.add_argument("--context-events", type=Path, action="append", default=[])
    parser.add_argument("--since", default="2026.09.24 11:16:00")
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    inputs = [*args.context_events, args.events]
    if PRIOR_EVENTS.exists() and PRIOR_EVENTS not in inputs:
        inputs.insert(0, PRIOR_EVENTS)
    source_hash = hashlib.sha256(FROZEN_SOURCE.read_bytes()).hexdigest()
    if source_hash != FROZEN_HASH:
        raise SystemExit("Frozen source hash changed; audit definitions require review.")
    result = analyze(read_events(inputs), utc(args.since))
    result["frozen_source_sha256"] = source_hash
    result["inputs"] = [{"path": str(p), "sha256": hashlib.sha256(p.read_bytes()).hexdigest()} for p in inputs]
    args.output.mkdir(parents=True, exist_ok=True)
    (args.output / "fp-analysis.json").write_text(json.dumps(result, indent=2) + "\n")
    with (args.output / "fp-trades.csv").open("w", newline="") as stream:
        if result["trades"]:
            writer = csv.DictWriter(stream, fieldnames=list(result["trades"][0]))
            writer.writeheader()
            writer.writerows(result["trades"])
    print(json.dumps({"output": str(args.output), "metrics": result["metrics"], "anomalies": result["diagnostic_anomalies"]}, indent=2))


if __name__ == "__main__":
    main()
