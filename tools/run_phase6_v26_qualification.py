#!/usr/bin/env python3
"""Run availability-only H1 timestamp qualification for the V26 candidate universe."""
from __future__ import annotations

import csv
import json
import os
import shutil
import subprocess
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "reports/backtests/phase6-v26-cross-sectional-currency-momentum/data-qualification/attempt-2"
PREFIX = Path("/home/tibule12/.wine-fpmarkets")
TERMINAL = PREFIX / "drive_c/Program Files/FP Markets MT5 Terminal"
COMMON = PREFIX / "drive_c/users/tibule12/AppData/Roaming/MetaQuotes/Terminal/Common/Files"
WORK = PREFIX / "drive_c/v26"
SYMBOLS = ("EURUSD", "GBPUSD", "AUDUSD", "NZDUSD", "USDCAD", "USDCHF", "USDJPY")


def pairs(path: Path) -> dict[str, str]:
    with path.open() as handle:
        return {row[0]: row[1] for row in csv.reader(handle) if len(row) >= 2}


def config(symbol: str, port: int) -> str:
    return f"""[Common]\nKeepPrivate=1\nNewsEnable=0\n\n[Experts]\nEnabled=1\nAllowLiveTrading=0\nAllowDllImport=0\nAccount=0\nProfile=0\n\n[Tester]\nExpert=SolTradeHistoryQualificationHarness\nSymbol={symbol}\nPeriod=H1\nDeposit=10000\nCurrency=USD\nLeverage=1:30\nModel=1\nExecutionMode=0\nOptimization=0\nForwardMode=0\nFromDate=2024.12.01\nToDate=2026.08.01\nVisual=0\nUseCloud=0\nPort={port}\nReport=v26\\qualification-attempt-2-{symbol}.html\nReplaceReport=1\nShutdownTerminal=1\n\n[TesterInputs]\nBoundFrom=2024.12.01 00:00:00\nBoundTo=2026.08.01 00:00:00\nOutputRoot=SolTrade\\Phase6\\V26QualificationAttempt2\\{symbol}\n"""


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    executable = WORK / "SolTradeHistoryQualificationHarness.ex5"
    shutil.copy2(executable, TERMINAL / "MQL5/Experts/SolTradeHistoryQualificationHarness.ex5")
    results = []
    for index, symbol in enumerate(SYMBOLS, 1):
        destination = OUT / symbol
        runtime = COMMON / "SolTrade/Phase6/V26QualificationAttempt2" / symbol
        if destination.exists() or runtime.exists():
            raise SystemExit(f"REFUSE_EXISTING_QUALIFICATION {symbol}")
        destination.mkdir(parents=True)
        ini = WORK / f"qualification-{symbol}.ini"
        ini.write_text(config(symbol, 3600 + index))
        (destination / "strategy-tester.ini").write_text(ini.read_text())
        env = dict(os.environ, WINEPREFIX=str(PREFIX))
        started = time.time()
        proc = subprocess.run(
            ["wine", str(TERMINAL / "terminal64.exe"), f"/config:C:\\v26\\qualification-{symbol}.ini", "/portable"],
            cwd=ROOT, env=env, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=900,
        )
        elapsed = time.time() - started
        if runtime.exists():
            for artifact in runtime.iterdir():
                if artifact.is_file():
                    shutil.copy2(artifact, destination / artifact.name)
        summary_path = destination / "qualification-summary.csv"
        summary = pairs(summary_path) if summary_path.exists() else {}
        status = "PASS" if proc.returncode == 0 and summary.get("status") == "PASS" and summary.get("orders_or_positions") == "ZERO" and summary.get("post_seal_access") == "NO" else "FAIL"
        result = {
            "symbol": symbol, "elapsed_seconds": elapsed, "wine_return_code": proc.returncode,
            "h1_timestamp_count": int(summary.get("h1_timestamp_count", "0")),
            "first_h1": summary.get("first_h1"), "last_h1": summary.get("last_h1"),
            "price_fields_written": summary.get("price_fields_written"),
            "returns_or_rankings_calculated": summary.get("returns_or_rankings_calculated"),
            "orders_or_positions": summary.get("orders_or_positions"), "status": status,
        }
        (destination / "qualification-status.json").write_text(json.dumps(result, indent=2) + "\n")
        results.append(result)
        print(f"V26_QUALIFY {index}/7 {symbol} {status} h1={result['h1_timestamp_count']} elapsed={elapsed:.2f}s", flush=True)
        if status != "PASS":
            raise SystemExit(f"QUALIFICATION_FAILED {symbol}")
    (OUT / "qualification-inventory.json").write_text(json.dumps({
        "schema": "SOLTRADE_PHASE6_V26_QUALIFICATION_INVENTORY_V1", "status": "PASS",
        "prices_or_returns_inspected": False, "orders_or_positions": 0, "symbols": results,
    }, indent=2) + "\n")


if __name__ == "__main__":
    main()
