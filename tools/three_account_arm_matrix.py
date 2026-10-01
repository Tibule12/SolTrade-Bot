#!/usr/bin/env python3
"""Explicit account-by-arm completion matrix; never fill unsupported outcomes."""

import csv
import json
from pathlib import Path

BASE = Path(__file__).resolve().parents[1] / "reports/fast-multi-market-v2/three-account-replay-20261001"

ARMS = [
    ("PRODUCTION_SCORE_INVERTED_MIRRORED_DISTANCE", "Opposite bid/ask boundaries are observed only until actual baseline exit; right-censored cases and native runner manager prevent final-outcome accounting."),
    ("PRODUCTION_SCORE_INVERTED_NATIVE_OPPOSITE_STRUCTURE", "Opposite-side M5/M15 native structural stop and complete opposite quote lifetime are unavailable."),
    ("SCORE_SWAP_NORMAL_ALL_OPPORTUNITIES", "All historical production opportunities have not been joined to account-specific executable quotes and portfolio state."),
    ("SCORE_SWAP_SWAPPED_ALL_OPPORTUNITIES", "Opposite opportunity selection changes overlaps, sizing and later decisions; complete account-specific execution paths unavailable."),
    ("SCORE_SWAP_NO_SCORE", "A fixed causal flow policy and complete alternative execution paths are required; current flow descriptor alone is insufficient."),
    ("CURRENT_FLOW_DIRECTION", "A causal flow descriptor was computed for FP entered trades only; opposite native stops and chronological alternative account path unavailable."),
    ("PRODUCTION_ONLY_IF_CURRENT_FLOW_AGREES", "Skipping trades changes future balance, risk and admissions; observed entered-trade grouping is not an exact account replay."),
    ("OPPOSITE_WHEN_CURRENT_FLOW_STRONGLY_DISAGREES", "Opposite fills, native stops and whole lifetime after baseline exit unavailable."),
    ("ENTRY_FLIP_PLAYER_V1", "Flip timing, two full executable lifetimes, new stop/sizing and costs cannot be established from current path evidence."),
    ("DUAL_SIDE_PROBE_0.10R_EACH", "Historical hedge permission, both-side fills, double charges, margin and post-promotion account state unavailable."),
    ("DUAL_SIDE_PROBE_0.20R_EACH", "Historical hedge permission, both-side fills, double charges, margin and post-promotion account state unavailable."),
    ("DUAL_SIDE_PROBE_0.25R_EACH", "Historical hedge permission, both-side fills, double charges, margin and post-promotion account state unavailable."),
    ("ORACLE_FAILURE_INVERSION__HINDSIGHT_CEILING_NOT_TRADABLE", "Even a hindsight arm needs the opposite broker-valid path and propagated account sizing; cash cannot be computed by negating actual results."),
    ("TIMING_FIRST_QUALIFICATION", "Quote price and spread sampled where present; structural stop, resulting fills, final trade management and later sizing unresolved."),
    ("TIMING_PLUS_5S", "Quote price and spread sampled where present; resulting exits and account path unresolved."),
    ("TIMING_PLUS_15S", "Quote price and spread sampled where present; resulting exits and account path unresolved."),
    ("TIMING_PLUS_30S", "Quote price and spread sampled where present; resulting exits and account path unresolved."),
    ("TIMING_PLUS_60S", "Quote price and spread sampled where present; resulting exits and account path unresolved."),
    ("M1_BANK1R_RUNNER_BE_FLOOR", "FP quote crossing diagnostic exists; historical broker-valid stop/freeze acceptance and alternate fills/charges unresolved."),
    ("M2_BANK1R_COST_ADJUSTED_BE", "Historical nonspread charge allocation and broker-valid floor/alternate fills unresolved."),
    ("M3_WHOLE_TRADE_GUARANTEE", "No frozen numerical guarantee schedule; broker-valid dynamic stop and alternate fills unresolved."),
    ("M4_PERFECT_CONTINUOUS_OWNERSHIP", "Blocked action intents lack a complete counterfactual fill/manager state and later account response."),
    ("PLUS_0.5R_TO_BE", "FP quote crossing diagnostic exists; broker-valid stop/freeze acceptance, slippage and propagated account path unresolved."),
]


def main():
    baseline = json.loads((BASE / "baseline-replay.json").read_text())
    fp_score = json.loads((BASE / "fp-score-diagnostic.json").read_text())["cohorts"]["frozen_fp_manager_from_2026_09_13"]["summary"]
    fx = json.loads((BASE / "fxify-event-diagnostic.json").read_text())["accounts"]
    fx10 = fx["fxify-10k"]["cohorts"]["bank1r_from_2026_09_13"]["summary"]
    fx100 = fx["fxify-100k"]["cohorts"]["bank1r_from_2026_09_13"]["summary"]
    fx10_reconciliation = fx["fxify-10k"]["reconciliation"]
    fx100_reconciliation = fx["fxify-100k"]["reconciliation"]
    fp_baseline = baseline["fp"]
    accounts = [
        {"account": "FP 7404213", "period": "2026-08-20 through 2026-10-01 08:57 UTC",
         "trades": fp_baseline["closed_positions"], "wins": fp_baseline["wins"], "losses": fp_baseline["losses"],
         "net_cash": float(fp_baseline["trade_net_cash_since_deposit"]), "net_r": None,
         "actual_final_balance": float(fp_baseline["final_export_balance"]),
         "max_observed_realized_balance_dd": float(fp_baseline["max_observed_realized_balance_drawdown_cash"]),
         "baseline_status": "EXACT_BROKER_CASH_AND_POSITION_PATH; EQUITY_DD_UNOBSERVED",
         "baseline_missing": "Historical floating equity and complete risk marks are missing."},
        {"account": "FXIFY 7196820", "period": "2026-09-13 flat baseline through 2026-09-16 pause",
         "trades": fx10["n"], "wins": fx10["wins"], "losses": fx10["losses"],
         "net_cash": float(fx10["net_usd"]), "net_r": fx10["net_r"],
         "actual_final_balance": float(fx10_reconciliation["pause_flat_equity_usd"]),
         "max_observed_realized_balance_dd": abs(float(fx10["net_usd"])),
         "baseline_status": "EA_EVENT_CASH_BRIDGE_RECONCILES; NO_INDEPENDENT_BROKER_LEDGER",
         "baseline_missing": "Independent broker deal/order history, full inception cashflows and equity path are missing."},
        {"account": "FXIFY 7198096", "period": "2026-09-13 flat baseline through 2026-09-16 pause",
         "trades": fx100["n"], "wins": fx100["wins"], "losses": fx100["losses"],
         "net_cash": float(fx100["net_usd"]), "net_r": fx100["net_r"],
         "actual_final_balance": float(fx100_reconciliation["pause_flat_equity_usd"]),
         "max_observed_realized_balance_dd": abs(float(fx100["net_usd"])),
         "baseline_status": "EA_EVENT_CASH_BRIDGE_RECONCILES; NO_INDEPENDENT_BROKER_LEDGER",
         "baseline_missing": "Independent broker deal/order history, full inception cashflows and equity path are missing."},
    ]
    rows = []
    for account in accounts:
        rows.append({"account": account["account"], "arm": "BASELINE_REPLAY", "period": account["period"],
                     "status": account["baseline_status"], "trades": account["trades"],
                     "wins": account["wins"], "losses": account["losses"],
                     "net_r": account["net_r"], "net_cash": account["net_cash"],
                     "max_true_equity_dd": None,
                     "max_observed_realized_balance_dd": account["max_observed_realized_balance_dd"],
                     "full_stops": (fx10["full_structural_losses"] if account["account"] == "FXIFY 7196820" else
                                    fx100["full_structural_losses"] if account["account"] == "FXIFY 7198096" else None),
                     "bank1r": (fx10["confirmed_bank1r"] if account["account"] == "FXIFY 7196820" else
                                fx100["confirmed_bank1r"] if account["account"] == "FXIFY 7198096" else None),
                     "plus_3r": None, "plus_5r": None,
                     "actual_final_balance": account["actual_final_balance"],
                     "counterfactual_final_balance": None,
                     "missing_for_exact_path": account["baseline_missing"]})
        if account["account"].startswith("FP"):
            rows.append({"account": account["account"], "arm": "PRODUCTION_SCORE_NORMAL__FROZEN_MANAGER_COHORT",
                         "period": "2026-09-13 flat baseline through 2026-09-30 visual anchor",
                         "status": "ACTUAL_ADMITTED_TRADES__BROKER_NET_RECONCILED", "trades": fp_score["n"],
                         "wins": fp_score["wins"], "losses": fp_score["losses"],
                         "net_r": round(fp_score["total_r"], 5), "net_cash": round(fp_score["total_cash"], 2),
                         "max_true_equity_dd": None, "max_observed_realized_balance_dd": None,
                         "full_stops": fp_score["full_stop_losses"],
                         "bank1r": fp_score["confirmed_bank1r"],
                         "plus_3r": None, "plus_5r": None,
                         "actual_final_balance": float(fp_baseline["september_30_visual_anchor"]["balance"]),
                         "counterfactual_final_balance": None,
                         "missing_for_exact_path": "Price peaks are not cash +3R/+5R; historical equity curve missing."})
        for arm, reason in ARMS:
            rows.append({"account": account["account"], "arm": arm, "period": account["period"],
                         "status": "UNRESOLVED_EXACT_ACCOUNT_PATH", "trades": None, "wins": None,
                         "losses": None, "net_r": None, "net_cash": None, "max_true_equity_dd": None,
                         "max_observed_realized_balance_dd": None,
                         "full_stops": None, "bank1r": None, "plus_3r": None, "plus_5r": None,
                         "actual_final_balance": account["actual_final_balance"],
                         "counterfactual_final_balance": None,
                         "missing_for_exact_path": ("FXIFY broker deals and continuous quotes unavailable; " if account["account"].startswith("FXIFY") else "") + reason})
    with (BASE / "account-arm-matrix.csv").open("w", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=list(rows[0]))
        writer.writeheader()
        writer.writerows(rows)
    output = {"schema": "SOLTRADE_ACCOUNT_ARM_MATRIX_V1", "rows": len(rows),
              "matrix_csv": "account-arm-matrix.csv",
              "interpretation": "Null is not zero. Only observed baseline cash paths are populated; no experimental account balance is fabricated. Normalized R is populated only where recorded initial risk exists. Price-peak milestones are omitted from cash Bank1R/+3R/+5R columns.",
              "account_count": 3, "experimental_arm_count_per_account": len(ARMS)}
    (BASE / "account-arm-matrix.json").write_text(json.dumps(output, indent=2) + "\n")
    print(json.dumps(output))


if __name__ == "__main__":
    main()
