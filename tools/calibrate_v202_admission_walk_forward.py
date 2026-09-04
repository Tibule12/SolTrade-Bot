#!/usr/bin/env python3
"""Chronological calibration audit for the V2.202 admission score.

This tool never changes EA parameters. It trains only on earlier shadow
episodes, validates on a later untouched shadow day, and then evaluates the
frozen model on subsequent live/demo outcomes.
"""

from __future__ import annotations

import csv
import io
import json
import math
import statistics
import zipfile
from dataclasses import dataclass
from pathlib import Path

try:
    from tools.replay_v202_intelligence_candidates import detail_fields, market_name
except ModuleNotFoundError:  # Direct execution places tools/ itself on sys.path.
    from replay_v202_intelligence_candidates import detail_fields, market_name


ROOT = Path(__file__).resolve().parents[1]
SHADOW = ROOT / "reports/fast-multi-market-v2/shadow-admission-20260827"
REMOTE = ROOT / "ops/forexvps/remote-output"
OUTPUT = ROOT / "reports/fast-multi-market-v2/v202-admission-walk-forward-20260902.json"
FEATURES = (
    "score",
    "room_r",
    "spread_atr",
    "drift_atr",
    "impulse_atr",
    "session_asia",
    "session_london",
    "session_overlap",
)


@dataclass(frozen=True)
class Example:
    day: str
    source: str
    key: str
    score: float
    room_r: float
    spread_atr: float
    drift_atr: float
    impulse_atr: float
    session_asia: float
    session_london: float
    session_overlap: float
    net_r: float

    @property
    def won(self) -> bool:
        return self.net_r > 0

    def vector(self) -> list[float]:
        return [getattr(self, name) for name in FEATURES]


def sigmoid(value: float) -> float:
    value = max(-35.0, min(35.0, value))
    return 1.0 / (1.0 + math.exp(-value))


@dataclass
class LogisticModel:
    means: list[float]
    scales: list[float]
    weights: list[float]

    def probability(self, example: Example) -> float:
        scaled = [
            (value - mean) / scale
            for value, mean, scale in zip(example.vector(), self.means, self.scales)
        ]
        return sigmoid(self.weights[0] + sum(w * x for w, x in zip(self.weights[1:], scaled)))


def fit_logistic(examples: list[Example], iterations: int = 5000, l2: float = 0.20) -> LogisticModel:
    columns = list(zip(*(example.vector() for example in examples)))
    means = [statistics.mean(column) for column in columns]
    scales = [statistics.pstdev(column) or 1.0 for column in columns]
    matrix = [
        [1.0]
        + [(value - mean) / scale for value, mean, scale in zip(example.vector(), means, scales)]
        for example in examples
    ]
    labels = [1.0 if example.won else 0.0 for example in examples]
    weights = [0.0] * (len(FEATURES) + 1)
    learning_rate = 0.08
    for _ in range(iterations):
        gradients = [0.0] * len(weights)
        for row, label in zip(matrix, labels):
            error = sigmoid(sum(weight * value for weight, value in zip(weights, row))) - label
            for index, value in enumerate(row):
                gradients[index] += error * value
        for index in range(len(weights)):
            penalty = 0.0 if index == 0 else l2 * weights[index]
            weights[index] -= learning_rate * (gradients[index] / len(matrix) + penalty / len(matrix))
    return LogisticModel(means, scales, weights)


def wilson_lower(winners: int, count: int, z: float = 1.96) -> float:
    if count == 0:
        return 0.0
    rate = winners / count
    denominator = 1 + z * z / count
    return (
        rate
        + z * z / (2 * count)
        - z * math.sqrt(rate * (1 - rate) / count + z * z / (4 * count * count))
    ) / denominator


def metrics(examples: list[Example], model: LogisticModel, threshold: float) -> dict[str, float | int]:
    accepted = [example for example in examples if model.probability(example) >= threshold]
    winners = sum(example.won for example in accepted)
    return {
        "available": len(examples),
        "accepted": len(accepted),
        "admission_rate": round(len(accepted) / len(examples), 5) if examples else 0.0,
        "winners": winners,
        "losses": len(accepted) - winners,
        "win_rate": round(winners / len(accepted), 5) if accepted else 0.0,
        "mean_net_r": round(statistics.mean(example.net_r for example in accepted), 5)
        if accepted
        else 0.0,
        "aggregate_net_r": round(sum(example.net_r for example in accepted), 5),
        "wilson_lower_95": round(wilson_lower(winners, len(accepted)), 5),
    }


def select_threshold(examples: list[Example], model: LogisticModel) -> float:
    candidates = [value / 100 for value in range(40, 86)]
    ranked = []
    for threshold in candidates:
        result = metrics(examples, model, threshold)
        if result["accepted"] < 12 or result["mean_net_r"] <= 0:
            continue
        ranked.append(
            (
                result["wilson_lower_95"],
                result["mean_net_r"],
                result["accepted"],
                threshold,
            )
        )
    if not ranked:
        return 1.0
    return max(ranked)[-1]


def load_shadow() -> list[Example]:
    with (SHADOW / "shadow-candidates.csv").open(newline="", encoding="utf-8-sig") as handle:
        candidates = {
            (row["timestamp_utc"], row["symbol"], row["direction"], row["setup_key"]): row
            for row in csv.DictReader(handle)
        }
    examples = []
    with (SHADOW / "post-decision-outcomes.csv").open(newline="", encoding="utf-8-sig") as handle:
        for outcome in csv.DictReader(handle):
            if outcome["episode_anchor"] != "True" or outcome["window_60m_status"] != "COMPLETE":
                continue
            identity = (
                outcome["timestamp_utc"],
                outcome["symbol"],
                outcome["direction"],
                outcome["setup_key"],
            )
            candidate = candidates.get(identity)
            if not candidate:
                continue
            try:
                examples.append(
                    Example(
                        day=outcome["timestamp_utc"][:10],
                        source="SHADOW_60M",
                        key=outcome["episode_id"],
                        score=float(candidate["final_admission_score"]),
                        room_r=float(candidate["remaining_room_r_after_costs"]),
                        spread_atr=float(candidate["spread_m5_atr_percent"]),
                        drift_atr=float(candidate["signal_drift_atr"]),
                        impulse_atr=float(candidate["impulse_extension_atr"]),
                        session_asia=1.0 if int(outcome["timestamp_utc"][11:13]) < 7 else 0.0,
                        session_london=1.0 if 7 <= int(outcome["timestamp_utc"][11:13]) < 12 else 0.0,
                        session_overlap=1.0 if 12 <= int(outcome["timestamp_utc"][11:13]) < 17 else 0.0,
                        net_r=float(outcome["terminal_60m_net_r"]),
                    )
                )
            except ValueError:
                continue
    return examples


def evidence_rows(path: Path, day: str) -> tuple[list[dict[str, str]], dict[str, dict[str, str]]]:
    with path.open(newline="", encoding="utf-8-sig") as handle:
        rows = list(csv.DictReader(handle))
    exits = {
        detail_fields(row["detail"]).get("position_id", ""): row
        for row in rows
        if row["event"] == "EXIT"
    }
    entries = [
        row
        for row in rows
        if row["event"] == "ENTRY" and row["utc"].startswith(day) and row["ticket"] in exits
    ]
    return entries, exits


def matching_structure(
    rows: list[dict[str, str]], entries: list[dict[str, str]]
) -> dict[tuple[str, str], dict[str, str]]:
    targets = {(entry["utc"], market_name(entry["symbol"])) for entry in entries}
    return {
        (row["utc"], market_name(row["intended_market"])): row
        for row in rows
        if (row["utc"], market_name(row["intended_market"])) in targets
    }


def live_examples(
    source: str,
    entries: list[dict[str, str]],
    exits: dict[str, dict[str, str]],
    structures: dict[tuple[str, str], dict[str, str]],
) -> list[Example]:
    examples = []
    for entry in entries:
        structure = structures.get((entry["utc"], market_name(entry["symbol"])))
        if not structure:
            continue
        entered = detail_fields(entry["detail"])
        exited = detail_fields(exits[entry["ticket"]]["detail"])
        stop_distance = float(structure["stop_distance"])
        stop_atr = float(structure["stop_distance_m5_atr"])
        spread_atr = 100 * float(structure["spread_cost_move"]) / (stop_distance / stop_atr)
        risk = float(entered["initial_risk"])
        examples.append(
            Example(
                day=entry["utc"][:10],
                source=source,
                key=f"{entry['utc'][:16]}|{market_name(entry['symbol'])}|{entry['direction']}|{entered.get('admission_state_key','')}",
                score=float(entered["admission_score"]),
                room_r=float(structure["initial_clean_room_r"]),
                spread_atr=spread_atr,
                drift_atr=float(entered["entry_drift_m5_atr"]),
                impulse_atr=float(entered["impulse_extension_m5_atr"]),
                session_asia=1.0 if int(entry["utc"][11:13]) < 7 else 0.0,
                session_london=1.0 if 7 <= int(entry["utc"][11:13]) < 12 else 0.0,
                session_overlap=1.0 if 12 <= int(entry["utc"][11:13]) < 17 else 0.0,
                net_r=float(exited["net"]) / risk,
            )
        )
    return examples


def load_later_live() -> list[Example]:
    examples = []
    aug_entries, aug_exits = evidence_rows(REMOTE / "result-fp-evidence.csv", "2026.08.31")
    with zipfile.ZipFile(REMOTE / "v202-audit-20260831.zip") as archive:
        with archive.open("structure-telemetry-v6-20260831.csv") as raw:
            rows = list(csv.DictReader(io.TextIOWrapper(raw, encoding="utf-8-sig", newline="")))
    examples += live_examples("LIVE_AUG31", aug_entries, aug_exits, matching_structure(rows, aug_entries))

    sep_entries, sep_exits = evidence_rows(REMOTE / "loss-audit/fp-evidence.csv", "2026.09.01")
    with (REMOTE / "loss-audit/fp-structure-telemetry-v6-20260901.csv").open(
        newline="", encoding="utf-8-sig"
    ) as handle:
        rows = list(csv.DictReader(handle))
    examples += live_examples("LIVE_SEP01", sep_entries, sep_exits, matching_structure(rows, sep_entries))

    audit = json.loads((REMOTE / "trade-intelligence-audit.json").read_text(encoding="utf-8-sig"))
    for instance in audit["instances"]:
        events = instance["events"]
        exits = {
            detail_fields(row["detail"]).get("position_id", ""): row
            for row in events
            if row["event"] == "EXIT"
        }
        submitted = {
            (row["utc"], market_name(row["intended_market"])): row
            for row in instance["admission_scans"]
            if row["order_attempt_status"] == "BROKER_ORDER_SUBMITTED"
        }
        structures = {
            (row["utc"], market_name(row["intended_market"])): row
            for row in instance["admission_structure"]
        }
        for entry in [row for row in events if row["event"] == "ENTRY"]:
            exited = exits.get(entry["ticket"])
            key = (entry["utc"], market_name(entry["symbol"]))
            scan = submitted.get(key)
            structure = structures.get(key)
            if not exited or not scan or not structure:
                continue
            entered = detail_fields(entry["detail"])
            exit_detail = detail_fields(exited["detail"])
            risk = float(entered["initial_risk"])
            examples.append(
                Example(
                    day=entry["utc"][:10],
                    source=f"LIVE_SEP02_{instance['id']}",
                    key=f"{entry['utc'][:16]}|{market_name(entry['symbol'])}|{entry['direction']}|{entered.get('admission_state_key','')}",
                    score=float(entered["admission_score"]),
                    room_r=float(structure["initial_clean_room_r"]),
                    spread_atr=float(scan["spread_to_m5_atr_percent"]),
                    drift_atr=float(entered["entry_drift_m5_atr"]),
                    impulse_atr=float(entered["impulse_extension_m5_atr"]),
                    session_asia=1.0 if int(entry["utc"][11:13]) < 7 else 0.0,
                    session_london=1.0 if 7 <= int(entry["utc"][11:13]) < 12 else 0.0,
                    session_overlap=1.0 if 12 <= int(entry["utc"][11:13]) < 17 else 0.0,
                    net_r=float(exit_detail["net"]) / risk,
                )
            )

    grouped: dict[str, list[Example]] = {}
    for example in examples:
        grouped.setdefault(example.key, []).append(example)
    independent = []
    for key, variants in grouped.items():
        independent.append(
            Example(
                day=variants[0].day,
                source="+".join(sorted({variant.source for variant in variants})),
                key=key,
                score=statistics.mean(variant.score for variant in variants),
                room_r=statistics.mean(variant.room_r for variant in variants),
                spread_atr=statistics.mean(variant.spread_atr for variant in variants),
                drift_atr=statistics.mean(variant.drift_atr for variant in variants),
                impulse_atr=statistics.mean(variant.impulse_atr for variant in variants),
                session_asia=variants[0].session_asia,
                session_london=variants[0].session_london,
                session_overlap=variants[0].session_overlap,
                net_r=statistics.mean(variant.net_r for variant in variants),
            )
        )
    return sorted(independent, key=lambda item: (item.day, item.key))


def main() -> int:
    shadow = load_shadow()
    development = [example for example in shadow if example.day < "2026.08.28"]
    validation = [example for example in shadow if example.day == "2026.08.28"]
    later_live = load_later_live()
    model = fit_logistic(development)
    threshold = select_threshold(development, model)
    report = {
        "schema": "SOLTRADE_V202_ADMISSION_WALK_FORWARD_V1",
        "orders_placed": False,
        "strategy_changed": False,
        "deployment_performed": False,
        "features": list(FEATURES),
        "development_days": sorted({example.day for example in development}),
        "validation_days": sorted({example.day for example in validation}),
        "later_live_days": sorted({example.day for example in later_live}),
        "selected_probability_threshold": threshold,
        "model": {
            "means": dict(zip(FEATURES, model.means)),
            "scales": dict(zip(FEATURES, model.scales)),
            "intercept": model.weights[0],
            "coefficients": dict(zip(FEATURES, model.weights[1:])),
        },
        "development": metrics(development, model, threshold),
        "untouched_shadow_validation": metrics(validation, model, threshold),
        "later_live_holdout": metrics(later_live, model, threshold),
        "later_live_predictions": [
            {
                "day": example.day,
                "source": example.source,
                "key": example.key,
                "probability": round(model.probability(example), 5),
                "accepted": model.probability(example) >= threshold,
                "actual_net_r": round(example.net_r, 5),
                "won": example.won,
                "features": dict(zip(FEATURES, example.vector())),
            }
            for example in later_live
        ],
    }
    validation_ok = (
        report["untouched_shadow_validation"]["accepted"] >= 10
        and report["untouched_shadow_validation"]["mean_net_r"] > 0
        and report["later_live_holdout"]["accepted"] >= 5
        and report["later_live_holdout"]["mean_net_r"] > 0
        and report["later_live_holdout"]["win_rate"] >= 0.60
    )
    report["decision"] = {
        "walk_forward_pass": validation_ok,
        "safe_to_implement_in_ea": validation_ok,
        "safe_to_deploy": False,
        "reason": "PASS_REQUIRES_SEPARATE_EA_REPLAY" if validation_ok else "OUT_OF_SAMPLE_GATE_FAILED",
    }
    OUTPUT.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({
        "development": report["development"],
        "untouched_shadow_validation": report["untouched_shadow_validation"],
        "later_live_holdout": report["later_live_holdout"],
        "decision": report["decision"],
    }, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
