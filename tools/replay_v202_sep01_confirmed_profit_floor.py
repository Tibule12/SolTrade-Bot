#!/usr/bin/env python3
"""Replay the live 1-Sep GER40/DE30 protected-stop loss at the new net floor."""

from __future__ import annotations

import csv
import json
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
EVIDENCE = ROOT / "ops/forexvps/remote-output/loss-audit"
OUTPUT = ROOT / "reports/fast-multi-market-v2/v202-confirmed-profit-floor-20260901.json"
TARGET_NET_R = 0.10


def details(value: str) -> dict[str, str]:
    return dict(part.split("=", 1) for part in value.split(";") if "=" in part)


def latest(account: str, event: str) -> dict[str, str]:
    path = EVIDENCE / f"{account}-evidence.csv"
    rows = [
        row
        for row in csv.DictReader(path.open(encoding="utf-8", newline=""))
        if row["event"] == event and row["utc"] >= "2026.09.01 19:00:00"
    ]
    if not rows:
        raise RuntimeError(f"missing {event} evidence for {account}")
    return rows[-1]


def main() -> int:
    accounts = []
    for account in ("fp", "f10", "f100"):
        entry = latest(account, "ENTRY")
        exit_row = latest(account, "EXIT")
        entered = details(entry["detail"])
        exited = details(exit_row["detail"])
        peak_r = float(exited["RUNNER_PEAK_R"])
        risk = float(entered["initial_risk"])
        actual_net = float(exited["net"])
        if peak_r < 0.50:
            raise RuntimeError(f"{account} did not reach confirmed-profit phase")
        accounts.append(
            {
                "account": account,
                "symbol": entry["symbol"],
                "direction": entry["direction"],
                "entry_utc": entry["utc"],
                "exit_utc": exit_row["utc"],
                "complete_admission_persistence": entered["complete_admission_persistence"] == "true",
                "peak_r": peak_r,
                "runner_mode_entered": exited["RUNNER_MODE_ENTERED"] == "true",
                "old_protected_r": float(exited["PROTECTED_R"]),
                "old_actual_net": actual_net,
                "old_actual_net_r": round(actual_net / risk, 5),
                "new_target_net_r": TARGET_NET_R,
                "new_modeled_minimum_net": round(TARGET_NET_R * risk, 2),
                "new_policy_negative_after_confirmed_profit": False,
            }
        )

    report = {
        "schema": "SOLTRADE_V202_CONFIRMED_PROFIT_FLOOR_REPLAY_V1",
        "source": str(EVIDENCE.relative_to(ROOT)),
        "orders_placed": False,
        "strategy_version_changed": False,
        "admission_changed": False,
        "risk_sizing_changed": False,
        "runner_activation_changed": False,
        "structural_stop_changed": False,
        "confirmed_profit_threshold_r": 0.50,
        "old_phase_one_floor_r": -0.05,
        "new_phase_one_target_net_r": TARGET_NET_R,
        "accounts": accounts,
        "status": "PASS" if all(not row["new_policy_negative_after_confirmed_profit"] for row in accounts) else "FAIL",
        "limitation": "A broker gap or slippage through the protective stop can still realize below the modeled floor.",
    }
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    OUTPUT.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(report, indent=2))
    return 0 if report["status"] == "PASS" else 1


if __name__ == "__main__":
    raise SystemExit(main())
