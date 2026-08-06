#!/usr/bin/env python3
"""Validate and analyze SolTrade Phase 6 tester artifacts.

This program is reporting-only. It does not connect to MetaTrader, generate
signals, size positions, submit orders, manage positions, or modify EA state.
"""

from __future__ import annotations

import argparse
import csv
import hashlib
import json
import math
import random
import sys
from dataclasses import dataclass
from datetime import datetime
from pathlib import Path
from typing import Iterable, Sequence


CASHFLOW_SCHEMA = "SOLTRADE_PHASE6_CASHFLOW_V1"
ANALYSIS_SCHEMA = "SOLTRADE_PHASE6_SUPPLEMENTARY_ANALYSIS_V1"
MULTIPLIERS = {"NORMAL": 0.0, "HIGH": 0.50, "STRESS": 1.00}
PROFILE_LIMITS = {
    "NORMAL": {"profit_factor": 1.15, "drawdown": 8.0, "strict_dd": True},
    "HIGH": {"profit_factor": 1.05, "drawdown": 10.0, "strict_dd": False},
    "STRESS": {"profit_factor": 1.00, "drawdown": 12.0, "strict_dd": False},
}


class InvalidEvidence(RuntimeError):
    """Raised when an artifact cannot be accepted as test evidence."""


@dataclass(frozen=True)
class Trade:
    position_identifier: str
    entry_time: datetime
    exit_time: datetime
    native_trade_net: float
    native_friction: float
    supplementary_charge: float
    adjusted_trade_net: float
    equity_before: float
    naturally_closed: bool
    crosses_start_boundary: bool
    crosses_end_boundary: bool


def parse_timestamp(value: str) -> datetime:
    if not value:
        raise InvalidEvidence("missing trade timestamp")
    for pattern in ("%Y.%m.%d %H:%M:%S", "%Y-%m-%dT%H:%M:%S%z"):
        try:
            return datetime.strptime(value, pattern)
        except ValueError:
            continue
    raise InvalidEvidence(f"unsupported timestamp: {value}")


def require_float(row: dict[str, str], name: str) -> float:
    try:
        value = float(row[name])
    except (KeyError, TypeError, ValueError) as exc:
        raise InvalidEvidence(f"invalid or missing {name}") from exc
    if not math.isfinite(value):
        raise InvalidEvidence(f"non-finite {name}")
    return value


def load_cashflows(path: Path, profile: str) -> list[Trade]:
    if not path.is_file():
        raise InvalidEvidence(f"missing cash-flow artifact: {path}")
    multiplier = MULTIPLIERS[profile]
    trades: list[Trade] = []
    with path.open(newline="", encoding="utf-8-sig") as handle:
        reader = csv.DictReader(handle)
        required = {
            "schema",
            "position_identifier",
            "entry_time",
            "exit_time",
            "native_trade_net",
            "native_friction",
            "supplementary_multiplier",
            "supplementary_charge",
            "adjusted_trade_net",
            "equity_before",
            "naturally_closed",
            "crosses_start_boundary",
            "crosses_end_boundary",
        }
        if reader.fieldnames is None or not required.issubset(reader.fieldnames):
            raise InvalidEvidence("cash-flow header is incomplete")
        for row in reader:
            if row["schema"] != CASHFLOW_SCHEMA:
                raise InvalidEvidence("cash-flow schema mismatch")
            native = require_float(row, "native_trade_net")
            friction = require_float(row, "native_friction")
            recorded_multiplier = require_float(row, "supplementary_multiplier")
            recorded_charge = require_float(row, "supplementary_charge")
            recorded_adjusted = require_float(row, "adjusted_trade_net")
            if friction < 0:
                raise InvalidEvidence("native friction cannot be negative")
            if abs(recorded_multiplier - multiplier) > 1e-12:
                raise InvalidEvidence("supplementary multiplier mismatch")

            # Binding formula. Native trade net already contains native costs,
            # so only this extra charge is subtracted.
            charge = friction * multiplier
            adjusted = native - charge
            if abs(recorded_charge - charge) > 1e-7:
                raise InvalidEvidence("supplementary charge mismatch")
            if abs(recorded_adjusted - adjusted) > 1e-7:
                raise InvalidEvidence("adjusted trade net mismatch")
            trades.append(
                Trade(
                    position_identifier=row["position_identifier"],
                    entry_time=parse_timestamp(row["entry_time"]),
                    exit_time=parse_timestamp(row["exit_time"]),
                    native_trade_net=native,
                    native_friction=friction,
                    supplementary_charge=charge,
                    adjusted_trade_net=adjusted,
                    equity_before=require_float(row, "equity_before"),
                    naturally_closed=row["naturally_closed"] == "YES",
                    crosses_start_boundary=(
                        row["crosses_start_boundary"] == "YES"
                    ),
                    crosses_end_boundary=row["crosses_end_boundary"] == "YES",
                )
            )
    if not trades:
        raise InvalidEvidence("cash-flow artifact contains no trades")
    return trades


def percentile(values: Sequence[float], probability: float) -> float:
    if not values:
        raise InvalidEvidence("cannot calculate a percentile from no values")
    ordered = sorted(values)
    position = (len(ordered) - 1) * probability
    lower = math.floor(position)
    upper = math.ceil(position)
    if lower == upper:
        return ordered[lower]
    weight = position - lower
    return ordered[lower] * (1.0 - weight) + ordered[upper] * weight


def maximum_drawdown_percent(equity_curve: Iterable[float]) -> float:
    iterator = iter(equity_curve)
    try:
        peak = next(iterator)
    except StopIteration as exc:
        raise InvalidEvidence("empty equity curve") from exc
    maximum = 0.0
    for equity in iterator:
        peak = max(peak, equity)
        if peak > 0:
            maximum = max(maximum, 100.0 * (peak - equity) / peak)
    return maximum


def period_contribution(
    closed: Sequence[Trade],
    adjusted: Sequence[float],
    start: datetime,
    end: datetime,
    total_net: float,
) -> float:
    seconds = (end - start).total_seconds()
    if seconds <= 0:
        raise InvalidEvidence("invalid inclusive/exclusive interval")
    four_years = 4.0 * 365.2425 * 86400.0
    buckets: dict[int, float] = {}
    if seconds >= four_years:
        for trade, value in zip(closed, adjusted):
            buckets[trade.exit_time.year] = buckets.get(trade.exit_time.year, 0.0) + value
    else:
        for trade, value in zip(closed, adjusted):
            bucket = int(((trade.exit_time - start).total_seconds() * 5) / seconds)
            bucket = min(4, max(0, bucket))
            buckets[bucket] = buckets.get(bucket, 0.0) + value
    best = max([0.0, *buckets.values()])
    return math.inf if total_net <= 0 else 100.0 * best / total_net


def rebuild_metrics(
    trades: Sequence[Trade],
    starting_equity: float,
    start: datetime,
    end: datetime,
) -> dict[str, float | int]:
    if starting_equity <= 0 or not math.isfinite(starting_equity):
        raise InvalidEvidence("starting equity must be positive")
    closed = [trade for trade in trades if trade.naturally_closed]
    if not closed:
        raise InvalidEvidence("no naturally closed trades")
    if any(not (start <= trade.exit_time < end) for trade in closed):
        raise InvalidEvidence("closed trade lies outside registered interval")
    if any(
        closed[index].exit_time < closed[index - 1].exit_time
        for index in range(1, len(closed))
    ):
        raise InvalidEvidence("trade cash flows are not chronological")

    adjusted = [trade.adjusted_trade_net for trade in closed]
    native = [trade.native_trade_net for trade in closed]
    charges = [trade.supplementary_charge for trade in closed]
    equity = starting_equity
    curve = [equity]
    for value in adjusted:
        equity += value
        curve.append(equity)
    net = sum(adjusted)
    gross_profit = sum(value for value in adjusted if value >= 0)
    gross_loss = -sum(value for value in adjusted if value < 0)
    profit_factor = math.inf if gross_loss == 0 else gross_profit / gross_loss
    duration_days = (end - start).total_seconds() / 86400.0
    best_trade = max([0.0, *adjusted])
    equity_curve = [
        {
            "timestamp": start.isoformat(),
            "position_identifier": "STARTING_EQUITY",
            "equity": starting_equity,
        }
    ]
    running_equity = starting_equity
    for trade, value in zip(closed, adjusted):
        running_equity += value
        equity_curve.append(
            {
                "timestamp": trade.exit_time.isoformat(),
                "position_identifier": trade.position_identifier,
                "equity": running_equity,
            }
        )
    return {
        "closed_trades": len(closed),
        "native_trade_net_sum": sum(native),
        "supplementary_charge_sum": sum(charges),
        "adjusted_net_profit": net,
        "adjusted_gross_profit": gross_profit,
        "adjusted_gross_loss": gross_loss,
        "adjusted_expectancy": net / len(closed),
        "adjusted_profit_factor": profit_factor,
        "adjusted_maximum_drawdown_percent": maximum_drawdown_percent(curve),
        "adjusted_annualized_return_percent": (
            100.0 * (net / starting_equity) * (365.2425 / duration_days)
        ),
        "best_trade_contribution_percent": (
            math.inf if net <= 0 else 100.0 * best_trade / net
        ),
        "best_period_contribution_percent": period_contribution(
            closed, adjusted, start, end, net
        ),
        "ending_equity": equity,
        "equity_curve": equity_curve,
        "start_boundary_positions": sum(
            trade.crosses_start_boundary for trade in trades
        ),
        "boundary_positions": sum(trade.crosses_end_boundary for trade in trades),
    }


def acceptance_label(dataset: str, profile: str, metrics: dict[str, float | int]) -> str:
    closed = int(metrics["closed_trades"])
    if dataset == "OUT_OF_SAMPLE" and closed < 50:
        return "INCONCLUSIVE_INSUFFICIENT_SAMPLE"
    limits = PROFILE_LIMITS[profile]
    drawdown = float(metrics["adjusted_maximum_drawdown_percent"])
    drawdown_pass = (
        drawdown < limits["drawdown"]
        if limits["strict_dd"]
        else drawdown <= limits["drawdown"]
    )
    passed = (
        float(metrics["adjusted_net_profit"]) > 0
        and float(metrics["adjusted_expectancy"]) > 0
        and (
            float(metrics["adjusted_profit_factor"]) > limits["profit_factor"]
            if profile == "NORMAL"
            else float(metrics["adjusted_profit_factor"])
            >= limits["profit_factor"]
        )
        and drawdown_pass
        and float(metrics["best_trade_contribution_percent"]) <= 20.0
        and float(metrics["best_period_contribution_percent"]) <= 40.0
    )
    return "PASS" if passed else "RESEARCH_REJECTED"


def simulate_path(returns: Sequence[float], starting_equity: float) -> tuple[float, float]:
    equity = starting_equity
    curve = [equity]
    for trade_return in returns:
        equity *= 1.0 + trade_return
        curve.append(equity)
    return equity, maximum_drawdown_percent(curve)


def uncertainty_analysis(
    trades: Sequence[Trade],
    starting_equity: float,
    seed_material: str,
    paths: int,
) -> dict[str, object]:
    closed = [trade for trade in trades if trade.naturally_closed]
    if not closed:
        raise InvalidEvidence("uncertainty analysis requires closed trades")
    returns = []
    for trade in closed:
        if trade.equity_before <= 0:
            raise InvalidEvidence("trade equity-before value must be positive")
        returns.append(trade.adjusted_trade_net / trade.equity_before)

    seed = int.from_bytes(
        hashlib.sha256(seed_material.encode("utf-8")).digest()[:8], "big"
    )
    generator = random.Random(seed)
    bootstrap_expectancy: list[float] = []
    bootstrap_drawdown: list[float] = []
    negative_endings = 0
    for _ in range(paths):
        sampled = [returns[generator.randrange(len(returns))] for _ in returns]
        ending, drawdown = simulate_path(sampled, starting_equity)
        bootstrap_expectancy.append(sum(sampled) / len(sampled))
        bootstrap_drawdown.append(drawdown)
        negative_endings += ending < starting_equity

    permutation_drawdown: list[float] = []
    for _ in range(paths):
        shuffled = list(returns)
        generator.shuffle(shuffled)
        _, drawdown = simulate_path(shuffled, starting_equity)
        permutation_drawdown.append(drawdown)

    return {
        "method_label": (
            "REPORTING_ONLY_INDEPENDENTLY_RESAMPLED_HISTORICAL_TRADE_RETURNS"
        ),
        "independence_assumption": (
            "Individual-trade bootstrap assumes independently resampled historical "
            "trade returns. It does not reproduce serial dependence, market regimes, "
            "or the strategy time-based lock state."
        ),
        "paths": paths,
        "prng": "Python random.Random (MT19937)",
        "seed_uint64": seed,
        "bootstrap_expectancy_return_ci_90": [
            percentile(bootstrap_expectancy, 0.05),
            percentile(bootstrap_expectancy, 0.95),
        ],
        "bootstrap_expectancy_return_ci_95": [
            percentile(bootstrap_expectancy, 0.025),
            percentile(bootstrap_expectancy, 0.975),
        ],
        "bootstrap_drawdown_percent": {
            "median": percentile(bootstrap_drawdown, 0.50),
            "p90": percentile(bootstrap_drawdown, 0.90),
            "p95": percentile(bootstrap_drawdown, 0.95),
        },
        "bootstrap_probability_negative_net_profit": negative_endings / paths,
        "permutation_drawdown_percent": {
            "median": percentile(permutation_drawdown, 0.50),
            "p90": percentile(permutation_drawdown, 0.90),
            "p95": percentile(permutation_drawdown, 0.95),
        },
        "decision_use": "REPORTING_ONLY_NOT_A_TRADING_INPUT",
    }


def read_key_value_csv(path: Path) -> dict[str, str]:
    if not path.is_file():
        raise InvalidEvidence(f"missing artifact: {path}")
    values: dict[str, str] = {}
    with path.open(newline="", encoding="utf-8-sig") as handle:
        reader = csv.DictReader(handle)
        if reader.fieldnames != ["field", "value"]:
            raise InvalidEvidence(f"invalid key/value artifact header: {path}")
        for row in reader:
            values[row["field"]] = row["value"]
    return values


def run_analysis(arguments: argparse.Namespace) -> dict[str, object]:
    profile = arguments.profile.upper()
    dataset = arguments.dataset.upper()
    trades = load_cashflows(arguments.cashflows, profile)
    start = parse_timestamp(arguments.start_inclusive)
    end = parse_timestamp(arguments.end_exclusive)
    metrics = rebuild_metrics(trades, arguments.starting_equity, start, end)

    reconciliation = read_key_value_csv(arguments.reconciliation)
    if reconciliation.get("status") != "PASS":
        raise InvalidEvidence("MQL reconciliation artifact is not PASS")
    if abs(
        float(reconciliation["reconstructed_native_net"])
        - float(metrics["native_trade_net_sum"])
    ) > 0.01:
        raise InvalidEvidence("native trade net does not reconcile")

    seed_material = "|".join(
        [
            arguments.trading_input_hash,
            dataset,
            profile,
            "uncertainty-v1",
        ]
    )
    return {
        "schema": ANALYSIS_SCHEMA,
        "result_layer": "SUPPLEMENTARY_NOT_BROKER_NATIVE",
        "trading_input_hash": arguments.trading_input_hash,
        "execution_instance_id": arguments.execution_instance_id,
        "dataset": dataset,
        "cost_profile": profile,
        "supplementary_multiplier": MULTIPLIERS[profile],
        "formula": "adjusted_trade_net = native_trade_net - supplementary_charge",
        "metrics": metrics,
        "acceptance_label": acceptance_label(dataset, profile, metrics),
        "uncertainty": uncertainty_analysis(
            trades, arguments.starting_equity, seed_material, arguments.paths
        ),
    }


def self_test() -> None:
    native = 100.0
    friction = 20.0
    assert native - friction * MULTIPLIERS["NORMAL"] == 100.0
    assert native - friction * MULTIPLIERS["HIGH"] == 90.0
    assert native - friction * MULTIPLIERS["STRESS"] == 80.0
    assert percentile([1.0, 2.0, 3.0], 0.5) == 2.0
    assert maximum_drawdown_percent([100.0, 110.0, 99.0]) == 10.0
    start = parse_timestamp("2026-01-01T00:00:00+00:00")
    end = parse_timestamp("2026-03-01T00:00:00+00:00")
    trades: list[Trade] = []
    equity = 10_000.0
    for index in range(50):
        exit_time = start.replace(day=1) + (end - start) * ((index + 1) / 51)
        trades.append(
            Trade(
                position_identifier=str(index + 1),
                entry_time=exit_time,
                exit_time=exit_time,
                native_trade_net=10.0,
                native_friction=2.0,
                supplementary_charge=0.0,
                adjusted_trade_net=10.0,
                equity_before=equity,
                naturally_closed=True,
                crosses_start_boundary=False,
                crosses_end_boundary=False,
            )
        )
        equity += 10.0
    metrics = rebuild_metrics(trades, 10_000.0, start, end)
    assert metrics["closed_trades"] == 50
    assert metrics["adjusted_net_profit"] == 500.0
    assert len(metrics["equity_curve"]) == 51
    assert acceptance_label("OUT_OF_SAMPLE", "NORMAL", metrics) == "PASS"
    short_metrics = rebuild_metrics(trades[:49], 10_000.0, start, end)
    assert (
        acceptance_label("OUT_OF_SAMPLE", "NORMAL", short_metrics)
        == "INCONCLUSIVE_INSUFFICIENT_SAMPLE"
    )
    uncertainty = uncertainty_analysis(trades, 10_000.0, "self-test", 200)
    assert uncertainty["decision_use"] == "REPORTING_ONLY_NOT_A_TRADING_INPUT"
    assert uncertainty["paths"] == 200
    print("Independent Phase 6 reporting arithmetic checks passed.")


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser()
    parser.add_argument("--self-test", action="store_true")
    parser.add_argument("--cashflows", type=Path)
    parser.add_argument("--reconciliation", type=Path)
    parser.add_argument("--output", type=Path)
    parser.add_argument("--profile", choices=tuple(MULTIPLIERS))
    parser.add_argument(
        "--dataset",
        choices=("DEVELOPMENT", "VALIDATION", "OUT_OF_SAMPLE"),
    )
    parser.add_argument("--start-inclusive")
    parser.add_argument("--end-exclusive")
    parser.add_argument("--starting-equity", type=float)
    parser.add_argument("--trading-input-hash")
    parser.add_argument("--execution-instance-id")
    parser.add_argument("--paths", type=int, default=100_000)
    return parser


def main() -> int:
    parser = build_parser()
    arguments = parser.parse_args()
    if arguments.self_test:
        self_test()
        return 0

    required = (
        "cashflows",
        "reconciliation",
        "output",
        "profile",
        "dataset",
        "start_inclusive",
        "end_exclusive",
        "starting_equity",
        "trading_input_hash",
        "execution_instance_id",
    )
    missing = [name for name in required if getattr(arguments, name) is None]
    if missing:
        parser.error("missing arguments: " + ", ".join(missing))
    if arguments.paths <= 0:
        parser.error("--paths must be positive")

    try:
        result = run_analysis(arguments)
    except InvalidEvidence as exc:
        print(f"INVALID_TEST_EVIDENCE: {exc}", file=sys.stderr)
        return 1

    arguments.output.parent.mkdir(parents=True, exist_ok=True)
    arguments.output.write_text(
        json.dumps(result, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )
    print(f"Phase 6 supplementary analysis written to {arguments.output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
