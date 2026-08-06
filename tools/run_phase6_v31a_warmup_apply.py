#!/usr/bin/env python3
"""Apply and audit the extended FP Markets pre-start rates on V31A symbols."""
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
OUT = ROOT / "reports/backtests/phase6-v31a-v28-adapter-equivalence/fpmarkets-warmup-apply"
PREFIX = Path("/home/tibule12/.wine-fpmarkets")
TERMINAL = PREFIX / "drive_c/Program Files/FP Markets MT5 Terminal"
COMMON = PREFIX / "drive_c/users/tibule12/AppData/Roaming/MetaQuotes/Terminal/Common/Files"
WORK = PREFIX / "drive_c/v31a"
RUNTIME = COMMON / "SolTrade/Phase6/V31AWarmupApply"
SOURCE = ROOT / "research/factor_momentum/SolTradeV31AWarmupApply.mq5"
EX5 = WORK / "SolTradeV31AWarmupApply.ex5"
SOURCE_SHA256 = "1b5c54804fda0eea45ba34c2e648c6695e888215ad8a4c6e170c2026ddaf01d7"
EX5_SHA256 = "c5fb2a5eee72f88f830cdd73b20c1f26e13a72b559faef960f32684a734d648b"


def sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main() -> None:
    if sha(SOURCE) != SOURCE_SHA256 or sha(EX5) != EX5_SHA256:
        raise SystemExit("V31A_WARMUP_APPLY_HASH_MISMATCH")
    if OUT.exists() or RUNTIME.exists():
        raise SystemExit("REFUSE_EXISTING_V31A_WARMUP_APPLY")
    OUT.mkdir(parents=True)
    shutil.copy2(EX5, TERMINAL / "MQL5/Experts/SolTradeV31AWarmupApply.ex5")
    config = WORK / "warmup-apply.ini"
    config.write_text("""[Common]
KeepPrivate=1
NewsEnable=0
CertInstall=0

[Experts]
AllowLiveTrading=0
AllowDllImport=0
Enabled=0
Account=0
Profile=0

[StartUp]
Symbol=EURUSD
Period=M1
Expert=SolTradeV31AWarmupApply
""")
    (OUT / "terminal-config.ini").write_text(config.read_text())
    started = time.time()
    proc = subprocess.run(
        ["wine", str(TERMINAL / "terminal64.exe"), "/config:C:\\v31a\\warmup-apply.ini", "/portable"],
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
    logs = sorted((TERMINAL / "logs").glob("*.log"), key=lambda p: p.stat().st_mtime)
    if logs:
        shutil.copy2(logs[-1], OUT / "terminal-journal.log")
    shutil.copy2(WORK / "warmup-apply-compile.log", OUT / "warmup-apply-compile.log")
    rows = list(csv.DictReader((OUT / "summary.csv").open())) if (OUT / "summary.csv").exists() else []
    valid = proc.returncode == 0 and len(rows) == 7 and all(row["status"] == "PASS" and int(row["exact_rate_mismatches"]) == 0 for row in rows)
    status = {"schema": "SOLTRADE_PHASE6_V31A_WARMUP_APPLY_STATUS_V1", "status": "PASS" if valid else "FAIL", "elapsed_seconds": time.time() - started, "wine_return_code": proc.returncode, "symbols": len(rows), "source_rates": sum(int(row["source_rates"]) for row in rows), "reloaded_rates": sum(int(row["reloaded_rates"]) for row in rows), "exact_rate_mismatches": sum(int(row["exact_rate_mismatches"]) for row in rows), "tick_operations": "NONE", "trade_api_calls": "NONE", "pnl_calculated": False, "external_data_downloaded": False}
    (OUT / "status.json").write_text(json.dumps(status, indent=2) + "\n")
    print(json.dumps(status, indent=2), flush=True)
    if not valid:
        raise SystemExit("V31A_WARMUP_APPLY_FAILED_RETAINED")


if __name__ == "__main__":
    main()
