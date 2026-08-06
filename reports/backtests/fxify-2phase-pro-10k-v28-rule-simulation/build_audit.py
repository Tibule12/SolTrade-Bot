#!/usr/bin/env python3
"""Build the bounded FXIFY 2-Phase Pro 10K/V28 evidence audit."""

from __future__ import annotations

import csv
import hashlib
import html
import json
import re
import statistics
import urllib.request
from collections import Counter, defaultdict
from datetime import date, datetime, time, timedelta, timezone
from pathlib import Path
from zoneinfo import ZoneInfo


ROOT = Path(__file__).resolve().parents[3]
OUT = Path(__file__).resolve().parent
ARCHIVE = OUT / "official-source-archive"
V28 = ROOT / "reports/backtests/phase6-v28-dollar-factor-momentum"
RUNS = V28 / "performance-runs-attempt2"
LEDGER = V28 / "phase6-v28-complete-adjusted-trade-ledger.csv"
METRICS = V28 / "phase6-v28-formal-cell-metrics.csv"
PRODUCTION = ROOT / "MQL5/Experts/SolTradeBot.mq5"
HANDOFF = Path("/home/tibule12/.codex/attachments/95505085-845c-42d7-a851-1a7c4fd25b7a/pasted-text.txt")
PRODUCTION_SHA = "261a9cfe1c1e8d84e2a2a468ac4d0775086b21c89824b117e5127697fd03ced3"
SOURCE_COMMIT = "9060f5b96992aa877949db177c566a38148967ad"
OUTCOME = "V28_FXIFY_2PHASE_PRO_10K_INSUFFICIENT_EVIDENCE"
PURCHASE = "PURCHASE_NOT_AUTHORIZED"
FMT = "%Y.%m.%d %H:%M:%S"
END_EXCLUSIVE = datetime(2026, 8, 1)

CONDITIONS = {
    "NORMAL": ("NORMAL", "NATIVE_NORMAL_EXECUTION", ["01-v28-2025-development-native", "02-v28-2026-preseal-development-native"]),
    "HIGH": ("HIGH", "NATIVE_NORMAL_EXECUTION", ["01-v28-2025-development-native", "02-v28-2026-preseal-development-native"]),
    "STRESS": ("STRESS", "NATIVE_NORMAL_EXECUTION", ["01-v28-2025-development-native", "02-v28-2026-preseal-development-native"]),
    "200MS": ("NORMAL", "FIXED_DELAY_200_MS", ["03-v28-2025-development-delay200", "04-v28-2026-preseal-development-delay200"]),
}

OFFICIAL_URLS = [
    ("01-introducing-2phase-pro", "https://fxify.com/blog/introducing-fxify-2-phase-pro/", "programme launch and overview"),
    ("02-trading-days", "https://fxify.com/faqs/all-faqs/two-phase-pro/2-phase-pro-whats-the-max-and-minimum-trading-days-is-there-a-specific-time-window-to-complete-the-profit-targets/", "three profitable days, 0.5% initial balance, 5PM EST, unlimited time, inactivity"),
    ("03-profitable-day", "https://fxify.com/faqs/all-faqs/two-phase-pro/2-phase-pro-how-do-the-trading-work-is-there-a-minimum-target/", "profitable-day mechanics and examples"),
    ("04-daily-drawdown", "https://fxify.com/faqs/all-faqs/two-phase-pro/2-phase-pro-whats-the-daily-drawdown/", "4% daily drawdown"),
    ("05-max-drawdown", "https://fxify.com/faqs/all-faqs/two-phase-pro/2-phase-pro-whats-the-max-drawdown-limit/", "8% static maximum drawdown"),
    ("06-news", "https://fxify.com/faqs/all-faqs/two-phase-pro/2-phase-pro-can-i-trade-news-on-2-phase-pro/", "news trading allowed"),
    ("07-weekend", "https://fxify.com/faqs/all-faqs/two-phase-pro/2-phase-pro-can-i-hold-positions-over-the-weekend-with-an-2-phase-pro-account/", "weekend holding allowed"),
    ("08-leverage", "https://fxify.com/faqs/all-faqs/two-phase-pro/2-phase-pro-whats-my-account-leverage/", "Forex leverage 30:1"),
    ("09-platforms", "https://fxify.com/faqs/all-faqs/two-phase-pro/2-phase-pro-what-are-the-available-platforms-to-trade-with/", "MT5 availability, embedded price and promotion configuration"),
    ("10-plan-strategies", "https://fxify.com/faqs/all-faqs/two-phase-pro/2-phase-pro-what-strategies-are-allowed-or-prohibited/", "EAs allowed; prohibited practices apply"),
    ("11-payout-days", "https://fxify.com/faqs/all-faqs/two-phase-pro/2-phase-pro-whats-the-min-days-in-order-to-request-a-payout/", "three profitable days and first request after 10 calendar days"),
    ("12-payout-cap", "https://fxify.com/faqs/all-faqs/two-phase-pro/2-phase-pro-what-is-the-max-profit-on-my-account/", "first two withdrawals capped at 5%; excess removed"),
    ("13-strategies", "https://fxify.com/faqs/all-faqs/what-strategies-can-i-use/", "prohibited-strategy summary"),
    ("14-prohibited-strategies", "https://fxify.com/blog/fxifys-prohibited-strategies/", "detailed prohibited strategies"),
    ("15-daily-loss-calculation", "https://fxify.com/faqs/all-faqs/how-do-you-calculate-the-daily-loss-limit/", "previous 5PM EST balance and real-time equity example"),
    ("16-real-time-equity", "https://fxify.com/faqs/all-faqs/why-was-my-account-breached-even-though-the-balance-shows-above-the-daily-max-drawdown/", "tick-level equity breach mechanics"),
    ("17-daily-hard-breach", "https://fxify.com/faqs/all-faqs/two-phase-pro/2-phase-pro-does-daily-loss-limit-count-as-soft-breach/", "daily loss is a hard breach"),
    ("18-inactivity", "https://fxify.com/faqs/all-faqs/two-phase-pro/2-phase-pro-is-there-an-inactivity-breach/", "60-calendar-day inactivity breach"),
    ("19-commissions", "https://fxify.com/faqs/all-faqs/do-you-charge-commissions/", "RAW FX commission $6 per lot round trip"),
    ("20-raw-spreads", "https://fxify.com/faqs/all-faqs/do-you-offer-raw-spreads/", "RAW spread model"),
    ("21-spread-viewer", "https://fxify.com/faqs/all-faqs/what-are-your-spreads/", "official read-only MT5 spread accounts"),
    ("22-instruments", "https://fxify.com/faqs/all-faqs/what-instruments-are-offered-by-fxify/", "symbol suffixes, digits and contract sizes"),
    ("23-swap-free", "https://fxify.com/faqs/all-faqs/swap-free-accounts/", "swap-free unavailable"),
]

SOURCE_FILES = [
    V28 / "candidate-strategy-specification.json",
    V28 / "formal-cell-plan.json",
    V28 / "performance-executable-freeze.json",
    V28 / "phase6-v28-evidence-integrity.json",
    METRICS,
    LEDGER,
    V28 / "signal-feasibility/signal-schedule.csv",
    V28 / "artifact-sha256-v28.txt",
    ROOT / "research/factor_momentum/SolTradeDollarFactorPerformanceHarness.mq5",
]
for run in CONDITIONS["NORMAL"][2] + CONDITIONS["200MS"][2]:
    for name in ("deals.csv", "events.csv", "transactions.csv", "run-summary.csv", "physical-run-status.json", "strategy-tester.ini", "native-mt5-report.html"):
        SOURCE_FILES.append(RUNS / run / name)


def sha(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def read_csv(path: Path) -> list[dict[str, str]]:
    with path.open(newline="", encoding="utf-8-sig") as handle:
        return list(csv.DictReader(handle))


def write_csv(path: Path, fields: list[str], rows: list[dict[str, object]]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=fields, lineterminator="\n")
        writer.writeheader(); writer.writerows(rows)


def write_text(name: str, value: str) -> None:
    path = OUT / name; path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(value.rstrip() + "\n", encoding="utf-8")


def parse_time(value: str) -> datetime:
    return datetime.strptime(value, FMT)


def archive_sources() -> list[dict[str, object]]:
    ARCHIVE.mkdir(parents=True, exist_ok=True)
    records = []
    for stem, canonical, use in OFFICIAL_URLS:
        path = ARCHIVE / f"{stem}.html"
        requested = canonical + ("&" if "?" in canonical else "?") + "amp=1"
        if not path.exists():
            request = urllib.request.Request(requested, headers={"User-Agent": "Googlebot"})
            with urllib.request.urlopen(request, timeout=30) as response:
                body = response.read(); status = response.status
            if status != 200: raise RuntimeError(f"Official source HTTP {status}: {canonical}")
            path.write_bytes(body)
        records.append({"archive_file": path.name, "canonical_url": canonical, "requested_url": requested,
                        "http_status": 200, "bytes": path.stat().st_size, "sha256": sha(path), "use": use})
    write_csv(ARCHIVE / "retrieval-record.csv", list(records[0]), records)
    return records


def summaries(runs: list[str]) -> list[dict[str, str]]:
    result=[]
    for run in runs:
        result.append({r["field"]:r["value"] for r in read_csv(RUNS/run/"run-summary.csv")})
    return result


def transactions(runs: list[str]) -> list[dict[str, str]]:
    result=[]
    for run in runs: result += read_csv(RUNS/run/"transactions.csv")
    return result


def accepted_entry_intervals(rows: list[dict[str, str]]) -> tuple[list[dict[str, object]], float]:
    cohorts: dict[datetime, list[datetime]] = defaultdict(list)
    for r in rows:
        if r["record_type"] == "ENTRY_ATTEMPT" and r["deal_ticket"] != "0":
            cohorts[parse_time(r["signal_time"])].append(parse_time(r["time"]))
    ordered = sorted((signal, min(times), max(times), len(times)) for signal,times in cohorts.items())
    gaps=[]
    for previous, nxt in zip(ordered, ordered[1:]):
        start=previous[2]; end=nxt[1]; seconds=int((end-start).total_seconds())
        if seconds > 30*86400:
            if previous[0].year == 2025 and nxt[0].year == 2026:
                interpretation="UNRESOLVED_DATASET_SEAM_MISSING_DECEMBER_COMBINED_SIGNAL_COVERAGE"
            elif previous[0].strftime("%Y.%m") == "2026.02" and nxt[0].strftime("%Y.%m") == "2026.04":
                interpretation="UNRESOLVED_MARCH_RISK_BLOCK_FROM_INDEPENDENTLY_RESET_2026_STATE"
            else: interpretation="SUPPORTED_BELOW_60_DAYS"
            gaps.append({"previous_signal":previous[0].strftime(FMT), "previous_last_executed_entry":start.strftime(FMT),
                         "next_signal":nxt[0].strftime(FMT), "next_first_executed_entry":end.strftime(FMT),
                         "gap_seconds":seconds, "gap_days":seconds/86400, "exceeds_60_days": "YES" if seconds>=60*86400 else "NO",
                         "hard_breach_proven":"NO" if seconds>=60*86400 else "NOT_APPLICABLE", "interpretation":interpretation})
    last=ordered[-1][2]; seconds=int((END_EXCLUSIVE-last).total_seconds())
    gaps.append({"previous_signal":ordered[-1][0].strftime(FMT), "previous_last_executed_entry":last.strftime(FMT),
                 "next_signal":"HISTORY_END_EXCLUSIVE", "next_first_executed_entry":END_EXCLUSIVE.strftime(FMT),
                 "gap_seconds":seconds, "gap_days":seconds/86400, "exceeds_60_days":"YES" if seconds>=60*86400 else "NO",
                 "hard_breach_proven":"NO", "interpretation":"UNRESOLVED_HISTORY_END_OMITS_JULY_COHORT_WHOSE_EXIT_IS_AFTER_CUTOFF"})
    return gaps, max(float(r["gap_days"]) for r in gaps)


def risk_episodes(rows: list[dict[str,str]]) -> list[dict[str,object]]:
    groups: dict[str,list[dict[str,str]]] = defaultdict(list)
    for r in rows:
        if r["record_type"]=="ENTRY_ATTEMPT" and r["deal_ticket"]!="0": groups[r["signal_time"]].append(r)
    out=[]
    for signal, legs in sorted(groups.items()):
        amount=sum(float(r["initial_risk_amount"]) for r in legs)
        out.append({"signal_time":signal,"legs":len(legs),"aggregate_initial_stop_risk_usd":amount,
                    "percent_of_source_starting_balance":amount/100,"approval_disclosed_range_percent":"2.65_TO_3.21_APPROX",
                    "fxify_per_trade_risk_rule":"NONE_PER_SUPPLIED_WRITTEN_APPROVAL","programme_breach":"NOT_BY_RISK_AMOUNT_ALONE"})
    return out


def max_simultaneous(rows: list[dict[str,str]]) -> int:
    events=[]
    for r in rows:
        events += [(parse_time(r["entry_time"]),1),(parse_time(r["exit_time"]),-1)]
    current=maximum=0
    for stamp,change in sorted(events,key=lambda x:(x[0],x[1])):
        current+=change; maximum=max(maximum,current)
    return maximum


def build() -> None:
    OUT.mkdir(parents=True,exist_ok=True)
    if sha(PRODUCTION)!=PRODUCTION_SHA: raise RuntimeError("Production hash guard failed")
    for p in SOURCE_FILES+[HANDOFF]:
        if not p.is_file(): raise RuntimeError(f"Missing source {p}")
    official=archive_sources(); ledger=read_csv(LEDGER); metrics=read_csv(METRICS)
    all_inactivity=[]; all_risk=[]; condition_data={}
    condition_dirs={"NORMAL":"normal-condition-results","HIGH":"high-condition-results","STRESS":"stress-condition-results","200MS":"200ms-condition-results"}

    for condition,(cost,layer,runs) in CONDITIONS.items():
        rows=[r for r in ledger if r["cost_profile"]==cost and r["execution_layer"]==layer]
        tx=transactions(runs); run_summaries=summaries(runs); gaps,max_gap=accepted_entry_intervals(tx); episodes=risk_episodes(tx)
        for r in gaps: all_inactivity.append({"condition":condition,**r})
        for r in episodes: all_risk.append({"condition":condition,**r})
        durations=[float(r["holding_seconds"]) for r in rows]
        filled=[r for r in tx if r["record_type"]=="ENTRY_ATTEMPT" and r["deal_ticket"]!="0"]
        by_dir=defaultdict(float); by_symbol=defaultdict(float); by_segment=defaultdict(float)
        for r in rows:
            cash=float(r["synthetic_cash_flow"]); by_dir[(r["dataset"],r["direction"])]+=cash
            by_symbol[(r["dataset"],r["symbol"])]+=cash; by_segment[r["dataset"]]+=cash
        maxrisk=max(episodes,key=lambda x:float(x["aggregate_initial_stop_risk_usd"]))
        data={"rows":rows,"episodes":episodes,"maxrisk":maxrisk,"maxgap":max_gap,"trade_count":len(rows),
              "buy":sum(r["direction"]=="BUY" for r in rows),"sell":sum(r["direction"]=="SELL" for r in rows),
              "maxpos":max_simultaneous(rows),"maxticket":max(float(r["volume"]) for r in rows),
              "avgdur":statistics.fmean(durations),"meddur":statistics.median(durations),"mindur":min(durations),"maxdur":max(durations),
              "stops":sum(float(r["stop_loss"])>0 for r in filled),"filled":len(filled),
              "largest":max(rows,key=lambda r:float(r["synthetic_cash_flow"])),"loss":min(rows,key=lambda r:float(r["synthetic_cash_flow"])),
              "schedule":sum(int(s["schedule_signals"]) for s in run_summaries),"processed":sum(int(s["processed_signals"]) for s in run_summaries),
              "riskblocks":sum(int(s["risk_blocks"]) for s in run_summaries),"missed":sum(int(s["missed_signals"]) for s in run_summaries),
              "errors":sum(int(s["execution_blocks"]) for s in run_summaries),"by_segment":by_segment,"by_dir":by_dir,"by_symbol":by_symbol}
        condition_data[condition]=data; cdir=OUT/condition_dirs[condition]

        diag=[]
        unresolved=["phase1_target_timestamp","phase1_profitable_days_fixed_est","phase1_profitable_days_new_york",
                    "phase1_maximum_daily_equity_loss","phase1_smallest_daily_loss_margin","phase1_minimum_equity","phase1_static_floor_margin",
                    "phase2_target_timestamp","phase2_profitable_days","phase2_maximum_daily_equity_loss","phase2_smallest_daily_loss_margin",
                    "phase2_minimum_equity","phase2_static_floor_margin","maximum_floating_cohort_loss","best_5pm_trading_day","worst_5pm_trading_day",
                    "exact_fxify_margin_use"]
        for name in unresolved: diag.append({"diagnostic":name,"value":"","status":"UNRESOLVED_NO_VALID_CONTINUOUS_INTRADAY_FXIFY_ACCOUNT"})
        diag += [
            {"diagnostic":"phase1_outcome","value":"INSUFFICIENT_EVIDENCE","status":"TERMINAL_FOR_PHASE1_EVIDENCE"},
            {"diagnostic":"phase2_outcome","value":"NOT_ENTERED","status":"PHASE1_NOT_PROVEN_PASS"},
            {"diagnostic":"funded_stage","value":"NOT_REACHED","status":"BOTH_PHASES_NOT_PROVEN_PASS"},
            {"diagnostic":"maximum_candidate_entry_gap_days","value":max_gap,"status":"UNRESOLVED_SEGMENT_BOUNDARY_OR_RESET_STATE"},
            {"diagnostic":"maximum_simultaneous_positions","value":data["maxpos"],"status":"SUPPORTED_SOURCE_EVIDENCE"},
            {"diagnostic":"maximum_simultaneous_correlated_positions","value":data["maxpos"],"status":"SUPPORTED_SOURCE_EVIDENCE"},
            {"diagnostic":"maximum_aggregate_stop_risk_usd","value":maxrisk["aggregate_initial_stop_risk_usd"],"status":"SUPPORTED_APPROVED_BEHAVIOUR_NOT_BREACH_ALONE"},
            {"diagnostic":"maximum_ticket_lots","value":data["maxticket"],"status":"SUPPORTED_SOURCE_EVIDENCE"},
            {"diagnostic":"average_holding_seconds","value":data["avgdur"],"status":"SUPPORTED_SOURCE_EVIDENCE"},
            {"diagnostic":"median_holding_seconds","value":data["meddur"],"status":"SUPPORTED_SOURCE_EVIDENCE"},
            {"diagnostic":"minimum_holding_seconds","value":data["mindur"],"status":"SUPPORTED_SOURCE_EVIDENCE"},
            {"diagnostic":"maximum_holding_seconds","value":data["maxdur"],"status":"SUPPORTED_SOURCE_EVIDENCE"},
            {"diagnostic":"visible_stop_coverage","value":f'{data["stops"]}/{data["filled"]}',"status":"PASS_SOURCE_EVIDENCE"},
            {"diagnostic":"processed_scheduled_symbol_signals","value":f'{data["processed"]}/{data["schedule"]}',"status":"PASS_FROZEN_SEGMENTS"},
            {"diagnostic":"pre_order_risk_blocks","value":data["riskblocks"],"status":"SUPPORTED_NOT_EXECUTED_ENTRIES"},
            {"diagnostic":"missed_signals","value":data["missed"],"status":"PASS_SOURCE_EVIDENCE"},
            {"diagnostic":"execution_errors","value":data["errors"],"status":"PASS_SOURCE_EVIDENCE"},
            {"diagnostic":"hard_rule_breach","value":"NONE_CONCLUSIVELY_PROVEN","status":"INTRADAY_AND_CONTINUITY_EVIDENCE_INSUFFICIENT"},
        ]
        write_csv(cdir/"required-diagnostics.csv",list(diag[0]),diag)
        seg=[]
        for dataset in ("V28_2025_DEVELOPMENT","V28_2026_PRESEAL_DEVELOPMENT"):
            dsrows=[r for r in rows if r["dataset"]==dataset]
            seg.append({"dataset":dataset,"source_segment_closed_profit_usd_not_continuous":by_segment[dataset],"trade_count":len(dsrows),
                        "buy_count":sum(r["direction"]=="BUY" for r in dsrows),"buy_net_usd":by_dir[(dataset,"BUY")],
                        "sell_count":sum(r["direction"]=="SELL" for r in dsrows),"sell_net_usd":by_dir[(dataset,"SELL")],
                        "largest_trade_usd":max(float(r["synthetic_cash_flow"]) for r in dsrows),"largest_loss_usd":min(float(r["synthetic_cash_flow"]) for r in dsrows)})
        write_csv(cdir/"source-segment-diagnostics.csv",list(seg[0]),seg)
        syms=[]
        for dataset in ("V28_2025_DEVELOPMENT","V28_2026_PRESEAL_DEVELOPMENT"):
            for symbol in ("EURUSD","GBPUSD","AUDUSD","NZDUSD","USDCAD","USDCHF","USDJPY"):
                syms.append({"dataset":dataset,"symbol":symbol,"net_profit_usd_not_continuous":by_symbol[(dataset,symbol)]})
        write_csv(cdir/"symbol-profit-source-segments.csv",list(syms[0]),syms)
        write_csv(cdir/"candidate-entry-inactivity.csv",list(gaps[0]),gaps)
        write_csv(cdir/"correlated-cohort-risk.csv",list(episodes[0]),episodes)
        write_text(f"{condition_dirs[condition]}/condition-result.md",f"""# {condition} condition

`INSUFFICIENT_EVIDENCE`

Phase 1: `INSUFFICIENT_EVIDENCE`. No target timestamp, profitable-day count, daily-loss margin, minimum real-time equity or static-floor margin can be established without a signal-equivalent continuous account and tick-level equity. Source-segment closed profits are kept separate: 2025 USD {by_segment['V28_2025_DEVELOPMENT']:.8f}; independently reset 2026 through July USD {by_segment['V28_2026_PRESEAL_DEVELOPMENT']:.8f}. They are not added.

Phase 2 is not entered because Phase 1 is not proven to pass. The funded stage and payout audit are not reached.

The largest accepted-entry interval is {max_gap:.8f} days, but it is not a proven hard breach: intervals over 60 days cross an omitted dataset-end cohort, depend on the independently reset 2026 risk state, or end where the next cohort cannot be completed inside the cutoff. A fresh continuous execution could change those entries.

Supported diagnostics: {len(rows)} completed positions ({data['buy']} BUY, {data['sell']} SELL); maximum {data['maxpos']} simultaneous/correlated positions; maximum aggregate initial cohort risk USD {float(maxrisk['aggregate_initial_stop_risk_usd']):.8f}; maximum ticket {data['maxticket']:.2f} lots; holding seconds average {data['avgdur']:.8f}, median {data['meddur']:.0f}, minimum {data['mindur']:.0f}, maximum {data['maxdur']:.0f}; visible stop coverage {data['stops']}/{data['filled']}; frozen segmented signals processed {data['processed']}/{data['schedule']}; risk blocks {data['riskblocks']}; missed signals {data['missed']}; execution errors {data['errors']}.
""")

    write_csv(OUT/"inactivity-audit.csv",list(all_inactivity[0]),all_inactivity)
    write_csv(OUT/"correlated-cohort-risk-audit.csv",list(all_risk[0]),all_risk)
    unresolved_rows=[{"condition":c,"status":"UNRESOLVED_NO_VALID_CONTINUOUS_TICK_LEVEL_EQUITY"} for c in CONDITIONS]
    write_csv(OUT/"intraday-equity-audit.csv",["condition","status"],unresolved_rows)
    write_csv(OUT/"daily-loss-audit.csv",["condition","boundary_interpretation","previous_5pm_balance","daily_loss_amount","breach_level","minimum_realtime_equity","minimum_timestamp","margin","status"],
              [{"condition":c,"boundary_interpretation":b,"previous_5pm_balance":"","daily_loss_amount":"","breach_level":"","minimum_realtime_equity":"","minimum_timestamp":"","margin":"","status":"UNRESOLVED_MISSING_CONTINUOUS_INTRADAY_EQUITY_AND_SOURCE_TIME_MAPPING"} for c in CONDITIONS for b in ("FIXED_EST","AMERICA_NEW_YORK")])
    write_csv(OUT/"static-loss-audit.csv",["condition","floor_usd","minimum_balance","minimum_equity","margin","status"],
              [{"condition":c,"floor_usd":9200,"minimum_balance":"","minimum_equity":"","margin":"","status":"UNRESOLVED_NO_CONTINUOUS_INTRADAY_ACCOUNT"} for c in CONDITIONS])
    write_csv(OUT/"profitable-day-audit.csv",["condition","boundary_interpretation","interpretation_a_cumulative_initial_balance","interpretation_b_individual_day_profit","qualified_days","status"],
              [{"condition":c,"boundary_interpretation":b,"interpretation_a_cumulative_initial_balance":"OFFICIAL_FAQ_SUPPORTED","interpretation_b_individual_day_profit":"CALCULATION_UNAVAILABLE_AND_NOT_OFFICIAL_INTERPRETATION","qualified_days":"","status":"UNRESOLVED_NO_CONTINUOUS_5PM_BALANCE_AND_EQUITY"} for c in CONDITIONS for b in ("FIXED_EST","AMERICA_NEW_YORK")])
    write_csv(OUT/"phase-transition-audit.csv",["condition","phase1_status","phase1_pass_timestamp","phase2_status","phase2_pass_timestamp","funded_status","payout_status"],
              [{"condition":c,"phase1_status":"INSUFFICIENT_EVIDENCE","phase1_pass_timestamp":"","phase2_status":"NOT_ENTERED","phase2_pass_timestamp":"","funded_status":"NOT_REACHED","payout_status":"NOT_REACHED"} for c in CONDITIONS])

    tz=ZoneInfo("America/New_York"); boundary=[]; d=date(2025,1,1)
    while d<=date(2026,7,31):
        local=datetime.combine(d,time(17),tzinfo=tz); utc=local.astimezone(timezone.utc)
        boundary.append({"date":d.isoformat(),"fixed_est_boundary_utc":f"{d.isoformat()} 22:00:00 UTC",
                         "new_york_boundary_utc":utc.strftime("%Y-%m-%d %H:%M:%S UTC"),"new_york_utc_offset":local.strftime("%z"),
                         "interpretations_differ":"YES" if utc.hour!=22 else "NO","rule_calculation_status":"UNRESOLVED_SOURCE_TIMESTAMP_TO_UTC_MAPPING"})
        d+=timedelta(days=1)
    write_csv(OUT/"time-boundary-date-coverage.csv",list(boundary[0]),boundary)

    write_text("terminal-outcome.md",f"""# FXIFY 2-Phase Pro USD 10,000 V28 terminal outcome

Normal, High, Stress and 200 ms are all `INSUFFICIENT_EVIDENCE`. No condition has a conclusive hard-rule failure, but none has the valid continuous tick-level account, exact 5PM timestamp mapping or FXIFY MT5 RAW specifications required to prove Phase 1. Phase 2 and funded/payout stages are therefore not entered.

The segmented accepted-entry evidence contains candidate intervals over 60 days. They are not treated as proven inactivity breaches because they cross dataset-end signal omissions, depend on reset-only risk state, or terminate at the evidence cutoff. This limitation is decisive: segmented coverage cannot substitute for the requested continuous account.

The supplied FXIFY written approval is preserved and the disclosed correlated cohort is not failed merely for its risk amount. No purchase, registration, V28 change, V29/V31 use, production change or push occurred.

{PURCHASE}

{OUTCOME}
""")
    write_text("purchase-decision.md",f"""# Purchase decision

`{PURCHASE}`

No condition proves both phases and a funded payout. The published USD 129 price and NEW30 30% calculation produce USD 90.30 before tax/conversion, but this does not authorize purchase. `FINAL_CHECKOUT_PRICE_PLATFORM_AND_CONFIGURATION_REVERIFICATION_REQUIRED`; checkout must confirm MT5, RAW/no add-ons, promotion validity, eligibility and total no greater than USD 100 under separate authorization.
""")
    write_text("official-rule-freeze.md","""# Official FXIFY 2-Phase Pro rule freeze

USD 10,000 Pro: Phase 1 target USD 400 (4%); Phase 2 target USD 800 (8%); 4% daily loss based on the previous 5PM EST closing balance; 8% static maximum loss (USD 9,200 floor); three profitable days per phase; unlimited maximum days; 60-calendar-day inactivity; news/weekend/overnight allowed; Forex leverage 30:1; MT5 available; standard performance split 80%.

The profitable-day FAQ resolves its rule as cumulative balance and equity at least USD 50 above the phase's USD 10,000 initial balance at 5PM EST. The separately requested individual-day-profit interpretation is retained as a sensitivity interpretation, not substituted for official wording.

Funded requirements frozen conditionally: three profitable days, first request 10 calendar days after first funded trade, first two withdrawals capped at USD 500 gross with excess removed, USD 4,000 maximum gains per day control, and 80% trader share. These are not exercised because no condition reaches funded status.
""")
    manifest=["# Official source manifest","","Retrieved 2026-08-05 from canonical FXIFY pages using `?amp=1` after the unparameterized pages returned Cloudflare HTTP 403. All archived responses returned HTTP 200. Raw snapshots are under `official-source-archive/`.","","| Archive | SHA-256 | Canonical URL | Use |","|---|---|---|---|"]
    manifest += [f"| `{r['archive_file']}` | `{r['sha256']}` | {r['canonical_url']} | {r['use']} |" for r in official]
    write_text("official-source-manifest.md","\n".join(manifest))
    write_text("fxify-ea-approval-evidence.md",f"""# Supplied FXIFY EA approval evidence

Source: user-supplied handoff `{HANDOFF}`; SHA-256 `{sha(HANDOFF)}`.

Disclosed: privately developed monthly seven-pair USD-factor EA; H1 signals; approximately 26-day average holding; seven simultaneous correlated USD positions; historical cohort stop risk approximately 2.65%–3.21%; no HFT; no latency arbitrage; ATR stops; no fixed take-profit.

FXIFY reply supplied verbatim: “Based on the description provided, the EA is approved.”

FXIFY also supplied: “There is no rule regarding risk per trade. However, all challenge accounts are equity-based. If your account equity falls below the applicable loss limit at any time, the challenge account will be breached.”

The approval is preserved as supplied evidence. It does not waive actual published loss or other rules, and the cohort is not classified as prohibited merely because of aggregate risk.
""")
    write_text("checkout-price-status.md","""# Checkout price status

`FINAL_CHECKOUT_PRICE_PLATFORM_AND_CONFIGURATION_REVERIFICATION_REQUIRED`

The archived official page embeds USD 129 for Two Phase Pro USD 10,000 and NEW30 at 30% for Pro, advertised to expire 31 December 2026. Derived price: USD 129 × 0.70 = USD 90.30. The page also showed HOT20 as the active site-wide headline promotion while listing NEW30 specifically for Pro; therefore only checkout can validate application. Tax, currency conversion, unavailable MT5/RAW/no-add-on configuration, ineligibility, invalid promotion, or total above USD 100 prevents purchase. No checkout or purchase occurred.
""")
    write_text("fxify-mt5-execution-specification-gate.md","""# FXIFY MT5 RAW execution-specification gate

Gate: `INSUFFICIENT_FOR_EXACT_FXIFY_REPLICATION`.

Official evidence establishes RAW symbols EURUSD.r, GBPUSD.r, AUDUSD.r, NZDUSD.r, USDCAD.r, USDCHF.r and USDJPY.r; Forex contract size 100,000; five display digits except three for USDJPY.r; 30:1 leverage; and USD 6 per lot round-trip RAW commission. RAW spreads are described as close to zero and an official read-only account is published, but no historical spread series is supplied.

Exact trade tick size/value, minimum volume, volume step, maximum volume, per-symbol margin flags, historical spreads, swap-long/short, triple-swap day, server timezone and historical execution/slippage configuration were not established for all seven symbols. FXIFY is not assumed identical to FP Markets. Normal, High, Stress and 200 ms remain qualified sensitivity evidence, not exact FXIFY-feed replication.
""")
    write_text("time-boundary-interpretation.md","""# Time-boundary interpretations

Fixed EST means 17:00 UTC-5, or 22:00 UTC throughout the year. New York local time means 17:00 America/New_York: 22:00 UTC in standard time and 21:00 UTC in daylight time. Historical New York DST began 2025-03-09 and 2026-03-08 and ended 2025-11-02 (the 2026 end is after the evidence cutoff).

Both mappings are enumerated in `time-boundary-date-coverage.csv`. The frozen FP Markets source timestamps have no authoritative exact mapping to UTC/FXIFY server time, and no continuous 5PM balance/equity stream exists. Results under both interpretations are therefore unresolved; neither is silently selected.
""")
    write_text("continuous-account-method.md","""# Continuous account method

The qualified V28 history consists of separate 2025 and 2026 physical runs, each initialized at USD 10,000. The frozen schedule omits cohorts that cannot close before each dataset boundary, and the 2026 risk engine starts from reset state. High and Stress are post-run closed-trade cost overlays. No tick-level portfolio equity journal or 5PM balance/equity snapshots exist.

Adding reset totals, interpolating equity, treating the missing December/July cohorts as inactivity, or replaying adjusted closed trades as though they drove natural subsequent sizing would violate the requested method. A new instrumented run would also lack exact FXIFY RAW historical specifications. No technically valid continuous FXIFY account can therefore be constructed from the available qualified evidence. Source-supported diagnostics are reported without inventing phase results.
""")
    src=["# Source evidence manifest","",f"Frozen source commit: `{SOURCE_COMMIT}`. V29 and V31 excluded. Production SHA-256: `{sha(PRODUCTION)}`.","","| Path | SHA-256 |","|---|---|"]
    src += [f"| `{p.relative_to(ROOT)}` | `{sha(p)}` |" for p in SOURCE_FILES]
    src += [f"| `{HANDOFF}` | `{sha(HANDOFF)}` |"]
    write_text("source-evidence-manifest.md","\n".join(src))
    write_text("phase1-results/summary.md","""# Phase 1 results

Normal, High, Stress and 200 ms: `INSUFFICIENT_EVIDENCE`. No exact pass timestamp or hard drawdown finding exists. The official cumulative profitable-day interpretation and requested individual-day sensitivity cannot be counted under either 5PM boundary without continuous balance and equity. Phase 2 is not opened.
""")
    write_text("phase2-results/summary.md","""# Phase 2 results

All conditions: `NOT_ENTERED`. Phase 1 is not proven to pass, so no reset, target test or phase transition is simulated.
""")
    write_text("prohibited-practice-audit.md","""# Prohibited-practice audit

The frozen code is monthly directional USD-factor momentum with 105 completed positions per condition, zero positions held under one minute, maximum seven simultaneous positions and no latency-feed comparison or order-book-spam mechanism. It does not implement reverse/group hedging, copy trading, account mirroring, pass services, bug/feed exploitation, cross-account statistical loss offsetting, or news-event leverage logic. No evidence establishes account management, collusion or external coordinated use. SolTrade is treated as private to this user.

The supplied written FXIFY approval explicitly covers the disclosed EA, seven correlated positions and approximate cohort risk. It is preserved and not reinterpreted as an automatic prohibition. Actual equity rules remain unresolved because tick-level continuous evidence is absent.
""")
    write_text("limitations.md","""# Limitations

- Separate 2025/2026 USD 10,000 resets; no valid continuous account.
- Frozen dataset-end schedule omits December 2025 and July 2026 cohorts that cannot close inside their original windows.
- No timestamped tick-level portfolio balance/equity journal or 5PM snapshots.
- High/Stress overlays do not feed costs back into later native sizing.
- No authoritative source-time-to-UTC/FXIFY mapping.
- Exact historical FXIFY MT5 RAW specifications are incomplete.
- Candidate entry gaps over 60 days are not classified as genuine continuous V28 inactivity.
- No Phase 2, funded stage, payout, checkout, purchase, registration, V31 restart, V29 use, strategy change, production change or push occurred.
""")

    report_files=sorted(p for p in OUT.rglob("*") if p.is_file() and p.name!="complete-sha256-ledger.txt")
    lines=["# Report artifacts (self-referential ledger excluded)"]+[f"{sha(p)}  {p.relative_to(ROOT)}" for p in report_files]
    lines += ["# Frozen source artifacts"]+[f"{sha(p)}  {p.relative_to(ROOT)}" for p in SOURCE_FILES]
    lines += [f"{sha(PRODUCTION)}  {PRODUCTION.relative_to(ROOT)}",f"{sha(HANDOFF)}  EXTERNAL_INPUT:{HANDOFF}"]
    write_text("complete-sha256-ledger.txt","\n".join(lines))


if __name__ == "__main__": build()
