#!/usr/bin/env python3
"""Run isolated V3.1 tester-only segment harnesses before the OOS seal."""
import os, subprocess, time
from pathlib import Path

ROOT=Path(__file__).resolve().parents[1]
PREFIX=Path('/home/tibule12/.wine-fpmarkets')
TERMINAL=PREFIX/'drive_c/Program Files/FP Markets MT5 Terminal'
WORK=PREFIX/'drive_c/v22'
COMMON=PREFIX/'drive_c/users/tibule12/AppData/Roaming/MetaQuotes/Terminal/Common/Files'
RUNS=[
 ('2025_S1','2025.01.02 00:00:00','2025.01.16 00:00:00','2025.02.05 00:00:00','2025.01.02','2025.02.06'),
 ('2025_S2','2025.02.17 09:00:00','2025.02.17 09:00:00','2025.03.07 23:00:00','2025.02.17','2025.03.09'),
 ('2025_S3','2025.03.20 08:00:00','2025.03.20 08:00:00','2025.08.06 16:00:00','2025.03.20','2025.08.08'),
 ('2025_S4','2025.08.19 02:00:00','2025.08.19 02:00:00','2025.12.24 00:00:00','2025.08.19','2025.12.25'),
 ('2026_P1','2026.01.02 00:00:00','2026.01.16 00:00:00','2026.04.09 00:00:00','2026.01.02','2026.04.10'),
 ('2026_P2','2026.04.09 00:00:00','2026.04.09 00:00:00','2026.07.01 00:00:00','2026.04.09','2026.07.02'),
 ('2026_P3','2026.07.01 00:00:00','2026.07.01 00:00:00','2026.08.01 00:00:00','2026.07.01','2026.08.01'),
]
def ini(run,port):
 name,reset,eligible,end,frm,to=run; output=f'SolTradeV31-{name}.csv'
 return f'''[Common]\nKeepPrivate=1\nNewsEnable=0\n\n[Experts]\nEnabled=1\nAllowLiveTrading=0\nAllowDllImport=0\nAccount=0\nProfile=0\n\n[Tester]\nExpert=SolTradeV31TesterHarness\nSymbol=EURUSD\nPeriod=H1\nDeposit=10000\nCurrency=USD\nLeverage=1:30\nModel=4\nOptimization=0\nForwardMode=0\nFromDate={frm}\nToDate={to}\nVisual=0\nUseCloud=0\nPort={port}\nShutdownTerminal=1\n\n[TesterInputs]\nResetAt={reset}\nEligibleFrom={eligible}\nEligibleTo={end}\nResearchCutoff=2026.08.01 00:00:00\nSegmentId={name}\nOutputFile={output}\n''',output
def run_fixture(env):
 text='''[Common]\nKeepPrivate=1\nNewsEnable=0\n\n[Experts]\nEnabled=1\nAllowLiveTrading=0\nAllowDllImport=0\nAccount=0\nProfile=0\n\n[Tester]\nExpert=SolTradeV31RestartFixtures\nSymbol=EURUSD\nPeriod=H1\nDeposit=10000\nCurrency=USD\nLeverage=1:30\nModel=4\nOptimization=0\nForwardMode=0\nFromDate=2026.01.02\nToDate=2026.01.03\nVisual=0\nUseCloud=0\nPort=3210\nShutdownTerminal=1\n'''
 cfg=WORK/'fixture.ini';cfg.write_text(text)
 p=subprocess.run(['wine',str(TERMINAL/'terminal64.exe'),'/config:C:\\v22\\fixture.ini','/portable'],cwd=ROOT,env=env,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,timeout=600)
 if p.returncode:raise SystemExit(f'FAIL fixture rc={p.returncode}')
 print('V22_RESTART_FIXTURES TESTER_RUN_COMPLETE')
def main():
 env=dict(os.environ,WINEPREFIX=str(PREFIX));WORK.mkdir(exist_ok=True)
 for i,run in enumerate(RUNS):
  text,out=ini(run,3201+i);cfg=WORK/f'run-{i+1}.ini';cfg.write_text(text)
  target=COMMON/out
  if target.exists(): target.unlink()
  start=time.time();p=subprocess.run(['wine',str(TERMINAL/'terminal64.exe'),f'/config:C:\\v22\\run-{i+1}.ini','/portable'],cwd=ROOT,env=env,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,timeout=600)
  if p.returncode or not target.exists():raise SystemExit(f'FAIL {run[0]} rc={p.returncode}')
  print(f'V22_TESTER {run[0]} PASS {time.time()-start:.2f}s {target.stat().st_size}')
 run_fixture(env)
if __name__=='__main__':main()
