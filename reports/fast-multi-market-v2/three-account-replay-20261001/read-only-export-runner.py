#!/usr/bin/env python3
"""Run only the non-trading audit probe in the existing isolated local terminal."""
import argparse
import hashlib
import json
import os
import shutil
import subprocess
import time
from pathlib import Path

from audit_fp_all_symbols import ROOT, PATHS

PREFIX = Path('/home/tibule12/.wine-fpmarkets')
TERMINAL = PREFIX/'drive_c/v202-validation-terminal'


def run(out, request=None, suffix='', timeout=600):
    out.mkdir(parents=True, exist_ok=True)
    for p in Path('/proc').glob('[0-9]*/cmdline'):
        try: executable = p.read_bytes().split(b'\0')[0].decode(errors='replace').replace('\\', '/').lower()
        except OSError: continue
        if executable == 'c:/v202-validation-terminal/terminal64.exe':
            raise ValueError('Isolated research terminal is already running')
    source = ROOT/'tools/mql/SolTradeFPAllSymbolAudit.mq5'
    text = source.read_text()
    for forbidden in ('OrderSend(', 'OrderSendAsync(', 'CTrade', '#include <Trade', '.Buy(', '.Sell(', 'PositionClose('):
        if forbidden in text: raise ValueError('Unexpected trading capability')
    for chart in (TERMINAL/'MQL5/Profiles/Charts').glob('**/*.chr'):
        # Refuse to reuse a profile carrying anything except this read-only probe.
        content = chart.read_bytes().decode('utf-16', errors='ignore') if chart.read_bytes().startswith(b'\xff\xfe') else chart.read_text(errors='ignore')
        if '<expert>' in content and not any(name in content for name in ('SolTradeFPAllSymbolAudit', 'SolTradeFPShadowFeed')):
            raise ValueError('Unexpected expert in isolated chart '+str(chart))
    shutil.copy2(source, TERMINAL/'MQL5/Experts'/source.name)
    env = dict(os.environ, WINEPREFIX=str(PREFIX), WINEDEBUG='-all')
    subprocess.run(['wine', str(TERMINAL/'MetaEditor64.exe'),
        '/compile:C:\\v202-validation-terminal\\MQL5\\Experts\\'+source.name,
        '/log:C:\\v202-validation-terminal\\all-symbol-audit-compile.log'], env=env, capture_output=True, timeout=90)
    log = TERMINAL/'all-symbol-audit-compile.log'
    if '0 errors, 0 warnings' not in log.read_text(encoding='utf-16'):
        raise ValueError('Read-only exporter compilation failed')
    shutil.copy2(log, out/'compile.log');shutil.copy2(source, out/source.name)
    if request: shutil.copy2(request, PATHS/request.name)
    preset = 'ReadOnlyAuditConfirmed=true\nExportPaths='+('true' if request else 'false')+'\nCloseIsolatedTerminalWhenDone=true\n'
    if request: preset += 'RequestFilename='+request.name+'\nExportSuffix='+suffix+'\n'
    (TERMINAL/'MQL5/Presets/SolTradeFPAllSymbolAudit.set').write_text(preset)
    status_path = PATHS/('paths-status'+suffix+'.csv' if request else 'history-status.csv')
    before = status_path.stat().st_mtime_ns if status_path.exists() else None
    config = '[Common]\nLogin=7404213\nServer=FPMarketsSC-Demo\nKeepPrivate=1\nNewsEnable=0\n[Experts]\nEnabled=1\nAllowLiveTrading=0\nAllowDllImport=0\nAccount=0\nProfile=0\n[StartUp]\nSymbol=EURUSD.r\nPeriod=M1\nExpert=SolTradeFPAllSymbolAudit\nExpertParameters=SolTradeFPAllSymbolAudit.set\n'
    (TERMINAL/'all-symbol-audit.ini').write_text(config)
    started = time.time()
    with (out/'terminal.log').open('wb') as f:
        proc = subprocess.Popen(['wine', str(TERMINAL/'terminal64.exe'), '/portable',
            '/config:C:\\v202-validation-terminal\\all-symbol-audit.ini'], env=env, stdout=f, stderr=f)
        try: code = proc.wait(timeout=timeout)
        except subprocess.TimeoutExpired:
            proc.terminate();raise RuntimeError('Read-only export timed out; inspect isolated terminal')
    if not status_path.exists() or status_path.stat().st_mtime_ns == before:
        raise ValueError('Fresh export completion record missing')
    shutil.copy2(status_path, out/status_path.name)
    names = ['path-coverage'+suffix+'.csv', 'path-chunks'+suffix+'.csv', 'symbol-specifications'+suffix+'.csv'] if request else ['deals.csv', 'orders.csv']
    for name in names: shutil.copy2(PATHS/name, out/name)
    result = dict(exit_code=code, elapsed_seconds=time.time()-started, source_sha256=hashlib.sha256(source.read_bytes()).hexdigest(),
                  read_only=True, live_trading_allowed=False, completed_status=status_path.read_text())
    (out/'export-receipt.json').write_text(json.dumps(result, indent=2)+'\n')
    print(result['completed_status'], flush=True)


if __name__ == '__main__':
    p = argparse.ArgumentParser(description=__doc__);p.add_argument('output', type=Path);p.add_argument('--request', type=Path);p.add_argument('--suffix', default='');p.add_argument('--timeout', type=int, default=600)
    a = p.parse_args();run(a.output, a.request, a.suffix, a.timeout)
