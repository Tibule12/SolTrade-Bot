#!/usr/bin/env python3
"""Generate the frozen V28 signal schedule on qualified V31 custom ticks."""
from __future__ import annotations

import csv
import hashlib
import json
import os
import shutil
import subprocess
import time
from collections import Counter
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "reports/backtests/phase6-v31-v28-external-feed-replication-attempt2"
DEST = OUT / "signal-generation"
PREFIX = Path("/home/tibule12/.wine-fpmarkets")
TERMINAL = PREFIX / "drive_c/Program Files/FP Markets MT5 Terminal"
COMMON = PREFIX / "drive_c/users/tibule12/AppData/Roaming/MetaQuotes/Terminal/Common/Files"
RUNTIME = COMMON / "SolTrade/Phase6/V31ExternalSignals"
WORK = PREFIX / "drive_c/v31-external"
EX5 = WORK / "SolTradeDollarFactorV31SignalAdapter.ex5"
EX5_SHA256 = "fe4cbd2a0b28a6743ffda29e6b0cb04ffa041665a1f05f4ce3ff011687e7ee71"
REPORT_DIR = TERMINAL / "v31-external"


def sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def pairs(path: Path) -> dict[str, str]:
    with path.open() as handle:
        return {row[0]: row[1] for row in csv.reader(handle) if len(row) >= 2}


def main() -> None:
    if sha(EX5) != EX5_SHA256:
        raise SystemExit("V31_SIGNAL_ADAPTER_EXECUTABLE_HASH_MISMATCH")
    qualification = json.loads((OUT / "data-qualification/qualification-physical-run-inventory.json").read_text())
    if qualification.get("status") != "PASS":
        raise SystemExit("V31_DATA_QUALIFICATION_NOT_PASS")
    if DEST.exists() or RUNTIME.exists():
        raise SystemExit("REFUSE_EXISTING_V31_SIGNAL_OUTPUT")
    DEST.mkdir(parents=True)
    shutil.copy2(EX5, TERMINAL / "MQL5/Experts/SolTradeDollarFactorV31SignalAdapter.ex5")
    config = WORK / "external-signals.ini"
    config.write_text("""[Common]
KeepPrivate=1
NewsEnable=0

[Experts]
Enabled=1
AllowLiveTrading=0
AllowDllImport=0

[Tester]
Expert=SolTradeDollarFactorV31SignalAdapter
Symbol=EURUSD.V31
Period=H1
Deposit=10000
Currency=USD
Leverage=1:30
Model=4
ExecutionMode=0
Optimization=0
ForwardMode=0
FromDate=2018.01.01
ToDate=2025.01.01
Visual=0
UseCloud=0
Port=4390
Report=v31-external\\signals.html
ReplaceReport=1
ShutdownTerminal=1

[TesterInputs]
EligibleFrom=2018.01.01 00:00:00
EligibleTo=2025.01.01 00:00:00
ResearchCutoff=2025.01.01 00:00:00
DatasetId=V31_EXTERNAL_2018_2024
ExpectedCohorts=82
ExpectedLegs=574
OutputRoot=SolTrade\\Phase6\\V31ExternalSignals
""")
    (DEST / "strategy-tester.ini").write_text(config.read_text())
    started = time.time()
    proc = subprocess.run(
        ["wine", str(TERMINAL / "terminal64.exe"), "/config:C:\\v31-external\\external-signals.ini", "/portable"],
        cwd=ROOT,
        env=dict(os.environ, WINEPREFIX=str(PREFIX)),
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        timeout=10800,
    )
    elapsed = time.time() - started
    (DEST / "terminal-stdout.log").write_bytes(proc.stdout)
    if RUNTIME.exists():
        for artifact in RUNTIME.iterdir():
            if artifact.is_file():
                shutil.copy2(artifact, DEST / artifact.name)
    for artifact in REPORT_DIR.glob("signals*"):
        if artifact.is_file():
            shutil.copy2(artifact, DEST / ("native-mt5-report" + artifact.suffix))
    agent = TERMINAL / "Tester/Agent-127.0.0.1-4390"
    logs = sorted(agent.glob("logs/*.log"), key=lambda path: path.stat().st_mtime)
    if logs:
        shutil.copy2(logs[-1], DEST / "tester-agent.log")
    summary = pairs(DEST / "signal-summary.csv") if (DEST / "signal-summary.csv").exists() else {}
    rows = list(csv.DictReader((DEST / "signal-schedule.csv").open())) if (DEST / "signal-schedule.csv").exists() else []
    cohorts = {row["target"] for row in rows}
    by_direction = Counter(row["chart_direction"] for row in rows)
    by_symbol = Counter(row["canonical_symbol"] for row in rows)
    valid = (
        proc.returncode == 0
        and summary.get("status") == "PASS"
        and summary.get("orders_or_positions") == "ZERO"
        and summary.get("pnl_calculated") == "NO"
        and len(rows) == 574
        and len(cohorts) == 82
        and all(count == 82 for count in by_symbol.values())
        and (DEST / "tester-agent.log").exists()
    )
    status = {
        "schema": "SOLTRADE_PHASE6_V31_EXTERNAL_SIGNAL_STATUS_V1",
        "status": "PASS" if valid else "FAIL",
        "elapsed_seconds": elapsed,
        "wine_return_code": proc.returncode,
        "cohorts": len(cohorts),
        "signals": len(rows),
        "BUY": by_direction["BUY"],
        "SELL": by_direction["SELL"],
        "by_symbol": dict(by_symbol),
        "schedule_sha256": sha(DEST / "signal-schedule.csv") if rows else None,
        "orders_or_positions": 0,
        "pnl_calculated": False,
    }
    (DEST / "signal-generation-status.json").write_text(json.dumps(status, indent=2) + "\n")
    print(json.dumps(status, sort_keys=True), flush=True)
    if not valid:
        raise SystemExit("V31_EXTERNAL_SIGNAL_GENERATION_FAILED_RETAINED")


if __name__ == "__main__":
    main()
