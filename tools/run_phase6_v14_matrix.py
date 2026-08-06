#!/usr/bin/env python3
"""Execute and capture the frozen Phase 6 V14 36-run MT5 tester matrix."""

from __future__ import annotations

import csv
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import time


REPO = Path(__file__).resolve().parents[1]
OUT = REPO / "reports/backtests/phase6-v14-controlled-practical-backtest"
PREFIX = Path.home() / ".wine-fpmarkets"
TERMINAL = PREFIX / "drive_c/Program Files/FP Markets MT5 Terminal"
COMMON = PREFIX / "drive_c/users/tibule12/AppData/Roaming/MetaQuotes/Terminal/Common/Files"
RUNTIME_ROOT = COMMON / "SolTrade/Phase6/V14"
WORK = PREFIX / "drive_c/v14"
REPORTS = TERMINAL / "v14/reports"
CONTROLLER_LOG = TERMINAL / "Tester/logs/20260803.log"
EXPERT = "SolTradePhase6V14PracticalBacktest"
CORE_HASH = "d6185b478920f6f6cbbb26ffc3d4758e34a6bf89129230b4db4b96ac5666c3c0"

SEGMENTS = [
    dict(id="D1", dataset="DEVELOPMENT", dataset_n=1,
         reset="2025.01.02 00:00:00", eligible_from="2025.01.16 00:00:00",
         eligible_to="2025.02.05 00:00:00", from_date="2025.01.02",
         to_date="2025.02.06", evaluations=335, first="2025.01.16 00:00:00"),
    dict(id="D2", dataset="DEVELOPMENT", dataset_n=1,
         reset="2025.02.05 01:00:00", eligible_from="2025.02.18 05:00:00",
         eligible_to="2025.03.07 23:00:00", from_date="2025.02.05",
         to_date="2025.03.09", evaluations=329, first="2025.02.18 05:00:00"),
    dict(id="D3", dataset="DEVELOPMENT", dataset_n=1,
         reset="2025.03.10 01:00:00", eligible_from="2025.03.21 04:00:00",
         eligible_to="2025.07.05 00:00:00", from_date="2025.03.10",
         to_date="2025.07.06", evaluations=1819, first="2025.03.21 04:00:00"),
    dict(id="V1", dataset="VALIDATION", dataset_n=2,
         reset="2025.03.10 01:00:00", eligible_from="2025.07.05 00:00:00",
         eligible_to="2025.08.06 16:00:00", from_date="2025.03.10",
         to_date="2025.08.08", evaluations=543, first="2025.07.07 00:00:00"),
    dict(id="V2", dataset="VALIDATION", dataset_n=2,
         reset="2025.08.06 18:00:00", eligible_from="2025.08.19 22:00:00",
         eligible_to="2025.09.29 00:00:00", from_date="2025.08.06",
         to_date="2025.09.30", evaluations=673, first="2025.08.19 22:00:00"),
    dict(id="O1", dataset="OUT_OF_SAMPLE", dataset_n=3,
         reset="2025.08.06 18:00:00", eligible_from="2025.09.29 00:00:00",
         eligible_to="2025.12.24 00:00:00", from_date="2025.08.06",
         to_date="2025.12.25", evaluations=1487, first="2025.09.29 00:00:00"),
]
PROFILES = [("NORMAL", 1, 0.0), ("HIGH", 2, 0.5), ("STRESS", 3, 1.0)]
LAYERS = [("NATIVE_NORMAL_EXECUTION", 0, "native"),
          ("FIXED_DELAY_200_MS", 200, "delay200")]


def sha(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for block in iter(lambda: f.read(1 << 20), b""):
            h.update(block)
    return h.hexdigest()


def read_summary(path: Path) -> dict[str, str]:
    with path.open(newline="", encoding="utf-8-sig") as f:
        rows = list(csv.reader(f))
    return {row[0]: row[1] for row in rows[1:] if len(row) >= 2}


def plans() -> list[dict]:
    result = []
    number = 0
    for layer, delay, layer_slug in LAYERS:
        for segment in SEGMENTS:
            for profile, profile_n, multiplier in PROFILES:
                number += 1
                slug = f"{number:03d}-{segment['id'].lower()}-{profile.lower()}-{layer_slug}"
                instance = f"V14-{number:03d}-{segment['id']}-{profile}-" + (
                    "NATIVE" if delay == 0 else "DELAY200")
                result.append({**segment, "number": number, "slug": slug,
                               "instance": instance, "profile": profile,
                               "profile_n": profile_n, "multiplier": multiplier,
                               "layer": layer, "delay": delay, "port": 3100 + number})
    return result


def ini_text(p: dict) -> str:
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
Expert={EXPERT}
Symbol=EURUSD
Period=H1
Deposit=10000
Currency=USD
Leverage=1:30
Model=4
ExecutionMode={p['delay']}
Optimization=0
ForwardMode=0
FromDate={p['from_date']}
ToDate={p['to_date']}
Visual=0
UseCloud=0
Port={p['port']}
Report=v14\\reports\\{p['slug']}.html
ReplaceReport=1
ShutdownTerminal=1

[TesterInputs]
ResetAt={p['reset']}
EligibleFrom={p['eligible_from']}
EligibleTo={p['eligible_to']}
ResearchCutoff=2025.12.24 00:00:00
SegmentId={p['id']}
Dataset={p['dataset_n']}
CostProfile={p['profile_n']}
ExecutionLayer={p['layer']}
ExpectedExecutionMode={p['delay']}
ExecutionInstanceId={p['instance']}
CoreTradingInputHash={CORE_HASH}
ExpectedEvaluationCount={p['evaluations']}
ExpectedFirstEvaluation={p['first']}
OutputRoot=SolTrade\\Phase6\\V14\\{p['instance']}
"""


def copy_runtime(p: dict, run_dir: Path) -> dict:
    runtime = RUNTIME_ROOT / p["instance"]
    required = ["events.csv", "transactions.csv", "deals.csv", "cutoff.csv", "run-summary.csv"]
    for name in required:
        source = runtime / name
        if source.exists():
            shutil.copy2(source, run_dir / name)
    summary_path = run_dir / "run-summary.csv"
    if summary_path.exists():
        shutil.copy2(summary_path, run_dir / "native-mt5-statistics.csv")

    agent = TERMINAL / f"Tester/Agent-127.0.0.1-{p['port']}/logs/20260803.log"
    if agent.exists():
        shutil.copy2(agent, run_dir / "tester-agent.log")
    cache = TERMINAL / "Tester/cache"
    candidates = sorted(cache.glob(f"{EXPERT}.EURUSD.H1.*.tst"),
                        key=lambda x: x.stat().st_mtime, reverse=True)
    if candidates:
        shutil.copy2(candidates[0], run_dir / "native-tester-cache.tst")
    report = REPORTS / f"{p['slug']}.html"
    if report.exists():
        shutil.copy2(report, run_dir / "native-mt5-report.html")
        for image_file in REPORTS.glob(f"{p['slug']}*.png"):
            suffix = image_file.name[len(p['slug']):]
            shutil.copy2(image_file, run_dir / f"native-mt5-report{suffix}")

    summary = read_summary(summary_path) if summary_path.exists() else {}
    status = {
        "schema": "SOLTRADE_PHASE6_V14_PHYSICAL_RUN_STATUS_V1",
        "run_number": p["number"], "run_id": p["slug"],
        "execution_instance_id": p["instance"], "segment": p["id"],
        "dataset": p["dataset"], "cost_profile": p["profile"],
        "supplementary_multiplier": p["multiplier"],
        "execution_layer": p["layer"], "execution_mode": p["delay"],
        "model": "EVERY_TICK_BASED_ON_REAL_TICKS", "optimization": False,
        "generated_tick_fallback": False,
        "core_trading_input_hash": summary.get("core_trading_input_hash"),
        "evaluations": int(summary.get("evaluations", "0")),
        "expected_evaluations": p["evaluations"],
        "first_evaluation": summary.get("first_evaluation"),
        "expected_first_evaluation": p["first"],
        "run_evidence_status": summary.get("run_evidence_status", "MISSING"),
        "native_tester_statistics_present": summary_path.exists(),
        "native_html_report_present": (run_dir / "native-mt5-report.html").exists(),
        "native_tester_cache_present": (run_dir / "native-tester-cache.tst").exists(),
        "tester_agent_log_present": (run_dir / "tester-agent.log").exists(),
        "runtime_artifacts_present": all((run_dir / n).exists() for n in required),
    }
    status["status"] = "PASS" if (
        status["run_evidence_status"] == "PASS"
        and status["core_trading_input_hash"] == CORE_HASH
        and status["evaluations"] == p["evaluations"]
        and status["first_evaluation"] == p["first"]
        and status["native_tester_cache_present"]
        and status["tester_agent_log_present"]
        and status["runtime_artifacts_present"]
    ) else "FAIL"
    (run_dir / "physical-run-status.json").write_text(
        json.dumps(status, indent=2) + "\n", encoding="utf-8")
    return status


def execute(p: dict) -> dict:
    run_dir = OUT / "physical-runs" / p["slug"]
    run_dir.mkdir(parents=True, exist_ok=True)
    ini = ini_text(p)
    (run_dir / "strategy-tester.ini").write_text(ini, encoding="utf-8")
    config_hash = hashlib.sha256(ini.encode()).hexdigest()
    (run_dir / "configuration-sha256.txt").write_text(
        f"{config_hash}  strategy-tester.ini\n", encoding="ascii")
    work_ini = WORK / f"run-{p['number']:03d}.ini"
    work_ini.write_text(ini, encoding="utf-8")

    before = CONTROLLER_LOG.stat().st_size if CONTROLLER_LOG.exists() else 0
    started = time.time()
    command = ["wine", str(TERMINAL / "terminal64.exe"),
               f"/config:C:\\v14\\run-{p['number']:03d}.ini", "/portable"]
    env = dict(os.environ, WINEPREFIX=str(PREFIX))
    proc = subprocess.run(command, cwd=REPO, env=env,
                          stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                          timeout=900)
    (run_dir / "wine-launch.log").write_bytes(proc.stdout)
    ended = time.time()
    if CONTROLLER_LOG.exists():
        with CONTROLLER_LOG.open("rb") as f:
            f.seek(before)
            (run_dir / "tester-controller-delta.log").write_bytes(f.read())
    status = copy_runtime(p, run_dir)
    status.update({"wine_return_code": proc.returncode,
                   "wall_time_seconds": round(ended - started, 3),
                   "configuration_sha256": config_hash})
    (run_dir / "physical-run-status.json").write_text(
        json.dumps(status, indent=2) + "\n", encoding="utf-8")
    print(f"V14_RUN {p['number']:02d}/36 {p['slug']} {status['status']} "
          f"{ended-started:.1f}s", flush=True)
    return status


def main() -> int:
    OUT.mkdir(parents=True, exist_ok=True)
    REPORTS.mkdir(parents=True, exist_ok=True)
    WORK.mkdir(parents=True, exist_ok=True)
    all_plans = plans()
    statuses = []
    for p in all_plans:
        if p["number"] == 1:
            run_dir = OUT / "physical-runs" / p["slug"]
            run_dir.mkdir(parents=True, exist_ok=True)
            ini = ini_text(p)
            (run_dir / "strategy-tester.ini").write_text(ini, encoding="utf-8")
            status = copy_runtime(p, run_dir)
            print(f"V14_RUN 01/36 {p['slug']} {status['status']} CAPTURED", flush=True)
        else:
            status = execute(p)
        statuses.append(status)
        if status["status"] != "PASS":
            print("V14_MATRIX_STOP INVALID_TEST_EVIDENCE", flush=True)
            break
    inventory = {"schema": "SOLTRADE_PHASE6_V14_PHYSICAL_RUN_INVENTORY_V1",
                 "planned_runs": 36, "executed_valid_runs": len(statuses),
                 "runs": statuses}
    (OUT / "phase6-v14-physical-run-inventory.json").write_text(
        json.dumps(inventory, indent=2) + "\n", encoding="utf-8")
    return 0 if len(statuses) == 36 and all(s["status"] == "PASS" for s in statuses) else 2


if __name__ == "__main__":
    sys.exit(main())
