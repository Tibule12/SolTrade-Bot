#!/usr/bin/env python3
"""Reconstruct the frozen 2026-08-25 Fast Multi V2 demo failure session.

This is an evidence/reporting tool, not trading code. It deliberately reports
UNKNOWN where the frozen snapshot did not retain the raw tick path needed for
an exact value. The corrected replay is a deterministic lower-bound policy
replay from recorded scan decisions and recorded MFE; it is not a claim of an
exact counterfactual fill sequence.
"""

from __future__ import annotations

import argparse
import csv
import hashlib
import json
from datetime import datetime
from pathlib import Path


TRADES = [
    # id, symbol, direction, entry utc, exit utc, entry, exit, lot, sl, risk, gross, commission, swap, net, mfe, mae, peak_r, runner utc, reason
    (1,"XAUUSD.r","SELL","2026.08.25 03:50:11","2026.08.25 05:05:50",4633.33,4633.28,.25,4642.94,242.75,1.25,-1.50,0,-.25,233.50,-109.25,.96815,"2026.08.25 04:41:10","DEAL_REASON_SL"),
    (2,"XAUUSD.r","SELL","2026.08.25 05:05:51","2026.08.25 05:15:57",4633.46,4640.23,.36,4640.23,245.88,-243.72,-2.16,0,-245.88,.72,-229.68,.00295,"UNKNOWN","DEAL_REASON_SL"),
    (3,"US100","BUY","2026.08.25 06:46:21","2026.08.25 07:11:32",29204.60,29203.93,11.14,29182.24,249.09,-7.46,0,0,-7.46,347.01,-232.27,1.39290,"2026.08.25 07:03:10","DEAL_REASON_SL"),
    (4,"GER40","BUY","2026.08.25 07:10:20","2026.08.25 07:12:05",26207.45,26188.88,11.52,26188.88,249.41,-249.42,0,0,-249.42,0,-221.61,0,"UNKNOWN","DEAL_REASON_SL"),
    (5,"US100","BUY","2026.08.25 07:13:11","2026.08.25 07:16:05",29201.60,29200.89,10.53,29178.00,248.51,-7.48,0,0,-7.48,80.55,-58.97,.32419,"UNKNOWN","DEAL_REASON_SL"),
    (6,"XAUUSD.r","SELL","2026.08.25 07:40:11","2026.08.25 08:23:49",4637.08,4637.31,.31,4644.88,243.66,-7.13,-1.86,0,-8.99,500.03,-111.29,2.06923,"2026.08.25 07:55:10","DEAL_REASON_SL"),
    (7,"XAGUSD.r","SELL","2026.08.25 08:24:41","2026.08.25 08:30:01",68.196,68.049,.28,68.372,248.08,205.80,-1.68,0,204.12,228.20,-64.40,.92591,"2026.08.25 08:28:30","DEAL_REASON_EXPERT"),
    (8,"US100","BUY","2026.08.25 09:26:21","2026.08.25 11:09:43",29257.35,29256.28,6.98,29221.46,248.77,-7.47,0,0,-7.47,686.83,-14.66,2.76122,"2026.08.25 09:34:10","DEAL_REASON_SL"),
    (9,"GER40","BUY","2026.08.25 10:30:01","2026.08.25 10:43:49",26333.45,26332.74,9.04,26309.74,249.96,-7.49,0,0,-7.49,258.31,0,1.03319,"2026.08.25 10:36:20","DEAL_REASON_SL"),
    (10,"GER40","BUY","2026.08.25 10:43:50","2026.08.25 11:02:27",26332.45,26331.74,9.03,26308.74,249.68,-7.48,0,0,-7.48,205.34,-5.27,.82234,"2026.08.25 10:49:40","DEAL_REASON_SL"),
    (11,"GER40","BUY","2026.08.25 11:03:11","2026.08.25 11:05:03",26320.45,26319.81,10.03,26300.13,249.35,-7.49,0,0,-7.49,87.73,0,.35171,"UNKNOWN","DEAL_REASON_SL"),
    (12,"GER40","BUY","2026.08.25 11:25:51","2026.08.25 12:10:36",26311.45,26312.05,7.42,26283.70,248.72,5.19,0,0,5.19,263.90,-47.59,1.06103,"2026.08.25 11:46:50","DEAL_REASON_SL"),
    (13,"US100","BUY","2026.08.25 12:21:20","2026.08.25 12:32:23",29323.35,29294.33,8.58,29294.33,248.99,-248.99,0,0,-248.99,33.46,-236.81,.13438,"UNKNOWN","DEAL_REASON_SL"),
    (14,"XAUUSD.r","SELL","2026.08.25 14:00:41","2026.08.25 14:26:32",4616.74,4628.41,.21,4628.41,246.33,-245.07,-1.26,0,-246.33,12.39,-238.77,.05054,"UNKNOWN","DEAL_REASON_SL"),
]


def protected_floor(peak_r: float) -> float:
    if peak_r < .50: return -1.0
    if peak_r < .75: return -.05
    if peak_r < 1.0: return .10
    return max(.25, peak_r - max(.75, .40 * peak_r))


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def parse_dt(value: str) -> datetime:
    return datetime.strptime(value, "%Y.%m.%d %H:%M:%S")


def load_entries(path: Path) -> dict[tuple[str, str], dict[str, str]]:
    found = {}
    with path.open(newline="", encoding="ascii") as stream:
        for row in csv.DictReader(stream):
            if row["order_attempt_status"] == "BROKER_ORDER_SUBMITTED" and row["utc"] >= "2026.08.25 03:18:36":
                found[(row["utc"], row["resolved_broker_symbol"])] = row
    return found


def load_entry_context(path: Path) -> dict[tuple[str, str], dict[str, str]]:
    found = {}
    with path.open(newline="", encoding="ascii") as stream:
        for row in csv.DictReader(stream):
            if row["event"] == "ENTRY" and row["utc"] >= "2026.08.25 03:18:36":
                found[(row["utc"], row["symbol"])] = row
    return found


def write_outputs(snapshot: Path, output: Path) -> None:
    scan_path = snapshot / "runtime-common/scan-history-v3-20260825.csv"
    evidence_path = snapshot / "runtime-common/evidence.csv"
    entries = load_entries(scan_path)
    contexts = load_entry_context(evidence_path)
    output.mkdir(parents=True, exist_ok=True)
    rows = []
    prior_by_symbol = {}
    for trade in TRADES:
        (number,symbol,direction,entry_utc,exit_utc,entry_price,exit_price,lot,initial_sl,risk,
         gross,commission,swap,net,mfe,mae,peak_r,runner_utc,exit_reason) = trade
        scan = entries[(entry_utc, symbol)]
        context = contexts[(entry_utc, symbol)]
        atr = float(scan["raw_spread"]) / (float(scan["spread_to_m5_atr_percent"]) / 100.0)
        signed = 1 if direction == "BUY" else -1
        m5_extension = signed * (float(scan["entry"]) - float(scan["m5_invalidation_swing"])) / atr
        previous = prior_by_symbol.get(symbol)
        churn = bool(previous and (parse_dt(entry_utc) - parse_dt(previous["exit_timestamp_utc"])).total_seconds() < 1800)
        floor_r = protected_floor(peak_r)
        lower_bound = net if floor_r < -0.5 else max(net, floor_r * risk + commission)
        replay = "REJECT_SAME_SYMBOL_CHURN" if churn else "RETAIN_ENTRY_AND_APPLY_MONOTONIC_PROTECTION"
        replay_net = 0.0 if churn else lower_bound
        row = {
            "trade": number, "symbol": symbol, "direction": direction,
            "entry_timestamp_utc": entry_utc, "entry_price": entry_price, "lot": lot,
            "initial_sl": initial_sl, "initial_dollar_risk": risk, "initial_r": 1.0,
            "entry_score": float(scan["score"]), "no_trade_score": float(scan["no_trade_score"]),
            "m5_state": context["m5"], "m15_state": context["m15"],
            "recent_swing_structure": context["levels"],
            "movement_before_signal": "UNKNOWN_RAW_PRE_SIGNAL_TICK_PATH_NOT_RETAINED",
            "movement_before_first_confirmation": "UNKNOWN_OLD_CONFIRMATION_NOT_SETUP_SPECIFIC",
            "movement_before_second_confirmation": "UNKNOWN_OLD_CONFIRMATION_NOT_SETUP_SPECIFIC",
            "distance_already_travelled_before_entry": "UNKNOWN_RAW_PRE_SIGNAL_TICK_PATH_NOT_RETAINED",
            "m5_atr_normalized_extension": round(m5_extension, 6),
            "m15_atr_normalized_extension": "UNKNOWN_ATR15_NOT_RETAINED_IN_AUDIT",
            "opposing_structure_reward_r": float(scan["reward_r"]),
            "spread": float(scan["raw_spread"]), "spread_points": float(scan["spread_points"]),
            "expected_cost_move": float(scan["expected_cost_move"]),
            "expected_net_move": float(scan["expected_net_move"]),
            "mfe_dollars": mfe, "mfe_r": peak_r, "mae_dollars": mae,
            "mae_r": round(mae / risk, 6), "runner_mode_timestamp_utc": runner_utc,
            "peak_price": "UNKNOWN_NOT_RETAINED", "peak_mfe": mfe,
            "stop_modifications": 0, "protected_dollars": 0.0, "protected_r": 0.0,
            "exit_timestamp_utc": exit_utc, "exit_price": exit_price, "exit_reason": exit_reason,
            "realized_pl": net, "gross_pl": gross, "commission": commission, "swap": swap,
            "holding_seconds": int((parse_dt(exit_utc)-parse_dt(entry_utc)).total_seconds()),
            "same_symbol_previous_trade": previous["trade"] if previous else "NONE",
            "same_symbol_next_trade": "PENDING", "reentry_reason": "NEW_SCORE_SETUP_ID_ONLY" if previous else "NOT_REENTRY",
            "setup_id": int(scan["setup_key"]),
            "final_capture_ratio": round(max(0.0, net) / mfe, 6) if mfe > 0 else 0.0,
            "corrected_floor_r": floor_r, "corrected_replay_action": replay,
            "corrected_replay_net_lower_bound": round(replay_net, 2),
        }
        if previous:
            previous["same_symbol_next_trade"] = number
        prior_by_symbol[symbol] = row
        rows.append(row)

    csv_path = output / "all-14-trades.csv"
    with csv_path.open("w", newline="", encoding="utf-8") as stream:
        writer = csv.DictWriter(stream, fieldnames=list(rows[0]))
        writer.writeheader(); writer.writerows(rows)

    original_net = sum(r["realized_pl"] for r in rows)
    original_mfe = sum(r["mfe_dollars"] for r in rows)
    replay_net = sum(r["corrected_replay_net_lower_bound"] for r in rows)
    old_positive_capture = sum(max(0.0, r["realized_pl"]) for r in rows) / original_mfe if original_mfe else 0.0
    old_net_capture = original_net / original_mfe if original_mfe else 0.0
    protected_trades = [r for r in rows if r["corrected_floor_r"] >= -0.5 and not r["corrected_replay_action"].startswith("REJECT")]
    replay_capture = sum(max(0.0, r["corrected_replay_net_lower_bound"]) for r in rows) / original_mfe
    summary = {
        "schema": "SOLTRADE_FAST_MULTI_V2_20260825_FORENSIC_REPLAY_V1",
        "snapshot_sha256sums_sha256": sha256(snapshot / "SHA256SUMS"),
        "source_inputs": {str(scan_path): sha256(scan_path), str(evidence_path): sha256(evidence_path)},
        "trade_count": len(rows), "wins": sum(r["realized_pl"] > 0 for r in rows),
        "losses": sum(r["realized_pl"] < 0 for r in rows), "original_net": round(original_net, 2),
        "total_mfe": round(original_mfe, 2),
        "old_session_net_to_mfe_ratio": round(old_net_capture, 6),
        "old_positive_realized_to_mfe_ratio": round(old_positive_capture, 6),
        "old_same_symbol_churn_reentries": sum(r["corrected_replay_action"].startswith("REJECT") for r in rows),
        "corrected_same_symbol_churn_reentries": 0,
        "corrected_replay_retained_trades": sum(not r["corrected_replay_action"].startswith("REJECT") for r in rows),
        "corrected_replay_net_lower_bound": round(replay_net, 2),
        "corrected_replay_positive_mfe_capture_ratio": round(replay_capture, 6),
        "monotonic_protection_applied_trade_count": len(protected_trades),
        "limitations": [
            "Raw tick streams and exact peak prices were not retained; exact tick-by-tick historical reconstruction is impossible.",
            "The replay uses recorded broker fills, recorded 10-second decision audit state, recorded MFE/MAE, and a deterministic protection floor.",
            "The replay result is a failure-envelope lower bound, not an exact counterfactual fill or a profitability claim.",
            "New setup-specific 30-second confirmation can only be proven prospectively because the old audit did not preserve its state fields."
        ],
    }
    json_path = output / "replay-summary.json"
    json_path.write_text(json.dumps(summary, indent=2) + "\n", encoding="utf-8")

    lines = [
        "# SolTrade Fast Multi Market V2 — 25 August 2026 forensic reconstruction",
        "", "## Evidence boundary", "",
        "This report uses the immutable broker/log/scan snapshot. Missing raw tick paths are explicitly `UNKNOWN`; no future data was substituted.",
        "", "## Session totals", "",
        f"- 14 trades: {summary['wins']} wins, {summary['losses']} losses.",
        f"- Realized net: ${summary['original_net']:.2f}.",
        f"- Recorded aggregate MFE: ${summary['total_mfe']:.2f}.",
        f"- Session net/MFE ratio: {summary['old_session_net_to_mfe_ratio']:.2%}; positive-realized/MFE capture: {summary['old_positive_realized_to_mfe_ratio']:.2%}.",
        f"- Same-symbol entries within 30 minutes: {summary['old_same_symbol_churn_reentries']}; corrected replay: 0.",
        f"- Corrected failure-envelope replay: ${summary['corrected_replay_net_lower_bound']:.2f}; positive-MFE capture {summary['corrected_replay_positive_mfe_capture_ratio']:.2%}.",
        "", "The corrected figure is not a backtest or profit promise. It proves only that the recorded +1R/+2R/+2.76R failure cases are bounded by monotonic protection and that rapid churn is blocked.",
        "", "## Root causes", "",
        "1. Runner protection advanced only when a conservative M5/M15 structural trail was already beyond entry. Recorded runners therefore retained `PROTECTED_R=0` and `TRAIL_UPDATES=0` even after +2.76R.",
        "2. The +0.25R branch moved the stop to entry minus 0.03R, deliberately allowing a winner to become a small net loss.",
        "3. Entry persistence counted direction across bars, not a stable setup identity. A new setup could inherit an old count and enter immediately.",
        "4. Re-entry rejected only the exact prior setup key; changed score/setup IDs allowed retries one second to minutes after an exit.",
        "5. Exit evidence used the current score direction instead of held-position direction, corrupting interpretation without changing broker execution.",
        "6. The entry cost gate included spread, slippage allowance and observed/fallback commission, but repeated churn multiplied those costs.",
        "", "## Fourteen-trade table", "",
        "|#|Symbol|Dir|Entry UTC|Exit UTC|Risk $|MFE $ / R|MAE $ / R|Net $|Replay action|Replay lower bound $|",
        "|---:|---|---|---|---|---:|---:|---:|---:|---|---:|",
    ]
    for r in rows:
        lines.append(f"|{r['trade']}|{r['symbol']}|{r['direction']}|{r['entry_timestamp_utc']}|{r['exit_timestamp_utc']}|{r['initial_dollar_risk']:.2f}|{r['mfe_dollars']:.2f} / {r['mfe_r']:.3f}|{r['mae_dollars']:.2f} / {r['mae_r']:.3f}|{r['realized_pl']:.2f}|{r['corrected_replay_action']}|{r['corrected_replay_net_lower_bound']:.2f}|")
    lines += ["", "Every requested per-trade field, including explicit `UNKNOWN` values, is in `all-14-trades.csv`.",
              "", "## Limitations", ""] + [f"- {item}" for item in summary["limitations"]]
    report_path = output / "forensic-report.md"
    report_path.write_text("\n".join(lines) + "\n", encoding="utf-8")

    manifest = output / "SHA256SUMS"
    manifest.write_text("\n".join(f"{sha256(path)}  {path.name}" for path in (csv_path,json_path,report_path)) + "\n", encoding="utf-8")
    print(json.dumps(summary, indent=2))


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--snapshot", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    write_outputs(args.snapshot, args.output)


if __name__ == "__main__":
    main()
