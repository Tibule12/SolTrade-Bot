#!/usr/bin/env python3
"""Read-only FXIFY EA event score and flat-baseline diagnostics.

Inputs are preserved local event, deployment, and pause files. No terminal, broker,
account state, or production configuration is accessed by this script.
"""

from __future__ import annotations

import argparse
import csv
import json
import math
import re
import statistics
from collections import Counter, defaultdict
from decimal import Decimal, InvalidOperation
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
AUDIT = ROOT / "ops/forexvps/remote-output/full-readonly-audit-20260930"
BASELINE = ROOT / "reports/fast-multi-market-v2/fxify-bank1r-giveback-deployment-20260913/baseline.json"
PAUSE = ROOT / "reports/fast-multi-market-v2/fxify-pause-20260916/verification.json"
DEFAULT_OUTPUT = ROOT / "reports/fast-multi-market-v2/three-account-replay-20261001"
ACCOUNTS = {
    "fxify-10k": {"login": "7196820", "nominal_usd": Decimal("10000"), "pause_key": "fxify_10k"},
    "fxify-100k": {"login": "7198096", "nominal_usd": Decimal("100000"), "pause_key": "fxify_100k"},
}
SCORE_BOUNDS = (60, 62.5, 65, 67.5, 70, 72.5, 75, 77.5)
SCORE_FIELDS = ("admission_score", "directional_score", "opposite_score")


def fields(value: str) -> dict[str, str]:
    return dict(re.findall(r"(?:^|;)([A-Za-z_][A-Za-z_0-9]*)=([^;]*)", value or ""))


def decimal(value: str | float | int | None) -> Decimal | None:
    if value is None or value == "":
        return None
    try:
        answer = Decimal(str(value))
    except InvalidOperation:
        return None
    return answer if answer.is_finite() else None


def money(value: Decimal) -> str:
    return str(value.quantize(Decimal("0.01")))


def utc_from_iso(value: str) -> str:
    return value[:10].replace("-", ".") + " " + value[11:19]


def score_band(score: Decimal | None) -> str:
    if score is None:
        return "MISSING"
    if score < Decimal(str(SCORE_BOUNDS[0])):
        return "<60"
    for low, high in zip(SCORE_BOUNDS, SCORE_BOUNDS[1:]):
        if Decimal(str(low)) <= score < Decimal(str(high)):
            return f"{low:g}-{high:g}"
    return "77.5+"


def average_ranks(values: list[float]) -> list[float]:
    indices = sorted(range(len(values)), key=values.__getitem__)
    result = [0.0] * len(values)
    start = 0
    while start < len(values):
        end = start + 1
        while end < len(values) and values[indices[end]] == values[indices[start]]:
            end += 1
        rank = (start + end - 1) / 2 + 1
        for i in range(start, end):
            result[indices[i]] = rank
        start = end
    return result


def pearson(xs: list[float], ys: list[float]) -> float | None:
    if len(xs) < 3 or len(xs) != len(ys):
        return None
    xbar, ybar = statistics.mean(xs), statistics.mean(ys)
    cross = sum((x - xbar) * (y - ybar) for x, y in zip(xs, ys))
    spread = math.sqrt(sum((x - xbar) ** 2 for x in xs) * sum((y - ybar) ** 2 for y in ys))
    return cross / spread if spread else None


def load_trades(path: Path, login: str) -> tuple[list[dict], dict]:
    entries: dict[str, dict] = {}
    exits: dict[str, dict] = {}
    events = Counter()
    bank_events: set[str] = set()
    first_utc: str | None = None
    last_utc: str | None = None
    with path.open(newline="", encoding="utf-8-sig") as handle:
        for row in csv.DictReader(handle):
            utc, event = row["utc"], row["event"]
            first_utc = min(first_utc, utc) if first_utc else utc
            last_utc = max(last_utc, utc) if last_utc else utc
            events[event] += 1
            if event == "ENTRY":
                ticket = row["ticket"]
                if not ticket or ticket in entries:
                    raise ValueError(f"{path}: missing or repeated ENTRY ticket {ticket!r}")
                entries[ticket] = row
            elif event == "EXIT":
                ticket = fields(row["detail"]).get("position_id")
                if not ticket or ticket in exits:
                    raise ValueError(f"{path}: missing or repeated EXIT position_id {ticket!r}")
                exits[ticket] = row
            elif event in ("PARTIAL_BANK_1R", "PARTIAL_EXIT_DEAL"):
                bank_events.add(row["ticket"])

    if set(entries) != set(exits):
        missing_exits = sorted(set(entries) - set(exits))
        missing_entries = sorted(set(exits) - set(entries))
        raise ValueError(f"{path}: unmatched events: entries without exits={missing_exits}; exits without entries={missing_entries}")

    trades = []
    for ticket, entry in entries.items():
        exit_row = exits[ticket]
        entry_detail, exit_detail = fields(entry["detail"]), fields(exit_row["detail"])
        case = fields(entry["no_trade_case"])
        own = fields(entry["buy_case"] if entry["direction"] == "BUY" else entry["sell_case"])
        opposite = fields(entry["sell_case"] if entry["direction"] == "BUY" else entry["buy_case"])
        risk = decimal(entry_detail.get("initial_risk"))
        net = decimal(exit_detail.get("net"))
        if risk is None or risk <= 0 or net is None:
            raise ValueError(f"{path}: position {ticket} lacks positive initial_risk or EXIT net")
        score = decimal(entry_detail.get("admission_score"))
        fallback = decimal(case.get("admission_score"))
        if score is not None and fallback is not None and abs(score - fallback) > Decimal("0.0051"):
            raise ValueError(f"{path}: position {ticket} ENTRY scores disagree")
        peak = decimal(exit_detail.get("RUNNER_PEAK_R"))
        trade = {
            "account": login,
            "position_id": ticket,
            "entry_utc": entry["utc"],
            "exit_utc": exit_row["utc"],
            "symbol": entry["symbol"],
            "direction": entry["direction"],
            "admission_score": score if score is not None else fallback,
            "admission_score_source": "ENTRY.detail" if score is not None else ("ENTRY.no_trade_case" if fallback is not None else "MISSING"),
            "directional_score": decimal(own.get("score")),
            "opposite_score": decimal(opposite.get("score")),
            "no_trade_score": decimal(case.get("score")),
            "initial_risk_usd": risk,
            "net_usd": net,
            "net_r": net / risk,
            "peak_price_r": peak,
            "exit_class": exit_detail.get("exit_class", ""),
            "exit_reason": exit_detail.get("reason", ""),
            "bank1_confirmed": exit_detail.get("partial_banking") == "true" or ticket in bank_events,
            "manager": exit_detail.get("manager", "EARLIER_MANAGER"),
        }
        if trade["entry_utc"] > trade["exit_utc"]:
            raise ValueError(f"{path}: position {ticket} exits before ENTRY UTC")
        trades.append(trade)
    trades.sort(key=lambda row: (row["entry_utc"], row["position_id"]))
    return trades, {
        "source": str(path.relative_to(ROOT)) if path.is_relative_to(ROOT) else str(path),
        "event_rows": sum(events.values()),
        "event_types": dict(sorted(events.items())),
        "first_event_utc": first_utc,
        "last_event_utc": last_utc,
        "entry_events": len(entries),
        "exit_events": len(exits),
        "matched_closed_positions": len(trades),
        "entry_detail_admission_scores": sum(t["admission_score_source"] == "ENTRY.detail" for t in trades),
    }


def summarize(trades: list[dict]) -> dict:
    net = sum((t["net_usd"] for t in trades), Decimal(0))
    total_r = sum((t["net_r"] for t in trades), Decimal(0))
    return {
        "n": len(trades),
        "wins": sum(t["net_usd"] > 0 for t in trades),
        "losses": sum(t["net_usd"] < 0 for t in trades),
        "net_usd": money(net),
        "net_r": float(total_r),
        "mean_r": float(total_r / len(trades)) if trades else None,
        "full_structural_losses": sum(t["exit_class"] == "INITIAL_STRUCTURAL_STOP_EXIT" for t in trades),
        "confirmed_bank1r": sum(t["bank1_confirmed"] for t in trades),
        "sampled_peak_at_least_1r": sum(t["peak_price_r"] is not None and t["peak_price_r"] >= 1 for t in trades),
    }


def score_diagnostic(trades: list[dict]) -> dict:
    result = {}
    for field in SCORE_FIELDS:
        eligible = [t for t in trades if t[field] is not None]
        xs = [float(t[field]) for t in eligible]
        ys = [float(t["net_r"]) for t in eligible]
        buckets: dict[str, list[dict]] = defaultdict(list)
        for trade in eligible:
            buckets[score_band(trade[field])].append(trade)
        result[field] = {
            "scored_n": len(eligible),
            "missing_n": len(trades) - len(eligible),
            "pearson_score_vs_realized_net_r": pearson(xs, ys),
            "spearman_score_vs_realized_net_r": pearson(average_ranks(xs), average_ranks(ys)) if xs else None,
            "fixed_bins": {name: summarize(rows) for name, rows in sorted(buckets.items())},
        }
    return result


def reconcile_account(
    account_id: str, trades: list[dict], baseline_account: dict, pause_account: dict,
    baseline_utc: str,
) -> tuple[dict, list[dict]]:
    account = ACCOUNTS[account_id]
    if str(baseline_account["account"]) != account["login"] or pause_account["login"] != account["login"]:
        raise ValueError(f"{account_id}: account identity mismatch")
    if any(int(x["positions"]) != 0 or int(x["orders"]) != 0 for x in (baseline_account, pause_account)):
        raise ValueError(f"{account_id}: expected flat balance anchors")
    baseline_equity, pause_equity = decimal(baseline_account["equity"]), decimal(pause_account["equity"])
    if baseline_equity is None or pause_equity is None:
        raise ValueError(f"{account_id}: missing flat-equity anchor")
    pause_utc = pause_account["timestamp_utc"]
    prior = [t for t in trades if t["exit_utc"] < baseline_utc]
    later = [t for t in trades if baseline_utc <= t["exit_utc"] <= pause_utc]
    out_of_window = [t["position_id"] for t in trades if t["exit_utc"] > pause_utc]
    carry_in = [t["position_id"] for t in later if t["entry_utc"] < baseline_utc]
    if carry_in or out_of_window:
        raise ValueError(f"{account_id}: flat-path bounds violated: carry_in={carry_in}; after_pause={out_of_window}")
    prior_net = sum((t["net_usd"] for t in prior), Decimal(0))
    balance = baseline_equity
    path = []
    for trade in sorted(later, key=lambda row: (row["exit_utc"], row["position_id"])):
        balance += trade["net_usd"]
        path.append({
            "account": account["login"], "position_id": trade["position_id"],
            "exit_utc": trade["exit_utc"], "symbol": trade["symbol"],
            "net_usd": money(trade["net_usd"]), "balance_after_exit_usd": money(balance),
        })
    later_net = sum((t["net_usd"] for t in later), Decimal(0))
    gap = pause_equity - (baseline_equity + later_net)
    partials = sum(t["bank1_confirmed"] for t in later)
    return {
        "baseline_utc": baseline_utc,
        "baseline_flat_equity_usd": money(baseline_equity),
        "pause_runtime_utc": pause_account["timestamp_utc"],
        "pause_flat_equity_usd": money(pause_equity),
        "prior_recorded_exit_count": len(prior),
        "prior_recorded_net_usd": money(prior_net),
        "nominal_start_usd": money(account["nominal_usd"]),
        "inception_arithmetic_gap_usd": money(baseline_equity - account["nominal_usd"] - prior_net),
        "inception_status": "INCOMPLETE_HISTORY_NO_INDEPENDENT_BROKER_LEDGER",
        "post_baseline_exit_count": len(later),
        "post_baseline_recorded_net_usd": money(later_net),
        "projected_pause_balance_usd": money(baseline_equity + later_net),
        "pause_reconciliation_gap_usd": money(gap),
        "exact_ea_event_to_runtime_reconciliation": gap == 0,
        "post_baseline_confirmed_partials": partials,
        "balance_path_basis": "EA_EXIT_CASH_POSTED_AT_EXIT; NO_CONFIRMED_PARTIALS" if not partials else "TIMING_INCOMPLETE_CONFIRMED_PARTIALS",
        "current_broker_exposure_verified": False,
    }, path


def build(evidence_paths: dict[str, Path], baseline_path: Path, pause_path: Path) -> tuple[dict, dict[str, list[dict]], dict[str, list[dict]]]:
    baseline = json.loads(baseline_path.read_text(encoding="utf-8-sig"))
    pause = json.loads(pause_path.read_text(encoding="utf-8-sig"))
    baseline_accounts = {str(x["account"]): x for x in baseline["accounts"]}
    baseline_utc = utc_from_iso(baseline["timestamp_utc"])
    result = {
        "schema": "SOLTRADE_FXIFY_RECORDED_EVENT_DIAGNOSTIC_V1",
        "evidence_basis": "Preserved FXIFY EA events and flat runtime anchors; no independent FXIFY broker deal/order or tick-level equity path",
        "score_interpretation": "Descriptive association among executed trades. Accounts are analyzed separately because their signals are often mirrored. Small samples, strategy versions, and post-selection prevent a causal score threshold claim.",
        "score_measure": "ENTRY.detail.admission_score where present, otherwise ENTRY.no_trade_case.admission_score; realized net R is EXIT.detail.net divided by ENTRY.detail.initial_risk",
        "accounts": {},
    }
    all_trades, all_paths = {}, {}
    for account_id, config in ACCOUNTS.items():
        trades, coverage = load_trades(evidence_paths[account_id], config["login"])
        paused = pause["accounts"][config["pause_key"]]
        reconciliation, path = reconcile_account(
            account_id, trades, baseline_accounts[config["login"]], paused, baseline_utc
        )
        frozen = [t for t in trades if t["entry_utc"] >= baseline_utc]
        result["accounts"][account_id] = {
            "login": config["login"],
            "coverage": coverage,
            "reconciliation": reconciliation,
            "cohorts": {
                "all_recorded_mixed_managers": {"summary": summarize(trades), "scores": score_diagnostic(trades)},
                "bank1r_from_2026_09_13": {"summary": summarize(frozen), "scores": score_diagnostic(frozen)},
            },
        }
        all_trades[account_id], all_paths[account_id] = trades, path
    return result, all_trades, all_paths


TRADE_COLUMNS = (
    "account", "position_id", "entry_utc", "exit_utc", "symbol", "direction", "manager",
    "admission_score", "admission_score_source", "directional_score", "opposite_score", "no_trade_score",
    "initial_risk_usd", "net_usd", "net_r", "peak_price_r", "exit_class", "exit_reason", "bank1_confirmed",
)
PATH_COLUMNS = ("account", "position_id", "exit_utc", "symbol", "net_usd", "balance_after_exit_usd")


def write_csv(path: Path, rows: list[dict], columns: tuple[str, ...]) -> None:
    with path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=columns)
        writer.writeheader()
        for row in rows:
            writer.writerow({key: str(row[key]) if row[key] is not None else "" for key in columns})


def markdown_report(result: dict) -> str:
    def dollars(value: str, signed: bool = False) -> str:
        amount = Decimal(value)
        prefix = "−" if amount < 0 else ("+" if signed else "")
        return f"{prefix}${abs(amount):,.2f}"

    lines = [
        "# FXIFY recorded ENTRY/EXIT and score diagnostic",
        "",
        "These are descriptive EA-event results, not an independent broker ledger or a counterfactual strategy run. The two logins are kept separate because many entries are copies of one signal. Scores are recorded at entry; realized R uses recorded net cash divided by the entry's initial dollar risk.",
        "",
        "| Login | Closed positions | W / L | All recorded net | Sep 13–16 exits/net | Sep 13 flat equity → Sep 16 paused equity | Reconciliation gap |",
        "|---|---:|---:|---:|---:|---:|---:|",
    ]
    for account_id, data in result["accounts"].items():
        all_summary = data["cohorts"]["all_recorded_mixed_managers"]["summary"]
        bank_summary = data["cohorts"]["bank1r_from_2026_09_13"]["summary"]
        rec = data["reconciliation"]
        lines.append(
            f"| {data['login']} | {all_summary['n']} | {all_summary['wins']} / {all_summary['losses']} | "
            f"{dollars(all_summary['net_usd'], signed=True)} | {bank_summary['n']} / {dollars(bank_summary['net_usd'], signed=True)} | "
            f"{dollars(rec['baseline_flat_equity_usd'])} → {dollars(rec['pause_flat_equity_usd'])} | {dollars(rec['pause_reconciliation_gap_usd'])} |"
        )
    lines += [
        "",
        "The baseline bridge posts each post-September-13 whole-position net at its recorded EA `EXIT` UTC. No Bank1R partial was confirmed in that cohort. This reconstructs a closed-balance path at exits, not intratrade equity or provider daily-loss enforcement. The September 16 pause runtime is the last preserved FXIFY account-state row; it does not prove present broker exposure.",
        "",
        "## Recorded admission-score association",
        "",
        "| Login / cohort | Scored trades | Pearson score vs net R | Spearman score vs net R |",
        "|---|---:|---:|---:|",
    ]
    for data in result["accounts"].values():
        for cohort_name, cohort in data["cohorts"].items():
            score = cohort["scores"]["admission_score"]
            p = score["pearson_score_vs_realized_net_r"]
            s = score["spearman_score_vs_realized_net_r"]
            lines.append(f"| {data['login']} / {cohort_name} | {score['scored_n']} | {p:.3f} | {s:.3f} |" if p is not None and s is not None else f"| {data['login']} / {cohort_name} | {score['scored_n']} | undefined | undefined |")
    lines += [
        "",
        "### Admission-score bins",
        "",
        "| Login / cohort | Score interval | Trades | W / L | Net R |",
        "|---|---|---:|---:|---:|",
    ]
    for data in result["accounts"].values():
        for cohort_name, cohort in data["cohorts"].items():
            for interval, stats in cohort["scores"]["admission_score"]["fixed_bins"].items():
                lines.append(
                    f"| {data['login']} / {cohort_name} | {interval} | {stats['n']} | "
                    f"{stats['wins']} / {stats['losses']} | {stats['net_r']:+.3f} |"
                )
    lines += [
        "",
        "Bins are fixed at 2.5 score points. Directional/opposite score associations and every trade are in `fxify-event-diagnostic.json` and the account-specific CSVs. Four Bank1R-era observations per login cannot validate a score threshold; paired signals across accounts are not independent confirmations. The earlier cohort mixes manager versions and 0.25%/1.00% sizing.",
        "",
        "The nominal-inception arithmetic gap is −$2.77 on 10K and $0.00 on 100K, but neither account has complete inception deal/cash-flow history here. Missing FXIFY broker deals/orders and continuous bid/ask/equity paths prevent independent settlement, daily drawdown, or exact challenge-counterfactual claims.",
        "",
    ]
    return "\n".join(lines)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output-dir", type=Path, default=DEFAULT_OUTPUT)
    args = parser.parse_args()
    evidence = {key: AUDIT / f"{key}-evidence.csv" for key in ACCOUNTS}
    result, trades, paths = build(evidence, BASELINE, PAUSE)
    args.output_dir.mkdir(parents=True, exist_ok=True)
    (args.output_dir / "fxify-event-diagnostic.json").write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")
    (args.output_dir / "fxify-event-diagnostic.md").write_text(markdown_report(result), encoding="utf-8")
    for account_id in ACCOUNTS:
        write_csv(args.output_dir / f"{account_id}-event-trades.csv", trades[account_id], TRADE_COLUMNS)
        write_csv(args.output_dir / f"{account_id}-baseline-path.csv", paths[account_id], PATH_COLUMNS)
    print(json.dumps({"accounts": {k: v["reconciliation"] for k, v in result["accounts"].items()}}, indent=2))


if __name__ == "__main__":
    main()
