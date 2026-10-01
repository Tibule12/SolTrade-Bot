#!/usr/bin/env python3
"""Publish account-by-arm completion and exactness coverage without imputation."""

import csv
import json
from collections import Counter
from pathlib import Path

from tools.three_account_completion.replay import ARM_MATRIX_COLUMNS

ROOT = Path(__file__).resolve().parents[2]
PRIOR = ROOT / "reports/fast-multi-market-v2/three-account-replay-20261001"
OUT = ROOT / "reports/fast-multi-market-v2/three-account-replay-completion-20261001"

EXTRA_COLUMNS = ("last_observed_account_balance", "last_observed_balance_basis", "eligibility_basis")


def read_csv(path):
    with path.open(newline="") as stream:
        return list(csv.DictReader(stream))


def load():
    previous = read_csv(PRIOR / "account-arm-matrix.csv")
    coverage = read_csv(OUT / "fp-arm-trade-coverage.csv")
    native = read_csv(OUT / "native-opposite/native-opposite-stops.csv")
    if len(coverage) != 29 or len(native) != 29:
        raise ValueError("FP alternative evidence must cover all 29 recorded entries")
    native_ids = {row["position_id"] for row in native}
    if native_ids != {row["position_id"] for row in coverage}:
        raise ValueError("FP native stops and tick paths disagree by position")
    prior_baseline = json.loads((PRIOR / "baseline-replay.json").read_text())
    fx = json.loads((PRIOR / "fxify-event-diagnostic.json").read_text())["accounts"]
    fx_10k_broker = json.loads((OUT / "fxify-10k-broker-reconciliation.json").read_text())
    return previous, coverage, prior_baseline, fx, fx_10k_broker


def build():
    previous, coverage, baseline, fx, fx_10k_broker = load()
    rows = []
    for old in previous:
        account, arm = old["account"], old["arm"]
        fp = account == "FP 7404213"
        if arm == "BASELINE_REPLAY" and fp:
            count = baseline["fp"]["closed_positions"]
            row = dict(account=account, arm=arm, opening_balance="100000.00",
                       eligible_trades=count, exact_replay_trades=count,
                       modelled_complete_trades=0, censored_trades=0, unresolved_trades=0,
                       exact_coverage_pct="100.00", broker_exact_final_balance=baseline["fp"]["final_export_balance"],
                       modelled_final_balance=None, net_cash=baseline["fp"]["trade_net_cash_since_deposit"],
                       net_r=None, max_realized_balance_dd=baseline["fp"]["max_observed_realized_balance_drawdown_cash"],
                       max_true_equity_dd=None, wins=baseline["fp"]["wins"], losses=baseline["fp"]["losses"],
                       full_stops=None, bank1r=baseline["fp"]["two_close_positions"], plus_3r=None,
                       plus_5r=None, status="BROKER_CASH_BASELINE_EXACT_EQUITY_UNOBSERVED",
                       first_ambiguity_trade=None,
                       missing_evidence="FLOATING_EQUITY_AND_COMPLETE_STOP_RISK_MARKS",
                       last_observed_account_balance=baseline["fp"]["final_export_balance"],
                       last_observed_balance_basis="FRESH_FP_BROKER_DEAL_EXPORT_2026_10_01_11_09_50_UTC",
                       eligibility_basis="ALL_103_BROKER_CLOSED_FP_POSITIONS")
        elif arm == "BASELINE_REPLAY" and account == "FXIFY 7196820":
            b = fx_10k_broker
            row = dict(account=account, arm=arm, opening_balance=b["initial_deposit"],
                       eligible_trades=b["closed_positions"], exact_replay_trades=b["closed_positions"],
                       modelled_complete_trades=0, censored_trades=0, unresolved_trades=0,
                       exact_coverage_pct="100.00", broker_exact_final_balance=b["broker_final_balance"],
                       modelled_final_balance=None, net_cash=b["broker_net_trade_cash"], net_r=None,
                       max_realized_balance_dd=b["max_observed_realized_balance_drawdown_cash"],
                       max_true_equity_dd=None, wins=b["wins"], losses=b["losses"],
                       full_stops=None, bank1r=b["two_close_positions"], plus_3r=None, plus_5r=None,
                       status="BROKER_CASH_BASELINE_EXACT_RESEARCH_PERMISSION_EXCEPTION",
                       first_ambiguity_trade=None,
                       missing_evidence="FLOATING_EQUITY_AND_COMPLETE_INTRATRADE_R_MARKS;RESEARCH_TERMINAL_PERMISSION_EXCEPTION_DISCLOSED",
                       last_observed_account_balance=b["broker_final_balance"],
                       last_observed_balance_basis="FRESH_FXIFY_10K_BROKER_DEAL_EXPORT_2026_10_01_16_39_05_UTC",
                       eligibility_basis="ALL_24_BROKER_CLOSED_10K_POSITIONS_INCLUDING_TWO_AUGUST_PILOT")
        elif arm == "BASELINE_REPLAY":
            key = "fxify-10k" if account == "FXIFY 7196820" else "fxify-100k"
            # This baseline row is the four-trade Sep 13-to-pause bridge.
            # The 22 September EA pairs belong to the broader research arms.
            observed = int(old["trades"])
            paused = fx[key]["reconciliation"]["pause_flat_equity_usd"]
            row = dict(account=account, arm=arm, opening_balance=fx[key]["reconciliation"]["baseline_flat_equity_usd"],
                       eligible_trades=observed, exact_replay_trades=0, modelled_complete_trades=0,
                       censored_trades=0, unresolved_trades=observed, exact_coverage_pct="0.00",
                       broker_exact_final_balance=None, modelled_final_balance=None,
                       net_cash=old["net_cash"], net_r=old["net_r"],
                       max_realized_balance_dd=None, max_true_equity_dd=None,
                       wins=old["wins"], losses=old["losses"], full_stops=None,
                       bank1r=None, plus_3r=None, plus_5r=None,
                       status="EA_EVENT_BASELINE_BRIDGE_ONLY_NO_INDEPENDENT_BROKER_HISTORY",
                       first_ambiguity_trade=None,
                       missing_evidence="INDEPENDENT_SEPTEMBER_DEALS_ORDERS_ACCOUNT_OPERATIONS_AND_EQUITY",
                       last_observed_account_balance=paused,
                       last_observed_balance_basis="FXIFY_SEPTEMBER_16_PAUSE_RUNTIME_FLAT_ANCHOR_NOT_CURRENT",
                       eligibility_basis="FOUR_SEPTEMBER_13_TO_16_FROZEN_MANAGER_EA_EXIT_PAIRS")
        elif arm == "PRODUCTION_SCORE_NORMAL__FROZEN_MANAGER_COHORT":
            row = dict(account=account, arm=arm, opening_balance="99579.64", eligible_trades=old["trades"],
                       exact_replay_trades=old["trades"], modelled_complete_trades=0, censored_trades=0,
                       unresolved_trades=0, exact_coverage_pct="100.00", broker_exact_final_balance=old["actual_final_balance"],
                       modelled_final_balance=None, net_cash=old["net_cash"], net_r=old["net_r"],
                       max_realized_balance_dd=None, max_true_equity_dd=None,
                       wins=old["wins"], losses=old["losses"], full_stops=old["full_stops"],
                       bank1r=old["bank1r"], plus_3r=None, plus_5r=None,
                       status="RECORDED_FP_BROKER_CASH_SUBCOHORT_EXACT_EQUITY_UNOBSERVED",
                       first_ambiguity_trade=None, missing_evidence="FLOATING_EQUITY_AND_CASH_3R_5R_MILESTONES",
                       last_observed_account_balance=old["actual_final_balance"],
                       last_observed_balance_basis="SEPTEMBER_30_FP_BROKER_BALANCE_WITH_ONE_OPEN_POSITION",
                       eligibility_basis="26_RECORDED_CLOSED_FP_TRADES_FROM_SEPTEMBER_13")
        else:
            eligible = 29 if fp else 22
            # Two FP windows were short of 24h, but one of those also lacks a
            # fresh entry quote and belongs in the unresolved-history bucket.
            censored = (sum(r["twentyfour_hour_quote_window_complete"] == "false"
                            and r["entry_anchor_status"] == "FRESH_QUOTE_WITHIN_2S"
                            for r in coverage)
                        if fp else 0)
            if fp and censored != 1:
                raise ValueError(f"Unexpected 24h censor count: {censored}")
            unresolved = eligible - censored
            missing = old["missing_for_exact_path"]
            missing = missing.replace(
                "Opposite bid/ask boundaries are observed only until actual baseline exit; right-censored cases and native runner manager prevent final-outcome accounting.",
                "Opposite bid/ask quotes now extend through entry+24h for 27/29 rows; a hypothetical position may outlive that horizon and its frozen runner path is not fully reconstructed.",
            ).replace(
                "Opposite-side M5/M15 native structural stop and complete opposite quote lifetime are unavailable.",
                "Opposite-side M5/M15 structural geometry is reconstructed for 25/29 rows, but historical broker stop/freeze floor and complete runner lifetime are unavailable.",
            ).replace(
                "Opposite fills, native stops and whole lifetime after baseline exit unavailable.",
                "Opposite bid/ask quotes extend beyond baseline exit; historical stop/freeze floor, fill, cost, runner lifetime and propagated account path remain unavailable.",
            )
            if fp:
                missing += "; 4/29 no fresh <=2s entry quote; 25/29 structural geometry reconstructed but historical broker floor unverified; full alternative Bank1R/runner/fill/ownership/cost lifetime missing"
            elif account == "FXIFY 7196820":
                missing = "Independent September deals/orders recovered and broker cash reconciled; account-specific historical bid/ask, native opposite stops, alternative fills and manager lifetime remain unavailable"
            else:
                missing += "; September FXIFY broker deals/orders/account operations and continuous bid/ask were not recovered"
            row = dict(account=account, arm=arm, opening_balance=("100000.00" if fp else
                           fx_10k_broker["september_opening_balance_after_august_pilot"] if account == "FXIFY 7196820" else None),
                       eligible_trades=eligible, exact_replay_trades=0, modelled_complete_trades=0,
                       censored_trades=censored, unresolved_trades=unresolved,
                       exact_coverage_pct=(None if "ALL_OPPORTUNITIES" in arm else "0.00"),
                       broker_exact_final_balance=None,
                       modelled_final_balance=None, net_cash=None, net_r=None,
                       max_realized_balance_dd=None, max_true_equity_dd=None,
                       wins=None, losses=None, full_stops=None, bank1r=None,
                       plus_3r=None, plus_5r=None,
                       status="INCOMPLETE_CHRONOLOGICAL_ALTERNATIVE_PATH",
                       first_ambiguity_trade=(coverage[0]["position_id"] if fp else
                                              read_csv(PRIOR / "fxify-10k-event-trades.csv")[0]["position_id"]
                                              if account == "FXIFY 7196820" else "FXIFY_100K_SEPTEMBER_BROKER_HISTORY"),
                       missing_evidence=missing,
                       last_observed_account_balance=old["actual_final_balance"],
                       last_observed_balance_basis=("FP_OCTOBER_1_BROKER_EXPORT_BASELINE_ONLY" if fp else
                                                    "FXIFY_10K_OCTOBER_1_BROKER_EXPORT_BASELINE_ONLY" if account == "FXIFY 7196820" else
                                                    "FXIFY_100K_SEPTEMBER_16_PAUSE_RUNTIME_NOT_CURRENT"),
                       eligibility_basis=("AT_LEAST_29_FP_ACTUAL_ENTRIES_TRUE_ALL_OPPORTUNITY_DENOMINATOR_UNKNOWN" if fp and "ALL_OPPORTUNITIES" in arm else
                                          "29_FP_ACTUAL_ENTRIES_WITH_24H_QUOTE_REQUESTS" if fp else
                                          "22_SEPTEMBER_EA_PAIRS_ALL_BROKER_CONFIRMED_BUT_ALTERNATIVES_UNKNOWN" if account == "FXIFY 7196820" else
                                          "22_MATCHED_SEPTEMBER_EA_ENTRY_EXIT_PAIRS_OPENING_BALANCE_UNKNOWN"))
        if int(row["eligible_trades"]) != (int(row["exact_replay_trades"]) +
                int(row["modelled_complete_trades"]) + int(row["censored_trades"]) +
                int(row["unresolved_trades"])):
            raise ValueError(f"Coverage does not partition eligibility: {account}/{arm}")
        rows.append(row)
    if len(rows) != 73 or Counter(row["account"] for row in rows) != {
        "FP 7404213": 25, "FXIFY 7196820": 24, "FXIFY 7198096": 24,
    }:
        raise ValueError("All prior accounts and arms must be retained")
    OUT.mkdir(parents=True, exist_ok=True)
    with (OUT / "account-arm-completion-matrix.csv").open("w", newline="") as stream:
        writer = csv.DictWriter(stream, fieldnames=ARM_MATRIX_COLUMNS + EXTRA_COLUMNS, lineterminator="\n")
        writer.writeheader()
        writer.writerows(rows)
    summary = {"schema": "THREE_ACCOUNT_EXACT_ARM_COMPLETION_MATRIX_V1",
               "rows": len(rows), "account_count": 3, "experimental_arms_per_account": 23,
               "counterfactual_arms_with_exact_final_balance": 0,
               "prior_arm_labels_preserved": True,
               "numeric_null_policy": "No experimental cash, R, W/L, drawdown or final balance populated without a complete chronological terminal path.",
               "baseline_fp_broker_cash_exact": True,
               "fxify_10k_independent_broker_baseline_exact": True,
               "fxify_100k_independent_broker_baseline_exact": False,
               "matrix_csv": "account-arm-completion-matrix.csv"}
    (OUT / "account-arm-completion-matrix.json").write_text(json.dumps(summary, indent=2) + "\n")
    fx_rows = []
    for login, label in (("7196820", "10k"), ("7198096", "100k")):
        for trade in read_csv(PRIOR / f"fxify-{label}-event-trades.csv"):
            fx_rows.append({
                "account": login,
                "position_id": trade["position_id"],
                "entry_utc": trade["entry_utc"],
                "symbol": trade["symbol"],
                "actual_direction": trade["direction"],
                "ea_event_net_cash": trade["net_usd"],
                "broker_baseline_status": ("BROKER_CASH_CONFIRMED" if login == "7196820" else
                                           "EA_EVENTS_ONLY"),
                "missing_broker_data": ("" if login == "7196820" else
                                        "SEPTEMBER_DEALS_ORDERS_FILL_CHARGES_AND_ACCOUNT_OPERATIONS"),
                "missing_alternative_data": "ACCOUNT_SPECIFIC_BID_ASK_NATIVE_OPPOSITE_STOP_AND_FULL_MANAGER_LIFETIME",
            })
    if len(fx_rows) != 44 or len({(r["account"], r["position_id"]) for r in fx_rows}) != 44:
        raise ValueError("Expected 22 distinct unresolved FXIFY event trades per account")
    with (OUT / "fxify-unresolved-trades.csv").open("w", newline="") as stream:
        writer = csv.DictWriter(stream, fieldnames=tuple(fx_rows[0]), lineterminator="\n")
        writer.writeheader()
        writer.writerows(fx_rows)
    return summary


if __name__ == "__main__":
    print(json.dumps(build()))
