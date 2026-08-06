#!/usr/bin/env python3
"""Compile and run the frozen V27 signal-only sample-feasibility evaluator."""
from __future__ import annotations

import csv
import hashlib
import json
import os
import shutil
import subprocess
from collections import Counter
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "reports/backtests/phase6-v27-weekend-overreaction-reversal"
DEST = OUT / "signal-feasibility"
PREFIX = Path("/home/tibule12/.wine-fpmarkets")
TERMINAL = PREFIX / "drive_c/Program Files/FP Markets MT5 Terminal"
COMMON = PREFIX / "drive_c/users/tibule12/AppData/Roaming/MetaQuotes/Terminal/Common/Files"
WORK = PREFIX / "drive_c/v27"
RUNTIME = COMMON / "SolTrade/Phase6/V27Signals"
SOURCE = ROOT / "research/weekend_overreaction/SolTradeWeekendOverreactionSignalHarness.mq5"


def pairs(path: Path) -> dict[str, str]:
    with path.open() as handle:
        return {row[0]: row[1] for row in csv.reader(handle) if len(row) >= 2}


def sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main() -> None:
    if DEST.exists() or RUNTIME.exists():
        raise SystemExit("REFUSE_EXISTING_V27_SIGNAL_EVIDENCE")
    WORK.mkdir(parents=True, exist_ok=True)
    DEST.mkdir(parents=True)
    work_source = WORK / SOURCE.name
    shutil.copy2(SOURCE, work_source)
    compile_log = WORK / "signal-compile.log"
    env = dict(os.environ, WINEPREFIX=str(PREFIX))
    compiler = subprocess.run(
        ["wine", str(TERMINAL / "MetaEditor64.exe"), "/portable", f"/compile:C:\\v27\\{SOURCE.name}", "/log:C:\\v27\\signal-compile.log"],
        cwd=ROOT, env=env, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=120,
    )
    if not (WORK / SOURCE.with_suffix(".ex5").name).exists():
        raise SystemExit(f"V27_SIGNAL_COMPILE_FAILED return={compiler.returncode}")
    shutil.copy2(compile_log, DEST / "signal-compile.log")
    shutil.copy2(WORK / SOURCE.with_suffix(".ex5").name, TERMINAL / "MQL5/Experts/SolTradeWeekendOverreactionSignalHarness.ex5")
    config = WORK / "signals.ini"
    config.write_text(
        "[Common]\nKeepPrivate=1\nNewsEnable=0\n\n[Experts]\nEnabled=1\nAllowLiveTrading=0\nAllowDllImport=0\nAccount=0\nProfile=0\n\n"
        "[Tester]\nExpert=SolTradeWeekendOverreactionSignalHarness\nSymbol=EURUSD\nPeriod=H1\nDeposit=10000\nCurrency=USD\nLeverage=1:30\n"
        "Model=2\nExecutionMode=0\nOptimization=0\nForwardMode=0\nFromDate=2019.12.30\nToDate=2026.08.01\nVisual=0\nUseCloud=0\nPort=3971\n"
        "Report=v27\\signals.html\nReplaceReport=1\nShutdownTerminal=1\n\n[TesterInputs]\nResearchCutoff=2026.08.01 00:00:00\nOutputRoot=SolTrade\\Phase6\\V27Signals\n"
    )
    (DEST / "strategy-tester.ini").write_text(config.read_text())
    proc = subprocess.run(
        ["wine", str(TERMINAL / "terminal64.exe"), "/config:C:\\v27\\signals.ini", "/portable"],
        cwd=ROOT, env=env, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=900,
    )
    if RUNTIME.exists():
        for artifact in RUNTIME.iterdir():
            if artifact.is_file():
                shutil.copy2(artifact, DEST / artifact.name)
    summary_path = DEST / "signal-summary.csv"
    ledger_path = DEST / "signal-ledger.csv"
    summary = pairs(summary_path) if summary_path.exists() else {}
    rows = list(csv.DictReader(ledger_path.open())) if ledger_path.exists() else []
    signals = [row for row in rows if row["tail"] in ("UPPER", "LOWER")]
    by_dataset = Counter(row["dataset"] for row in signals)
    by_direction = Counter(("BUY" if (row["tail"] == "LOWER") == (int(row["orientation"]) > 0) else "SELL") for row in signals)
    by_symbol = Counter(row["symbol"] for row in signals)
    valid = proc.returncode == 0 and summary.get("status") == "PASS" and summary.get("orders_or_positions") == "ZERO" and summary.get("pnl_calculated") == "NO"
    inventory = {
        "schema": "SOLTRADE_PHASE6_V27_SIGNAL_FEASIBILITY_V1",
        "status": "PASS" if valid else "FAIL",
        "source_sha256": sha(SOURCE),
        "executable_sha256": sha(WORK / SOURCE.with_suffix(".ex5").name),
        "tester_model": "OPEN_PRICES_ONLY_SIGNAL_EVALUATION",
        "optimization": False,
        "orders_or_positions": 0,
        "pnl_calculated": False,
        "weeks": int(summary.get("weeks", "0")),
        "evaluations": int(summary.get("evaluations", "0")),
        "signals": len(signals),
        "by_dataset": dict(sorted(by_dataset.items())),
        "by_direction": dict(sorted(by_direction.items())),
        "by_symbol": {symbol: by_symbol[symbol] for symbol in ("EURUSD", "GBPUSD", "AUDUSD", "NZDUSD", "USDCAD", "USDCHF", "USDJPY")},
        "current_reference_missing": int(summary.get("current_reference_missing", "0")),
        "threshold_history_unavailable": int(summary.get("threshold_history_unavailable", "0")),
        "seal_breach": summary.get("seal_breach"),
    }
    (DEST / "signal-feasibility-inventory.json").write_text(json.dumps(inventory, indent=2) + "\n")
    print(json.dumps(inventory, indent=2), flush=True)
    if not valid:
        raise SystemExit("V27_SIGNAL_FEASIBILITY_FAILED")


if __name__ == "__main__":
    main()
