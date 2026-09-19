#!/usr/bin/env python3
"""Frozen reference calculations for the V3 forward-evidence evaluator.

This module has no order or deployment capability. The scheduled Windows evaluator
implements the same declared calculations against append-only tracker artifacts.
"""
from __future__ import annotations

from collections import defaultdict
from dataclasses import dataclass
from datetime import datetime, timezone
from math import exp
from statistics import median
from typing import Iterable, Mapping, Sequence

QUALITY_BANDS = ((0.0, 0.50), (0.50, 0.55), (0.55, 0.60), (0.60, 0.65), (0.65, 0.70), (0.70, 0.80), (0.80, 1.01))
FULL_LOSS_REASON = "INITIAL_STRUCTURAL_STOP"
CANDIDATE_IDS = (
    "FROZEN_V3_DIAGNOSTIC",
    "STRICT_PRESSURE_RESUMPTION",
    "STRUCTURAL_REVERSAL_CONFIRMATION",
    "EXPANDING_PULLBACK_FAILURE",
)
ORDER_CAPABILITY = False


def number(value: object, default: float = 0.0) -> float:
    try:
        return float(value)  # type: ignore[arg-type]
    except (TypeError, ValueError):
        return default


def flag(value: object) -> bool:
    return str(value).lower() == "true" or value is True or value == 1


def entry_quality(expected_net_r: float) -> float:
    return 1.0 / (1.0 + exp(-2.0 * expected_net_r))


def max_drawdown(payoffs: Sequence[float]) -> float:
    equity = peak = worst = 0.0
    for payoff in payoffs:
        equity += payoff
        peak = max(peak, equity)
        worst = max(worst, peak - equity)
    return worst


def _daily_net(rows: Sequence[Mapping[str, object]], payoff_key: str) -> dict[str, float]:
    result: dict[str, float] = defaultdict(float)
    for row in rows:
        epoch = int(number(row["entry_utc"]))
        day = datetime.fromtimestamp(epoch, tz=timezone.utc).strftime("%Y-%m-%d")
        result[day] += number(row[payoff_key])
    return dict(sorted(result.items()))


def _concentration(rows: Sequence[Mapping[str, object]], key: str, payoff_key: str) -> dict[str, object]:
    if not rows:
        return {"dominant": "", "entry_fraction": None, "absolute_net_r_fraction": None}
    counts: dict[str, int] = defaultdict(int)
    contributions: dict[str, float] = defaultdict(float)
    for row in rows:
        name = str(row[key])
        counts[name] += 1
        contributions[name] += number(row[payoff_key])
    dominant = max(counts, key=lambda name: (counts[name], name))
    total_abs = sum(abs(v) for v in contributions.values())
    net_dominant = max(contributions, key=lambda name: (abs(contributions[name]), name))
    return {
        "dominant": dominant,
        "entry_fraction": counts[dominant] / len(rows),
        "largest_absolute_net_r_contributor": net_dominant,
        "absolute_net_r_fraction": abs(contributions[net_dominant]) / total_abs if total_abs else None,
    }


def payoff_metrics(rows: Sequence[Mapping[str, object]], payoff_key: str) -> dict[str, object]:
    pays = [number(row[payoff_key]) for row in rows]
    wins = [x for x in pays if x > 0]
    losses = [x for x in pays if x < 0]
    total = sum(pays)
    gross_win = sum(wins)
    gross_loss = -sum(losses)
    avg_win = sum(wins) / len(wins) if wins else None
    avg_loss = sum(losses) / len(losses) if losses else None
    days = _daily_net(rows, payoff_key)
    best_day = max(days, key=days.get) if days else ""
    best = max(wins) if wins else 0.0
    return {
        "trades": len(rows),
        "total_net_r": total,
        "expectancy_r": total / len(rows) if rows else None,
        "max_drawdown_r": max_drawdown(pays),
        "profit_factor": gross_win / gross_loss if gross_loss else None,
        "average_winner_r": avg_win,
        "average_loser_r": avg_loss,
        "payoff_ratio": avg_win / abs(avg_loss) if avg_win is not None and avg_loss not in (None, 0) else None,
        "result_without_best_winner_r": total - best,
        "best_day_utc": best_day,
        "result_without_best_day_r": total - days.get(best_day, 0.0),
        "daily_net_r": days,
    }


def validate_right_censored(rows: Iterable[Mapping[str, object]]) -> list[str]:
    errors: list[str] = []
    for row in rows:
        if row.get("outcome_status") != "RIGHT_CENSORED":
            continue
        if flag(row.get("baseline_final_r_known")):
            errors.append(f"{row.get('opportunity_id')}: censored baseline marked known")
        if flag(row.get("aftermath_complete")):
            errors.append(f"{row.get('opportunity_id')}: censored aftermath marked complete")
        if str(row.get("baseline_final_r", "")).strip():
            errors.append(f"{row.get('opportunity_id')}: censored baseline result populated")
    return errors


def candidate_summary(rows: Sequence[Mapping[str, object]], candidate_id: str) -> dict[str, object]:
    selected = [row for row in rows if row.get("candidate_id") == candidate_id and row.get("outcome_status") == "TERMINAL"]
    baseline_losses = [row for row in selected if number(row["baseline_final_r"]) < 0]
    causal_losses = [row for row in selected if number(row["candidate_final_r"]) < 0]
    full_losses = [row for row in selected if row.get("terminal_reason") == FULL_LOSS_REASON]
    baseline = payoff_metrics(selected, "baseline_final_r")
    causal = payoff_metrics(selected, "candidate_final_r")
    total_saved = sum(number(row["candidate_final_r"]) - number(row["baseline_final_r"]) for row in selected)
    avoided = [
        row for row in full_losses
        if flag(row.get("candidate_fired"))
        and number(row["candidate_final_r"]) > number(row["baseline_final_r"])
    ]
    return {
        "candidate_id": candidate_id,
        "eligible_triggered_positions": len(selected),
        "invalidations": sum(flag(row.get("candidate_fired")) for row in selected),
        "full_minus_1_losses_avoided": len(avoided),
        "full_minus_1_losses_not_avoided": len(full_losses) - len(avoided),
        "average_losing_r_baseline": sum(number(r["baseline_final_r"]) for r in baseline_losses) / len(baseline_losses) if baseline_losses else None,
        "average_losing_r_with_invalidation": sum(number(r["candidate_final_r"]) for r in causal_losses) / len(causal_losses) if causal_losses else None,
        "median_losing_r_baseline": median(number(r["baseline_final_r"]) for r in baseline_losses) if baseline_losses else None,
        "median_losing_r_with_invalidation": median(number(r["candidate_final_r"]) for r in causal_losses) if causal_losses else None,
        "total_r_saved_vs_baseline": total_saved,
        "interrupted_breakeven_recoveries": sum(flag(r.get("candidate_fired")) and flag(r.get("recovered_to_breakeven")) for r in selected),
        "interrupted_bank1_trades": sum(flag(r.get("candidate_fired")) and flag(r.get("reached_plus_1_after_exit")) for r in selected),
        "interrupted_plus_2_trades": sum(flag(r.get("candidate_fired")) and flag(r.get("reached_plus_2_after_exit")) for r in selected),
        "interrupted_plus_3_trades": sum(flag(r.get("candidate_fired")) and flag(r.get("reached_plus_3_after_exit")) for r in selected),
        "interrupted_plus_5_trades": sum(flag(r.get("candidate_fired")) and flag(r.get("reached_plus_5_after_exit")) for r in selected),
        "baseline_total_net_r": baseline["total_net_r"],
        "invalidation_total_net_r": causal["total_net_r"],
        "expectancy_difference_r": (total_saved / len(selected)) if selected else None,
        "max_drawdown_baseline_r": baseline["max_drawdown_r"],
        "max_drawdown_invalidation_r": causal["max_drawdown_r"],
        "max_drawdown_difference_r": number(baseline["max_drawdown_r"]) - number(causal["max_drawdown_r"]),
        "profit_factor": causal["profit_factor"],
        "average_winner_r": causal["average_winner_r"],
        "average_loser_r": causal["average_loser_r"],
        "payoff_ratio": causal["payoff_ratio"],
        "result_without_best_winner_r": causal["result_without_best_winner_r"],
        "result_without_best_day_r": causal["result_without_best_day_r"],
        "symbol_concentration": _concentration(selected, "symbol", "candidate_final_r"),
        "session_concentration": _concentration(selected, "session", "candidate_final_r"),
    }


def quality_calibration(rows: Sequence[Mapping[str, object]]) -> list[dict[str, object]]:
    result = []
    for low, high in QUALITY_BANDS:
        group = [row for row in rows if low <= number(row.get("entry_quality"), -1) < high]
        if not group:
            continue
        n = len(group)
        result.append({
            "quality_low": low,
            "quality_high": high,
            "completed_entries": n,
            "average_net_r": sum(number(r["baseline_final_r"]) for r in group) / n,
            "full_loss_rate": sum(r.get("terminal_reason") == FULL_LOSS_REASON for r in group) / n,
            "bank1_rate": sum(flag(r.get("bank1_reached")) for r in group) / n,
            "plus_2_rate": sum(flag(r.get("baseline_plus_2")) for r in group) / n,
            "plus_3_rate": sum(flag(r.get("baseline_plus_3")) for r in group) / n,
            "plus_5_rate": sum(flag(r.get("baseline_plus_5")) for r in group) / n,
        })
    return result


def sequence_status(previous: Mapping[str, object] | None, integrity_errors: Sequence[str]) -> dict[str, object]:
    contaminated = bool(previous and previous.get("status") == "EVIDENCE_CONTAMINATED") or bool(integrity_errors)
    prior = list(previous.get("contamination_reasons", [])) if previous else []
    reasons = list(dict.fromkeys(prior + list(integrity_errors)))
    return {"status": "EVIDENCE_CONTAMINATED" if contaminated else "CLEAN", "contamination_reasons": reasons}
