#!/usr/bin/env python3
"""Run frozen V28 and the V31A symbol adapter on equivalent FP Markets data."""
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
OUT = ROOT / "reports/backtests/phase6-v31a-v28-adapter-equivalence"
RUN_ROOT = OUT / "equivalence-runs"
V28_OUT = ROOT / "reports/backtests/phase6-v28-dollar-factor-momentum"
PLAN = json.loads((V28_OUT / "physical-run-plan.json").read_text())["runs"]
PREFIX = Path("/home/tibule12/.wine-fpmarkets")
TERMINAL = PREFIX / "drive_c/Program Files/FP Markets MT5 Terminal"
COMMON = PREFIX / "drive_c/users/tibule12/AppData/Roaming/MetaQuotes/Terminal/Common/Files"
WORK = PREFIX / "drive_c/v31a"
REPORTS = TERMINAL / "v31a/reports"
ORIGINAL_EX5 = PREFIX / "drive_c/v28/SolTradeDollarFactorPerformanceHarness.ex5"
ADAPTER_EX5 = WORK / "SolTradeDollarFactorV31AAdapter.ex5"
ORIGINAL_SHA256 = "03f766bc7ab1cc2c3aed81f72f94f31cc5e122323357216f70ac3a50a5e043ca"
ADAPTER_SHA256 = "92bf94431803c0213b1d796c3a412b581978c680869b20de299bcef90ec8e886"


def sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def pairs(path: Path) -> dict[str, str]:
    with path.open() as handle:
        return {row[0]: row[1] for row in csv.reader(handle) if len(row) >= 2}


def ini(run: dict, side: str, port: int) -> str:
    adapter = side == "adapter"
    expert = "SolTradeDollarFactorV31AAdapter" if adapter else "SolTradeDollarFactorPerformanceHarness"
    symbol = "EURUSD.V31" if adapter else "EURUSD"
    instance = f"V31A-{side.upper()}-{run['dataset'].removeprefix('V28_')}-{run['execution_layer']}-R{run['run_number']}"
    root = f"SolTrade\\Phase6\\V31AParity{side[0].upper()}\\{instance}"
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
Expert={expert}
Symbol={symbol}
Period=H1
Deposit=10000
Currency=USD
Leverage=1:30
Model=4
ExecutionMode={run['execution_mode']}
Optimization=0
ForwardMode=0
FromDate={run['history_from']}
ToDate={run['eligible_to_exclusive'][:10]}
Visual=0
UseCloud=0
Port={port}
Report=v31a\\reports\\{side}-{run['run_id']}.html
ReplaceReport=1
ShutdownTerminal=1

[TesterInputs]
EligibleFrom={run['eligible_from']}
EligibleTo={run['eligible_to_exclusive']}
ResearchCutoff=2026.08.01 00:00:00
DatasetId={run['dataset']}
ExecutionLayer={run['execution_layer']}
ExpectedExecutionMode={run['execution_mode']}
ExpectedScheduleSignals={run['expected_schedule_signals']}
ScheduleFile=SolTrade\\Phase6\\V28Signals\\signal-schedule.csv
ExecutionInstanceId={instance}
OutputRoot={root}
"""


def execute(run: dict, side: str, sequence: int) -> None:
    destination = RUN_ROOT / side / run["run_id"]
    instance = f"V31A-{side.upper()}-{run['dataset'].removeprefix('V28_')}-{run['execution_layer']}-R{run['run_number']}"
    runtime = COMMON / f"SolTrade/Phase6/V31AParity{side[0].upper()}" / instance
    port = 4100 + sequence
    config = WORK / f"parity-{side}-{run['run_number']}.ini"
    if destination.exists() or runtime.exists():
        raise SystemExit(f"REFUSE_EXISTING {side} {run['run_id']}")
    destination.mkdir(parents=True)
    config.write_text(ini(run, side, port))
    (destination / "strategy-tester.ini").write_text(config.read_text())
    report_prefix = f"{side}-{run['run_id']}"
    for old in REPORTS.glob(report_prefix + "*"):
        if old.is_file():
            old.unlink()
    started = time.time()
    proc = subprocess.run(
        ["wine", str(TERMINAL / "terminal64.exe"), f"/config:C:\\v31a\\parity-{side}-{run['run_number']}.ini", "/portable"],
        cwd=ROOT,
        env=dict(os.environ, WINEPREFIX=str(PREFIX)),
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        timeout=1800,
    )
    (destination / "terminal-stdout.log").write_bytes(proc.stdout)
    if runtime.exists():
        for artifact in runtime.iterdir():
            if artifact.is_file():
                shutil.copy2(artifact, destination / artifact.name)
    native = []
    for artifact in REPORTS.glob(report_prefix + "*"):
        if artifact.is_file():
            shutil.copy2(artifact, destination / ("native-mt5-report" + artifact.name[len(report_prefix):]))
            native.append(artifact.name)
    agent = TERMINAL / "Tester" / f"Agent-127.0.0.1-{port}"
    logs = sorted(agent.glob("logs/*.log"), key=lambda p: p.stat().st_mtime)
    if logs:
        shutil.copy2(logs[-1], destination / "tester-agent.log")
    summary_path = destination / "run-summary.csv"
    summary = pairs(summary_path) if summary_path.exists() else {}
    deals_path = destination / "deals.csv"
    deals = list(csv.DictReader(deals_path.open())) if deals_path.exists() else []
    symbol_key = "canonical_symbol" if side == "adapter" else "symbol"
    positions_in = {r["position_identifier"] for r in deals if int(r["entry"]) == 0 and r.get(symbol_key)}
    positions_out = {r["position_identifier"] for r in deals if int(r["entry"]) in (1, 2) and r.get(symbol_key)}
    valid = (
        proc.returncode == 0
        and summary.get("run_evidence_status") == "PASS"
        and int(summary.get("entry_fills", "0")) > 0
        and positions_in == positions_out
        and bool(positions_in)
        and bool(native)
        and (destination / "tester-agent.log").exists()
    )
    status = {
        "schema": "SOLTRADE_PHASE6_V31A_PARITY_RUN_STATUS_V1",
        "side": side,
        "run_id": run["run_id"],
        "dataset": run["dataset"],
        "execution_layer": run["execution_layer"],
        "execution_mode": run["execution_mode"],
        "model": "EVERY_TICK_BASED_ON_REAL_TICKS",
        "optimization": False,
        "elapsed_seconds": time.time() - started,
        "wine_return_code": proc.returncode,
        "schedule_signals": int(summary.get("schedule_signals", "0")),
        "processed_signals": int(summary.get("processed_signals", "0")),
        "entry_attempts": int(summary.get("entry_attempts", "0")),
        "entry_fills": int(summary.get("entry_fills", "0")),
        "exit_fills": int(summary.get("exit_fills", "0")),
        "closed_positions": len(positions_out),
        "native_reports": native,
        "status": "PASS" if valid else "TECHNICAL_FAIL",
    }
    (destination / "physical-run-status.json").write_text(json.dumps(status, indent=2) + "\n")
    print(f"V31A_PARITY_RUN {sequence}/8 {side} {run['run_id']} {status['status']} elapsed={status['elapsed_seconds']:.2f}s fills={status['entry_fills']} exits={status['exit_fills']}", flush=True)
    if not valid:
        raise SystemExit(f"V31A_PARITY_TECHNICAL_FAIL_RETAINED {side} {run['run_id']}")


def main() -> None:
    if sha(ORIGINAL_EX5) != ORIGINAL_SHA256 or sha(ADAPTER_EX5) != ADAPTER_SHA256:
        raise SystemExit("V31A_PARITY_EXECUTABLE_HASH_MISMATCH")
    schedule_runtime = COMMON / "SolTrade/Phase6/V28Signals/signal-schedule.csv"
    schedule_evidence = V28_OUT / "signal-feasibility/signal-schedule.csv"
    if not schedule_runtime.exists() or sha(schedule_runtime) != sha(schedule_evidence):
        raise SystemExit("V31A_PARITY_SCHEDULE_HASH_MISMATCH")
    if RUN_ROOT.exists():
        raise SystemExit("REFUSE_EXISTING_V31A_PARITY_RUN_ROOT")
    REPORTS.mkdir(parents=True, exist_ok=True)
    shutil.copy2(ORIGINAL_EX5, TERMINAL / "MQL5/Experts/SolTradeDollarFactorPerformanceHarness.ex5")
    shutil.copy2(ADAPTER_EX5, TERMINAL / "MQL5/Experts/SolTradeDollarFactorV31AAdapter.ex5")
    sequence = 0
    for run in PLAN:
        for side in ("original", "adapter"):
            sequence += 1
            execute(run, side, sequence)


if __name__ == "__main__":
    main()
