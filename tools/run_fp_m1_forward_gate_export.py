#!/usr/bin/env python3
"""Run the order-incapable FP M1 forward-gate exporter in the isolated terminal."""

from __future__ import annotations

import hashlib
import json
import os
import shutil
import subprocess
import time
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
PREFIX = Path("/home/tibule12/.wine-fpmarkets")
TERMINAL = PREFIX / "drive_c/v202-validation-terminal"
COMMON = PREFIX / "drive_c/users/tibule12/AppData/Roaming/MetaQuotes/Terminal/Common/Files"
OUTPUT = ROOT / "reports/fast-multi-market-v2/fp-m1-forward-gate-20260915"
TAG = "fp-forward-gate-20260908-20260915"


def main() -> None:
    OUTPUT.mkdir(parents=True, exist_ok=True)
    for path in Path("/proc").glob("[0-9]*/cmdline"):
        try:
            executable = path.read_bytes().split(b"\0")[0].decode(errors="replace").replace("\\", "/").lower()
        except OSError:
            continue
        if executable == "c:/v202-validation-terminal/terminal64.exe":
            raise RuntimeError("isolated research terminal is already running")

    source = ROOT / "tools/mql/SolTradeM1ForwardGateProbe.mq5"
    source_text = source.read_text()
    forbidden = ("OrderSend(", "OrderSendAsync(", "CTrade", "#include <Trade", "PositionClose(", "PositionModify(")
    found = [token for token in forbidden if token in source_text]
    if found:
        raise RuntimeError(f"read-only probe contains forbidden trading API: {found}")

    target = TERMINAL / "MQL5/Experts" / source.name
    shutil.copy2(source, target)
    env = dict(os.environ, WINEPREFIX=str(PREFIX), WINEDEBUG="-all")
    subprocess.run(
        [
            "wine",
            str(TERMINAL / "MetaEditor64.exe"),
            "/compile:C:\\v202-validation-terminal\\MQL5\\Experts\\" + source.name,
            "/log:C:\\v202-validation-terminal\\m1-forward-gate-compile.log",
        ],
        env=env,
        capture_output=True,
        timeout=90,
        check=False,
    )
    compile_log = TERMINAL / "m1-forward-gate-compile.log"
    compile_text = compile_log.read_text(encoding="utf-16")
    if "0 errors, 0 warnings" not in compile_text:
        raise RuntimeError("M1 forward-gate probe compilation failed")
    shutil.copy2(compile_log, OUTPUT / "compile.log")

    preset_name = "SolTradeM1ForwardGateProbe.set"
    (TERMINAL / "MQL5/Presets" / preset_name).write_text(
        f"OutputTag={TAG}\nConnectedHistoricalReadOnly=true\nCloseIsolatedTerminalWhenDone=true\n"
    )
    config = (
        "[Common]\nLogin=7404213\nServer=FPMarketsSC-Demo\nKeepPrivate=1\nNewsEnable=0\n"
        "[Experts]\nEnabled=1\nAllowLiveTrading=0\nAllowDllImport=0\nAccount=0\nProfile=0\n"
        "[StartUp]\nSymbol=EURUSD.r\nPeriod=M1\nExpert=SolTradeM1ForwardGateProbe\n"
        f"ExpertParameters={preset_name}\n"
    )
    config_path = TERMINAL / "m1-forward-gate.ini"
    config_path.write_text(config)
    common_dir = COMMON / "SolTradeM1ForwardGate"
    bars = common_dir / f"{TAG}-bars.csv"
    summary = common_dir / f"{TAG}-summary.csv"
    before = summary.stat().st_mtime_ns if summary.exists() else None

    started = time.time()
    with (OUTPUT / "terminal.log").open("wb") as log:
        process = subprocess.Popen(
            ["wine", str(TERMINAL / "terminal64.exe"), "/portable", "/config:C:\\v202-validation-terminal\\m1-forward-gate.ini"],
            env=env,
            stdout=log,
            stderr=log,
        )
        try:
            exit_code = process.wait(timeout=300)
        except subprocess.TimeoutExpired:
            process.terminate()
            raise RuntimeError("read-only M1 export timed out")
    if not summary.exists() or summary.stat().st_mtime_ns == before:
        raise RuntimeError("fresh M1 export completion record missing")
    shutil.copy2(bars, OUTPUT / "m1-bars.csv")
    shutil.copy2(summary, OUTPUT / "m1-summary.csv")
    receipt = {
        "schema": "SOLTRADE_FP_M1_FORWARD_GATE_EXPORT_V1",
        "elapsed_seconds": round(time.time() - started, 3),
        "terminal_exit_code": exit_code,
        "account": 7404213,
        "server": "FPMarketsSC-Demo",
        "read_only": True,
        "live_trading_allowed": False,
        "tester_used": False,
        "order_api_present": False,
        "source_sha256": hashlib.sha256(source.read_bytes()).hexdigest(),
        "bars_sha256": hashlib.sha256(bars.read_bytes()).hexdigest(),
    }
    (OUTPUT / "export-receipt.json").write_text(json.dumps(receipt, indent=2) + "\n")
    print(json.dumps(receipt, indent=2))


if __name__ == "__main__":
    main()
