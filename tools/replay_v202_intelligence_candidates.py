#!/usr/bin/env python3
"""Evaluate V2.202 intelligence candidates without placing or modifying orders.

The replay deliberately separates three questions:

* Is there enough independent outcome data to calibrate the admission score?
* Would a delayed, state-confirmed early-failure exit reduce full-stop losses?
* Would a graduated net-profit floor improve capture after a trade proves itself?

Broker scan telemetry is sampled every ten seconds, so modeled exits are bounded
observations rather than claims about unseen intratick ordering.
"""

from __future__ import annotations

import csv
import json
import re
import zipfile
from dataclasses import asdict, dataclass
from datetime import datetime, timedelta
from pathlib import Path
from typing import Iterable, Iterator, TextIO


ROOT = Path(__file__).resolve().parents[1]
REMOTE = ROOT / "ops/forexvps/remote-output"
LOSS_AUDIT = REMOTE / "loss-audit"
OUTPUT = ROOT / "reports/fast-multi-market-v2/v202-intelligence-candidate-replay-20260902.json"

MIN_CALIBRATION_SIGNALS = 100
MIN_CALIBRATION_WINNERS = 30
MIN_CALIBRATION_LOSSES = 30

EARLY_FAILURE_MIN_AGE_SECONDS = 300
EARLY_FAILURE_MAX_MFE_R = 0.15
EARLY_FAILURE_CURRENT_R = -0.35
EARLY_FAILURE_CONFIRMATION_MINUTES = 2


def detail_fields(value: str) -> dict[str, str]:
    return dict(part.split("=", 1) for part in value.split(";") if "=" in part)


def stamp(value: str) -> datetime:
    return datetime.strptime(value, "%Y.%m.%d %H:%M:%S")


def market_name(symbol: str) -> str:
    symbol = symbol.upper()
    aliases = {
        "DE30": "GER40",
        "GER40": "GER40",
        "USTEC": "US100",
        "US100": "US100",
    }
    for prefix, market in aliases.items():
        if symbol.startswith(prefix):
            return market
    return symbol.split(".", 1)[0]


def direction_value(value: str) -> int:
    return 1 if value == "BUY" else -1


def current_net_floor(peak_r: float) -> float:
    if peak_r < 0.50:
        return -1.0
    if peak_r < 1.00:
        return 0.10
    return max(0.25, peak_r - max(0.75, 0.40 * peak_r))


def graduated_net_floor(peak_r: float) -> float:
    if peak_r < 0.50:
        return -1.0
    if peak_r < 0.75:
        return 0.10
    if peak_r < 1.00:
        return 0.25
    return max(0.40, peak_r - max(0.75, 0.40 * peak_r))


@dataclass(frozen=True)
class Trade:
    day: str
    account: str
    ticket: str
    market: str
    symbol: str
    direction: str
    entry_utc: str
    exit_utc: str
    fill: float
    stop: float
    initial_risk: float
    original_net_r: float
    exit_class: str
    admission_score: float | None
    admission_state_key: str

    @property
    def direction_number(self) -> int:
        return direction_value(self.direction)

    @property
    def initial_distance(self) -> float:
        return abs(self.stop - self.fill)

    @property
    def independent_key(self) -> str:
        rounded = self.entry_utc[:15]
        state = self.admission_state_key or "NO_STATE"
        return f"{self.day}|{rounded}|{self.market}|{self.direction}|{state}"


@dataclass(frozen=True)
class Observation:
    utc: str
    close_price: float
    candidate_direction: str
    trend_m5: float | None
    trend_m15: float | None


def trade_from_rows(account: str, entry: dict[str, str], exit_row: dict[str, str]) -> Trade:
    entered = detail_fields(entry["detail"])
    exited = detail_fields(exit_row["detail"])
    fill = float(entered.get("scratch_fill", exited.get("entry_price", entry["entry"])))
    risk = float(entered["initial_risk"])
    score = entered.get("admission_score")
    return Trade(
        day=entry["utc"][:10],
        account=account,
        ticket=entry["ticket"],
        market=market_name(entry["symbol"]),
        symbol=entry["symbol"],
        direction=entry["direction"],
        entry_utc=entry["utc"],
        exit_utc=exit_row["utc"],
        fill=fill,
        stop=float(entry["stop"]),
        initial_risk=risk,
        original_net_r=float(exited["net"]) / risk,
        exit_class=exited.get("exit_class", ""),
        admission_score=float(score) if score not in (None, "") else None,
        admission_state_key=entered.get("admission_state_key", ""),
    )


def evidence_trades(path: Path, account: str, day: str) -> tuple[list[Trade], list[dict[str, str]]]:
    with path.open(newline="", encoding="utf-8-sig") as handle:
        rows = list(csv.DictReader(handle))
    exits = {
        detail_fields(row["detail"]).get("position_id", ""): row
        for row in rows
        if row["event"] == "EXIT"
    }
    trades = []
    for entry in rows:
        if entry["event"] != "ENTRY" or not entry["utc"].startswith(day):
            continue
        exit_row = exits.get(entry["ticket"])
        if exit_row:
            trades.append(trade_from_rows(account, entry, exit_row))
    return trades, rows


def read_csv_stream(handle: TextIO) -> Iterator[dict[str, str]]:
    yield from csv.DictReader(handle)


def structure_observations(
    rows: Iterable[dict[str, str]], trades: list[Trade]
) -> dict[str, list[Observation]]:
    by_market: dict[str, list[Trade]] = {}
    for trade in trades:
        by_market.setdefault(trade.market, []).append(trade)
    result = {trade.ticket: [] for trade in trades}
    path_ends: dict[str, str] = {}
    for market_trades in by_market.values():
        ordered = sorted(market_trades, key=lambda item: item.entry_utc)
        for index, trade in enumerate(ordered):
            if trade.exit_class == "IMMEDIATE_DIRECTIONAL_SCRATCH_EXIT":
                next_entry = ordered[index + 1].entry_utc if index + 1 < len(ordered) else None
                horizon = (stamp(trade.entry_utc) + timedelta(hours=2)).strftime("%Y.%m.%d %H:%M:%S")
                path_ends[trade.ticket] = min(next_entry, horizon) if next_entry else horizon
            else:
                path_ends[trade.ticket] = trade.exit_utc
    for row in rows:
        row_market = market_name(row["intended_market"])
        candidates = by_market.get(row_market, ())
        if not candidates:
            continue
        row_time = row["utc"]
        raw_entry = float(row["entry"])
        spread = float(row["spread_cost_move"])
        row_direction = row["candidate_direction"]
        for trade in candidates:
            if not (trade.entry_utc <= row_time <= path_ends[trade.ticket]):
                continue
            if trade.direction == "BUY":
                close = raw_entry - spread if row_direction == "BUY" else raw_entry
            else:
                close = raw_entry + spread if row_direction == "SELL" else raw_entry
            result[trade.ticket].append(
                Observation(
                    utc=row_time,
                    close_price=close,
                    candidate_direction=row_direction,
                    trend_m5=float(row["trend_m5"]),
                    trend_m15=float(row["trend_m15"]),
                )
            )
    for observations in result.values():
        observations.sort(key=lambda item: item.utc)
    return result


CURRENT_R = re.compile(r"(?:^|;)current_r=([-0-9.]+)")


def evidence_observations(trade: Trade, rows: list[dict[str, str]]) -> list[Observation]:
    observations: list[Observation] = []
    for row in rows:
        if not (trade.entry_utc <= row["utc"] <= trade.exit_utc):
            continue
        if row["ticket"] != trade.ticket:
            continue
        match = CURRENT_R.search(row["detail"])
        if not match:
            continue
        current_r = float(match.group(1))
        close = trade.fill + trade.direction_number * current_r * trade.initial_distance
        observations.append(
            Observation(
                utc=row["utc"],
                close_price=close,
                candidate_direction=row["direction"],
                trend_m5=None,
                trend_m15=None,
            )
        )
    observations.sort(key=lambda item: item.utc)
    return observations


def short_term_support_lost(trade: Trade, observation: Observation) -> bool:
    if observation.trend_m5 is None:
        return observation.candidate_direction != trade.direction
    directional_m5 = trade.direction_number * observation.trend_m5
    # A fully scored opposite candidate is already short-horizon evidence even
    # while the slower M5 trend still points with the held position. Conversely,
    # loss of M5 support is sufficient when the ranker has not yet flipped.
    return observation.candidate_direction != trade.direction or directional_m5 < 0.20


def replay_trade(trade: Trade, observations: list[Observation], graduated: bool) -> dict[str, object]:
    if not observations:
        return {"status": "NO_PATH", "modeled_r": None}
    entry_time = stamp(trade.entry_utc)
    peak_r = 0.0
    protected_r = -1.0
    failure_minutes: list[str] = []
    last_r = 0.0
    for observation in observations:
        current_r = (
            trade.direction_number * (observation.close_price - trade.fill) / trade.initial_distance
        )
        last_r = current_r
        peak_r = max(peak_r, current_r)
        floor = graduated_net_floor(peak_r) if graduated else current_net_floor(peak_r)
        protected_r = max(protected_r, floor)
        if current_r <= protected_r:
            return {
                "status": "PROTECTED_STOP" if protected_r > -1.0 else "STRUCTURAL_STOP",
                "exit_utc": observation.utc,
                "modeled_r": round(protected_r, 5),
                "observed_cross_r": round(current_r, 5),
                "peak_r": round(peak_r, 5),
            }
        age = (stamp(observation.utc) - entry_time).total_seconds()
        early_failure = (
            age >= EARLY_FAILURE_MIN_AGE_SECONDS
            and peak_r < EARLY_FAILURE_MAX_MFE_R
            and current_r <= EARLY_FAILURE_CURRENT_R
            and short_term_support_lost(trade, observation)
        )
        minute = observation.utc[:16]
        if early_failure:
            if not failure_minutes or failure_minutes[-1] != minute:
                failure_minutes.append(minute)
        else:
            failure_minutes.clear()
        if len(failure_minutes) >= EARLY_FAILURE_CONFIRMATION_MINUTES:
            return {
                "status": "DELAYED_EARLY_FAILURE_EXIT",
                "exit_utc": observation.utc,
                "modeled_r": round(current_r, 5),
                "observed_cross_r": round(current_r, 5),
                "peak_r": round(peak_r, 5),
            }
    return {
        "status": "ARCHIVE_END",
        "exit_utc": observations[-1].utc,
        "modeled_r": round(last_r, 5),
        "observed_cross_r": None,
        "peak_r": round(peak_r, 5),
    }


def calibration_status(trades: list[Trade]) -> dict[str, object]:
    independent: dict[str, Trade] = {}
    for trade in trades:
        independent.setdefault(trade.independent_key, trade)
    labeled = list(independent.values())
    winners = sum(trade.original_net_r > 0 for trade in labeled)
    losses = sum(trade.original_net_r < 0 for trade in labeled)
    enough = (
        len(labeled) >= MIN_CALIBRATION_SIGNALS
        and winners >= MIN_CALIBRATION_WINNERS
        and losses >= MIN_CALIBRATION_LOSSES
    )
    return {
        "status": "READY" if enough else "INSUFFICIENT_SAMPLE_FAIL_CLOSED",
        "independent_signals": len(labeled),
        "winners": winners,
        "losses": losses,
        "minimums": {
            "independent_signals": MIN_CALIBRATION_SIGNALS,
            "winners": MIN_CALIBRATION_WINNERS,
            "losses": MIN_CALIBRATION_LOSSES,
        },
        "live_admission_change_authorized": False,
    }


def main() -> int:
    all_trades: list[Trade] = []
    paths: dict[str, list[Observation]] = {}

    aug_trades, _ = evidence_trades(REMOTE / "result-fp-evidence.csv", "fp", "2026.08.31")
    all_trades.extend(aug_trades)
    with zipfile.ZipFile(REMOTE / "v202-audit-20260831.zip") as archive:
        with archive.open("structure-telemetry-v6-20260831.csv") as raw:
            import io

            text = io.TextIOWrapper(raw, encoding="utf-8-sig", newline="")
            paths.update(structure_observations(read_csv_stream(text), aug_trades))

    sep_fp, _ = evidence_trades(LOSS_AUDIT / "fp-evidence.csv", "fp", "2026.09.01")
    sep_f10, _ = evidence_trades(LOSS_AUDIT / "f10-evidence.csv", "f10", "2026.09.01")
    fp_signal_slots = {(trade.entry_utc[:16], trade.market, trade.direction) for trade in sep_fp}
    sep_unique = sep_fp + [
        trade
        for trade in sep_f10
        if (trade.entry_utc[:16], trade.market, trade.direction) not in fp_signal_slots
    ]
    all_trades.extend(sep_unique)
    fp_sep = [trade for trade in sep_unique if trade.account == "fp"]
    f10_sep = [trade for trade in sep_unique if trade.account == "f10"]
    with (LOSS_AUDIT / "fp-structure-telemetry-v6-20260901.csv").open(
        newline="", encoding="utf-8-sig"
    ) as handle:
        paths.update(structure_observations(read_csv_stream(handle), fp_sep))
    with (LOSS_AUDIT / "f10-structure-telemetry-v6-20260901.csv").open(
        newline="", encoding="utf-8-sig"
    ) as handle:
        paths.update(structure_observations(read_csv_stream(handle), f10_sep))

    audit = json.loads((REMOTE / "trade-intelligence-audit.json").read_text(encoding="utf-8-sig"))
    sep02_path_data = json.loads(
        (REMOTE / "sep02-trade-paths.json").read_text(encoding="utf-8-sig")
    )
    sep02_rows = {instance["id"]: instance["rows"] for instance in sep02_path_data["instances"]}
    for instance in audit["instances"]:
        entries = [row for row in instance["events"] if row["event"] == "ENTRY"]
        exits = {
            detail_fields(row["detail"]).get("position_id", ""): row
            for row in instance["events"]
            if row["event"] == "EXIT"
        }
        rows = instance["events"]
        instance_trades = []
        for entry in entries:
            exit_row = exits.get(entry["ticket"])
            if not exit_row:
                continue
            trade = trade_from_rows(instance["id"], entry, exit_row)
            all_trades.append(trade)
            instance_trades.append(trade)
        full_paths = structure_observations(iter(sep02_rows[instance["id"]]), instance_trades)
        for trade in instance_trades:
            paths[trade.ticket] = full_paths.get(trade.ticket) or evidence_observations(trade, rows)

    trade_results = []
    for trade in all_trades:
        observations = paths.get(trade.ticket, [])
        current = replay_trade(trade, observations, graduated=False)
        candidate = replay_trade(trade, observations, graduated=True)
        trade_results.append(
            {
                "trade": asdict(trade),
                "independent_signal_key": trade.independent_key,
                "path_observations": len(observations),
                "original_net_r": round(trade.original_net_r, 5),
                "current_floor_model": current,
                "intelligence_candidate": candidate,
                "modeled_change_vs_original_r": (
                    None
                    if candidate["modeled_r"] is None
                    else round(float(candidate["modeled_r"]) - trade.original_net_r, 5)
                ),
            }
        )

    modeled = [row for row in trade_results if row["intelligence_candidate"]["modeled_r"] is not None]
    comparable_original_r = sum(float(row["original_net_r"]) for row in modeled)
    current_model_r = sum(float(row["current_floor_model"]["modeled_r"]) for row in modeled)
    candidate_model_r = sum(float(row["intelligence_candidate"]["modeled_r"]) for row in modeled)
    report = {
        "schema": "SOLTRADE_V202_INTELLIGENCE_CANDIDATE_REPLAY_V1",
        "orders_placed": False,
        "live_strategy_changed": False,
        "fxify_changed": False,
        "deployment_performed": False,
        "telemetry_resolution_seconds": 10,
        "candidate": {
            "admission": "calibrate only after minimum independent labeled sample",
            "early_failure": {
                "minimum_age_seconds": EARLY_FAILURE_MIN_AGE_SECONDS,
                "maximum_mfe_r": EARLY_FAILURE_MAX_MFE_R,
                "current_r_at_or_below": EARLY_FAILURE_CURRENT_R,
                "support_loss_confirmation_minutes": EARLY_FAILURE_CONFIRMATION_MINUTES,
            },
            "graduated_net_floor": {
                "peak_0.50_to_0.75": 0.10,
                "peak_0.75_to_1.00": 0.25,
                "peak_1.00_plus_minimum": 0.40,
            },
        },
        "calibration": calibration_status(all_trades),
        "trades": trade_results,
        "summary": {
            "account_executions": len(all_trades),
            "independent_signal_keys": len({trade.independent_key for trade in all_trades}),
            "original_aggregate_r": round(sum(trade.original_net_r for trade in all_trades), 5),
            "modeled_executions_with_complete_path": len(modeled),
            "comparable_original_aggregate_r": round(comparable_original_r, 5),
            "current_floor_modeled_aggregate_r": round(current_model_r, 5),
            "candidate_modeled_aggregate_r": round(candidate_model_r, 5),
            "candidate_change_vs_comparable_original_r": round(
                candidate_model_r - comparable_original_r, 5
            ),
            "candidate_change_vs_current_floor_model_r": round(
                candidate_model_r - current_model_r, 5
            ),
            "candidate_early_failure_exits": sum(
                row["intelligence_candidate"]["status"] == "DELAYED_EARLY_FAILURE_EXIT"
                for row in modeled
            ),
            "candidate_full_structural_stops": sum(
                row["intelligence_candidate"]["status"] == "STRUCTURAL_STOP" for row in modeled
            ),
            "candidate_material_regressions": sum(
                float(row["intelligence_candidate"]["modeled_r"]) - float(row["original_net_r"])
                < -0.10
                for row in modeled
            ),
            "safe_to_change_live_admission": False,
            "safe_to_deploy_candidate": False,
        },
        "limitations": [
            "scan telemetry is ten-second sampled rather than exact intratick execution",
            "the replay models net floors but not every structure-aware trailing update",
            "admission calibration is intentionally blocked until the minimum independent sample exists",
            "account executions sharing one setup are not independent market signals",
        ],
    }
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    OUTPUT.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(report["summary"], indent=2))
    print(json.dumps(report["calibration"], indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
