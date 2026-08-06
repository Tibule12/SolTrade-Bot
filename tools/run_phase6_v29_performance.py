#!/usr/bin/env python3
"""Execute the four frozen V29 multi-currency real-tick portfolio runs."""
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
OUT = ROOT / "reports/backtests/phase6-v29-weekly-cross-sectional-currency-momentum"
RUN_ROOT = "performance-runs-attempt2"
PLAN = json.loads((OUT / "physical-run-plan.json").read_text())["runs"]
PREFIX = Path("/home/tibule12/.wine-fpmarkets")
TERMINAL = PREFIX / "drive_c/Program Files/FP Markets MT5 Terminal"
COMMON = PREFIX / "drive_c/users/tibule12/AppData/Roaming/MetaQuotes/Terminal/Common/Files"
WORK = PREFIX / "drive_c/v29"
REPORTS = TERMINAL / "v29/reports"
EX5 = WORK / "SolTradeV29CrossSectionalMomentumPerformanceHarness.ex5"
FROZEN_EX5_SHA256 = "5fa64792a6b150a00e43c05cc141baad6c4802b8c7d32c4f3d10aef33aed46a8"
FROZEN_SCHEDULE_SHA256 = {
    "V26_2025_DEVELOPMENT": "25876a808a49044bfdb2f2b728e0cbd7d097678c377a9b4af8b4d7b0ed8487cf",
    "V26_2026_PRESEAL_DEVELOPMENT": "feada50576c4c6dd8ff716a2dda94abc053265ec8f545057bbd6e9a92425a11b",
}


def sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def pairs(path: Path) -> dict[str, str]:
    with path.open() as handle:
        return {row[0]: row[1] for row in csv.reader(handle) if len(row) >= 2}


def ini(run: dict, port: int) -> str:
    instance = f"V29-{run['dataset'].removeprefix('V29_')}-{run['execution_layer']}-R{run['run_number']}"
    return f"""[Common]\nKeepPrivate=1\nNewsEnable=0\n\n[Experts]\nEnabled=1\nAllowLiveTrading=0\nAllowDllImport=0\nAccount=0\nProfile=0\n\n[Tester]\nExpert=SolTradeV29CrossSectionalMomentumPerformanceHarness\nSymbol=EURUSD\nPeriod=H1\nDeposit=10000\nCurrency=USD\nLeverage=1:30\nModel=4\nExecutionMode={run['execution_mode']}\nOptimization=0\nForwardMode=0\nFromDate={run['history_from']}\nToDate={run['eligible_to_exclusive'][:10]}\nVisual=0\nUseCloud=0\nPort={port}\nReport=v29\\reports\\a2-{run['run_id']}.html\nReplaceReport=1\nShutdownTerminal=1\n\n[TesterInputs]\nEligibleFrom={run['eligible_from']}\nEligibleTo={run['eligible_to_exclusive']}\nResearchCutoff=2026.08.01 00:00:00\nDatasetId={run['dataset']}\nScheduleDatasetId={run['schedule_dataset']}\nExecutionLayer={run['execution_layer']}\nExpectedExecutionMode={run['execution_mode']}\nExpectedScheduleLegs={run['expected_schedule_legs']}\nScheduleFile={run['schedule_file']}\nExecutionInstanceId={instance}\nOutputRoot=SolTrade\\Phase6\\V29PerformanceA2\\{instance}\n"""


def execute(run: dict) -> None:
    destination = OUT / RUN_ROOT / run["run_id"]
    instance = f"V29-{run['dataset'].removeprefix('V29_')}-{run['execution_layer']}-R{run['run_number']}"
    runtime = COMMON / "SolTrade/Phase6/V29PerformanceA2" / instance
    port = 4020 + run["run_number"]
    config = WORK / f"performance-{run['run_number']}.ini"
    if destination.exists() or runtime.exists():
        raise SystemExit(f"REFUSE_EXISTING {run['run_id']}")
    destination.mkdir(parents=True)
    config.write_text(ini(run, port))
    (destination / "strategy-tester.ini").write_text(config.read_text())
    for old in REPORTS.glob("a2-" + run["run_id"] + "*"):
        if old.is_file():
            old.unlink()
    env = dict(os.environ, WINEPREFIX=str(PREFIX))
    started = time.time()
    proc = subprocess.run(["wine", str(TERMINAL / "terminal64.exe"), f"/config:C:\\v29\\performance-{run['run_number']}.ini", "/portable"], cwd=ROOT, env=env, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=1800)
    elapsed = time.time() - started
    if runtime.exists():
        for artifact in runtime.iterdir():
            if artifact.is_file():
                shutil.copy2(artifact, destination / artifact.name)
    native = []
    report_stem = "a2-" + run["run_id"]
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
    deal_rows = list(csv.DictReader((destination / "deals.csv").open())) if (destination / "deals.csv").exists() else []
    position_entries = {row["position_identifier"] for row in deal_rows if int(row["entry"]) == 0}
    position_exits = {row["position_identifier"] for row in deal_rows if int(row["entry"]) in (1, 2)}
    all_deal_positions_closed = position_entries == position_exits
    status = "PASS" if proc.returncode == 0 and summary.get("run_evidence_status") == "PASS" and summary.get("final_exit_target_cleared") == "YES" and all_deal_positions_closed and int(summary.get("missed_legs", "0")) == 0 and int(summary.get("max_portfolio_positions", "0")) <= 4 and native and (destination / "tester-agent.log").exists() else "TECHNICAL_FAIL"
    record = {"schema": "SOLTRADE_PHASE6_V29_PHYSICAL_RUN_STATUS_ATTEMPT2_V1", "run_number": run["run_number"], "run_id": run["run_id"], "dataset": run["dataset"], "schedule_dataset": run["schedule_dataset"], "execution_layer": run["execution_layer"], "execution_mode": run["execution_mode"], "model": "EVERY_TICK_BASED_ON_REAL_TICKS", "optimization": False, "elapsed_seconds": elapsed, "wine_return_code": proc.returncode, "schedule_legs": int(summary.get("schedule_legs", "0")), "processed_rebalances": int(summary.get("processed_rebalances", "0")), "entry_attempts": int(summary.get("entry_attempts", "0")), "entry_fills": int(summary.get("entry_fills", "0")), "exit_callback_fills": int(summary.get("exit_fills", "0")), "authoritative_closed_positions": len(position_exits), "all_deal_positions_closed": all_deal_positions_closed, "missed_legs": int(summary.get("missed_legs", "0")), "spread_blocks": int(summary.get("spread_blocks", "0")), "risk_blocks": int(summary.get("risk_blocks", "0")), "execution_blocks": int(summary.get("execution_blocks", "0")), "max_portfolio_positions": int(summary.get("max_portfolio_positions", "0")), "final_exit_target_cleared": summary.get("final_exit_target_cleared"), "open_positions_at_end": int(summary.get("open_positions_at_end", "0")), "seal_breach": summary.get("seal_breach"), "native_reports": native, "status": status}
    (destination / "physical-run-status.json").write_text(json.dumps(record, indent=2) + "\n")
    print(f"V29_RUN {run['run_number']}/4 {run['run_id']} {status} elapsed={elapsed:.2f}s attempts={record['entry_attempts']} fills={record['entry_fills']} closed={record['authoritative_closed_positions']} risk={record['risk_blocks']} execution={record['execution_blocks']}", flush=True)
    if status != "PASS":
        raise SystemExit(f"TECHNICAL_FAIL_RETAINED {run['run_id']}")


def main() -> None:
    if sha(EX5) != FROZEN_EX5_SHA256:
        raise SystemExit("FROZEN_V29_EXECUTABLE_HASH_MISMATCH")
    for schedule_dataset, expected_hash in FROZEN_SCHEDULE_SHA256.items():
        source = OUT / "frozen-v26-signal-set" / schedule_dataset / "signal-schedule.csv"
        if sha(source) != expected_hash:
            raise SystemExit(f"FROZEN_V29_SCHEDULE_HASH_MISMATCH {schedule_dataset}")
        runtime_schedule = COMMON / "SolTrade/Phase6/V29Signals" / schedule_dataset / "signal-schedule.csv"
        runtime_schedule.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source, runtime_schedule)
        if sha(runtime_schedule) != expected_hash:
            raise SystemExit(f"V29_RUNTIME_SCHEDULE_COPY_FAILED {schedule_dataset}")
    REPORTS.mkdir(parents=True, exist_ok=True)
    shutil.copy2(EX5, TERMINAL / "MQL5/Experts/SolTradeV29CrossSectionalMomentumPerformanceHarness.ex5")
    for run in PLAN:
        execute(run)


if __name__ == "__main__":
    main()
