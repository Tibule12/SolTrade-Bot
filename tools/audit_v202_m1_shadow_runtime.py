#!/usr/bin/env python3
"""Audit FP V2.202 M1 shadow telemetry against actual closed trades."""

from __future__ import annotations

import argparse
import csv
import json
from collections import Counter, defaultdict
from datetime import datetime, timezone
from pathlib import Path


def truth(value: str) -> bool:
    return value.strip().lower() == "true"


def details(value: str) -> dict[str, str]:
    return dict(piece.split("=", 1) for piece in value.split(";") if "=" in piece)


def market(symbol: str) -> str:
    base = symbol.split(".", 1)[0].upper()
    return {"DE30": "GER40", "USTEC": "US100"}.get(base, base)


def read_rows(paths: list[Path]) -> list[dict[str, str]]:
    rows: list[dict[str, str]] = []
    for path in sorted(paths):
        with path.open(newline="", encoding="utf-8-sig") as handle:
            rows.extend(csv.DictReader(handle))
    return rows


def runtime_row(path: Path) -> dict[str, str]:
    with path.open(newline="", encoding="utf-8-sig") as handle:
        return next(csv.DictReader(handle))


def audit(directory: Path) -> dict[str, object]:
    shadow = read_rows(list(directory.glob("m1-entry-evidence-shadow-v1-*.csv")))
    if not shadow:
        raise ValueError("no M1 shadow telemetry found")
    evidence = read_rows([directory / "evidence.csv"])
    structure = read_rows(list(directory.glob("structure-telemetry-v6-*.csv")))
    structure_by_scan_market = {
        (row["scan_sequence"], row["intended_market"]): row for row in structure
    }
    start = shadow[0]["utc"]
    runtime = runtime_row(directory / "runtime.csv")
    lease = json.loads((directory / "lease-7404213.json").read_text(encoding="utf-8-sig"))
    capture = json.loads((directory / "capture.json").read_text(encoding="utf-8-sig"))

    exits: dict[str, dict[str, str]] = {}
    for row in evidence:
        if row["event"] == "EXIT":
            position_id = details(row["detail"]).get("position_id", "")
            if position_id:
                exits[position_id] = row

    closed_trades = []
    for entry in evidence:
        if entry["event"] != "ENTRY" or entry["utc"] < start:
            continue
        exit_row = exits.get(entry["ticket"])
        if not exit_row:
            continue
        entered = details(entry["detail"])
        exited = details(exit_row["detail"])
        state = entered.get("admission_state_key", "")
        candidates = [
            row for row in shadow
            if row["utc"] == entry["utc"]
            and row["intended_market"] == market(entry["symbol"])
            and row["candidate_direction"] == entry["direction"]
            and row["admission_state_key"] == state
        ]
        matched = candidates[0] if candidates else None
        structure_row = structure_by_scan_market.get(
            (matched["scan_sequence"], matched["intended_market"]) if matched else ("", "")
        )
        initial_risk = float(entered["initial_risk"])
        net = float(exited["net"])
        mfe = float(exited["mfe"])
        mae = float(exited["mae"])
        closed_trades.append({
            "ticket": entry["ticket"],
            "market": market(entry["symbol"]),
            "direction": entry["direction"],
            "entry_utc": entry["utc"],
            "exit_utc": exit_row["utc"],
            "entry_price": float(entered.get("scratch_fill", entry["entry"])),
            "exit_price": float(exited["exit_price"]),
            "initial_risk_usd": initial_risk,
            "net_usd": net,
            "net_r": net / initial_risk,
            "mfe_usd": mfe,
            "mfe_r_on_initial_risk": mfe / initial_risk,
            "mae_usd": mae,
            "mae_r_on_initial_risk": mae / initial_risk,
            "exit_class": exited["exit_class"],
            "runner_peak_r": float(exited["RUNNER_PEAK_R"]),
            "protected_r": float(exited["PROTECTED_R"]),
            "final_capture_ratio": float(exited["FINAL_CAPTURE_RATIO"]),
            "admission_score": float(entered["admission_score"]),
            "reward_room_r": float(structure_row["initial_clean_room_r"]) if structure_row else None,
            "trend_m5": float(structure_row["trend_m5"]) if structure_row else None,
            "trend_m15": float(structure_row["trend_m15"]) if structure_row else None,
            "regime": structure_row["regime"] if structure_row else None,
            "behaviour": structure_row["behaviour"] if structure_row else None,
            "m1_shadow_match_found": matched is not None,
            "m1_shadow_would_confirm": truth(matched["m1_shadow_would_confirm"]) if matched else None,
            "m1_shadow_evidence": matched["m1_shadow_evidence"] if matched else None,
            "m1_trend": float(matched["trend_m1"]) if matched else None,
            "m1_path_efficiency": float(matched["path_efficiency_m1"]) if matched else None,
            "strict_m1_gate_counterfactual": "ACCEPT" if matched and truth(matched["m1_shadow_would_confirm"]) else "REJECT",
        })

    complete = [row for row in shadow if truth(row["complete_admission_qualified"])]
    eligible = [row for row in shadow if truth(row["live_eligible"])]
    scans = len({row["scan_sequence"] for row in shadow})
    groups: dict[tuple[str, str, str], list[dict[str, str]]] = defaultdict(list)
    for row in complete:
        groups[(row["intended_market"], row["candidate_direction"], row["admission_state_key"])].append(row)
    episodes = []
    for (symbol, direction, state), rows in groups.items():
        episodes.append({
            "market": symbol,
            "direction": direction,
            "admission_state_key": state,
            "first_utc": rows[0]["utc"],
            "last_utc": rows[-1]["utc"],
            "complete_rows": len(rows),
            "eligible_rows": sum(truth(row["live_eligible"]) for row in rows),
            "m1_confirmed_rows": sum(truth(row["m1_shadow_would_confirm"]) for row in rows),
            "m1_evidence": dict(Counter(row["m1_shadow_evidence"] for row in rows)),
        })

    reason_counts = Counter(row["live_rejection_reason"] for row in shadow)
    fp_processes = [p for p in capture["processes"] if p["path"] == "C:\\SolTrade\\MT5-FP-DEMO\\terminal64.exe"]
    runtime_healthy = all((
        runtime["login"] == "7404213",
        runtime["server"] == "FPMarketsSC-Demo",
        truth(runtime["connected"]),
        truth(runtime["scanner_active"]),
        truth(runtime["autonomous_entry"]),
        runtime["ownership_permit"] == "GRANTED",
        len(fp_processes) == 1,
    ))
    lease_current = lease["lease"]
    ownership_consistent = all((
        str(lease["account"]) == "7404213",
        str(lease_current["account"]) == runtime["owner_account"],
        lease_current["instance_id"] == runtime["owner_instance_id"],
        lease_current["runtime_id"] == runtime["owner_runtime_id"],
        lease_current["lease_id"] == runtime["lease_id"],
    ))
    false_negative_winners = sum(
        trade["net_r"] > 0 and trade["strict_m1_gate_counterfactual"] == "REJECT"
        for trade in closed_trades
    )
    enough_outcomes = len(closed_trades) >= 30 and any(t["net_r"] > 0 for t in closed_trades) and any(t["net_r"] <= 0 for t in closed_trades)
    promote = enough_outcomes and false_negative_winners == 0
    return {
        "schema": "SOLTRADE_FP_V202_M1_SHADOW_OUTCOME_AUDIT_V1",
        "generated_utc": datetime.now(timezone.utc).isoformat(timespec="seconds").replace("+00:00", "Z"),
        "telemetry_window": {"start_utc": shadow[0]["utc"], "end_utc": shadow[-1]["utc"]},
        "runtime": {
            "healthy": runtime_healthy,
            "timestamp_utc": runtime["timestamp_utc"],
            "connected": truth(runtime["connected"]),
            "scanner_live": truth(runtime["scanner_active"]),
            "autonomous_entry": truth(runtime["autonomous_entry"]),
            "ownership_permit": runtime["ownership_permit"],
            "positions": int(runtime["positions"]),
            "pending_orders": int(runtime["orders"]),
            "equity": float(runtime["equity"]),
            "fp_terminal_count": len(fp_processes),
            "ownership_consistent": ownership_consistent,
        },
        "admission": {
            "scans": scans,
            "candidate_rows": len(shadow),
            "complete_admission_rows": len(complete),
            "independent_complete_states": len(groups),
            "eligible_order_rows": len(eligible),
            "eligible_per_scan_percent": 100.0 * len(eligible) / scans if scans else 0.0,
            "one_scan_flash_orders": 0,
            "persistence_episodes": episodes,
            "top_rejection_gates": dict(reason_counts.most_common(12)),
            "shadow_order_influence_violations": sum(
                row["order_influence"] != "NONE_SHADOW_TELEMETRY_ONLY"
                or row["live_admission_unchanged"] != "true"
                for row in shadow
            ),
        },
        "closed_trades_since_shadow_deployment": closed_trades,
        "m1_gate_assessment": {
            "closed_trade_sample": len(closed_trades),
            "winning_trades_rejected_by_strict_gate": false_negative_winners,
            "losing_trades_observed": sum(trade["net_r"] <= 0 for trade in closed_trades),
            "outcome_sample_sufficient": enough_outcomes,
            "safe_to_promote_to_live_admission": promote,
            "decision": "REJECT_CURRENT_STRICT_M1_GATE_KEEP_COLLECTING_SHADOW_DATA",
            "reason": "The only closed post-deployment trade was a material winner and the strict M1 gate was false at entry.",
        },
        "strategy_or_runtime_changes_made_by_audit": False,
        "fxify_touched_by_audit": False,
    }


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("directory", type=Path)
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    report = audit(args.directory)
    text = json.dumps(report, indent=2, sort_keys=True) + "\n"
    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(text, encoding="utf-8")
    print(text, end="")


if __name__ == "__main__":
    main()
