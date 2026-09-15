#!/usr/bin/env python3
"""Development-only chronological evaluation for ENTRY_ENGINE_V2.

This program deliberately has no holdout path and imports no September trade
artifact.  It either emits a frozen deployable model or a statistical stop
showing that the current directional generator has not supplied separable
entry opportunities.
"""
from __future__ import annotations

import csv
import json
import math
import random
import statistics
from collections import Counter, defaultdict
from pathlib import Path
from typing import Any

import numpy as np

from entry_engine_v2_common import FEATURES, fit_logistic, number

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "reports/fast-multi-market-v2/entry-engine-v2-clean-rebuild-20260915"
MONTHS = ("2026.05", "2026.06", "2026.07", "2026.08")


def read_rows() -> list[dict[str, str]]:
    rows: list[dict[str, str]] = []
    for name in ("development-dataset-april-may.csv", "development-dataset-june-august.csv"):
        with (OUT / name).open(newline="", encoding="utf-8") as handle:
            rows.extend(csv.DictReader(handle))
    return sorted(rows, key=lambda row: row["entry_utc"])


def won(row: dict[str, Any]) -> bool:
    return row["primary_label"] == "WIN_1R_BEFORE_STOP"


def max_drawdown(rows: list[dict[str, Any]]) -> float:
    balance = peak = drawdown = 0.0
    for row in sorted(rows, key=lambda value: value["entry_utc"]):
        balance += 1.0 if won(row) else -1.0
        peak = max(peak, balance)
        drawdown = max(drawdown, peak - balance)
    return drawdown


def auc(pairs: list[tuple[float, dict[str, Any]]]) -> float:
    positive = [p for p, row in pairs if won(row)]
    negative = [p for p, row in pairs if not won(row)]
    if not positive or not negative:
        return 0.5
    return sum(1.0 if a > b else 0.5 if a == b else 0.0 for a in positive for b in negative) / (len(positive) * len(negative))


def metrics(scored: list[tuple[float, dict[str, Any]]], threshold: float, wait_width: float) -> dict[str, Any]:
    entered = [row for score, row in scored if score >= threshold]
    waited = [row for score, row in scored if threshold - wait_width <= score < threshold]
    rejected = [row for score, row in scored if score < threshold - wait_width]
    wins, losses = sum(map(won, entered)), sum(not won(row) for row in entered)
    wait_wins, wait_losses = sum(map(won, waited)), sum(not won(row) for row in waited)
    reject_wins, reject_losses = sum(map(won, rejected)), sum(not won(row) for row in rejected)
    all_wins = sum(map(won, (row for _, row in scored)))
    all_losses = len(scored) - all_wins
    symbols = Counter(row["symbol"] for row in entered)
    symbol_r = defaultdict(float)
    for row in entered:
        symbol_r[row["symbol"]] += 1.0 if won(row) else -1.0
    return {
        "available": len(scored), "enter": len(entered), "wait": len(waited), "reject": len(rejected),
        "entered_winners": wins, "entered_losses": losses, "entered_net_r": float(wins - losses),
        "waited_winners": wait_wins, "waited_losses": wait_losses, "waited_net_r": float(wait_wins-wait_losses),
        "rejected_winners": reject_wins, "rejected_losses": reject_losses, "rejected_net_r": float(reject_wins-reject_losses),
        "mean_entered_r": (wins - losses) / len(entered) if entered else None,
        "winner_retention": wins / all_wins if all_wins else None,
        "loss_rejection": reject_losses / all_losses if all_losses else None,
        "winner_rejection": reject_wins / all_wins if all_wins else None,
        "max_drawdown_r": max_drawdown(entered), "auc": auc(scored),
        "accepted_symbols": dict(symbols),
        "largest_symbol_share": max(symbols.values(), default=0) / len(entered) if entered else None,
        "net_r_without_best_symbol": (wins - losses) - max(symbol_r.values(), default=0.0),
    }


def train_stumps(rows: list[dict[str, Any]], count: int = 5) -> list[dict[str, Any]]:
    x = np.asarray([[number(row[name]) for name in FEATURES] for row in rows])
    y = np.asarray([1 if won(row) else -1 for row in rows])
    weights = np.ones(len(rows)) / len(rows)
    result = []
    for _ in range(count):
        best = None
        for index, name in enumerate(FEATURES):
            for split in np.unique(np.quantile(x[:, index], [.15, .30, .45, .55, .70, .85])):
                for polarity in (-1, 1):
                    prediction = np.where(x[:, index] >= split, polarity, -polarity)
                    error = float(weights[prediction != y].sum())
                    candidate = (error, index, name, float(split), polarity, prediction)
                    if best is None or candidate[:5] < best[:5]:
                        best = candidate
        error, index, name, split, polarity, prediction = best
        error = max(1e-6, min(.499999, error))
        alpha = .5 * math.log((1 - error) / error)
        result.append({"feature": name, "split": split, "polarity": polarity, "alpha": alpha})
        weights *= np.exp(-alpha * y * prediction); weights /= weights.sum()
    return result


def stump_score(model: list[dict[str, Any]], row: dict[str, Any]) -> float:
    return sum(tree["alpha"] * (tree["polarity"] if number(row[tree["feature"]]) >= tree["split"] else -tree["polarity"]) for tree in model)


def chronological(rows: list[dict[str, Any]], kind: str, parameter: float, threshold: float) -> dict[str, Any]:
    scored: list[tuple[float, dict[str, Any]]] = []
    folds = []
    models = []
    for month in MONTHS:
        training = [row for row in rows if row["entry_utc"][:7] < month]
        validation = [row for row in rows if row["entry_utc"][:7] == month]
        if kind == "RIDGE_LOGISTIC":
            model = fit_logistic(training, parameter)
            values = [(model.probability({name: number(row[name]) for name in FEATURES}), row) for row in validation]
            models.append(model.payload())
            wait_width = .10
        else:
            model = train_stumps(training, int(parameter))
            values = [(stump_score(model, row), row) for row in validation]
            models.append(model)
            wait_width = .25
        fold = metrics(values, threshold, wait_width)
        fold.update({"month": month, "training_count": len(training)})
        folds.append(fold); scored.extend(values)
    overall = metrics(scored, threshold, .10 if kind == "RIDGE_LOGISTIC" else .25)
    baseline = metrics([(1.0, row) for _, row in scored], 0.0, 0.0)
    stable = all(fold["entered_net_r"] >= 0 and fold["enter"] >= 8 for fold in folds)
    gates = {
        "positive_oof_expectancy": overall["entered_net_r"] > 0 and overall["mean_entered_r"] > 0,
        "loss_rejection_exceeds_winner_rejection_by_10pct": overall["loss_rejection"] >= overall["winner_rejection"] + .10,
        "winner_retention_at_least_50pct": overall["winner_retention"] >= .50,
        "at_least_60_entered_resolved": overall["enter"] >= 60,
        "nonnegative_every_month_and_at_least_8_entries": stable,
        "drawdown_not_worse_than_baseline": overall["max_drawdown_r"] <= baseline["max_drawdown_r"],
        "largest_symbol_below_50pct": overall["largest_symbol_share"] < .50,
        "positive_without_best_symbol": overall["net_r_without_best_symbol"] > 0,
        "positive_after_removing_one_winner": overall["entered_net_r"] - 1 > 0,
    }
    return {"kind": kind, "parameter": parameter, "enter_threshold": threshold,
            "wait_width": .10 if kind == "RIDGE_LOGISTIC" else .25, "folds": folds,
            "oof": overall, "baseline_oof": baseline, "gates": gates, "passed": all(gates.values()),
            "fold_models": models}


def wilson(wins: int, total: int, z: float = 1.96) -> tuple[float, float]:
    p = wins / total; den = 1 + z*z/total; center = (p + z*z/(2*total))/den
    width = z*math.sqrt(p*(1-p)/total + z*z/(4*total*total))/den
    return center-width, center+width


def bootstrap_mean_ci(rows: list[dict[str, Any]], iterations: int = 20000) -> tuple[float, float]:
    rng = random.Random(20260915)
    values = [1.0 if won(row) else -1.0 for row in rows]
    means = sorted(sum(rng.choice(values) for _ in values) / len(values) for _ in range(iterations))
    return means[int(.025*iterations)], means[int(.975*iterations)]


def feature_stability(rows: list[dict[str, Any]]) -> list[dict[str, Any]]:
    result = []
    months = ("2026.04",) + MONTHS
    for feature in FEATURES:
        aucs = []
        for month in months:
            sample = [row for row in rows if row["entry_utc"][:7] == month]
            aucs.append(auc([(number(row[feature]), row) for row in sample]))
        result.append({"feature": feature, "monthly_auc": dict(zip(months, aucs)),
                       "direction_stable": all(value >= .5 for value in aucs) or all(value <= .5 for value in aucs),
                       "mean_absolute_auc": statistics.mean(max(value, 1-value) for value in aucs)})
    return result


def shadow_generator() -> dict[str, Any]:
    path = ROOT / "reports/fast-multi-market-v2/shadow-admission-20260827/post-decision-outcomes.csv"
    with path.open(newline="", encoding="utf-8-sig") as handle:
        rows = [row for row in csv.DictReader(handle) if row["episode_anchor"] == "True" and row["window_60m_status"] == "COMPLETE"]
    wins = [row for row in rows if number(row["mfe_before_theoretical_stop_60m_r"]) >= 1]
    losses = [row for row in rows if row["theoretical_stop_hit"] == "True" and row not in wins]
    return {"episodes": len(rows), "resolved": len(wins)+len(losses), "wins": len(wins), "losses": len(losses),
            "censored": len(rows)-len(wins)-len(losses), "resolved_net_r": len(wins)-len(losses),
            "resolved_mean_r": (len(wins)-len(losses))/(len(wins)+len(losses))}


def main() -> int:
    all_rows = read_rows()
    resolved = [row for row in all_rows if row["primary_label"] != "CENSORED_NO_BOUNDARY"]
    experiments = []
    for l2 in (.3, 1.0, 3.0, 10.0, 30.0):
        for threshold in (.40, .45, .50, .55, .60, .65):
            experiments.append(chronological(resolved, "RIDGE_LOGISTIC", l2, threshold))
    for trees in (3, 5, 8, 12):
        for threshold in (-.50, 0.0, .25, .50):
            experiments.append(chronological(resolved, "SHALLOW_STUMP_ENSEMBLE", trees, threshold))
    passed = [item for item in experiments if item["passed"]]
    best = max(experiments, key=lambda item: (sum(item["gates"].values()), item["oof"]["entered_net_r"], item["oof"]["enter"]))
    wins = sum(map(won, resolved)); low, high = wilson(wins, len(resolved)); boot_low, boot_high = bootstrap_mean_ci(resolved)
    months = []
    for month in ("2026.04",) + MONTHS:
        sample = [row for row in resolved if row["entry_utc"][:7] == month]
        month_wins = sum(map(won, sample))
        months.append({"month": month, "resolved": len(sample), "wins": month_wins,
                       "losses": len(sample)-month_wins, "net_r": 2*month_wins-len(sample),
                       "mean_r": (2*month_wins-len(sample))/len(sample)})
    stability = feature_stability(resolved)
    decision = "FROZEN_CANDIDATE_PASSED_DEVELOPMENT" if passed else "DIRECTIONAL_GENERATOR_HAS_NO_DEMONSTRATED_EXPLOITABLE_SIGNAL"
    payload = {
        "schema": "ENTRY_ENGINE_V2_DEVELOPMENT_RESULT_V1", "decision": decision,
        "holdout_opened": False, "holdout_evaluations": 0, "live_accounts_touched": False,
        "development_boundary": {"start": all_rows[0]["entry_utc"], "end": all_rows[-1]["entry_utc"],
                                 "locked_holdout_start": "2026.09.08 00:00:00"},
        "population": {"opportunities": len(all_rows), "resolved": len(resolved), "wins": wins,
                       "losses": len(resolved)-wins, "censored": len(all_rows)-len(resolved),
                       "baseline_net_r": 2*wins-len(resolved), "baseline_mean_r": (2*wins-len(resolved))/len(resolved),
                       "win_rate": wins/len(resolved), "win_rate_wilson_95": [low, high],
                       "bootstrap_mean_r_95": [boot_low, boot_high]},
        "monthly_generator_results": months, "rejected_shadow_generator_check": shadow_generator(),
        "feature_stability": stability,
        "stable_features": [item for item in stability if item["direction_stable"]],
        "experiments_tested": len(experiments), "passing_experiments": len(passed),
        "best_nonpassing_diagnostic": best,
        "all_experiment_summary": [{k: item[k] for k in ("kind", "parameter", "enter_threshold", "wait_width", "oof", "gates", "passed")} for item in experiments],
        "stop_reason": "No compact formulation passed all predeclared chronological usability and robustness gates; the holdout remains sealed." if not passed else None,
    }
    (OUT / "development-results.json").write_text(json.dumps(payload, indent=2) + "\n")
    (OUT / "feature-manifest.json").write_text(json.dumps({"schema":"ENTRY_ENGINE_V2_FEATURE_MANIFEST_V1",
        "features": list(FEATURES), "causal_cutoff":"completed bars before entry plus fields recorded at entry",
        "future_values_used_as_features":False, "symbol_specific_features":False}, indent=2) + "\n")
    (OUT / "model-freeze.json").write_text(json.dumps({"status": "NO_MODEL_FROZEN" if not passed else "MODEL_FROZEN",
        "reason": payload["stop_reason"], "holdout_must_remain_sealed": not bool(passed),
        "best_nonpassing_model": {k: best[k] for k in ("kind", "parameter", "enter_threshold", "wait_width", "fold_models")}}, indent=2) + "\n")
    print(json.dumps({"decision": decision, "population": payload["population"],
                      "passing_experiments": len(passed), "best": {k: best[k] for k in ("kind","parameter","enter_threshold","oof","gates")}}, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
