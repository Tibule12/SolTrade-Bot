#!/usr/bin/env python3
"""Rank observed loss mechanisms without inventing counterfactual causal savings."""

import csv
import json
from collections import defaultdict
from pathlib import Path

BASE = Path(__file__).resolve().parents[1] / "reports/fast-multi-market-v2/three-account-replay-20261001"


def read(path):
    with path.open(newline="") as handle:
        return list(csv.DictReader(handle))


def run():
    flow = {r["position_id"]: r for r in read(BASE / "fp-current-flow-entries.csv")}
    cases = []
    sources = [
        ("FP 7404213", BASE / "fp-score-trades.csv", "net_cash", "final_r"),
        ("FXIFY 7196820", BASE / "fxify-10k-event-trades.csv", "net_usd", "net_r"),
        ("FXIFY 7198096", BASE / "fxify-100k-event-trades.csv", "net_usd", "net_r"),
    ]
    for account, path, cash_field, r_field in sources:
        for trade in read(path):
            net = float(trade[cash_field])
            if net >= 0:
                continue
            label = trade["exit_class"]
            layers = []
            if label == "PRE_BANK_GIVEBACK_FAILED":
                layers.append("PRE_BANK_GIVEBACK")
            if label in ("RUNNER_STRUCTURAL_EXIT", "PROTECTED_STOP_EXIT") and trade.get("bank1_confirmed") == "True":
                layers.append("POST_BANK_GIVEBACK")
            observed_flow = flow.get(trade["position_id"]) if account.startswith("FP") else None
            if observed_flow and observed_flow["flow_agrees"] == "False":
                layers.append("CURRENT_FLOW_CONFLICT")
            # A stop hit demonstrates the exit mechanism, not a wrong-direction cause.
            if not layers:
                layers.append("UNRESOLVED_DATA")
            cases.append({
                "account": account, "position_id": trade["position_id"], "entry_utc": trade["entry_utc"],
                "symbol": trade["symbol"], "direction": trade["direction"],
                "manager_cohort": "FROZEN_BANK1R_FROM_SEP13" if trade["entry_utc"] >= "2026.09.13" else "EARLIER_MIXED_MANAGER",
                "observed_exit_class": label,
                "observed_loss_cash": -net, "observed_loss_r": -float(trade[r_field]),
                "supported_observation_labels": "|".join(layers),
                "causal_counterfactual_savings_proven": False,
                "what_would_fix_this": "UNRESOLVED_COUNTERFACTUAL",
                "evidence_source": str(path.relative_to(BASE.parent.parent.parent)),
            })
    cases.sort(key=lambda x: (x["entry_utc"], x["account"], x["position_id"]))
    with (BASE / "per-loss-attribution.csv").open("w", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=list(cases[0]))
        writer.writeheader()
        writer.writerows(cases)
    groups = defaultdict(list)
    for case in cases:
        if case["manager_cohort"] == "FROZEN_BANK1R_FROM_SEP13":
            groups[(case["account"], case["observed_exit_class"])].append(case)
    ledger = [{
        "account": account, "observed_exit_class": exit_class, "loss_positions": len(group),
        "observed_loss_cash": round(sum(x["observed_loss_cash"] for x in group), 2),
        "observed_loss_r": round(sum(x["observed_loss_r"] for x in group), 5),
        "counterfactual_recoverable_cash": None,
        "reversibility": "UNPROVEN_BY_BASELINE_OUTCOME",
    } for (account, exit_class), group in groups.items()]
    ledger.sort(key=lambda x: -x["observed_loss_cash"])
    output = {
        "schema": "SOLTRADE_OBSERVED_FAILURE_LEDGER_V1",
        "scope": "Losses with matched EA ENTRY/EXIT evidence. Ranked frozen post-Sep13 manager cohort; earlier mixed managers remain in per-loss CSV.",
        "interpretation": "Observed loss cash is the money lost in recorded closes, not estimated recoverable savings. A structural-stop loss does not prove direction was wrong; score, timing and ownership causal attributions need complete opposite/alternate paths. CURRENT_FLOW_CONFLICT records a pre-entry quote state but does not prove it caused the loss.",
        "frozen_cohort_ranked_observed_loss_mechanisms": ledger,
        "unrankable_in_cash": [
            {"layer": "OWNERSHIP_BLOCK", "reason": "Blocked action logs lack a complete counterfactual broker quote/fill and later account response; exact incremental P&L unresolved."},
            {"layer": "POST_BANK_GIVEBACK", "reason": "Price peak R and actual cash R have different accounting; a broker-valid alternate stop/fill is not established."},
            {"layer": "SCORE_POLARITY_ERROR", "reason": "Opposite native structural stops, post-baseline quote lifetime and account-path propagation are unresolved."},
        ],
    }
    (BASE / "engineering-failure-ledger.json").write_text(json.dumps(output, indent=2) + "\n")
    print(json.dumps({"loss_rows": len(cases), "ranked_frozen_mechanisms": ledger}))


if __name__ == "__main__":
    run()
