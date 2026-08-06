#!/usr/bin/env python3
import csv,hashlib,json,os,shutil,subprocess
from collections import Counter
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1];OUT=ROOT/"reports/backtests/phase6-v28-dollar-factor-momentum";DEST=OUT/"signal-feasibility";PREFIX=Path("/home/tibule12/.wine-fpmarkets");TERM=PREFIX/"drive_c/Program Files/FP Markets MT5 Terminal";COMMON=PREFIX/"drive_c/users/tibule12/AppData/Roaming/MetaQuotes/Terminal/Common/Files";WORK=PREFIX/"drive_c/v28";RUNTIME=COMMON/"SolTrade/Phase6/V28Signals";SRC=ROOT/"research/factor_momentum/SolTradeDollarFactorSignalHarness.mq5"
def pairs(p):
 with p.open() as h:return {r[0]:r[1] for r in csv.reader(h) if len(r)>1}
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def main():
 if DEST.exists() or RUNTIME.exists():raise SystemExit("REFUSE_EXISTING")
 WORK.mkdir(parents=True,exist_ok=True);DEST.mkdir(parents=True);shutil.copy2(SRC,WORK/SRC.name);env=dict(os.environ,WINEPREFIX=str(PREFIX));subprocess.run(["wine",str(TERM/"MetaEditor64.exe"),"/portable",f"/compile:C:\\v28\\{SRC.name}","/log:C:\\v28\\compile.log"],cwd=ROOT,env=env,timeout=120,check=False,stdout=subprocess.PIPE,stderr=subprocess.STDOUT);ex=WORK/SRC.with_suffix(".ex5").name
 if not ex.exists():raise SystemExit("COMPILE_FAIL")
 shutil.copy2(ex,TERM/"MQL5/Experts/SolTradeDollarFactorSignalHarness.ex5");cfg=WORK/"signals.ini";cfg.write_text("[Common]\nKeepPrivate=1\nNewsEnable=0\n\n[Experts]\nEnabled=1\nAllowLiveTrading=0\nAllowDllImport=0\n\n[Tester]\nExpert=SolTradeDollarFactorSignalHarness\nSymbol=EURUSD\nPeriod=H1\nDeposit=10000\nCurrency=USD\nLeverage=1:30\nModel=1\nExecutionMode=0\nOptimization=0\nForwardMode=0\nFromDate=2024.12.01\nToDate=2026.08.01\nVisual=0\nUseCloud=0\nPort=3991\nReport=v28\\signals.html\nReplaceReport=1\nShutdownTerminal=1\n\n[TesterInputs]\nResearchCutoff=2026.08.01 00:00:00\nOutputRoot=SolTrade\\Phase6\\V28Signals\n");(DEST/"strategy-tester.ini").write_text(cfg.read_text());p=subprocess.run(["wine",str(TERM/"terminal64.exe"),"/config:C:\\v28\\signals.ini","/portable"],cwd=ROOT,env=env,timeout=900,stdout=subprocess.PIPE,stderr=subprocess.STDOUT)
 if RUNTIME.exists():
  for x in RUNTIME.iterdir():
   if x.is_file():shutil.copy2(x,DEST/x.name)
 s=pairs(DEST/"signal-summary.csv") if (DEST/"signal-summary.csv").exists() else {};rows=list(csv.DictReader((DEST/"signal-schedule.csv").open())) if (DEST/"signal-schedule.csv").exists() else [];c=Counter(r["dataset"] for r in rows);d=Counter(r["chart_direction"] for r in rows);sy=Counter(r["symbol"] for r in rows);valid=p.returncode==0 and s.get("status")=="PASS" and s.get("pnl_calculated")=="NO"
 inv={"schema":"SOLTRADE_PHASE6_V28_SIGNAL_FEASIBILITY_V1","status":"PASS" if valid else "FAIL","source_sha256":sha(SRC),"ex5_sha256":sha(ex),"cohorts":int(s.get("cohorts","0")),"legs":len(rows),"by_dataset":dict(c),"by_direction":dict(d),"by_symbol":dict(sy),"orders_or_positions":0,"pnl_calculated":False,"seal_breach":s.get("seal_breach")};(DEST/"inventory.json").write_text(json.dumps(inv,indent=2)+"\n");print(json.dumps(inv,indent=2));
 if not valid:raise SystemExit("SIGNAL_FAIL")
if __name__=="__main__":main()
