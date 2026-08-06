#!/usr/bin/env python3
"""Prove the V31 signal symbol adapter matches frozen V28 decisions on FP data."""
from __future__ import annotations

import csv
import hashlib
import json
import os
import shutil
import subprocess
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "reports/backtests/phase6-v31-v28-external-feed-replication-attempt2/signal-adapter-parity-attempt2"
V28_SCHEDULE = ROOT / "reports/backtests/phase6-v28-dollar-factor-momentum/signal-feasibility/signal-schedule.csv"
PREFIX = Path("/home/tibule12/.wine-fpmarkets")
TERMINAL = PREFIX / "drive_c/Program Files/FP Markets MT5 Terminal"
COMMON = PREFIX / "drive_c/users/tibule12/AppData/Roaming/MetaQuotes/Terminal/Common/Files"
WORK = PREFIX / "drive_c/v31-external"
EX5 = WORK / "SolTradeDollarFactorV31SignalAdapter.ex5"
EX5_SHA256 = "fe4cbd2a0b28a6743ffda29e6b0cb04ffa041665a1f05f4ce3ff011687e7ee71"
MAPPING = {symbol: f"{symbol}.V31" for symbol in ("EURUSD", "GBPUSD", "AUDUSD", "NZDUSD", "USDCAD", "USDCHF", "USDJPY")}
RUNS = (
    {"id": "2025", "from": "2024.12.01", "eligible_from": "2025.01.06 00:00:00", "to": "2026.01.01 00:00:00", "cohorts": 11, "legs": 77, "port": 4210},
    {"id": "2026", "from": "2025.12.01", "eligible_from": "2026.01.05 00:00:00", "to": "2026.08.01 00:00:00", "cohorts": 6, "legs": 42, "port": 4211},
)


def sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def ini(run: dict) -> str:
    return f"""[Common]
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
FromDate={run['from']}
ToDate={run['to'][:10]}
Visual=0
UseCloud=0
Port={run['port']}
Report=v31-external\\signal-parity-{run['id']}.html
ReplaceReport=1
ShutdownTerminal=1

[TesterInputs]
EligibleFrom={run['eligible_from']}
EligibleTo={run['to']}
ResearchCutoff={run['to']}
DatasetId=V31_SIGNAL_ADAPTER_EQUIVALENCE_{run['id']}
ExpectedCohorts={run['cohorts']}
ExpectedLegs={run['legs']}
OutputRoot=SolTrade\\Phase6\\V31SignalParity{run['id']}
"""


def main() -> None:
    if OUT.exists():
        raise SystemExit("REFUSE_EXISTING_V31_SIGNAL_PARITY_OUTPUT")
    if sha(EX5) != EX5_SHA256:
        raise SystemExit("SIGNAL_ADAPTER_EXECUTABLE_HASH_MISMATCH")
    OUT.mkdir(parents=True)
    expert = TERMINAL / "MQL5/Experts/SolTradeDollarFactorV31SignalAdapter.ex5"
    shutil.copy2(EX5, expert)
    env = dict(os.environ, WINEPREFIX=str(PREFIX))
    adapter = []
    summaries = []
    return_codes = []
    for run in RUNS:
        destination = OUT / run["id"]
        destination.mkdir()
        runtime = COMMON / f"SolTrade/Phase6/V31SignalParity{run['id']}"
        if runtime.exists():
            shutil.rmtree(runtime)
        config = WORK / f"signal-parity-{run['id']}.ini"
        config.write_text(ini(run))
        (destination / "strategy-tester.ini").write_text(config.read_text())
        proc = subprocess.run(
            ["wine", str(TERMINAL / "terminal64.exe"), f"/config:C:\\v31-external\\signal-parity-{run['id']}.ini", "/portable"],
            cwd=ROOT, env=env, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=1800,
        )
        return_codes.append(proc.returncode)
        (destination / "terminal-stdout.log").write_bytes(proc.stdout)
        for artifact in runtime.glob("*"):
            if artifact.is_file():
                shutil.copy2(artifact, destination / artifact.name)
        report_dir = TERMINAL / "v31-external"
        for artifact in report_dir.glob(f"signal-parity-{run['id']}*"):
            if artifact.is_file():
                shutil.copy2(artifact, destination / ("native-mt5-report" + artifact.suffix))
        agent = TERMINAL / "Tester" / f"Agent-127.0.0.1-{run['port']}"
        logs = sorted(agent.glob("logs/*.log"), key=lambda path: path.stat().st_mtime)
        if logs:
            shutil.copy2(logs[-1], destination / "tester-agent.log")
        with (destination / "signal-schedule.csv").open() as handle:
            adapter.extend(csv.DictReader(handle))
        with (destination / "signal-summary.csv").open() as handle:
            summaries.append({row[0]: row[1] for row in csv.reader(handle) if len(row) >= 2})
    with V28_SCHEDULE.open() as handle:
        original = list(csv.DictReader(handle))
    fields = (
        ("target", "target"),
        ("symbol", "canonical_symbol"),
        ("orientation", "orientation"),
        ("dollar_factor_return", "dollar_factor_return"),
        ("factor_side", "factor_side"),
        ("chart_direction", "chart_direction"),
        ("recent_h1", "recent_h1"),
        ("recent_close", "recent_close"),
        ("anchor_h1", "anchor_h1"),
        ("anchor_close", "anchor_close"),
        ("scheduled_exit", "scheduled_exit"),
    )
    divergences = []
    for index in range(max(len(original), len(adapter))):
        if index >= len(original) or index >= len(adapter):
            divergences.append({"row": index + 1, "reason": "ROW_COUNT_MISMATCH"})
            continue
        for original_field, adapter_field in fields:
            if original[index][original_field] != adapter[index][adapter_field]:
                divergences.append(
                    {
                        "row": index + 1,
                        "field": original_field,
                        "original": original[index][original_field],
                        "adapter": adapter[index][adapter_field],
                    }
                )
        canonical = adapter[index]["canonical_symbol"]
        if adapter[index]["research_symbol"] != MAPPING.get(canonical):
            divergences.append({"row": index + 1, "field": "research_symbol", "adapter": adapter[index]["research_symbol"]})
    passed = all(code == 0 for code in return_codes) and all(summary.get("status") == "PASS" for summary in summaries) and len(original) == len(adapter) == 119 and not divergences
    evidence = {
        "schema": "SOLTRADE_PHASE6_V31_SIGNAL_ADAPTER_PARITY_V1",
        "status": "PASS" if passed else "FAIL",
        "classification": "SIGNAL_ONLY_NO_PNL",
        "original_v28_schedule_sha256": sha(V28_SCHEDULE),
        "signal_adapter_source_sha256": sha(ROOT / "research/factor_momentum/SolTradeDollarFactorV31SignalAdapter.mq5"),
        "signal_adapter_executable_sha256": sha(EX5),
        "original_signals": len(original),
        "adapter_signals": len(adapter),
        "exact_decision_fields_compared_per_signal": len(fields),
        "exact_decision_values_compared": min(len(original), len(adapter)) * len(fields),
        "divergence_count": len(divergences),
        "divergences": divergences,
        "mapping": MAPPING,
        "orders_or_positions": "ZERO",
        "pnl_calculated": False,
        "wine_return_codes": return_codes,
    }
    (OUT / "parity-evidence.json").write_text(json.dumps(evidence, indent=2) + "\n")
    print(json.dumps(evidence, sort_keys=True))
    if not passed:
        raise SystemExit("V31_SIGNAL_ADAPTER_PARITY_FAILED")


if __name__ == "__main__":
    main()
