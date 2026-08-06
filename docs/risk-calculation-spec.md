# Risk Calculation Specification

This is the normative design implemented by the Phase 2 Risk Engine. It does not
authorise signals or orders.

## Definitions

```text
equity_now              = current ACCOUNT_EQUITY
risk_fraction           = RiskPerTradePercent / 100
risk_money              = equity_now × risk_fraction
entry_price             = validated executable-side price
stop_price              = validated initial protective stop
stop_distance_price     = abs(entry_price - stop_price)
tick_size               = SYMBOL_TRADE_TICK_SIZE
tick_value_loss         = broker loss-side tick value for one lot
raw_volume              = risk_money /
                          ((stop_distance_price / tick_size) × tick_value_loss)
```

The loss-side tick value must be used when available. If broker metadata is
missing, zero, inconsistent, or currency conversion cannot be validated, the
trade is rejected.

Phase 2 uses the broker's loss-side tick value, tick size, and volume metadata.
Before execution is implemented, its result must also be compared with
`OrderCalcProfit` for both long and short requests because that API accounts for
symbol/account currency conversion.

## Volume normalisation

1. Calculate `raw_volume`; never start from a fixed lot.
2. Read `SYMBOL_VOLUME_MIN`, `SYMBOL_VOLUME_MAX`, and `SYMBOL_VOLUME_STEP`.
3. Round **down** on the broker grid anchored at `SYMBOL_VOLUME_MIN`; never
   round up and increase risk.
4. Reject if the normalised volume is below minimum.
5. Cap only at the configured/broker maximum if the resulting monetary risk is
   rechecked and still within the risk budget.
6. Recalculate expected stop loss at normalised volume.
7. Reject if expected loss exceeds `risk_money` beyond a small documented
   floating-point tolerance.

## Stop validation

- Version 1 initial distance is `2 × ATR(14)` from completed-bar data.
- Buy stop is below the requested ask-side entry; sell stop is above the
  requested bid-side entry.
- Price is normalised to `SYMBOL_TRADE_TICK_SIZE`, in the risk-safer direction.
- Broker stop/freeze levels and current executable price are checked immediately
  before submission.
- Zero/negative ATR, price, tick size, or stop distance rejects the trade.
- A request must carry the stop where the broker supports it.
- A position is never intentionally left unprotected.

Widening a stop to satisfy a broker minimum requires recalculating volume. Moving
a stop closer merely to fit a desired lot is prohibited.

## Loss lock baselines

### Daily

At the first valid observation of a new broker trading day:

```text
daily_start_equity = current equity
daily_loss = daily_start_equity - current equity
daily_loss_fraction = daily_loss / daily_start_equity
lock when daily_loss_fraction >= 1%
```

Current equity includes realised and unrealised P/L. The lock remains until a new
broker trading day and must survive terminal restart.

### Weekly

At the first valid observation of a new broker trading week:

```text
weekly_start_equity = current equity
weekly_loss = weekly_start_equity - current equity
weekly_loss_fraction = weekly_loss / weekly_start_equity
lock when weekly_loss_fraction >= 2.5%
```

The week boundary uses broker server time and a documented Monday-based key. The
lock survives restart and clears only in the following trading week.

### Emergency

```text
emergency_loss = ProductionBaselineEquity - current equity
emergency_fraction = emergency_loss / ProductionBaselineEquity
trigger when emergency_fraction >= 5%
```

The configured production baseline never ratchets downward automatically.
Phase 2 latches and persists the emergency entry lock and journals the event.
Actual closure of SolTrade magic-number positions remains a Phase 5
position-management responsibility and is not simulated here. Manual/unrelated
positions are never taken over.

## Consecutive losing trades

Closed SolTrade deals are grouped into logical positions. A net result after
commission and swap below zero increments the counter; a positive result resets
it. Breakeven does not hide a prior losing streak. At three consecutive losses,
new entries pause until the next broker trading day. Duplicate deal callbacks
must not double-count a loss.

Phase 2 provides duplicate-safe `RecordClosedOutcome` accounting but does not
subscribe to trade transactions because this build cannot create or manage
positions. The later position manager must supply one net logical-position result
including commission and swap.

## Spread gate

Both conditions must pass:

```text
spread_points <= MaxSpreadPoints
spread_price <= ATR(14) × (MaxSpreadAtrPercent / 100)
```

Invalid ATR or spread metadata rejects the trade. Passing one condition does not
override failure of the other.

## Position capacity

The Risk Engine exposes a pure capacity gate for the fixed Version 1 maximum of
one open SolTrade position. A supplied count of zero passes; one or more is
rejected. A negative or otherwise unavailable count fails closed. Phase 2 does
not enumerate or manage broker positions; the later permission/position layer
must supply the magic-number-scoped count before asking for entry approval.

## Numerical rules

- Use `double` for prices/money and the broker's tick/volume increments for
  normalisation.
- Compare monetary risk with an explicit tolerance no larger than one account
  currency cent unless symbol precision requires a stricter value.
- Log raw and normalised volume, risk budget, expected stop loss, entry, stop,
  and every rejection reason.
- NaN, infinity, division by zero, or non-positive broker values fail closed.

## Persistent state

State is scoped by pseudonymous account identifier and SolTrade magic number. It
contains broker-day/week keys and baselines, lock flags, consecutive losses, the
consecutive-lock day, and the last processed outcome identifier. It is stored
under `MQL5/Files/SolTradeBot/state` using checksum validation and
temporary-write then replace.

Daily and weekly locks clear only at the matching next broker period. The
emergency lock never clears because equity recovers. It requires
`ResetEmergencyLock=true`; if the configured baseline threshold is still
breached, the same initialisation immediately re-latches it.
