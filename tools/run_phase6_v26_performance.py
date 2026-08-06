#!/usr/bin/env python3
"""Execute the four frozen V26 multi-currency real-tick portfolio runs."""
from __future__ import annotations

import csv
import json
import os
import shutil
import subprocess
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "reports/backtests/phase6-v26-cross-sectional-currency-momentum"
PLAN = json.loads((OUT / "physical-run-plan.json").read_text())["runs"]
PREFIX = Path("/home/tibule12/.wine-fpmarkets")
TERMINAL = PREFIX / "drive_c/Program Files/FP Markets MT5 Terminal"
COMMON = PREFIX / "drive_c/users/tibule12/AppData/Roaming/MetaQuotes/Terminal/Common/Files"
WORK = PREFIX / "drive_c/v26"
REPORTS = TERMINAL / "v26/reports"


def pairs(path: Path) -> dict[str, str]:
    with path.open() as handle:
        return {row[0]: row[1] for row in csv.reader(handle) if len(row) >= 2}


def ini(run: dict, port: int) -> str:
    instance = run["execution_instance_id"] + "-A2"
    return f"""[Common]\nKeepPrivate=1\nNewsEnable=0\n\n[Experts]\nEnabled=1\nAllowLiveTrading=0\nAllowDllImport=0\nAccount=0\nProfile=0\n\n[Tester]\nExpert=SolTradeRelativeStrengthPerformanceHarness\nSymbol=EURUSD\nPeriod=H1\nDeposit=10000\nCurrency=USD\nLeverage=1:30\nModel=4\nExecutionMode={run['execution_mode']}\nOptimization=0\nForwardMode=0\nFromDate={run['history_from']}\nToDate={run['eligible_to_exclusive'][:10]}\nVisual=0\nUseCloud=0\nPort={port}\nReport=v26\\reports\\attempt-2-{run['run_id']}.html\nReplaceReport=1\nShutdownTerminal=1\n\n[TesterInputs]\nEligibleFrom={run['eligible_from']}\nEligibleTo={run['eligible_to_exclusive']}\nResearchCutoff=2026.08.01 00:00:00\nDatasetId={run['dataset']}\nExecutionLayer={run['execution_layer']}\nExpectedExecutionMode={run['execution_mode']}\nExpectedScheduleLegs={run['expected_schedule_legs']}\nScheduleFile={run['schedule_file']}\nExecutionInstanceId={instance}\nOutputRoot=SolTrade\\Phase6\\V26PerformanceAttempt2\\{instance}\n"""


def execute(run: dict) -> None:
    destination = OUT / "performance-runs-attempt-2" / run["run_id"]
    runtime = COMMON / "SolTrade/Phase6/V26PerformanceAttempt2" / (run["execution_instance_id"] + "-A2")
    port = 3950 + run["run_number"]
    config = WORK / f"performance-attempt-2-{run['run_number']}.ini"
    if destination.exists() or runtime.exists():
        raise SystemExit(f"REFUSE_EXISTING {run['run_id']}")
    destination.mkdir(parents=True)
    config.write_text(ini(run, port))
    (destination / "strategy-tester.ini").write_text(config.read_text())
    for old in REPORTS.glob("attempt-2-" + run["run_id"] + "*"):
        if old.is_file():
            old.unlink()
    env = dict(os.environ, WINEPREFIX=str(PREFIX))
    started = time.time()
    proc = subprocess.run(["wine", str(TERMINAL / "terminal64.exe"), f"/config:C:\\v26\\performance-attempt-2-{run['run_number']}.ini", "/portable"], cwd=ROOT, env=env, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=1800)
    elapsed = time.time() - started
    if runtime.exists():
        for artifact in runtime.iterdir():
            if artifact.is_file():
                shutil.copy2(artifact, destination / artifact.name)
    native = []
    report_stem = "attempt-2-" + run["run_id"]
    for artifact in REPORTS.glob(report_stem + "*"):
        if artifact.is_file():
            shutil.copy2(artifact, destination / ("native-mt5-report" + artifact.name[len(report_stem):]))
            native.append(artifact.name)
    agent = TERMINAL / "Tester" / f"Agent-127.0.0.1-{port}"
    logs = sorted(agent.glob("logs/*.log"), key=lambda p: p.stat().st_mtime)
    if logs:
        shutil.copy2(logs[-1], destination / "tester-agent.log")
    caches = sorted((TERMINAL / "Tester/cache").glob("*.tst"), key=lambda p: p.stat().st_mtime)
    if caches:
        shutil.copy2(caches[-1], destination / "native-tester-cache.tst")
    summary_path = destination / "run-summary.csv"
    summary = pairs(summary_path) if summary_path.exists() else {}
    has_performance_sample = int(summary.get("entry_fills", "0")) > 0 and int(summary.get("exit_fills", "0")) > 0
    status = "PASS" if proc.returncode == 0 and summary.get("run_evidence_status") == "PASS" and has_performance_sample and native and (destination / "tester-agent.log").exists() else "TECHNICAL_FAIL"
    record = {"schema": "SOLTRADE_PHASE6_V26_PHYSICAL_RUN_STATUS_ATTEMPT2_V1", "supersedes_zero-entry_technical_failure": run["run_number"] == 1, "run_number": run["run_number"], "run_id": run["run_id"], "dataset": run["dataset"], "execution_layer": run["execution_layer"], "execution_mode": run["execution_mode"], "model": "EVERY_TICK_BASED_ON_REAL_TICKS", "optimization": False, "elapsed_seconds": elapsed, "wine_return_code": proc.returncode, "schedule_legs": int(summary.get("schedule_legs", "0")), "entry_attempts": int(summary.get("entry_attempts", "0")), "entry_fills": int(summary.get("entry_fills", "0")), "exit_fills": int(summary.get("exit_fills", "0")), "open_positions_at_end": int(summary.get("open_positions_at_end", "0")), "seal_breach": summary.get("seal_breach"), "native_reports": native, "status": status}
    (destination / "physical-run-status.json").write_text(json.dumps(record, indent=2) + "\n")
    print(f"V26_RUN {run['run_number']}/4 {run['run_id']} {status} elapsed={elapsed:.2f}s attempts={record['entry_attempts']} fills={record['entry_fills']} exits={record['exit_fills']}", flush=True)
    if status != "PASS":
        raise SystemExit(f"TECHNICAL_FAIL_RETAINED {run['run_id']}")


def main() -> None:
    REPORTS.mkdir(parents=True, exist_ok=True)
    shutil.copy2(WORK / "SolTradeRelativeStrengthPerformanceHarness.ex5", TERMINAL / "MQL5/Experts/SolTradeRelativeStrengthPerformanceHarness.ex5")
    for run in PLAN:
        execute(run)


if __name__ == "__main__":
    main()
