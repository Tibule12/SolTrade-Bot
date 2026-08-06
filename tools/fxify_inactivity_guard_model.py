#!/usr/bin/env python3
"""Deterministic reference model for the independent FXIFY inactivity guard."""
from __future__ import annotations

from dataclasses import dataclass, field
from datetime import datetime, timedelta
import math


SECONDS_PER_DAY = 86_400.0
GUARD_MAGIC = 608055001


@dataclass(frozen=True)
class Deal:
    time: datetime
    entry: str
    deal_type: str = "BUY"
    magic: int = 0
    volume: float = 0.01


@dataclass(frozen=True)
class Config:
    warning_day: int = 45
    maintenance_day: int = 50
    critical_day: int = 55
    volume: float = 0.01
    stop_pips: float = 10.0
    take_profit_pips: float = 5.0
    maximum_holding_minutes: int = 60
    maximum_spread_pips: float = 1.5
    slippage_pips: float = 1.0
    commission_per_lot: float = 6.0
    maximum_stop_risk: float = 1.10
    maximum_projected_loss: float = 2.0
    reference_balance: float = 10_000.0
    daily_loss_percent: float = 4.0
    maximum_loss_percent: float = 8.0
    safety_buffer: float = 50.0
    retry_minutes: int = 15
    guard_magic: int = GUARD_MAGIC


@dataclass(frozen=True)
class Snapshot:
    now: datetime
    history_anchor: datetime
    deals: tuple[Deal, ...] = ()
    connected: bool = True
    terminal_trade_allowed: bool = True
    program_trade_allowed: bool = True
    account_trade_allowed: bool = True
    account_expert_allowed: bool = True
    market_open: bool = True
    tick_valid: bool = True
    spread_pips: float = 0.6
    symbol_specs_valid: bool = True
    min_volume: float = 0.01
    max_volume: float = 100.0
    volume_step: float = 0.01
    free_margin: float = 9_500.0
    margin_required: float = 333.34
    equity: float = 10_000.0
    boundary_balance: float = 10_000.0
    guard_order_active: bool = False
    guard_position_active: bool = False
    symbol_position_active: bool = False
    previous_request_rejected: bool = False
    last_attempt: datetime | None = None
    margin_mode: str = "HEDGING"
    stop_pip_value: float = 0.10


@dataclass(frozen=True)
class Evaluation:
    elapsed_days: float
    anchor: datetime
    events: tuple[str, ...]
    blocker: str = ""
    projected_loss: float = 0.0
    risk_components: dict[str, float] = field(default_factory=dict)

    @property
    def maintenance_intent(self) -> bool:
        return "MAINTENANCE_ENTRY_INTENT" in self.events


@dataclass(frozen=True)
class Position:
    opened: datetime
    stop_present: bool
    owned_by_guard: bool = True


def is_legitimate_entry(deal: Deal) -> bool:
    return (
        deal.deal_type in {"BUY", "SELL"}
        and deal.entry in {"IN", "INOUT"}
        and deal.volume > 0
    )


def latest_entry(deals: tuple[Deal, ...]) -> Deal | None:
    entries = [deal for deal in deals if is_legitimate_entry(deal)]
    return max(entries, key=lambda deal: deal.time) if entries else None


def projected_risk(snapshot: Snapshot, config: Config) -> tuple[float, dict[str, float]]:
    stop = config.stop_pips * snapshot.stop_pip_value
    spread = snapshot.spread_pips * snapshot.stop_pip_value
    slippage = config.slippage_pips * snapshot.stop_pip_value
    commission = config.commission_per_lot * config.volume
    components = {
        "stop": stop,
        "spread": spread,
        "slippage": slippage,
        "commission": commission,
    }
    return sum(components.values()), components


def evaluate(snapshot: Snapshot, config: Config = Config()) -> Evaluation:
    entry = latest_entry(snapshot.deals)
    anchor = entry.time if entry else snapshot.history_anchor
    elapsed = max(0.0, (snapshot.now - anchor).total_seconds() / SECONDS_PER_DAY)
    events: list[str] = []
    if elapsed >= config.warning_day:
        events.append("DAY_45_WARNING")
    if elapsed >= config.critical_day:
        events.append("DAY_55_CRITICAL")
    if elapsed < config.maintenance_day:
        return Evaluation(elapsed, anchor, tuple(events))

    blockers = [
        (not snapshot.connected, "TERMINAL_DISCONNECTED"),
        (not snapshot.terminal_trade_allowed, "ALGO_TRADING_DISABLED"),
        (not snapshot.program_trade_allowed, "PROGRAM_TRADING_DISABLED"),
        (
            not snapshot.account_trade_allowed or not snapshot.account_expert_allowed,
            "ACCOUNT_READ_ONLY_OR_TRADE_DISABLED",
        ),
        (not snapshot.market_open, "MARKET_CLOSED_OR_NOT_TRADEABLE"),
        (not snapshot.tick_valid, "INVALID_MARKET_DATA"),
        (snapshot.spread_pips > config.maximum_spread_pips, "EXCESSIVE_SPREAD"),
        (snapshot.guard_order_active, "GUARD_ORDER_ACTIVE"),
        (snapshot.guard_position_active, "GUARD_POSITION_ACTIVE"),
        (snapshot.symbol_position_active, "SYMBOL_POSITION_CONFLICT"),
        (not snapshot.symbol_specs_valid, "INVALID_SYMBOL_SPECIFICATIONS"),
        (
            snapshot.min_volume <= 0
            or snapshot.volume_step <= 0
            or snapshot.min_volume > snapshot.max_volume
            or snapshot.min_volume > config.volume,
            "VOLUME_LIMIT_REJECTED",
        ),
    ]
    for blocked, code in blockers:
        if blocked:
            return Evaluation(elapsed, anchor, tuple(events + ["MAINTENANCE_BLOCKED"]), code)

    loss, components = projected_risk(snapshot, config)
    if components["stop"] > config.maximum_stop_risk:
        return Evaluation(
            elapsed,
            anchor,
            tuple(events + ["MAINTENANCE_BLOCKED"]),
            "STOP_RISK_TOO_HIGH",
            loss,
            components,
        )
    if not math.isfinite(loss) or loss <= 0 or loss > config.maximum_projected_loss:
        return Evaluation(
            elapsed,
            anchor,
            tuple(events + ["MAINTENANCE_BLOCKED"]),
            "PROJECTED_LOSS_TOO_HIGH",
            loss,
            components,
        )
    daily_floor = snapshot.boundary_balance * (1 - config.daily_loss_percent / 100)
    maximum_floor = config.reference_balance * (1 - config.maximum_loss_percent / 100)
    if snapshot.equity - loss < daily_floor + config.safety_buffer:
        return Evaluation(
            elapsed,
            anchor,
            tuple(events + ["MAINTENANCE_BLOCKED"]),
            "DAILY_LOSS_SAFETY_BUFFER",
            loss,
            components,
        )
    if snapshot.equity - loss < maximum_floor + config.safety_buffer:
        return Evaluation(
            elapsed,
            anchor,
            tuple(events + ["MAINTENANCE_BLOCKED"]),
            "MAXIMUM_LOSS_SAFETY_BUFFER",
            loss,
            components,
        )
    if snapshot.free_margin < snapshot.margin_required + loss + config.safety_buffer:
        return Evaluation(
            elapsed,
            anchor,
            tuple(events + ["MAINTENANCE_BLOCKED"]),
            "INSUFFICIENT_MARGIN",
            loss,
            components,
        )
    if snapshot.last_attempt is not None:
        retry_at = snapshot.last_attempt + timedelta(minutes=config.retry_minutes)
        if snapshot.now < retry_at:
            return Evaluation(elapsed, anchor, tuple(events + ["RETRY_WAIT"]), "RETRY_INTERVAL")
    if snapshot.previous_request_rejected:
        events.append("RETRY_AFTER_REJECTION")
    events.append("MAINTENANCE_ENTRY_INTENT")
    return Evaluation(elapsed, anchor, tuple(events), projected_loss=loss, risk_components=components)


def manage_position(now: datetime, position: Position, config: Config = Config()) -> str:
    if not position.owned_by_guard:
        return "POSITION_OWNERSHIP_CHANGED"
    if not position.stop_present:
        return "EMERGENCY_CLOSE_MISSING_STOP"
    if now - position.opened >= timedelta(minutes=config.maximum_holding_minutes):
        return "CLOSE_MAXIMUM_HOLDING_TIME"
    return "HOLD_PROTECTED_GUARD_POSITION"


def simulate_historical_gap() -> list[dict[str, str]]:
    config = Config()
    start = datetime(2026, 2, 2, 10, 5, 1)
    end = datetime(2026, 4, 6, 10, 5, 0)
    deals: list[Deal] = [Deal(start, "IN", magic=2607202601)]
    rows: list[dict[str, str]] = []
    for day, label in ((45, "WARNING_CHECK"), (50, "MAINTENANCE_CHECK")):
        now = start + timedelta(days=day)
        result = evaluate(Snapshot(now=now, history_anchor=start, deals=tuple(deals)), config)
        rows.append(
            {
                "timestamp": now.isoformat(sep=" "),
                "event": label,
                "elapsed_days_before_event": f"{result.elapsed_days:.8f}",
                "decision_events": ";".join(result.events),
                "projected_loss_usd": f"{result.projected_loss:.8f}",
                "inactivity_breach": "NO",
            }
        )
        if result.maintenance_intent:
            deals.append(Deal(now, "IN", magic=config.guard_magic))
            rows.append(
                {
                    "timestamp": now.isoformat(sep=" "),
                    "event": "GUARD_ENTRY_EXECUTED",
                    "elapsed_days_before_event": f"{day:.8f}",
                    "decision_events": "EXECUTED_DEAL_ENTRY_IN;TIMER_RESET",
                    "projected_loss_usd": f"{result.projected_loss:.8f}",
                    "inactivity_breach": "NO",
                }
            )
    final = evaluate(Snapshot(now=end, history_anchor=start, deals=tuple(deals)), config)
    rows.append(
        {
            "timestamp": end.isoformat(sep=" "),
            "event": "NEXT_V28_ENTRY",
            "elapsed_days_before_event": f"{final.elapsed_days:.8f}",
            "decision_events": "V28_EXECUTED_DEAL_ENTRY_IN;TIMER_RESET",
            "projected_loss_usd": "0.00000000",
            "inactivity_breach": "NO" if final.elapsed_days < 60 else "YES",
        }
    )
    return rows
