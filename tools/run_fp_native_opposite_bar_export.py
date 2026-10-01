#!/usr/bin/env python3
"""Export historical completed FP bars from an isolated local, trading-disabled terminal."""

import argparse
import hashlib
import json
import os
import shutil
import subprocess
import time
from pathlib import Path

from audit_fp_all_symbols import PATHS, ROOT
from run_fp_readonly_audit_export import PREFIX, TERMINAL

SOURCE = ROOT / 'tools/mql/SolTradeFPReadOnlyNativeStopBars.mq5'
EXPERT = 'SolTradeFPReadOnlyNativeStopBars'


def run(output: Path, request: Path, suffix: str = '-fp-20261001', timeout: int = 600) -> dict:
    output.mkdir(parents=True, exist_ok=True)
    source_text = SOURCE.read_text()
    for forbidden in ('OrderSend(', 'OrderSendAsync(', 'CTrade', '#include <Trade', '.Buy(', '.Sell(', 'PositionClose('):
        if forbidden in source_text:
            raise ValueError(f'Order-capable token {forbidden} found in probe')
    for process in Path('/proc').glob('[0-9]*/cmdline'):
        try:
            executable = process.read_bytes().split(b'\0')[0].decode(errors='replace').replace('\\', '/').lower()
        except OSError:
            continue
        if executable == 'c:/v202-validation-terminal/terminal64.exe':
            raise RuntimeError('Isolated terminal already running')
    shutil.copy2(SOURCE, TERMINAL / 'MQL5/Experts' / SOURCE.name)
    shutil.copy2(request, PATHS / request.name)
    env = dict(os.environ, WINEPREFIX=str(PREFIX), WINEDEBUG='-all')
    compile_path = TERMINAL / 'native-stop-bars-compile.log'
    subprocess.run([
        'wine', str(TERMINAL / 'MetaEditor64.exe'),
        '/compile:C:\\v202-validation-terminal\\MQL5\\Experts\\' + SOURCE.name,
        '/log:C:\\v202-validation-terminal\\native-stop-bars-compile.log',
    ], env=env, capture_output=True, timeout=90, check=False)
    if '0 errors, 0 warnings' not in compile_path.read_text(encoding='utf-16'):
        raise RuntimeError('Read-only bar probe did not compile cleanly')
    shutil.copy2(compile_path, output / 'compile.log')
    shutil.copy2(SOURCE, output / SOURCE.name)
    preset_name = EXPERT + '.set'
    (TERMINAL / 'MQL5/Presets' / preset_name).write_text(
        'ReadOnlyAuditConfirmed=true\nCloseIsolatedTerminalWhenDone=true\n'
        f'RequestFilename={request.name}\nExportSuffix={suffix}\n'
    )
    config_name = 'native-stop-bars.ini'
    (TERMINAL / config_name).write_text(
        '[Common]\nLogin=7404213\nServer=FPMarketsSC-Demo\nKeepPrivate=1\nNewsEnable=0\n'
        '[Experts]\nEnabled=1\nAllowLiveTrading=0\nAllowDllImport=0\nAccount=0\nProfile=0\n'
        f'[StartUp]\nSymbol=EURUSD.r\nPeriod=M1\nExpert={EXPERT}\nExpertParameters={preset_name}\n'
    )
    status_name = f'native-stop-status{suffix}.csv'
    status = PATHS / status_name
    previous = status.stat().st_mtime_ns if status.exists() else None
    started = time.time()
    with (output / 'terminal.log').open('wb') as log:
        process = subprocess.Popen([
            'wine', str(TERMINAL / 'terminal64.exe'), '/portable',
            '/config:C:\\v202-validation-terminal\\' + config_name,
        ], env=env, stdout=log, stderr=log)
        try:
            exit_code = process.wait(timeout=timeout)
        except subprocess.TimeoutExpired:
            process.terminate()
            raise RuntimeError('Read-only bar probe timed out')
    if not status.exists() or status.stat().st_mtime_ns == previous:
        raise RuntimeError('Fresh native-stop export completion receipt missing')
    for filename in (
        status_name,
        f'native-stop-bars{suffix}.csv',
        f'native-stop-coverage{suffix}.csv',
        f'native-stop-specifications{suffix}.csv',
    ):
        shutil.copy2(PATHS / filename, output / filename)
    receipt = {
        'read_only': True,
        'order_capability': False,
        'live_trading_allowed': False,
        'isolated_terminal': str(TERMINAL),
        'source_sha256': hashlib.sha256(SOURCE.read_bytes()).hexdigest(),
        'request_sha256': hashlib.sha256(request.read_bytes()).hexdigest(),
        'elapsed_seconds': round(time.time() - started, 3),
        'process_exit_code': exit_code,
        'status_rows': status.read_text().splitlines(),
    }
    (output / 'export-receipt.json').write_text(json.dumps(receipt, indent=2) + '\n')
    return receipt


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('output', type=Path)
    parser.add_argument('request', type=Path)
    parser.add_argument('--suffix', default='-fp-20261001')
    parser.add_argument('--timeout', type=int, default=600)
    args = parser.parse_args()
    print(json.dumps(run(args.output, args.request, args.suffix, args.timeout), indent=2))
