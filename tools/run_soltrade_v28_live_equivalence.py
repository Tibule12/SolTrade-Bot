#!/usr/bin/env python3
"""Run the production V28 EA against the four frozen V28 physical cells."""
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
V28 = ROOT / "reports/backtests/phase6-v28-dollar-factor-momentum"
OUT = ROOT / "reports/backtests/soltrade-v28-live-ea-equivalence"
RUN_ROOT = OUT / "runs"
PLAN = json.loads((V28 / "physical-run-plan.json").read_text())["runs"]
PREFIX = Path("/home/tibule12/.wine-fpmarkets")
TERMINAL = PREFIX / "drive_c/Program Files/FP Markets MT5 Terminal"
COMMON = PREFIX / "drive_c/users/tibule12/AppData/Roaming/MetaQuotes/Terminal/Common/Files"
WORK = PREFIX / "drive_c/v28-live-ea"
EX5 = WORK / "SolTradeV28.ex5"
REPORTS = TERMINAL / "v28-live-ea/reports"
EXPECTED_EX5_SHA256 = "5ca4de97e56bbd1e6d0cff71d7c71c753dbb1d4f29f0237915754bad93205536"


def sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def pairs(path: Path) -> dict[str, str]:
    with path.open() as handle:
        return {row[0]: row[1] for row in csv.reader(handle) if len(row) >= 2}


def render_ini(run: dict, port: int) -> tuple[str, str]:
    instance = f"SOLTRADEV28-{run['dataset'].removeprefix('V28_')}-{run['execution_layer']}-R{run['run_number']}"
    output = f"SolTrade\\V28Equivalence\\{instance}"
    ini = f"""[Common]
KeepPrivate=1
NewsEnable=0

[Experts]
Enabled=1
AllowLiveTrading=0
AllowDllImport=0
Account=0
Profile=0

[Tester]
Expert=SolTradeV28
Symbol=EURUSD
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
Report=v28-live-ea\\reports\\{run['run_id']}.html
ReplaceReport=1
ShutdownTerminal=1

[TesterInputs]
ApprovedAccount=0
ApprovedServer=FXIFY-Server
ProductionBaselineEquity=10000.0
DryRunMode=false
SymbolSuffix=.r
EURUSDSymbol=EURUSD
GBPUSDSymbol=GBPUSD
AUDUSDSymbol=AUDUSD
NZDUSDSymbol=NZDUSD
USDCADSymbol=USDCAD
USDCHFSymbol=USDCHF
USDJPYSymbol=USDJPY
EquivalenceMode=true
EligibleFrom={run['eligible_from']}
EligibleTo={run['eligible_to_exclusive']}
ResearchCutoff=2026.08.01 00:00:00
DatasetId={run['dataset']}
ExecutionLayer={run['execution_layer']}
ExpectedExecutionMode={run['execution_mode']}
ExpectedScheduleSignals={run['expected_schedule_signals']}
ExecutionInstanceId={instance}
OutputRoot={output}
"""
    return instance, ini


def execute(run: dict, sequence: int) -> None:
    destination = RUN_ROOT / run["run_id"]
    instance, ini = render_ini(run, 5100 + sequence)
    runtime = COMMON / "SolTrade/V28Equivalence" / instance
    config = WORK / f"equivalence-{run['run_number']}.ini"
    if destination.exists() or runtime.exists():
        raise SystemExit(f"REFUSE_EXISTING_EQUIVALENCE_OUTPUT {run['run_id']}")
    destination.mkdir(parents=True)
    config.write_text(ini)
    (destination / "strategy-tester.ini").write_text(ini)
    report_prefix = run["run_id"]
    for old in REPORTS.glob(report_prefix + "*"):
        if old.is_file():
            old.unlink()
    started = time.time()
    proc = subprocess.run(
        [
            "wine",
            str(TERMINAL / "terminal64.exe"),
            f"/config:C:\\v28-live-ea\\equivalence-{run['run_number']}.ini",
            "/portable",
        ],
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
            target = destination / ("native-mt5-report" + artifact.name[len(report_prefix) :])
            shutil.copy2(artifact, target)
            native.append(target.name)
    agent = TERMINAL / "Tester" / f"Agent-127.0.0.1-{5100 + sequence}"
    logs = sorted(agent.glob("logs/*.log"), key=lambda path: path.stat().st_mtime)
    if logs:
        shutil.copy2(logs[-1], destination / "tester-agent.log")
    summary = pairs(destination / "run-summary.csv") if (destination / "run-summary.csv").exists() else {}
    valid = (
        proc.returncode == 0
        and summary.get("run_evidence_status") == "PASS"
        and int(summary.get("schedule_signals", "0")) == run["expected_schedule_signals"]
        and int(summary.get("processed_signals", "0")) == run["expected_schedule_signals"]
        and int(summary.get("open_positions_at_end", "-1")) == 0
        and bool(native)
        and (destination / "tester-agent.log").exists()
    )
    status = {
        "schema": "SOLTRADE_V28_LIVE_EA_EQUIVALENCE_RUN_STATUS_V1",
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
        "open_positions_at_end": int(summary.get("open_positions_at_end", "-1")),
        "native_reports": native,
        "status": "PASS" if valid else "TECHNICAL_FAIL",
    }
    (destination / "physical-run-status.json").write_text(json.dumps(status, indent=2) + "\n")
    print(
        f"SOLTRADEV28_EQUIVALENCE_RUN {sequence}/4 {run['run_id']} {status['status']} "
        f"elapsed={status['elapsed_seconds']:.2f}s fills={status['entry_fills']} exits={status['exit_fills']}",
        flush=True,
    )
    if not valid:
        raise SystemExit(f"SOLTRADEV28_EQUIVALENCE_TECHNICAL_FAIL {run['run_id']}")


def main() -> None:
    if sha(EX5) != EXPECTED_EX5_SHA256:
        raise SystemExit("SOLTRADEV28_EX5_HASH_MISMATCH")
    if RUN_ROOT.exists():
        raise SystemExit("REFUSE_EXISTING_SOLTRADEV28_EQUIVALENCE_ROOT")
    REPORTS.mkdir(parents=True, exist_ok=True)
    shutil.copy2(EX5, TERMINAL / "MQL5/Experts/SolTradeV28.ex5")
    for sequence, run in enumerate(PLAN, 1):
        execute(run, sequence)


if __name__ == "__main__":
    main()
