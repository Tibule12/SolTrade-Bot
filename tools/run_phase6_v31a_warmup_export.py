#!/usr/bin/env python3
"""Export the already-consumed FP Markets M1 warm-up bars in Strategy Tester."""
from __future__ import annotations

import csv
import hashlib
import json
import os
import shutil
import subprocess
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "reports/backtests/phase6-v31a-v28-adapter-equivalence/fpmarkets-warmup-export"
PREFIX = Path("/home/tibule12/.wine-fpmarkets")
TERMINAL = PREFIX / "drive_c/Program Files/FP Markets MT5 Terminal"
COMMON = PREFIX / "drive_c/users/tibule12/AppData/Roaming/MetaQuotes/Terminal/Common/Files"
WORK = PREFIX / "drive_c/v31a"
RUNTIME = COMMON / "SolTrade/Phase6/V31AWarmup"
SOURCE = ROOT / "research/factor_momentum/SolTradeV31AWarmupExport.mq5"
EX5 = WORK / "SolTradeV31AWarmupExport.ex5"
SOURCE_SHA256 = "98034d3528a4f0a5d559df9709b4506235572a1beda6e2053158bfdeac09eb6f"
EX5_SHA256 = "c5140a1affeeacd6e7749b04b1e196e8999c38b307d4099092b842ad3a3c4f40"


def sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main() -> None:
    if sha(SOURCE) != SOURCE_SHA256 or sha(EX5) != EX5_SHA256:
        raise SystemExit("V31A_WARMUP_EXPORT_HASH_MISMATCH")
    if OUT.exists() or RUNTIME.exists():
        raise SystemExit("REFUSE_EXISTING_V31A_WARMUP_EXPORT")
    OUT.mkdir(parents=True)
    shutil.copy2(EX5, TERMINAL / "MQL5/Experts/SolTradeV31AWarmupExport.ex5")
    config = WORK / "warmup-export.ini"
    config.write_text("""[Common]
KeepPrivate=1
NewsEnable=0

[Experts]
Enabled=1
AllowLiveTrading=0
AllowDllImport=0
Account=0
Profile=0

[Tester]
Expert=SolTradeV31AWarmupExport
Symbol=EURUSD
Period=M1
Deposit=10000
Currency=USD
Leverage=1:30
Model=1
ExecutionMode=0
Optimization=0
ForwardMode=0
FromDate=2024.11.01
ToDate=2025.01.02
Visual=0
UseCloud=0
Port=4091
Report=v31a\\reports\\warmup-export.html
ReplaceReport=1
ShutdownTerminal=1
""")
    (OUT / "strategy-tester.ini").write_text(config.read_text())
    started = time.time()
    proc = subprocess.run(
        ["wine", str(TERMINAL / "terminal64.exe"), "/config:C:\\v31a\\warmup-export.ini", "/portable"],
        cwd=ROOT,
        env=dict(os.environ, WINEPREFIX=str(PREFIX)),
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        timeout=900,
    )
    (OUT / "terminal-stdout.log").write_bytes(proc.stdout)
    if RUNTIME.exists():
        for artifact in RUNTIME.iterdir():
            if artifact.is_file():
                shutil.copy2(artifact, OUT / artifact.name)
    agent = TERMINAL / "Tester/Agent-127.0.0.1-4091"
    logs = sorted(agent.glob("logs/*.log"), key=lambda p: p.stat().st_mtime)
    if logs:
        shutil.copy2(logs[-1], OUT / "tester-agent.log")
    shutil.copy2(WORK / "warmup-export-compile.log", OUT / "warmup-export-compile.log")
    summary = list(csv.DictReader((OUT / "summary.csv").open())) if (OUT / "summary.csv").exists() else []
    valid = proc.returncode == 0 and len(summary) == 7 and all(r["status"] == "PASS" for r in summary)
    status = {
        "schema": "SOLTRADE_PHASE6_V31A_WARMUP_EXPORT_STATUS_V1",
        "status": "PASS" if valid else "FAIL",
        "elapsed_seconds": time.time() - started,
        "wine_return_code": proc.returncode,
        "symbols": len(summary),
        "m1_rates": sum(int(r["rates"]) for r in summary),
        "trade_api_calls": "NONE",
        "pnl_calculated": False,
        "external_data_downloaded": False,
    }
    (OUT / "status.json").write_text(json.dumps(status, indent=2) + "\n")
    print(json.dumps(status, indent=2), flush=True)
    if not valid:
        raise SystemExit("V31A_WARMUP_EXPORT_FAILED_RETAINED")


if __name__ == "__main__":
    main()
