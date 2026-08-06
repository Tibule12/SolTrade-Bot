#!/usr/bin/env python3
"""Export non-price broker contract and swap specifications for V26."""
from __future__ import annotations

import csv
import json
import os
import shutil
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "reports/backtests/phase6-v26-cross-sectional-currency-momentum/symbol-specification"
PREFIX = Path("/home/tibule12/.wine-fpmarkets")
TERMINAL = PREFIX / "drive_c/Program Files/FP Markets MT5 Terminal"
COMMON = PREFIX / "drive_c/users/tibule12/AppData/Roaming/MetaQuotes/Terminal/Common/Files"
WORK = PREFIX / "drive_c/v26"
SYMBOLS = ("EURUSD", "GBPUSD", "AUDUSD", "NZDUSD", "USDCAD", "USDCHF", "USDJPY")


def read_pairs(path: Path) -> dict[str, str]:
    with path.open() as handle:
        return {row[0]: row[1] for row in csv.reader(handle) if len(row) >= 2}


def ini(symbol: str, port: int) -> str:
    return f"""[Common]\nKeepPrivate=1\nNewsEnable=0\n\n[Experts]\nEnabled=1\nAllowLiveTrading=0\nAllowDllImport=0\nAccount=0\nProfile=0\n\n[Tester]\nExpert=SolTradeSymbolSpecificationHarness\nSymbol={symbol}\nPeriod=H1\nDeposit=10000\nCurrency=USD\nLeverage=1:30\nModel=1\nExecutionMode=0\nOptimization=0\nForwardMode=0\nFromDate=2026.07.30\nToDate=2026.07.31\nVisual=0\nUseCloud=0\nPort={port}\nReport=v26\\symbol-spec-{symbol}.html\nReplaceReport=1\nShutdownTerminal=1\n\n[TesterInputs]\nOutputRoot=SolTrade\\Phase6\\V26SymbolSpecs\\{symbol}\n"""


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    shutil.copy2(WORK / "SolTradeSymbolSpecificationHarness.ex5", TERMINAL / "MQL5/Experts/SolTradeSymbolSpecificationHarness.ex5")
    specifications = []
    for index, symbol in enumerate(SYMBOLS, 1):
        destination = OUT / symbol
        runtime = COMMON / "SolTrade/Phase6/V26SymbolSpecs" / symbol
        if destination.exists() or runtime.exists():
            raise SystemExit(f"REFUSE_EXISTING {symbol}")
        destination.mkdir(parents=True)
        configuration = WORK / f"symbol-spec-{symbol}.ini"
        configuration.write_text(ini(symbol, 3700 + index))
        env = dict(os.environ, WINEPREFIX=str(PREFIX))
        proc = subprocess.run(["wine", str(TERMINAL / "terminal64.exe"), f"/config:C:\\v26\\symbol-spec-{symbol}.ini", "/portable"], cwd=ROOT, env=env, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=300)
        if runtime.exists():
            for artifact in runtime.iterdir():
                if artifact.is_file():
                    shutil.copy2(artifact, destination / artifact.name)
        path = destination / "symbol-specification.csv"
        values = read_pairs(path) if path.exists() else {}
        status = "PASS" if proc.returncode == 0 and values.get("status") == "PASS" and values.get("orders_or_positions") == "ZERO" else "FAIL"
        record = {"symbol": symbol, "status": status, **values}
        specifications.append(record)
        print(f"V26_SYMBOL_SPEC {index}/7 {symbol} {status} swap=({values.get('swap_long')},{values.get('swap_short')})", flush=True)
        if status != "PASS":
            raise SystemExit(f"SYMBOL_SPEC_FAILED {symbol}")
    (OUT / "symbol-specification-inventory.json").write_text(json.dumps({"schema": "SOLTRADE_PHASE6_V26_SYMBOL_SPECIFICATION_INVENTORY_V1", "status": "PASS", "prices_inspected": False, "orders_or_positions": 0, "symbols": specifications}, indent=2) + "\n")


if __name__ == "__main__":
    main()
