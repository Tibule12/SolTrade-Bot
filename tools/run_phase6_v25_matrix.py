#!/usr/bin/env python3
"""Execute the immutable V25 Strategy Tester matrix in locked order."""
from __future__ import annotations

import argparse
import csv
import hashlib
import json
import os
import shutil
import subprocess
import time
from datetime import datetime, timedelta
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "reports/backtests/phase6-v25-fx-fixing-inventory-reversal"
PLAN = json.loads((OUT / "phase6-v25-physical-run-plan.json").read_text())["runs"]
PREFIX = Path("/home/tibule12/.wine-fpmarkets")
TERMINAL = PREFIX / "drive_c/Program Files/FP Markets MT5 Terminal"
COMMON = PREFIX / "drive_c/users/tibule12/AppData/Roaming/MetaQuotes/Terminal/Common/Files"
WORK = PREFIX / "drive_c/v25"
REPORTS = TERMINAL / "v25/reports"


def fields(path: Path) -> dict[str, str]:
    with path.open() as handle:
        return {r[0]: r[1] for r in csv.reader(handle) if len(r) >= 2}


def rendered_ini(run: dict, port: int) -> str:
    profile = {"NORMAL": 1, "HIGH": 2, "STRESS": 3}[run["cost_profile"]]
    end = datetime.strptime(run["eligible_to_exclusive"], "%Y.%m.%d %H:%M:%S")
    to_date = (end + timedelta(days=1) if end.time().isoformat() != "00:00:00" else end).strftime("%Y.%m.%d")
    return f"""[Common]\nKeepPrivate=1\nNewsEnable=0\n\n[Experts]\nEnabled=1\nAllowLiveTrading=0\nAllowDllImport=0\nAccount=0\nProfile=0\n\n[Tester]\nExpert=SolTradeFixingReversalHarness\nSymbol=EURUSD\nPeriod=H1\nDeposit=10000\nCurrency=USD\nLeverage=1:30\nModel=4\nExecutionMode={run['execution_mode']}\nOptimization=0\nForwardMode=0\nFromDate={run['reset_at'][:10]}\nToDate={to_date}\nVisual=0\nUseCloud=0\nPort={port}\nReport=v25\\reports\\{run['run_id']}.html\nReplaceReport=1\nShutdownTerminal=1\n\n[TesterInputs]\nResetAt={run['reset_at']}\nEligibleFrom={run['eligible_from']}\nEligibleTo={run['eligible_to_exclusive']}\nResearchCutoff=2026.08.01 00:00:00\nSegmentId={run['segment_id']}\nDataset=1\nCostProfile={profile}\nExecutionLayer={run['execution_layer']}\nExpectedExecutionMode={run['execution_mode']}\nExecutionInstanceId={run['execution_instance_id']}\nExpectedEvaluationCount={run['expected_indicator_eligible_h1_bars']}\nExpectedFirstEvaluation={run['expected_first_indicator_eligible_h1']}\nOutputRoot=SolTrade\\Phase6\\V25\\{run['execution_instance_id']}\n"""


def execute(run: dict) -> None:
    dest = OUT / run["output_subdirectory"]
    runtime = COMMON / "SolTrade/Phase6/V25" / run["execution_instance_id"]
    port = 3500 + run["run_number"]
    config = WORK / f"run-{run['run_number']:03d}.ini"
    ini = rendered_ini(run, port)
    ini_sha = hashlib.sha256(ini.encode()).hexdigest()
    if dest.exists():
        raise SystemExit(f"REFUSE_RERUN_EXISTING {run['run_id']}")
    if runtime.exists():
        shutil.rmtree(runtime)
    for old in REPORTS.glob(run["run_id"] + "*"):
        if old.is_file():
            old.unlink()
    dest.mkdir(parents=True)
    config.write_text(ini)
    (dest / "strategy-tester.ini").write_text(ini)
    (dest / "configuration-sha256.txt").write_text(ini_sha + "\n")
    env = dict(os.environ, WINEPREFIX=str(PREFIX))
    started = time.time()
    proc = subprocess.run(
        ["wine", str(TERMINAL / "terminal64.exe"), f"/config:C:\\v25\\run-{run['run_number']:03d}.ini", "/portable"],
        cwd=ROOT, env=env, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=900,
    )
    elapsed = time.time() - started
    if runtime.exists():
        for artifact in runtime.iterdir():
            if artifact.is_file():
                shutil.copy2(artifact, dest / artifact.name)
    native_reports = []
    for artifact in REPORTS.glob(run["run_id"] + "*"):
        if artifact.is_file():
            shutil.copy2(artifact, dest / ("native-mt5-report" + artifact.name[len(run["run_id"]):]))
            native_reports.append(artifact.name)
    agent = TERMINAL / "Tester" / f"Agent-127.0.0.1-{port}"
    logs = sorted(agent.glob("logs/*.log"), key=lambda p: p.stat().st_mtime)
    if logs:
        shutil.copy2(logs[-1], dest / "tester-agent.log")
    caches = sorted((TERMINAL / "Tester/cache").glob("*.tst"), key=lambda p: p.stat().st_mtime)
    if caches:
        shutil.copy2(caches[-1], dest / "native-tester-cache.tst")
    summary = fields(dest / "run-summary.csv") if (dest / "run-summary.csv").exists() else {}
    status = "PASS" if proc.returncode == 0 and summary.get("run_evidence_status") == "PASS" and native_reports and (dest / "tester-agent.log").exists() and (dest / "native-tester-cache.tst").exists() else "TECHNICAL_FAIL"
    record = {
        "schema": "SOLTRADE_PHASE6_V25_PHYSICAL_RUN_STATUS_V1",
        "run_number": run["run_number"], "run_id": run["run_id"],
        "execution_instance_id": run["execution_instance_id"], "formal_dataset": run["formal_dataset"],
        "segment_id": run["segment_id"], "cost_profile": run["cost_profile"],
        "execution_layer": run["execution_layer"], "execution_mode": run["execution_mode"],
        "model": "EVERY_TICK_BASED_ON_REAL_TICKS", "optimization": False,
        "frozen_complete_run_configuration_sha256": run["complete_run_configuration_sha256"],
        "rendered_ini_sha256": ini_sha, "wine_return_code": proc.returncode,
        "elapsed_seconds": elapsed, "run_evidence_status": summary.get("run_evidence_status"),
        "evaluations": int(summary.get("evaluations", "0")),
        "entry_opportunities": int(summary.get("entry_opportunities", "0")),
        "entry_fills": int(summary.get("entry_fills", "0")), "exit_fills": int(summary.get("exit_fills", "0")),
        "seal_breach": summary.get("seal_breach"), "native_reports": native_reports, "status": status,
    }
    (dest / "physical-run-status.json").write_text(json.dumps(record, indent=2) + "\n")
    print(f"V25_RUN {run['run_number']:02d}/42 {run['run_id']} {status} {elapsed:.2f}s opportunities={record['entry_opportunities']} entries={record['entry_fills']} exits={record['exit_fills']}", flush=True)
    if status != "PASS":
        raise SystemExit(f"TECHNICAL_FAIL_RETAINED {run['run_id']}")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--start", type=int, default=1)
    parser.add_argument("--end", type=int, default=42)
    args = parser.parse_args()
    WORK.mkdir(exist_ok=True)
    REPORTS.mkdir(parents=True, exist_ok=True)
    for run in PLAN:
        if args.start <= run["run_number"] <= args.end:
            execute(run)


if __name__ == "__main__":
    main()
