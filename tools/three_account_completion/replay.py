"""Chronological alternative-path replay with explicit execution provenance.

This module has no MT5 connection and no order API. Its inputs are already
observed broker fills, or explicitly modelled fills. Quote crossings alone do
not become fills. The ordinary `final_balance` field is populated only for a
complete, broker-executed path. A complete quote-model path may produce a
separate `modelled_final_balance`, never an exact account balance.

The module deliberately does not invent entry decisions, native structural
stops, rescores, ownership, partial-bank fills, or runner exits. Callers must
provide those decisions and every fill with its provenance. A missing trade
stops the propagated account path at the first ambiguity, because subsequent
lot sizing and portfolio gates depend on that unknown outcome.
"""

from __future__ import annotations

from dataclasses import dataclass
from decimal import Decimal, InvalidOperation, ROUND_FLOOR
from typing import Iterable, Literal, Sequence


D = Decimal
ZERO = D("0")
ONE = D("1")

EvidenceGrade = Literal["BROKER_EXECUTION", "QUOTE_FILL_MODEL"]
CoverageStatus = Literal[
    "COMPLETE", "RIGHT_CENSORED", "UNRESOLVED_BROKER_HISTORY",
    "UNRESOLVED_NATIVE_STOP", "UNRESOLVED_EXECUTION",
    "UNRESOLVED_COST", "UNRESOLVED_MANAGER", "NOT_ELIGIBLE",
]
CloseKind = Literal["BANK1R", "INITIAL_STOP", "RUNNER_STOP", "MANAGER_EXIT", "OTHER_TERMINAL"]


ARM_MATRIX_COLUMNS = (
    "account", "arm", "opening_balance", "eligible_trades", "exact_replay_trades",
    "modelled_complete_trades", "censored_trades", "unresolved_trades",
    "exact_coverage_pct", "broker_exact_final_balance", "modelled_final_balance",
    "net_cash", "net_r", "max_realized_balance_dd", "max_true_equity_dd",
    "wins", "losses", "full_stops", "bank1r", "plus_3r", "plus_5r",
    "status", "first_ambiguity_trade", "missing_evidence",
)


def _finite(value: object, name: str) -> Decimal:
    try:
        n = D(str(value))
    except (InvalidOperation, TypeError, ValueError) as exc:
        raise ValueError(f"{name} must be a finite decimal") from exc
    if not n.is_finite():
        raise ValueError(f"{name} must be a finite decimal")
    return n


@dataclass(frozen=True)
class EntryFill:
    """Executable entry side as broker deal or explicit quote-fill model.

    `cash_per_price_unit_per_lot` must come from historical contract/tick-value
    evidence, not a modern symbol property silently projected backward.
    `risk_per_lot` is expected *cash* at the native initial stop including
    entry/exit costs, supplied from an independently specified cost model.
    """

    time_msc: int
    price: Decimal
    stop_price: Decimal
    direction: Literal["BUY", "SELL"]
    cash_per_price_unit_per_lot: Decimal
    risk_per_lot: Decimal
    commission_per_lot: Decimal
    fee_per_lot: Decimal
    source: str
    grade: EvidenceGrade
    stop_basis: Literal["NATIVE_OPPOSITE_STRUCTURE", "RECORDED_PRODUCTION_STOP"]


@dataclass(frozen=True)
class CloseFill:
    """One evidenced close; swap is applied when that close occurs.

    The BANK1R quantity is calculated from the lot step by the replay engine,
    matching the one-time floor-to-step production rule. Any other close is a
    terminal close of the entire remaining volume.
    """

    time_msc: int
    price: Decimal
    kind: CloseKind
    commission_per_lot: Decimal
    swap_per_lot: Decimal
    fee_per_lot: Decimal
    source: str
    grade: EvidenceGrade


@dataclass(frozen=True)
class TradePath:
    account: str
    arm: str
    trade_id: str
    symbol: str
    theme: str
    eligible: bool
    status: CoverageStatus
    reason: str
    entry: EntryFill | None = None
    closes: tuple[CloseFill, ...] = ()
    plus_3r: bool | None = None
    plus_5r: bool | None = None


@dataclass(frozen=True)
class RiskPolicy:
    opening_balance: Decimal
    risk_fraction: Decimal
    max_portfolio_risk_fraction: Decimal
    max_simultaneous_positions: int
    max_positions_per_theme: int
    minimum_lot: Decimal
    maximum_lot: Decimal
    lot_step: Decimal
    # An alternate position's margin requirement is independent evidence.
    # If absent, the account balance may still be computed conditionally, but
    # the path is never labelled broker exact.
    margin_per_lot: Decimal | None = None


@dataclass(frozen=True)
class CoverageCase:
    trade_id: str
    eligible: bool
    status: CoverageStatus
    grade: EvidenceGrade | None
    reason: str


@dataclass(frozen=True)
class AccountArmResult:
    account: str
    arm: str
    opening_balance: Decimal
    eligible_trades: int
    exact_replay_trades: int
    modelled_complete_trades: int
    censored_trades: int
    unresolved_trades: int
    exact_coverage_pct: Decimal
    broker_exact_final_balance: Decimal | None
    modelled_final_balance: Decimal | None
    net_cash: Decimal | None
    net_r: Decimal | None
    max_realized_balance_dd: Decimal | None
    max_true_equity_dd: Decimal | None
    wins: int | None
    losses: int | None
    full_stops: int | None
    bank1r: int | None
    plus_3r: int | None
    plus_5r: int | None
    status: str
    first_ambiguity_trade: str | None
    missing_evidence: tuple[str, ...]

    def as_csv_row(self) -> dict[str, str]:
        """Use empty cells for unknowns; never turn unknown into zero."""
        result: dict[str, str] = {}
        for key in ARM_MATRIX_COLUMNS:
            value = getattr(self, key)
            result[key] = "" if value is None else (";".join(value) if isinstance(value, tuple) else str(value))
        return result


@dataclass
class _Open:
    path: TradePath
    lots: Decimal
    remaining: Decimal
    cash_risk: Decimal
    entry_cash: Decimal
    close_cash: Decimal = ZERO
    banked: bool = False


def _validate_policy(policy: RiskPolicy) -> RiskPolicy:
    numeric = (
        "opening_balance", "risk_fraction", "max_portfolio_risk_fraction",
        "minimum_lot", "maximum_lot", "lot_step",
    )
    for field in numeric:
        _finite(getattr(policy, field), field)
    if policy.margin_per_lot is not None:
        _finite(policy.margin_per_lot, "margin_per_lot")
    if policy.opening_balance <= ZERO or not ZERO < policy.risk_fraction <= ONE:
        raise ValueError("Opening balance and risk fraction must be positive")
    if not ZERO < policy.max_portfolio_risk_fraction <= ONE:
        raise ValueError("Portfolio risk cap must be positive and <= 1")
    if policy.minimum_lot <= ZERO or policy.lot_step <= ZERO or policy.maximum_lot < policy.minimum_lot:
        raise ValueError("Invalid lot constraints")
    if policy.max_simultaneous_positions < 1 or policy.max_positions_per_theme < 1:
        raise ValueError("Position caps must be positive")
    if policy.margin_per_lot is not None and policy.margin_per_lot < ZERO:
        raise ValueError("Margin per lot cannot be negative")
    return policy


def _validate_path(path: TradePath, account: str, arm: str) -> None:
    if (path.account, path.arm) != (account, arm) or not path.trade_id or not path.symbol:
        raise ValueError("Trade path account, arm, ID or symbol mismatch")
    if not path.eligible:
        if path.status != "NOT_ELIGIBLE":
            raise ValueError("Ineligible path must be NOT_ELIGIBLE")
        return
    if path.status == "NOT_ELIGIBLE":
        raise ValueError("Eligible path cannot be NOT_ELIGIBLE")
    if not path.reason and path.status != "COMPLETE":
        raise ValueError("Censored or unresolved path requires an exact reason")
    if path.status != "COMPLETE":
        return
    entry = path.entry
    if entry is None or not path.closes or path.closes[-1].kind == "BANK1R":
        raise ValueError("COMPLETE path needs an entry and terminal close")
    if not entry.source or not path.theme or entry.time_msc < 0:
        raise ValueError("Entry source, theme and time are required")
    if entry.grade not in ("BROKER_EXECUTION", "QUOTE_FILL_MODEL"):
        raise ValueError("Unknown entry evidence grade")
    for key in ("price", "stop_price", "cash_per_price_unit_per_lot", "risk_per_lot",
                "commission_per_lot", "fee_per_lot"):
        _finite(getattr(entry, key), key)
    if entry.price <= ZERO or entry.stop_price <= ZERO or entry.cash_per_price_unit_per_lot <= ZERO or entry.risk_per_lot <= ZERO:
        raise ValueError("Entry price, stop, contract value and risk must be positive")
    sign = ONE if entry.direction == "BUY" else -ONE
    if entry.direction not in ("BUY", "SELL") or sign * (entry.price - entry.stop_price) <= ZERO:
        raise ValueError("Stop must be adverse to entry")
    if entry.stop_basis not in ("NATIVE_OPPOSITE_STRUCTURE", "RECORDED_PRODUCTION_STOP"):
        raise ValueError("Only a native or recorded production stop can complete a path")
    bank_count = sum(close.kind == "BANK1R" for close in path.closes)
    if bank_count > 1 or (bank_count and path.closes[0].kind != "BANK1R") or len(path.closes) != 1 + bank_count:
        raise ValueError("Exactly one terminal close and at most one prior Bank1R are allowed")
    prior = entry.time_msc
    for close in path.closes:
        if close.time_msc < prior or not close.source or close.grade not in ("BROKER_EXECUTION", "QUOTE_FILL_MODEL"):
            raise ValueError("Close time, provenance or grade invalid")
        prior = close.time_msc
        for key in ("price", "commission_per_lot", "swap_per_lot", "fee_per_lot"):
            _finite(getattr(close, key), key)
        if close.price <= ZERO:
            raise ValueError("Close price must be positive")
    if path.plus_3r is None or path.plus_5r is None:
        raise ValueError("Completed path requires observed +3R/+5R flags")


def classify_arm_coverage(cases: Sequence[CoverageCase]) -> tuple[int, int, int, int, int, Decimal, tuple[str, ...]]:
    """Return eligible, exact, modelled, censored, unresolved, exact %, reasons."""
    ids = [case.trade_id for case in cases]
    if len(ids) != len(set(ids)):
        raise ValueError("Duplicate coverage trade ID")
    eligible = [case for case in cases if case.eligible]
    exact = sum(case.status == "COMPLETE" and case.grade == "BROKER_EXECUTION" for case in eligible)
    modelled = sum(case.status == "COMPLETE" and case.grade == "QUOTE_FILL_MODEL" for case in eligible)
    censored = sum(case.status == "RIGHT_CENSORED" for case in eligible)
    unresolved = len(eligible) - exact - modelled - censored
    if any(case.status == "NOT_ELIGIBLE" for case in eligible):
        raise ValueError("Eligible case cannot be NOT_ELIGIBLE")
    pct = (D(100) * D(exact) / D(len(eligible))) if eligible else ZERO
    reasons = tuple(sorted({f"{case.trade_id}:{case.reason}" for case in eligible
                            if case.status != "COMPLETE"}))
    return len(eligible), exact, modelled, censored, unresolved, pct, reasons


def _lot_size(balance: Decimal, risk_per_lot: Decimal, policy: RiskPolicy) -> Decimal:
    target = balance * policy.risk_fraction / risk_per_lot
    steps = (target / policy.lot_step).to_integral_value(rounding=ROUND_FLOOR)
    lots = min(policy.maximum_lot, steps * policy.lot_step)
    return lots if lots >= policy.minimum_lot else ZERO


def _cash_from_close(entry: EntryFill, close: CloseFill, lots: Decimal) -> Decimal:
    direction = ONE if entry.direction == "BUY" else -ONE
    gross = direction * (close.price - entry.price) * entry.cash_per_price_unit_per_lot * lots
    return gross + lots * (close.commission_per_lot + close.swap_per_lot + close.fee_per_lot)


def replay_filled_arm(
    account: str, arm: str, paths: Iterable[TradePath], policy: RiskPolicy,
) -> AccountArmResult:
    """Replay all evidenced fills in time order, with risk/slot/theme gates.

    `TradePath` contains a complete alternative decision and fill path supplied
    by the caller. If any eligible path is censored or unresolved, no final
    balance is emitted because its unknown lifetime may block a later trade.
    If every path is complete but any fill is a quote model, only a separately
    labelled modelled balance is emitted. This is never a broker fill claim.
    """
    policy = _validate_policy(policy)
    rows = tuple(paths)
    if len({row.trade_id for row in rows}) != len(rows):
        raise ValueError("Duplicate trade ID")
    for row in rows:
        _validate_path(row, account, arm)
    coverage = [CoverageCase(
        row.trade_id, row.eligible, row.status,
        ("BROKER_EXECUTION" if row.entry and row.entry.grade == "BROKER_EXECUTION" and
         all(c.grade == "BROKER_EXECUTION" for c in row.closes) else
         "QUOTE_FILL_MODEL" if row.status == "COMPLETE" else None), row.reason,
    ) for row in rows]
    eligible_n, exact_n, model_n, cens_n, unresolved_n, pct, reasons = classify_arm_coverage(coverage)
    ambiguity = next((row for row in sorted(rows, key=lambda r: r.entry.time_msc if r.entry else -1)
                      if row.eligible and row.status != "COMPLETE"), None)
    if ambiguity:
        return AccountArmResult(
            account, arm, policy.opening_balance, eligible_n, exact_n, model_n,
            cens_n, unresolved_n, pct, None, None, None, None, None, None,
            None, None, None, None, None, None,
            "INCOMPLETE_CHRONOLOGICAL_PATH", ambiguity.trade_id, reasons,
        )
    complete = [row for row in rows if row.eligible]
    # Close events take precedence over entries at the same millisecond only
    # when their independently supplied timestamps permit it. A same-ms entry
    # and close for different trades has no proven broker ordering; reject it.
    entry_times = {row.entry.time_msc for row in complete if row.entry}
    close_times = {close.time_msc for row in complete for close in row.closes}
    if entry_times & close_times:
        raise ValueError("Entry/close same-millisecond ordering is unresolved")
    events: list[tuple[int, int, str, TradePath, CloseFill | None]] = []
    for row in complete:
        assert row.entry is not None
        events.append((row.entry.time_msc, 0, row.trade_id, row, None))
        for number, close in enumerate(row.closes):
            events.append((close.time_msc, number + 1, row.trade_id, row, close))
    events.sort(key=lambda x: (x[0], x[1], x[2]))
    balance = policy.opening_balance
    peak = balance
    max_dd = ZERO
    open_positions: dict[str, _Open] = {}
    results: dict[str, tuple[Decimal, Decimal, bool, bool, bool, bool]] = {}
    missing: set[str] = set()
    if policy.margin_per_lot is None:
        missing.add("HISTORICAL_MARGIN_REQUIREMENT_UNAVAILABLE")
    for _, _, _, row, close in events:
        entry = row.entry
        assert entry is not None
        if close is None:
            lots = _lot_size(balance, entry.risk_per_lot, policy)
            if lots == ZERO:
                missing.add(f"{row.trade_id}:LOT_BELOW_BROKER_MINIMUM")
                continue
            desired_risk = lots * entry.risk_per_lot
            aggregate_risk = sum((item.cash_risk * item.remaining / item.lots
                                  for item in open_positions.values()), ZERO)
            portfolio_cap = balance * policy.max_portfolio_risk_fraction
            if aggregate_risk + desired_risk > portfolio_cap:
                missing.add(f"{row.trade_id}:PORTFOLIO_CAP_REJECTED")
                continue
            if len(open_positions) >= policy.max_simultaneous_positions or any(
                item.path.symbol == row.symbol for item in open_positions.values()
            ) or sum(item.path.theme == row.theme for item in open_positions.values()) >= policy.max_positions_per_theme:
                missing.add(f"{row.trade_id}:POSITION_OR_THEME_CAP_REJECTED")
                continue
            if policy.margin_per_lot is not None and sum(
                item.lots * policy.margin_per_lot for item in open_positions.values()
            ) + lots * policy.margin_per_lot > balance:
                missing.add(f"{row.trade_id}:MARGIN_CAP_REJECTED")
                continue
            entry_cash = lots * (entry.commission_per_lot + entry.fee_per_lot)
            balance += entry_cash
            open_positions[row.trade_id] = _Open(row, lots, lots, desired_risk, entry_cash)
        else:
            position = open_positions.get(row.trade_id)
            if position is None:
                continue  # Earlier independently evidenced portfolio gate rejected entry.
            if close.kind == "BANK1R":
                if position.banked:
                    raise ValueError("Repeated Bank1R")
                half_steps = ((position.lots * D("0.5")) / policy.lot_step).to_integral_value(rounding=ROUND_FLOOR)
                close_lots = half_steps * policy.lot_step
                if close_lots < policy.minimum_lot or position.remaining - close_lots < policy.minimum_lot:
                    raise ValueError("Bank1R partial volume invalid under broker lot constraints")
                position.banked = True
            else:
                close_lots = position.remaining
            cash = _cash_from_close(entry, close, close_lots)
            balance += cash
            position.close_cash += cash
            position.remaining -= close_lots
            if close.kind != "BANK1R":
                net = position.entry_cash + position.close_cash
                initial_risk = position.cash_risk
                results[row.trade_id] = (net, net / initial_risk, close.kind == "INITIAL_STOP",
                                         position.banked, bool(row.plus_3r), bool(row.plus_5r))
                del open_positions[row.trade_id]
        peak = max(peak, balance)
        max_dd = max(max_dd, peak - balance)
    if open_positions:
        raise ValueError("Complete paths must not leave an open simulated position")
    # Policy-gated rejects are a conditional scenario decision. Their originally
    # supplied closes never apply. A missing margin schedule still prevents an
    # exact broker-executable status; cash is only a quote/ledger model.
    net_cash = balance - policy.opening_balance
    net_r = sum((item[1] for item in results.values()), ZERO)
    wins = sum(item[0] > ZERO for item in results.values())
    losses = sum(item[0] < ZERO for item in results.values())
    full_stops = sum(item[2] for item in results.values())
    banks = sum(item[3] for item in results.values())
    plus3 = sum(item[4] for item in results.values())
    plus5 = sum(item[5] for item in results.values())
    all_broker = exact_n == eligible_n and not missing
    return AccountArmResult(
        account, arm, policy.opening_balance, eligible_n, exact_n, model_n,
        cens_n, unresolved_n, pct,
        balance if all_broker else None,
        balance if not all_broker else None,
        net_cash, net_r, max_dd, None,
        wins, losses, full_stops, banks, plus3, plus5,
        "BROKER_EXECUTION_COMPLETE" if all_broker else "CONDITIONAL_ACCOUNT_MODEL_ONLY",
        None, tuple(sorted(missing)),
    )
