#!/usr/bin/env python3
"""Run the bounded V28 FXIFY continuous-account evidence addendum."""
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
AUDIT = ROOT / "reports/backtests/fxify-2phase-pro-10k-v28-rule-simulation"
ADDENDUM = AUDIT / "continuous-account-evidence-addendum"
FROZEN = ROOT / "reports/backtests/phase6-v28-dollar-factor-momentum"
FROZEN_SIGNAL_SOURCE = ROOT / "research/factor_momentum/SolTradeDollarFactorSignalHarness.mq5"
FROZEN_PERFORMANCE_SOURCE = ROOT / "research/factor_momentum/SolTradeDollarFactorPerformanceHarness.mq5"
PREFIX = Path("/home/tibule12/.wine-fpmarkets")
TERMINAL = PREFIX / "drive_c/Program Files/FP Markets MT5 Terminal"
COMMON = PREFIX / "drive_c/users/tibule12/AppData/Roaming/MetaQuotes/Terminal/Common/Files"
WORK = PREFIX / "drive_c/fxify-v28-continuous"
REPORTS = TERMINAL / "fxify-v28-continuous/reports"
RUNTIME_SIGNAL = COMMON / "SolTrade/FXIFY/V28ContinuousSignals"
RUNTIME_RUNS = COMMON / "SolTrade/FXIFY/V28ContinuousRuns"
EXPECTED_PRODUCTION_SHA = "261a9cfe1c1e8d84e2a2a468ac4d0775086b21c89824b117e5127697fd03ced3"
EXPECTED_FROZEN_SIGNAL_SHA = "7f080c26d26b634b2f8a1e840b3a9fa60926fb95e415956ba0a8475f838537bd"
EXPECTED_FROZEN_PERFORMANCE_SHA = "726273d332176ae3cb61c927c7959de12d947eed13c30cb2c080d95bc1f7f846"


def sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def pairs(path: Path) -> dict[str, str]:
    with path.open(newline="") as handle:
        return {row[0]: row[1] for row in csv.reader(handle) if len(row) >= 2}


def required_replace(text: str, old: str, new: str) -> str:
    if text.count(old) != 1:
        raise RuntimeError(f"replacement count is {text.count(old)}, expected 1: {old[:80]!r}")
    return text.replace(old, new)


def generated_signal_source() -> str:
    text = FROZEN_SIGNAL_SOURCE.read_text()
    text = required_replace(text, '#property version "1.000"', '#property version "1.001"')
    text = required_replace(
        text,
        '#property description "V28 frozen one-month dollar-factor momentum signal evaluator"',
        '#property description "V28 tester-only continuous FXIFY addendum signal evaluator"',
    )
    old = '''string Dataset(datetime target,datetime exit_time)
  {if(target>=D'2025.01.06 10:05:00'&&exit_time<D'2026.01.01 00:00:00')return "V28_2025_DEVELOPMENT";if(target>=D'2026.01.05 10:05:00'&&exit_time<D'2026.08.01 00:00:00')return "V28_2026_PRESEAL_DEVELOPMENT";return "NONE";}'''
    new = '''string Dataset(datetime target,datetime exit_time)
  {if(target>=D'2025.01.06 10:05:00'&&target<ResearchCutoff)return "V28_FXIFY_CONTINUOUS";return "NONE";}'''
    text = required_replace(text, old, new)
    text = required_replace(
        text,
        'bool pass=g_ok&&!g_seal&&g_cohorts==17&&g_legs==119;',
        'bool pass=g_ok&&!g_seal&&g_cohorts==19&&g_legs==133;',
    )
    return text


def generated_performance_source() -> str:
    text = FROZEN_PERFORMANCE_SOURCE.read_text()
    replacements = (
        ('#property version "1.001"', '#property version "1.002"'),
        (
            '#property description "V28 tester-only multi-currency dollar-factor-momentum performance harness"',
            '#property description "V28 tester-only continuous FXIFY evidence harness"',
        ),
        ("input datetime EligibleFrom=D'2025.01.06 00:00:00';", "input datetime EligibleFrom=D'2025.01.01 00:00:00';"),
        ("input datetime EligibleTo=D'2026.01.01 00:00:00';", "input datetime EligibleTo=D'2026.08.01 00:00:00';"),
        ('input string DatasetId="V28_2025_DEVELOPMENT";', 'input string DatasetId="V28_FXIFY_CONTINUOUS";'),
        ('input int ExpectedScheduleSignals=77;', 'input int ExpectedScheduleSignals=133;'),
        (
            'input string ScheduleFile="SolTrade\\\\Phase6\\\\V28Signals\\\\signal-schedule.csv";',
            'input string ScheduleFile="SolTrade\\\\FXIFY\\\\V28ContinuousSignals\\\\signal-schedule.csv";',
        ),
        ('input string ExecutionInstanceId="V28-2025-NATIVE";', 'input string ExecutionInstanceId="FXIFY-V28-CONTINUOUS";'),
        (
            'input string OutputRoot="SolTrade\\\\Phase6\\\\V28Performance\\\\V28-2025-NATIVE";',
            'input string OutputRoot="SolTrade\\\\FXIFY\\\\V28ContinuousRuns\\\\FXIFY-V28-CONTINUOUS";\ninput bool CaptureEvidence=false;',
        ),
    )
    for old, new in replacements:
        text = required_replace(text, old, new)

    text = required_replace(
        text,
        'datetime g_exit_target[7],g_max_tick=0,g_last_exit_submission_tick=0;\nbool g_preflight=false,g_seal_breach=false;\nint g_events=INVALID_HANDLE,g_transactions=INVALID_HANDLE,g_atr[7];',
        '''datetime g_exit_target[7],g_max_tick=0,g_last_exit_submission_tick=0;
bool g_preflight=false,g_seal_breach=false;
int g_events=INVALID_HANDLE,g_transactions=INVALID_HANDLE,g_atr[7];
int g_equity_hours=INVALID_HANDLE,g_balance_events=INVALID_HANDLE;
long g_hour_key=0,g_hour_open_msc=0,g_hour_close_msc=0,g_hour_min_msc=0,g_observation_calls=0,g_hour_rows=0;
double g_hour_open_balance=0,g_hour_open_equity=0,g_hour_close_balance=0,g_hour_close_equity=0,g_hour_min_equity=0,g_hour_min_profit=0;
int g_hour_open_positions=0,g_hour_close_positions=0,g_hour_max_positions=0;''',
    )

    anchor = 'string TS(datetime value){return value>0?TimeToString(value,TIME_DATE|TIME_SECONDS):"NONE";}\n'
    instrumentation = r'''string TS(datetime value){return value>0?TimeToString(value,TIME_DATE|TIME_SECONDS):"NONE";}
long CurrentTickMsc(){MqlTick tick;if(SymbolInfoTick(_Symbol,tick)&&tick.time_msc>0)return tick.time_msc;return (long)TimeCurrent()*1000;}
void FlushEquityHour()
  {
   if(!CaptureEvidence||g_equity_hours==INVALID_HANDLE||g_hour_key<=0)return;
   FileWrite(g_equity_hours,"SOLTRADE_FXIFY_V28_EQUITY_HOUR_V1",TS((datetime)g_hour_key),g_hour_open_msc,g_hour_close_msc,DoubleToString(g_hour_open_balance,8),DoubleToString(g_hour_open_equity,8),DoubleToString(g_hour_close_balance,8),DoubleToString(g_hour_close_equity,8),DoubleToString(g_hour_min_equity,8),g_hour_min_msc,DoubleToString(g_hour_min_profit,8),g_hour_open_positions,g_hour_close_positions,g_hour_max_positions);
   g_hour_rows++;
  }
void ObserveEquity(const string reason)
  {
   if(!CaptureEvidence)return;g_observation_calls++;datetime now=TimeCurrent();long key=(long)now-(long)now%3600;long msc=CurrentTickMsc();double balance=AccountInfoDouble(ACCOUNT_BALANCE),equity=AccountInfoDouble(ACCOUNT_EQUITY),profit=AccountInfoDouble(ACCOUNT_PROFIT);int positions=PortfolioPositions();
   if(g_hour_key!=key){FlushEquityHour();g_hour_key=key;g_hour_open_msc=msc;g_hour_open_balance=balance;g_hour_open_equity=equity;g_hour_min_equity=equity;g_hour_min_msc=msc;g_hour_min_profit=profit;g_hour_open_positions=positions;g_hour_max_positions=positions;}
   g_hour_close_msc=msc;g_hour_close_balance=balance;g_hour_close_equity=equity;g_hour_close_positions=positions;g_hour_max_positions=MathMax(g_hour_max_positions,positions);
   if(equity<g_hour_min_equity){g_hour_min_equity=equity;g_hour_min_msc=msc;g_hour_min_profit=profit;}
   if(reason=="TRADE_TRANSACTION"&&g_balance_events!=INVALID_HANDLE)FileWrite(g_balance_events,"SOLTRADE_FXIFY_V28_BALANCE_EVENT_V1",TS(now),msc,reason,DoubleToString(balance,8),DoubleToString(equity,8),DoubleToString(profit,8),DoubleToString(AccountInfoDouble(ACCOUNT_MARGIN),8),DoubleToString(AccountInfoDouble(ACCOUNT_MARGIN_FREE),8),positions);
  }
'''
    text = required_replace(text, anchor, instrumentation)

    text = required_replace(
        text,
        'bool WriteSummary()\n  {\n   int open=PortfolioPositions();',
        '''bool CutoffOpenStateValid()
  {int found=0;for(int i=0;i<7;i++){bool present=false;for(int p=0;p<PositionsTotal();p++){ulong ticket=PositionGetTicket(p);if(ticket==0)continue;if(PositionGetInteger(POSITION_MAGIC)==V28_MAGIC_BASE+i+1){present=true;break;}}if(present){found++;if(g_exit_target[i]<EligibleTo)return false;}}return found==PortfolioPositions();}

bool WriteSummary()
  {
   int open=PortfolioPositions();''',
    )
    text = required_replace(
        text,
        'FileWrite(h,"seal_breach",g_seal_breach?"YES":"NO");bool valid=g_preflight&&!g_seal_breach&&g_signal_count==ExpectedScheduleSignals&&g_processed==g_signal_count&&open==0;',
        'FileWrite(h,"seal_breach",g_seal_breach?"YES":"NO");FileWrite(h,"capture_evidence",CaptureEvidence?"YES":"NO");FileWrite(h,"equity_observation_calls",g_observation_calls);FileWrite(h,"equity_hour_rows",g_hour_rows);FileWrite(h,"cutoff_open_state_valid",CutoffOpenStateValid()?"YES":"NO");bool valid=g_preflight&&!g_seal_breach&&g_signal_count==ExpectedScheduleSignals&&g_processed==g_signal_count&&CutoffOpenStateValid();',
    )
    text = required_replace(
        text,
        'g_events=FileOpen(OutputRoot+"\\\\events.csv",FILE_WRITE|FILE_CSV|FILE_ANSI|FILE_COMMON,\',\');g_transactions=FileOpen(OutputRoot+"\\\\transactions.csv",FILE_WRITE|FILE_CSV|FILE_ANSI|FILE_COMMON,\',\');if(g_events==INVALID_HANDLE||g_transactions==INVALID_HANDLE)return INIT_FAILED;',
        'g_events=FileOpen(OutputRoot+"\\\\events.csv",FILE_WRITE|FILE_CSV|FILE_ANSI|FILE_COMMON,\',\');g_transactions=FileOpen(OutputRoot+"\\\\transactions.csv",FILE_WRITE|FILE_CSV|FILE_ANSI|FILE_COMMON,\',\');if(g_events==INVALID_HANDLE||g_transactions==INVALID_HANDLE)return INIT_FAILED;if(CaptureEvidence){g_equity_hours=FileOpen(OutputRoot+"\\\\equity-hours.csv",FILE_WRITE|FILE_CSV|FILE_ANSI|FILE_COMMON,\',\');g_balance_events=FileOpen(OutputRoot+"\\\\balance-events.csv",FILE_WRITE|FILE_CSV|FILE_ANSI|FILE_COMMON,\',\');if(g_equity_hours==INVALID_HANDLE||g_balance_events==INVALID_HANDLE)return INIT_FAILED;FileWrite(g_equity_hours,"schema","server_hour","opening_time_msc","closing_time_msc","opening_balance","opening_equity","closing_balance","closing_equity","minimum_equity","minimum_time_msc","profit_at_minimum","opening_positions","closing_positions","maximum_positions");FileWrite(g_balance_events,"schema","server_time","time_msc","event","balance","equity","floating_profit","margin","free_margin","positions");}',
    )
    text = required_replace(
        text,
        'void OnTick(){datetime now=TimeCurrent();if(now>=ResearchCutoff){g_seal_breach=true;return;}if(now>=EligibleTo)return;g_max_tick=now;ProcessExits(now);ProcessEntries(now);}',
        'void OnTick(){datetime now=TimeCurrent();if(now>=ResearchCutoff){g_seal_breach=true;return;}if(now>=EligibleTo)return;g_max_tick=now;ObserveEquity("PRE_TICK");ProcessExits(now);ProcessEntries(now);ObserveEquity("POST_TICK");}',
    )
    text = required_replace(
        text,
        '      SolTradePositionReport exit;if(g_pm[i].HandleTradeTransaction(t,exit)){if(exit.fill_confirmed){g_exit_fills++;g_exit_target[i]=0;}Event(exit.event_type,exit.reason_code,SYMBOLS[i]+";"+exit.exit_reason_code);RecordExit("EXIT_TRANSACTION",i,exit);string reason="";g_risk_engine.RecordClosedOutcome("V28_EXIT_"+StringFormat("%I64u",exit.deal_ticket),exit.final_profit_loss,TimeCurrent(),AccountInfoDouble(ACCOUNT_EQUITY),reason);g_risk_engine.GetStatus(g_risk);}\n     }\n  }',
        '      SolTradePositionReport exit;if(g_pm[i].HandleTradeTransaction(t,exit)){if(exit.fill_confirmed){g_exit_fills++;g_exit_target[i]=0;}Event(exit.event_type,exit.reason_code,SYMBOLS[i]+";"+exit.exit_reason_code);RecordExit("EXIT_TRANSACTION",i,exit);string reason="";g_risk_engine.RecordClosedOutcome("V28_EXIT_"+StringFormat("%I64u",exit.deal_ticket),exit.final_profit_loss,TimeCurrent(),AccountInfoDouble(ACCOUNT_EQUITY),reason);g_risk_engine.GetStatus(g_risk);}\n     }\n   ObserveEquity("TRADE_TRANSACTION");\n  }',
    )
    text = required_replace(
        text,
        'double OnTester(){bool ok=WriteDeals()&&WriteSummary();',
        'double OnTester(){FlushEquityHour();g_hour_key=0;bool ok=WriteDeals()&&WriteSummary();',
    )
    text = required_replace(
        text,
        'if(g_transactions!=INVALID_HANDLE)FileClose(g_transactions);}',
        'if(g_transactions!=INVALID_HANDLE)FileClose(g_transactions);if(g_equity_hours!=INVALID_HANDLE)FileClose(g_equity_hours);if(g_balance_events!=INVALID_HANDLE)FileClose(g_balance_events);}',
    )
    return text


def compile_source(source: Path) -> tuple[Path, Path]:
    WORK.mkdir(parents=True, exist_ok=True)
    work_source = WORK / source.name
    shutil.copy2(source, work_source)
    compile_log = WORK / f"{source.stem}-compile.log"
    env = dict(os.environ, WINEPREFIX=str(PREFIX))
    proc = subprocess.run(
        [
            "wine",
            str(TERMINAL / "MetaEditor64.exe"),
            "/portable",
            f"/compile:C:\\fxify-v28-continuous\\{source.name}",
            f"/log:C:\\fxify-v28-continuous\\{compile_log.name}",
        ],
        cwd=ROOT,
        env=env,
        timeout=180,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
    )
    ex5 = work_source.with_suffix(".ex5")
    log_text = compile_log.read_text(encoding="utf-16", errors="replace") if compile_log.exists() else ""
    if not ex5.exists() or "Result: 0 errors, 0 warnings" not in log_text:
        raise RuntimeError(f"compile failed for {source.name}: return={proc.returncode}")
    return ex5, compile_log


def signal_ini(expert: str) -> str:
    return f"""[Common]
KeepPrivate=1
NewsEnable=0

[Experts]
Enabled=1
AllowLiveTrading=0
AllowDllImport=0

[Tester]
Expert={expert}
Symbol=EURUSD
Period=H1
Deposit=10000
Currency=USD
Leverage=1:30
Model=1
ExecutionMode=0
Optimization=0
ForwardMode=0
FromDate=2024.12.01
ToDate=2026.08.01
Visual=0
UseCloud=0
Port=3970
Report=fxify-v28-continuous\\reports\\continuous-signals.html
ReplaceReport=1
ShutdownTerminal=1

[TesterInputs]
ResearchCutoff=2026.08.01 00:00:00
OutputRoot=SolTrade\\FXIFY\\V28ContinuousSignals
"""


def performance_ini(expert: str, run_id: str, port: int, mode: int, capture: bool) -> str:
    layer = "FIXED_DELAY_200_MS" if mode == 200 else "NATIVE_NORMAL_EXECUTION"
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
Expert={expert}
Symbol=EURUSD
Period=H1
Deposit=10000
Currency=USD
Leverage=1:30
Model=4
ExecutionMode={mode}
Optimization=0
ForwardMode=0
FromDate=2024.12.01
ToDate=2026.08.01
Visual=0
UseCloud=0
Port={port}
Report=fxify-v28-continuous\\reports\\{run_id}.html
ReplaceReport=1
ShutdownTerminal=1

[TesterInputs]
EligibleFrom=2025.01.01 00:00:00
EligibleTo=2026.08.01 00:00:00
ResearchCutoff=2026.08.01 00:00:00
DatasetId=V28_FXIFY_CONTINUOUS
ExecutionLayer={layer}
ExpectedExecutionMode={mode}
ExpectedScheduleSignals=133
ScheduleFile=SolTrade\\FXIFY\\V28ContinuousSignals\\signal-schedule.csv
ExecutionInstanceId={run_id}
OutputRoot=SolTrade\\FXIFY\\V28ContinuousRuns\\{run_id}
CaptureEvidence={'true' if capture else 'false'}
"""


def run_terminal(config: Path, timeout: int = 2400) -> tuple[subprocess.CompletedProcess[bytes], float]:
    env = dict(os.environ, WINEPREFIX=str(PREFIX))
    started = time.time()
    proc = subprocess.run(
        ["wine", str(TERMINAL / "terminal64.exe"), f"/config:C:\\fxify-v28-continuous\\{config.name}", "/portable"],
        cwd=ROOT,
        env=env,
        timeout=timeout,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
    )
    return proc, time.time() - started


def copy_agent_log(port: int, destination: Path) -> None:
    agent = TERMINAL / "Tester" / f"Agent-127.0.0.1-{port}"
    logs = sorted(agent.glob("logs/*.log"), key=lambda path: path.stat().st_mtime)
    if logs:
        shutil.copy2(logs[-1], destination / "tester-agent.log")


def prepare_signal_schedule(signal_ex5: Path, compile_log: Path) -> None:
    destination = ADDENDUM / "signal-generation"
    destination.mkdir()
    expert = "SolTradeDollarFactorContinuousSignalHarness"
    shutil.copy2(signal_ex5, TERMINAL / f"MQL5/Experts/{expert}.ex5")
    config = WORK / "continuous-signals.ini"
    config.write_text(signal_ini(expert))
    shutil.copy2(config, destination / "strategy-tester.ini")
    shutil.copy2(compile_log, destination / "compile.log")
    proc, elapsed = run_terminal(config, timeout=1200)
    if RUNTIME_SIGNAL.exists():
        for artifact in RUNTIME_SIGNAL.iterdir():
            if artifact.is_file():
                shutil.copy2(artifact, destination / artifact.name)
    copy_agent_log(3970, destination)
    summary = pairs(destination / "signal-summary.csv") if (destination / "signal-summary.csv").exists() else {}
    if proc.returncode != 0 or summary.get("status") != "PASS":
        raise RuntimeError(f"continuous signal generation failed: return={proc.returncode}, summary={summary}")
    generated = list(csv.DictReader((destination / "signal-schedule.csv").open(newline="")))
    frozen = list(csv.DictReader((FROZEN / "signal-feasibility/signal-schedule.csv").open(newline="")))
    comparable_fields = ["target", "symbol", "orientation", "dollar_factor_return", "factor_side", "chart_direction", "recent_h1", "recent_close", "anchor_h1", "anchor_close", "scheduled_exit"]
    generated_by_key = {(row["target"], row["symbol"]): row for row in generated}
    mismatches = []
    for row in frozen:
        candidate = generated_by_key.get((row["target"], row["symbol"]))
        if candidate is None:
            mismatches.append({"target": row["target"], "symbol": row["symbol"], "field": "ROW", "frozen": "PRESENT", "continuous": "MISSING"})
            continue
        for field in comparable_fields:
            if row[field] != candidate[field]:
                mismatches.append({"target": row["target"], "symbol": row["symbol"], "field": field, "frozen": row[field], "continuous": candidate[field]})
    with (destination / "frozen-signal-overlap-equivalence.csv").open("w", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=["target", "symbol", "field", "frozen", "continuous"], lineterminator="\n")
        writer.writeheader()
        writer.writerows(mismatches)
    if len(generated) != 133 or len(frozen) != 119 or mismatches:
        raise RuntimeError(f"signal equivalence failed: generated={len(generated)}, frozen={len(frozen)}, mismatches={len(mismatches)}")
    RUNTIME_SIGNAL.mkdir(parents=True, exist_ok=True)
    shutil.copy2(destination / "signal-schedule.csv", RUNTIME_SIGNAL / "signal-schedule.csv")
    (destination / "generation-status.json").write_text(json.dumps({
        "schema": "SOLTRADE_FXIFY_V28_CONTINUOUS_SIGNAL_GENERATION_V1",
        "status": "PASS",
        "elapsed_seconds": elapsed,
        "generated_cohorts": 19,
        "generated_legs": len(generated),
        "frozen_overlap_legs": len(frozen),
        "overlap_mismatches": 0,
        "new_seam_cohort": "2025.12.01 10:05:00",
        "new_cutoff_open_cohort": "2026.07.06 10:05:00",
    }, indent=2) + "\n")


def execute_performance_run(performance_ex5: Path, expert: str, run_id: str, port: int, mode: int, capture: bool) -> None:
    destination = ADDENDUM / "physical-runs" / run_id
    runtime = RUNTIME_RUNS / run_id
    if destination.exists() or runtime.exists():
        raise RuntimeError(f"refuse existing run {run_id}")
    destination.mkdir(parents=True)
    config = WORK / f"{run_id}.ini"
    config.write_text(performance_ini(expert, run_id, port, mode, capture))
    shutil.copy2(config, destination / "strategy-tester.ini")
    proc, elapsed = run_terminal(config)
    if runtime.exists():
        for artifact in runtime.iterdir():
            if artifact.is_file():
                shutil.copy2(artifact, destination / artifact.name)
    report_prefix = run_id
    native_reports = []
    for artifact in REPORTS.glob(report_prefix + "*"):
        if artifact.is_file():
            name = "native-mt5-report" + artifact.name[len(report_prefix):]
            shutil.copy2(artifact, destination / name)
            native_reports.append(name)
    copy_agent_log(port, destination)
    summary = pairs(destination / "run-summary.csv") if (destination / "run-summary.csv").exists() else {}
    status = "PASS" if (
        proc.returncode == 0
        and summary.get("run_evidence_status") == "PASS"
        and summary.get("schedule_signals") == "133"
        and summary.get("processed_signals") == "133"
        and summary.get("cutoff_open_state_valid") == "YES"
        and native_reports
        and (destination / "tester-agent.log").exists()
        and (not capture or int(summary.get("equity_hour_rows", "0")) > 0)
    ) else "TECHNICAL_FAIL"
    (destination / "physical-run-status.json").write_text(json.dumps({
        "schema": "SOLTRADE_FXIFY_V28_CONTINUOUS_PHYSICAL_RUN_V1",
        "run_id": run_id,
        "status": status,
        "wine_return_code": proc.returncode,
        "elapsed_seconds": elapsed,
        "execution_mode": mode,
        "capture_evidence": capture,
        "summary": summary,
        "native_reports": native_reports,
    }, indent=2) + "\n")
    print(f"CONTINUOUS_RUN {run_id} {status} elapsed={elapsed:.2f}s fills={summary.get('entry_fills')} open={summary.get('open_positions_at_end')} hours={summary.get('equity_hour_rows')}", flush=True)
    if status != "PASS":
        raise RuntimeError(f"continuous run failed: {run_id}")


def main() -> None:
    if sha(ROOT / "MQL5/Experts/SolTradeBot.mq5") != EXPECTED_PRODUCTION_SHA:
        raise SystemExit("production hash mismatch")
    if sha(FROZEN_SIGNAL_SOURCE) != EXPECTED_FROZEN_SIGNAL_SHA:
        raise SystemExit(f"frozen signal source hash mismatch: {sha(FROZEN_SIGNAL_SOURCE)}")
    if sha(FROZEN_PERFORMANCE_SOURCE) != EXPECTED_FROZEN_PERFORMANCE_SHA:
        raise SystemExit("frozen performance source hash mismatch")
    if ADDENDUM.exists() or RUNTIME_SIGNAL.exists() or RUNTIME_RUNS.exists():
        raise SystemExit("refuse existing addendum or runtime evidence")

    ADDENDUM.mkdir(parents=True)
    (ADDENDUM / "physical-runs").mkdir()
    source_dir = ADDENDUM / "instrumentation-source"
    source_dir.mkdir()
    signal_source = source_dir / "SolTradeDollarFactorContinuousSignalHarness.mq5"
    performance_source = source_dir / "SolTradeDollarFactorContinuousEvidenceHarness.mq5"
    signal_source.write_text(generated_signal_source())
    performance_source.write_text(generated_performance_source())
    signal_ex5, signal_compile_log = compile_source(signal_source)
    performance_ex5, performance_compile_log = compile_source(performance_source)
    shutil.copy2(signal_compile_log, source_dir / "signal-compile.log")
    shutil.copy2(performance_compile_log, source_dir / "performance-compile.log")
    shutil.copy2(signal_ex5, source_dir / signal_ex5.name)
    shutil.copy2(performance_ex5, source_dir / performance_ex5.name)

    REPORTS.mkdir(parents=True, exist_ok=True)
    prepare_signal_schedule(signal_ex5, signal_compile_log)
    expert = "SolTradeDollarFactorContinuousEvidenceHarness"
    shutil.copy2(performance_ex5, TERMINAL / f"MQL5/Experts/{expert}.ex5")
    runs = (
        ("reference-normal", 3971, 0, False),
        ("normal", 3972, 0, True),
        ("high", 3973, 0, True),
        ("stress", 3974, 0, True),
        ("reference-200ms", 3975, 200, False),
        ("200ms", 3976, 200, True),
    )
    for run_id, port, mode, capture in runs:
        execute_performance_run(performance_ex5, expert, run_id, port, mode, capture)

    (ADDENDUM / "run-completion.json").write_text(json.dumps({
        "schema": "SOLTRADE_FXIFY_V28_CONTINUOUS_RUN_COMPLETION_V1",
        "status": "PASS",
        "runs": [run_id for run_id, _, _, _ in runs],
        "production_sha256": sha(ROOT / "MQL5/Experts/SolTradeBot.mq5"),
        "frozen_signal_source_sha256": sha(FROZEN_SIGNAL_SOURCE),
        "frozen_performance_source_sha256": sha(FROZEN_PERFORMANCE_SOURCE),
        "generated_signal_source_sha256": sha(signal_source),
        "generated_performance_source_sha256": sha(performance_source),
        "generated_signal_ex5_sha256": sha(signal_ex5),
        "generated_performance_ex5_sha256": sha(performance_ex5),
    }, indent=2) + "\n")


if __name__ == "__main__":
    main()
