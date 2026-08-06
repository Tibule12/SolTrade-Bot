#!/usr/bin/env python3
"""Generate the frozen V26 signal-only schedules without trading or P&L."""
from __future__ import annotations

import csv
import json
import os
import shutil
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "reports/backtests/phase6-v26-cross-sectional-currency-momentum/signal-schedules"
PREFIX = Path("/home/tibule12/.wine-fpmarkets")
TERMINAL = PREFIX / "drive_c/Program Files/FP Markets MT5 Terminal"
COMMON = PREFIX / "drive_c/users/tibule12/AppData/Roaming/MetaQuotes/Terminal/Common/Files"
WORK = PREFIX / "drive_c/v26"
DATASETS = (
    ("V26_2025_DEVELOPMENT", "2024.12.02", "2025.01.06 10:05:00", "2026.01.01 00:00:00", "2026.01.01"),
    ("V26_2026_PRESEAL_DEVELOPMENT", "2025.12.01", "2026.01.05 10:05:00", "2026.08.01 00:00:00", "2026.08.01"),
)


def pairs(path: Path) -> dict[str, str]:
    with path.open() as handle:
        return {row[0]: row[1] for row in csv.reader(handle) if len(row) >= 2}


def ini(dataset: str, start: str, eligible: str, end: str, to_date: str, port: int) -> str:
    return f"""[Common]\nKeepPrivate=1\nNewsEnable=0\n\n[Experts]\nEnabled=1\nAllowLiveTrading=0\nAllowDllImport=0\nAccount=0\nProfile=0\n\n[Tester]\nExpert=SolTradeRelativeStrengthSignalHarness\nSymbol=EURUSD\nPeriod=H1\nDeposit=10000\nCurrency=USD\nLeverage=1:30\nModel=1\nExecutionMode=0\nOptimization=0\nForwardMode=0\nFromDate={start}\nToDate={to_date}\nVisual=0\nUseCloud=0\nPort={port}\nReport=v26\\signals-{dataset}.html\nReplaceReport=1\nShutdownTerminal=1\n\n[TesterInputs]\nEligibleFrom={eligible}\nEligibleTo={end}\nResearchCutoff=2026.08.01 00:00:00\nDatasetId={dataset}\nOutputRoot=SolTrade\\Phase6\\V26Signals\\{dataset}\n"""


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    shutil.copy2(WORK / "SolTradeRelativeStrengthSignalHarness.ex5", TERMINAL / "MQL5/Experts/SolTradeRelativeStrengthSignalHarness.ex5")
    inventory = []
    for index, (dataset, start, eligible, end, to_date) in enumerate(DATASETS, 1):
        destination = OUT / dataset
        runtime = COMMON / "SolTrade/Phase6/V26Signals" / dataset
        if destination.exists() or runtime.exists():
            raise SystemExit(f"REFUSE_EXISTING {dataset}")
        destination.mkdir(parents=True)
        config = WORK / f"signals-{index}.ini"
        config.write_text(ini(dataset, start, eligible, end, to_date, 3800 + index))
        (destination / "strategy-tester.ini").write_text(config.read_text())
        env = dict(os.environ, WINEPREFIX=str(PREFIX))
        proc = subprocess.run(["wine", str(TERMINAL / "terminal64.exe"), f"/config:C:\\v26\\signals-{index}.ini", "/portable"], cwd=ROOT, env=env, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=900)
        if runtime.exists():
            for artifact in runtime.iterdir():
                if artifact.is_file():
                    shutil.copy2(artifact, destination / artifact.name)
        summary_path = destination / "signal-summary.csv"
        summary = pairs(summary_path) if summary_path.exists() else {}
        status = "PASS" if proc.returncode == 0 and summary.get("status") == "PASS" and summary.get("orders_or_positions") == "ZERO" and summary.get("pnl_calculated") == "NO" else "FAIL"
        record = {"dataset": dataset, "status": status, "rebalances": int(summary.get("rebalances", "0")), "selected_legs": int(summary.get("selected_legs", "0")), "skipped_rebalances": int(summary.get("skipped_rebalances", "0")), "seal_breach": summary.get("seal_breach")}
        inventory.append(record)
        print(f"V26_SIGNALS {index}/2 {dataset} {status} rebalances={record['rebalances']} legs={record['selected_legs']} skips={record['skipped_rebalances']}", flush=True)
        if status != "PASS":
            raise SystemExit(f"SIGNAL_GENERATION_FAILED {dataset}")
    (OUT / "signal-schedule-inventory.json").write_text(json.dumps({"schema": "SOLTRADE_PHASE6_V26_SIGNAL_INVENTORY_V1", "status": "PASS", "orders_or_positions": 0, "pnl_calculated": False, "datasets": inventory}, indent=2) + "\n")


if __name__ == "__main__":
    main()
