#!/usr/bin/env python3
"""Run the two frozen V31 external-feed physical performance layers."""
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
OUT = ROOT / "reports/backtests/phase6-v31-v28-external-feed-replication-attempt2"
RUN_ROOT = OUT / "performance-runs"
PLAN_PATH = OUT / "v31-physical-run-plan.json"
SCHEDULE_EVIDENCE = OUT / "signal-generation/signal-schedule.csv"
PREFIX = Path("/home/tibule12/.wine-fpmarkets")
TERMINAL = PREFIX / "drive_c/Program Files/FP Markets MT5 Terminal"
COMMON = PREFIX / "drive_c/users/tibule12/AppData/Roaming/MetaQuotes/Terminal/Common/Files"
WORK = PREFIX / "drive_c/v31-external"
REPORTS = TERMINAL / "v31-external/reports"
EX5 = PREFIX / "drive_c/v31a/SolTradeDollarFactorV31AAdapter.ex5"
EX5_SHA256 = "92bf94431803c0213b1d796c3a412b581978c680869b20de299bcef90ec8e886"
RUNTIME_SCHEDULE = COMMON / "SolTrade/Phase6/V31ExternalSignals/signal-schedule.csv"


def sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def pairs(path: Path) -> dict[str, str]:
    with path.open() as handle:
        return {row[0]: row[1] for row in csv.reader(handle) if len(row) >= 2}


def ini(run: dict, port: int) -> str:
    instance = f"V31-EXTERNAL-{run['execution_layer']}-R{run['run_number']}"
    return f"""[Common]
KeepPrivate=1
NewsEnable=0

[Experts]
Enabled=1
AllowLiveTrading=0
AllowDllImport=0
Account=0
Profile=0

[Tester]
Expert=SolTradeDollarFactorV31AAdapter
Symbol=EURUSD.V31
Period=H1
Deposit=10000
Currency=USD
Leverage=1:30
Model=4
ExecutionMode={run['execution_mode']}
Optimization=0
ForwardMode=0
FromDate=2018.01.01
ToDate=2025.01.01
Visual=0
UseCloud=0
Port={port}
Report=v31-external\\reports\\{run['run_id']}.html
ReplaceReport=1
ShutdownTerminal=1

[TesterInputs]
EligibleFrom=2018.02.05 10:05:00
EligibleTo=2025.01.01 00:00:00
ResearchCutoff=2026.08.01 00:00:00
DatasetId=V31_EXTERNAL_2018_2024
ExecutionLayer={run['execution_layer']}
ExpectedExecutionMode={run['execution_mode']}
ExpectedScheduleSignals=574
ScheduleFile=SolTrade\\Phase6\\V31ExternalSignals\\signal-schedule.csv
ExecutionInstanceId={instance}
OutputRoot=SolTrade\\Phase6\\V31ExternalPerformance\\{instance}
"""


def main() -> None:
    if sha(EX5) != EX5_SHA256:
        raise SystemExit("V31A_ADAPTER_EXECUTABLE_HASH_MISMATCH")
    plan = json.loads(PLAN_PATH.read_text())
    runs = plan["runs"]
    if plan.get("frozen_before_profitability") is not True or len(runs) != 2:
        raise SystemExit("V31_PHYSICAL_RUN_PLAN_INVALID")
    if not RUNTIME_SCHEDULE.exists() or sha(RUNTIME_SCHEDULE) != sha(SCHEDULE_EVIDENCE):
        raise SystemExit("V31_EXTERNAL_SCHEDULE_HASH_MISMATCH")
    qualification = json.loads((OUT / "data-qualification/qualification-physical-run-inventory.json").read_text())
    if qualification.get("status") != "PASS":
        raise SystemExit("V31_DATA_QUALIFICATION_NOT_PASS")
    if RUN_ROOT.exists():
        raise SystemExit("REFUSE_EXISTING_V31_PERFORMANCE_RUN_ROOT")
    RUN_ROOT.mkdir(parents=True)
    REPORTS.mkdir(parents=True, exist_ok=True)
    shutil.copy2(EX5, TERMINAL / "MQL5/Experts/SolTradeDollarFactorV31AAdapter.ex5")
    env = dict(os.environ, WINEPREFIX=str(PREFIX))
    statuses = []
    for sequence, run in enumerate(runs, 1):
        destination = RUN_ROOT / run["run_id"]
        instance = f"V31-EXTERNAL-{run['execution_layer']}-R{run['run_number']}"
        runtime = COMMON / "SolTrade/Phase6/V31ExternalPerformance" / instance
        if destination.exists() or runtime.exists():
            raise SystemExit(f"REFUSE_EXISTING_V31_PERFORMANCE_{run['run_id']}")
        destination.mkdir()
        port = 4400 + sequence
        config = WORK / f"performance-{run['run_number']}.ini"
        config.write_text(ini(run, port))
        (destination / "strategy-tester.ini").write_text(config.read_text())
        for old in REPORTS.glob(run["run_id"] + "*"):
            if old.is_file():
                old.unlink()
        started = time.time()
        proc = subprocess.run(
            ["wine", str(TERMINAL / "terminal64.exe"), f"/config:C:\\v31-external\\performance-{run['run_number']}.ini", "/portable"],
            cwd=ROOT, env=env, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=10800,
        )
        elapsed = time.time() - started
        (destination / "terminal-stdout.log").write_bytes(proc.stdout)
        if runtime.exists():
            for artifact in runtime.iterdir():
                if artifact.is_file():
                    shutil.copy2(artifact, destination / artifact.name)
        native = []
        for artifact in REPORTS.glob(run["run_id"] + "*"):
            if artifact.is_file():
                name = "native-mt5-report" + artifact.name[len(run["run_id"]):]
                shutil.copy2(artifact, destination / name)
                native.append(name)
        agent = TERMINAL / "Tester" / f"Agent-127.0.0.1-{port}"
        logs = sorted(agent.glob("logs/*.log"), key=lambda path: path.stat().st_mtime)
        if logs:
            shutil.copy2(logs[-1], destination / "tester-agent.log")
        summary_path = destination / "run-summary.csv"
        summary = pairs(summary_path) if summary_path.exists() else {}
        deals_path = destination / "deals.csv"
        deals = list(csv.DictReader(deals_path.open())) if deals_path.exists() else []
        positions_in = {row["position_identifier"] for row in deals if int(row["entry"]) == 0}
        positions_out = {row["position_identifier"] for row in deals if int(row["entry"]) in (1, 2)}
        valid = (
            proc.returncode == 0
            and summary.get("run_evidence_status") == "PASS"
            and int(summary.get("schedule_signals", 0)) == 574
            and int(summary.get("processed_signals", 0)) == 574
            and int(summary.get("entry_fills", 0)) > 0
            and int(summary.get("open_positions_at_end", -1)) == 0
            and positions_in == positions_out
            and bool(positions_in)
            and bool(native)
            and (destination / "tester-agent.log").exists()
        )
        status = {
            "schema": "SOLTRADE_PHASE6_V31_PERFORMANCE_RUN_STATUS_V1",
            "status": "PASS" if valid else "TECHNICAL_FAIL",
            "run_id": run["run_id"],
            "execution_layer": run["execution_layer"],
            "execution_mode": run["execution_mode"],
            "model": "EVERY_TICK_BASED_ON_REAL_TICKS",
            "optimization": False,
            "elapsed_seconds": elapsed,
            "wine_return_code": proc.returncode,
            "schedule_signals": int(summary.get("schedule_signals", 0)),
            "processed_signals": int(summary.get("processed_signals", 0)),
            "entry_fills": int(summary.get("entry_fills", 0)),
            "exit_fills": int(summary.get("exit_fills", 0)),
            "closed_positions": len(positions_out),
            "spread_blocks": int(summary.get("spread_blocks", 0)),
            "risk_blocks": int(summary.get("risk_blocks", 0)),
            "execution_blocks": int(summary.get("execution_blocks", 0)),
            "native_reports": native,
        }
        (destination / "physical-run-status.json").write_text(json.dumps(status, indent=2) + "\n")
        statuses.append(status)
        print(f"V31_PERFORMANCE {sequence}/2 {run['run_id']} {status['status']} fills={status['entry_fills']} exits={status['exit_fills']} elapsed={elapsed:.1f}s", flush=True)
        if not valid:
            raise SystemExit(f"V31_PERFORMANCE_TECHNICAL_FAIL_RETAINED_{run['run_id']}")
    (OUT / "v31-physical-run-inventory.json").write_text(json.dumps({"schema": "SOLTRADE_PHASE6_V31_PHYSICAL_RUN_INVENTORY_V1", "status": "PASS", "runs": statuses}, indent=2) + "\n")


if __name__ == "__main__":
    main()
