#!/usr/bin/env python3
"""Export FP demo gold M1 history through an isolated, orderless Wine terminal."""

import argparse
import hashlib
import json
import os
import shutil
import subprocess
import time
from pathlib import Path

from audit_fp_all_symbols import COMMON, ROOT
from run_fp_readonly_audit_export import PREFIX, TERMINAL

SOURCE = ROOT / "tools/mql/SolTradeGoldWeekendReadOnly.mq5"
COMMON_OUTPUT = COMMON / "SolTradeGoldWeekendReadOnly"


def run(output: Path, timeout: int) -> dict:
    output.mkdir(parents=True, exist_ok=True)
    source_text = SOURCE.read_text()
    forbidden = ("OrderSend(", "OrderSendAsync(", "CTrade", "#include <Trade", ".Buy(", ".Sell(", "PositionClose(")
    if any(token in source_text for token in forbidden):
        raise RuntimeError("Export source contains trading capability")
    for process in Path("/proc").glob("[0-9]*/cmdline"):
        try:
            command = process.read_bytes().split(b"\0")[0].decode(errors="replace").replace("\\", "/").lower()
        except OSError:
            continue
        if command == "c:/v202-validation-terminal/terminal64.exe":
            raise RuntimeError("Isolated research terminal already running")
    for chart in (TERMINAL / "MQL5/Profiles/Charts").glob("**/*.chr"):
        data = chart.read_bytes()
        content = data.decode("utf-16", errors="ignore") if data.startswith(b"\xff\xfe") else data.decode(errors="ignore")
        if "<expert>" in content and not any(name in content for name in ("SolTradeFPAllSymbolAudit", "SolTradeFPShadowFeed", "SolTradeGoldWeekendReadOnly")):
            raise RuntimeError(f"Unexpected expert in isolated chart {chart}")
    shutil.copy2(SOURCE, TERMINAL / "MQL5/Experts" / SOURCE.name)
    env = dict(os.environ, WINEPREFIX=str(PREFIX), WINEDEBUG="-all")
    compile_name = "gold-weekend-compile.log"
    subprocess.run(
        ["wine", str(TERMINAL / "MetaEditor64.exe"),
         "/compile:C:\\v202-validation-terminal\\MQL5\\Experts\\" + SOURCE.name,
         "/log:C:\\v202-validation-terminal\\" + compile_name],
        env=env, capture_output=True, timeout=90, check=False,
    )
    compile_log = TERMINAL / compile_name
    if "0 errors, 0 warnings" not in compile_log.read_text(encoding="utf-16"):
        raise RuntimeError("Read-only exporter did not compile cleanly")
    shutil.copy2(compile_log, output / compile_name)
    shutil.copy2(SOURCE, output / SOURCE.name)
    preset_name = "SolTradeGoldWeekendReadOnly.set"
    (TERMINAL / "MQL5/Presets" / preset_name).write_text(
        "ReadOnlyResearchConfirmed=true\nCloseWhenDone=true\nOutputSuffix=20261003\n"
    )
    config_name = "gold-weekend-readonly.ini"
    (TERMINAL / config_name).write_text(
        "[Common]\nLogin=7404213\nServer=FPMarketsSC-Demo\nKeepPrivate=1\nNewsEnable=0\n"
        "[Experts]\nEnabled=1\nAllowLiveTrading=0\nAllowDllImport=0\nAccount=0\nProfile=0\n"
        "[StartUp]\nSymbol=XAUUSD.r\nPeriod=M1\nExpert=SolTradeGoldWeekendReadOnly\n"
        f"ExpertParameters={preset_name}\n"
    )
    status = COMMON_OUTPUT / "status-20261003.csv"
    before = status.stat().st_mtime_ns if status.exists() else None
    started = time.time()
    with (output / "terminal.log").open("wb") as log:
        process = subprocess.Popen(
            ["wine", str(TERMINAL / "terminal64.exe"), "/portable",
             "/config:C:\\v202-validation-terminal\\" + config_name],
            env=env, stdout=log, stderr=log,
        )
        try:
            exit_code = process.wait(timeout=timeout)
        except subprocess.TimeoutExpired:
            process.terminate()
            raise RuntimeError("Read-only exporter timed out")
    if not status.exists() or status.stat().st_mtime_ns == before:
        raise RuntimeError("Fresh completion status missing")
    bars = COMMON_OUTPUT / "m1-20261003.csv"
    shutil.copy2(status, output / status.name)
    if bars.exists():
        shutil.copy2(bars, output / bars.name)
    result = {
        "read_only": True,
        "source_sha256": hashlib.sha256(SOURCE.read_bytes()).hexdigest(),
        "isolated_terminal": str(TERMINAL),
        "elapsed_seconds": round(time.time() - started, 3),
        "process_exit_code": exit_code,
        "status": status.read_text().splitlines(),
    }
    (output / "receipt.json").write_text(json.dumps(result, indent=2) + "\n")
    return result


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("output", type=Path)
    parser.add_argument("--timeout", type=int, default=600)
    args = parser.parse_args()
    print(json.dumps(run(args.output, args.timeout), indent=2))
