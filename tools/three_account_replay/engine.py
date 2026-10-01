"""Chronological account-path replay from recorded MT5 deals.

The ledger calculation is exact for the supplied deal rows: every recorded
profit, commission, swap and fee enters balance once, including entry charges
and partial closes. An account export can omit earlier deals, so callers must
state the opening balance and whether a flat opening position book is proven.
Native MT5 `time_msc` is encoded in the broker server clock in these exports;
`read_native_deals` requires an explicit server-to-UTC offset and converts it.

Risk is *unknown* unless independently supplied for an entry ticket or by a
dated risk mark. Equity is sampled only where an equity observation exists;
the module never invents a quote, fill, floating P/L or trade. The conditional
cash counterfactual preserves the recorded position timeline and is expressly
not a strategy or broker execution replay.
"""

from __future__ import annotations

import csv
from dataclasses import dataclass, field, replace
from datetime import datetime, timezone
from decimal import Decimal, InvalidOperation
from pathlib import Path
from typing import Iterable, Mapping, Sequence


ZERO = Decimal("0")
NATIVE_FIELDS = frozenset({
    "ticket", "position_id", "time_server", "time_msc", "symbol", "entry", "type",
    "volume", "price", "profit", "commission", "swap", "fee",
})


def _money(value: object, label: str) -> Decimal:
    try:
        number = Decimal(str(value))
    except (InvalidOperation, TypeError, ValueError) as exc:
        raise ValueError(f"{label} must be a finite decimal") from exc
    if not number.is_finite():
        raise ValueError(f"{label} must be a finite decimal")
    return number


def _integer(value: object, label: str) -> int:
    try:
        return int(str(value))
    except (ValueError, TypeError) as exc:
        raise ValueError(f"{label} must be an integer") from exc


def _utc_ms(value: str) -> int:
    try:
        instant = datetime.strptime(value, "%Y.%m.%d %H:%M:%S").replace(tzinfo=timezone.utc)
    except ValueError as exc:
        raise ValueError(f"Invalid UTC timestamp: {value!r}") from exc
    return int(instant.timestamp() * 1000)


@dataclass(frozen=True)
class Deal:
    ticket: str
    position_id: str
    time_msc: int  # UTC after CSV ingestion; direct constructors must use UTC.
    symbol: str
    entry: int
    type: int
    volume: Decimal
    price: Decimal
    profit: Decimal
    commission: Decimal
    swap: Decimal
    fee: Decimal
    source: str = ""
    server_time_msc: int | None = None
    server_utc_offset_minutes: int | None = None

    @classmethod
    def from_native_row(
        cls, row: Mapping[str, str], source: str = "", *,
        server_utc_offset_minutes: int,
    ) -> "Deal":
        missing = NATIVE_FIELDS.difference(row)
        if missing:
            raise ValueError(f"Native deal is missing fields: {sorted(missing)}")
        ticket = str(row["ticket"]).strip()
        if not ticket:
            raise ValueError("Native deal ticket is empty")
        raw_msc = _integer(row["time_msc"], "time_msc")
        if raw_msc < 0 or abs(server_utc_offset_minutes) > 14 * 60:
            raise ValueError("Invalid server time or explicit UTC offset")
        server_wall = datetime.fromtimestamp(raw_msc / 1000, tz=timezone.utc).strftime("%Y.%m.%d %H:%M:%S")
        if server_wall != row["time_server"]:
            raise ValueError(f"Broker time_msc and time_server disagree for ticket {ticket}")
        return cls(
            ticket=ticket, position_id=str(row["position_id"]).strip(),
            time_msc=raw_msc - server_utc_offset_minutes * 60_000,
            symbol=str(row["symbol"]).strip(),
            entry=_integer(row["entry"], "entry"),
            type=_integer(row["type"], "type"),
            volume=_money(row["volume"], "volume"),
            price=_money(row["price"], "price"),
            profit=_money(row["profit"], "profit"),
            commission=_money(row["commission"], "commission"),
            swap=_money(row["swap"], "swap"),
            fee=_money(row["fee"], "fee"), source=source,
            server_time_msc=raw_msc, server_utc_offset_minutes=server_utc_offset_minutes,
        )

    @property
    def cash_delta(self) -> Decimal:
        return self.profit + self.commission + self.swap + self.fee

    @property
    def is_trade(self) -> bool:
        return self.type in (0, 1)


@dataclass(frozen=True)
class EquitySample:
    time_msc: int
    equity: Decimal
    observed_balance: Decimal | None = None
    source: str = ""


@dataclass(frozen=True)
class RiskMark:
    time_msc: int
    position_id: str
    remaining_risk: Decimal
    evidence_ref: str


@dataclass(frozen=True)
class PositionSnapshot:
    position_id: str
    symbol: str
    direction: str
    volume: Decimal
    average_entry: Decimal
    remaining_risk: Decimal | None
    risk_basis: str


@dataclass(frozen=True)
class PathPoint:
    """One observed ledger/risk/equity event; total_risk uses annotations only."""

    time_msc: int
    event: str
    reference: str
    balance: Decimal
    equity: Decimal | None
    observed_balance: Decimal | None
    positions: tuple[PositionSnapshot, ...]
    position_count: int | None
    known_risk: Decimal
    unknown_risk_positions: int
    total_risk: Decimal | None
    trade_gross_profit: Decimal
    commission: Decimal
    swap: Decimal
    fee: Decimal
    nontrade_cashflow: Decimal
    balance_reconciliation_delta: Decimal | None


@dataclass(frozen=True)
class ReplayResult:
    points: tuple[PathPoint, ...]
    final_balance: Decimal
    open_positions: tuple[PositionSnapshot, ...]
    ledger_status: str
    position_status: str
    risk_status: str
    equity_status: str
    issues: tuple[str, ...]
    unresolved_dependencies: tuple[str, ...] = ()
    scenario_status: str = "OBSERVED_LEDGER"
    changed_tickets: tuple[str, ...] = ()
    replacement_evidence: tuple[tuple[str, str], ...] = ()


@dataclass(frozen=True)
class CashReplacement:
    """Full cash components for one recorded deal in an accounting scenario."""

    ticket: str
    profit: Decimal
    commission: Decimal
    swap: Decimal
    fee: Decimal
    evidence_ref: str


@dataclass
class _Position:
    position_id: str
    symbol: str
    direction: str
    volume: Decimal
    average_entry: Decimal
    remaining_risk: Decimal | None
    risk_basis: str

    def snapshot(self) -> PositionSnapshot:
        return PositionSnapshot(
            self.position_id, self.symbol, self.direction, self.volume,
            self.average_entry, self.remaining_risk, self.risk_basis,
        )


def read_native_deals(path: Path, *, server_utc_offset_minutes: int) -> tuple[Deal, ...]:
    """Read broker deals with a caller-verified fixed UTC offset, then sort in UTC.

    For a server at UTC+3, pass 180. Split exports if the server changes offset
    during the interval. This function never infers a timezone from the host.
    """
    if isinstance(server_utc_offset_minutes, bool) or not isinstance(server_utc_offset_minutes, int):
        raise ValueError("An explicit integer server UTC offset in minutes is required")
    with Path(path).open(encoding="utf-8-sig", newline="") as handle:
        reader = csv.DictReader(handle)
        if reader.fieldnames is None or NATIVE_FIELDS.difference(reader.fieldnames):
            raise ValueError(f"Native deal CSV missing fields: {sorted(NATIVE_FIELDS.difference(reader.fieldnames or []))}")
        deals = tuple(Deal.from_native_row(
            row, f"{path}:{line}", server_utc_offset_minutes=server_utc_offset_minutes,
        ) for line, row in enumerate(reader, 2))
    return tuple(sorted(deals, key=_deal_sort_key))


def read_equity_samples(path: Path) -> tuple[EquitySample, ...]:
    """Read recorded UTC equity samples; the balance column is a check only."""
    with Path(path).open(encoding="utf-8-sig", newline="") as handle:
        reader = csv.DictReader(handle)
        required = {"utc", "equity"}
        if reader.fieldnames is None or required.difference(reader.fieldnames):
            raise ValueError(f"Equity CSV missing fields: {sorted(required.difference(reader.fieldnames or []))}")
        samples = tuple(EquitySample(
            _utc_ms(row["utc"]), _money(row["equity"], "equity"),
            _money(row["balance"], "observed balance") if row.get("balance") not in (None, "") else None,
            f"{path}:{line}",
        ) for line, row in enumerate(reader, 2))
    return tuple(sorted(samples, key=lambda sample: sample.time_msc))


def _deal_sort_key(deal: Deal) -> tuple[int, int, str]:
    # MT5 tickets are monotonically issued. A text fallback remains stable for
    # synthetic or redacted ticket identifiers.
    try:
        return deal.time_msc, 0, f"{int(deal.ticket):030d}"
    except ValueError:
        return deal.time_msc, 1, deal.ticket


def replay_account_path(
    deals: Iterable[Deal], *, opening_balance: Decimal | str | int,
    opening_flat_confirmed: bool,
    risk_by_entry_ticket: Mapping[str, Decimal | str | int] | None = None,
    risk_marks: Sequence[RiskMark] = (),
    equity_samples: Sequence[EquitySample] = (),
) -> ReplayResult:
    """Replay known cash and position events in UTC millisecond order.

    `risk_by_entry_ticket` is *independent evidence* of cash risk for each
    entry deal, not a risk estimate from stop distance. Risk marks can replace
    the remaining risk at a specific observed time. Missing risk stays unknown.
    """
    balance = _money(opening_balance, "opening_balance")
    deal_rows = tuple(sorted(deals, key=_deal_sort_key))
    if len({d.ticket for d in deal_rows}) != len(deal_rows):
        raise ValueError("Duplicate deal ticket: cannot count a broker cashflow twice")
    for deal in deal_rows:
        if deal.time_msc < 0 or deal.volume < ZERO:
            raise ValueError(f"Invalid time or volume for deal {deal.ticket}")
        for field_name in ("volume", "price", "profit", "commission", "swap", "fee"):
            _money(getattr(deal, field_name), f"deal {deal.ticket} {field_name}")
    risk_by_ticket = {str(ticket): _money(value, f"risk for {ticket}")
                      for ticket, value in (risk_by_entry_ticket or {}).items()}
    if any(value < ZERO for value in risk_by_ticket.values()):
        raise ValueError("Entry risk cannot be negative")
    for mark in risk_marks:
        if mark.time_msc < 0 or _money(mark.remaining_risk, "risk mark") < ZERO or not mark.evidence_ref:
            raise ValueError("Risk mark requires a valid time, nonnegative risk and evidence reference")
    for sample in equity_samples:
        if sample.time_msc < 0:
            raise ValueError("Equity sample time must be nonnegative")
        _money(sample.equity, "equity")
        if sample.observed_balance is not None:
            _money(sample.observed_balance, "observed balance")

    positions: dict[str, _Position] = {}
    unknown_position_ids: set[str] = set()
    position_state_known = opening_flat_confirmed
    issues: list[str] = []
    if not opening_flat_confirmed:
        issues.append("OPENING_POSITION_BOOK_UNVERIFIED")
    points: list[PathPoint] = []
    trade_gross = commission = swap = fee = external = ZERO

    def record(at: int, event: str, ref: str, sample: EquitySample | None = None) -> None:
        known_risk = sum((p.remaining_risk for p in positions.values()
                          if p.remaining_risk is not None), ZERO)
        unknown_risk = sum(p.remaining_risk is None for p in positions.values())
        snapshots = tuple(p.snapshot() for p in sorted(positions.values(), key=lambda p: p.position_id))
        observed_balance = sample.observed_balance if sample else None
        difference = observed_balance - balance if observed_balance is not None else None
        if difference is not None and difference != ZERO:
            issues.append(f"BALANCE_RECONCILIATION_MISMATCH:{ref}")
        points.append(PathPoint(
            time_msc=at, event=event, reference=ref, balance=balance,
            equity=sample.equity if sample else None, observed_balance=observed_balance,
            positions=snapshots,
            position_count=len(positions) if position_state_known and not unknown_position_ids else None,
            known_risk=known_risk, unknown_risk_positions=unknown_risk,
            total_risk=known_risk if position_state_known and not unknown_position_ids and not unknown_risk else None,
            trade_gross_profit=trade_gross, commission=commission, swap=swap,
            fee=fee, nontrade_cashflow=external,
            balance_reconciliation_delta=difference,
        ))

    def process_deal(deal: Deal) -> None:
        nonlocal balance, trade_gross, commission, swap, fee, external, position_state_known
        balance += deal.cash_delta
        if not deal.is_trade:
            external += deal.cash_delta
            return
        trade_gross += deal.profit
        commission += deal.commission
        swap += deal.swap
        fee += deal.fee
        pid = deal.position_id
        if not pid or pid == "0" or not deal.symbol or deal.volume <= ZERO:
            issues.append(f"TRADE_ID_SYMBOL_OR_VOLUME_UNRESOLVED:{deal.ticket}")
            position_state_known = False
            return
        direction = "BUY" if deal.type == 0 else "SELL"
        current = positions.get(pid)
        if deal.entry == 0:  # DEAL_ENTRY_IN
            annotation = risk_by_ticket.get(deal.ticket)
            if current is None:
                positions[pid] = _Position(pid, deal.symbol, direction, deal.volume,
                                           deal.price, annotation,
                                           "ENTRY_ANNOTATION" if annotation is not None else "UNKNOWN")
            elif current.direction == direction and current.symbol == deal.symbol:
                total = current.volume + deal.volume
                current.average_entry = (current.average_entry * current.volume + deal.price * deal.volume) / total
                current.volume = total
                current.remaining_risk = (current.remaining_risk + annotation
                    if current.remaining_risk is not None and annotation is not None else None)
                if current.remaining_risk is None:
                    current.risk_basis = "UNKNOWN"
            else:
                issues.append(f"ENTRY_CONFLICT:{deal.ticket}")
                positions.pop(pid, None)
                unknown_position_ids.add(pid)
                position_state_known = False
        elif deal.entry in (1, 3):  # OUT and OUT_BY
            if current is None:
                issues.append(f"EXIT_WITHOUT_ENTRY:{deal.ticket}")
                unknown_position_ids.add(pid)
                position_state_known = False
            elif current.symbol != deal.symbol or current.direction == direction or deal.volume > current.volume:
                issues.append(f"EXIT_POSITION_MISMATCH:{deal.ticket}")
                positions.pop(pid, None)
                unknown_position_ids.add(pid)
                position_state_known = False
            elif deal.volume == current.volume:
                del positions[pid]
            else:
                fraction = deal.volume / current.volume
                if current.remaining_risk is not None:
                    current.remaining_risk *= (Decimal("1") - fraction)
                current.volume -= deal.volume
        elif deal.entry == 2:  # INOUT: broker netting reversal
            if current is None or current.symbol != deal.symbol or current.direction == direction:
                issues.append(f"REVERSAL_POSITION_UNRESOLVED:{deal.ticket}")
                positions.pop(pid, None)
                unknown_position_ids.add(pid)
                position_state_known = False
            elif deal.volume <= current.volume:
                issues.append(f"REVERSAL_VOLUME_UNRESOLVED:{deal.ticket}")
                positions.pop(pid, None)
                unknown_position_ids.add(pid)
                position_state_known = False
            else:
                # MT5 INOUT volume closes the old side and opens the residual.
                # Its residual stop/risk is not established by this cash deal.
                residual = deal.volume - current.volume
                positions[pid] = _Position(pid, deal.symbol, direction, residual,
                                           deal.price, None, "UNKNOWN_AFTER_REVERSAL")
                issues.append(f"REVERSAL_RISK_UNRESOLVED:{deal.ticket}")
        else:
            issues.append(f"UNSUPPORTED_DEAL_ENTRY:{deal.ticket}")
            positions.pop(pid, None)
            unknown_position_ids.add(pid)
            position_state_known = False

    events: list[tuple[int, int, str, object]] = []
    for deal in deal_rows:
        events.append((deal.time_msc, 0, _deal_sort_key(deal)[2], deal))
    for mark in risk_marks:
        events.append((mark.time_msc, 1, mark.position_id, mark))
    for index, sample in enumerate(equity_samples):
        events.append((sample.time_msc, 2, f"{index:020d}", sample))
    events.sort(key=lambda item: item[:3])
    deal_times = {deal.time_msc for deal in deal_rows}
    for at, order, _, event in events:
        if order == 0:
            deal = event
            assert isinstance(deal, Deal)
            process_deal(deal)
            record(at, "DEAL", deal.ticket)
        elif order == 1:
            mark = event
            assert isinstance(mark, RiskMark)
            current = positions.get(mark.position_id)
            if current is None:
                issues.append(f"RISK_MARK_WITHOUT_POSITION:{mark.position_id}:{at}")
            else:
                current.remaining_risk = _money(mark.remaining_risk, "risk mark")
                current.risk_basis = f"DATED_MARK:{mark.evidence_ref}"
            record(at, "RISK_MARK", mark.position_id)
        else:
            sample = event
            assert isinstance(sample, EquitySample)
            if at in deal_times:
                issues.append(f"COINCIDENT_EQUITY_AND_DEAL_TIME:{at}")
            record(at, "EQUITY_SAMPLE", sample.source or str(at), sample)
    unused_risk = risk_by_ticket.keys() - {d.ticket for d in deal_rows if d.is_trade and d.entry == 0}
    issues.extend(f"UNUSED_ENTRY_RISK:{ticket}" for ticket in sorted(unused_risk))
    final = points[-1] if points else None
    final_positions = final.positions if final else ()
    risk_known = (bool(final) and final.total_risk is not None) or (not final and opening_flat_confirmed)
    if risk_known and not final_positions and position_state_known and not unknown_position_ids:
        risk_status = "FLAT_ZERO"
    elif risk_known:
        risk_status = "ANNOTATED_EXPOSURE_ONLY"
    else:
        risk_status = "PARTIAL_OR_UNKNOWN"
    dependencies = ["UNOBSERVED_INTRASAMPLE_EQUITY" if equity_samples else "NO_EQUITY_OBSERVATIONS"]
    if any(point.positions for point in points):
        dependencies.append("STOP_AND_RISK_CHANGES_BETWEEN_OBSERVATIONS")
    if not risk_known:
        dependencies.append("POSITION_RISK_UNQUALIFIED")
    return ReplayResult(
        points=tuple(points), final_balance=balance,
        open_positions=final_positions,
        ledger_status="EXACT_FOR_PROVIDED_DEALS",
        position_status="RECONSTRUCTED" if position_state_known and not unknown_position_ids else "UNRESOLVED",
        risk_status=risk_status,
        equity_status="SAMPLED_ONLY" if equity_samples else "UNOBSERVED",
        issues=tuple(issues),
        unresolved_dependencies=tuple(dependencies),
    )


def replay_cash_counterfactual(
    deals: Iterable[Deal], replacements: Sequence[CashReplacement], *,
    opening_balance: Decimal | str | int, opening_flat_confirmed: bool,
    risk_by_entry_ticket: Mapping[str, Decimal | str | int] | None = None,
    risk_marks: Sequence[RiskMark] = (),
) -> ReplayResult:
    """Recalculate a conditional ledger with evidenced ticket cash changes.

    Position IDs, timestamps, fills and volumes stay recorded. This answers an
    accounting question only. Changed future entry sizing, execution, broker
    charges, margin, quote path and floating equity remain unresolved.
    """
    original = tuple(deals)
    by_ticket = {deal.ticket: deal for deal in original}
    if len(by_ticket) != len(original):
        raise ValueError("Duplicate deal ticket")
    seen: set[str] = set()
    changed: list[str] = []
    evidence: list[tuple[str, str]] = []
    for item in replacements:
        if item.ticket in seen:
            raise ValueError(f"Duplicate replacement ticket: {item.ticket}")
        seen.add(item.ticket)
        if item.ticket not in by_ticket or not by_ticket[item.ticket].is_trade:
            raise ValueError(f"Replacement must reference a recorded trade deal: {item.ticket}")
        if not item.evidence_ref.strip():
            raise ValueError("Replacement requires an evidence reference")
        values = {name: _money(getattr(item, name), name)
                  for name in ("profit", "commission", "swap", "fee")}
        prior = by_ticket[item.ticket]
        by_ticket[item.ticket] = replace(prior, **values)
        if any(getattr(prior, name) != value for name, value in values.items()):
            changed.append(item.ticket)
            evidence.append((item.ticket, item.evidence_ref))
    scenario = replay_account_path(
        by_ticket.values(), opening_balance=opening_balance,
        opening_flat_confirmed=opening_flat_confirmed,
        risk_by_entry_ticket=risk_by_entry_ticket, risk_marks=risk_marks,
    )
    dependencies = (
        "ALTERNATIVE_CASH_COMPONENTS_NOT_BROKER_EXECUTION",
        "FUTURE_ENTRY_SIZING_AND_ADMISSION_DEPEND_ON_CHANGED_EQUITY",
        "MARGIN_AND_FLOATING_EQUITY_REQUIRE_QUOTES",
        "ALTERNATIVE_EXIT_FILL_REQUIRES_BID_ASK_PATH",
    ) if changed else ()
    return replace(
        scenario, scenario_status="CONDITIONAL_ACCOUNTING_ONLY" if changed else "IDENTICAL_LEDGER",
        equity_status="UNOBSERVED_COUNTERFACTUAL" if changed else scenario.equity_status,
        unresolved_dependencies=dependencies or scenario.unresolved_dependencies,
        changed_tickets=tuple(sorted(changed)),
        replacement_evidence=tuple(sorted(evidence)),
    )
