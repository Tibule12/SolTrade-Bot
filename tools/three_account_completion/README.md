# Orderless three-account account-path replay contract

`replay.py` consumes **already evidenced** chronological entries and closes.
It has no broker connection, order API, strategy search, or authority to alter
FP/FXIFY. An alternative entry requires its own direction, native structural
stop, price-unit cash value, cash risk per lot, execution side, volume/cost
evidence, and full lifetime closes. A crossing of a historical quote level is
not a broker deal or a broker-valid replacement fill.

Every `TradePath` is one of:

| Status | Meaning |
|---|---|
| `COMPLETE` | Entry and every one-time partial/final close supplied, with full execution provenance. |
| `RIGHT_CENSORED` | Quote/export window ended before a terminal outcome. |
| `UNRESOLVED_BROKER_HISTORY` | Required quotes, deals, orders or timestamps are missing. |
| `UNRESOLVED_NATIVE_STOP` | The date-specific native initial stop cannot be reconstructed. |
| `UNRESOLVED_EXECUTION` | Entry, stop/partial or final executable fill is unproved. |
| `UNRESOLVED_COST` | Date-specific commission, fee, swap, conversion or price-unit value is unproved. |
| `UNRESOLVED_MANAGER` | Cash Bank1R trigger, discretionary exit, runner stop or ownership decision is unproved. |
| `NOT_ELIGIBLE` | The arm never selected this opportunity. |

`BROKER_EXECUTION` means an actual broker deal with matching trade and account.
`QUOTE_FILL_MODEL` means a deterministic bid/ask-price assumption from a quote
stream. It may support a **modelled** balance if every path is complete and
every admission/cap decision is specified, but it does not establish the fill
the broker would have supplied. An unresolved or censored trade suppresses
the entire downstream final balance: its open risk and unknown exit can alter
later lot size, portfolio admission and cash.

The 24-field output (`ARM_MATRIX_COLUMNS`) is:

```text
account, arm, opening_balance, eligible_trades, exact_replay_trades,
modelled_complete_trades, censored_trades, unresolved_trades,
exact_coverage_pct, broker_exact_final_balance, modelled_final_balance,
net_cash, net_r, max_realized_balance_dd, max_true_equity_dd,
wins, losses, full_stops, bank1r, plus_3r, plus_5r,
status, first_ambiguity_trade, missing_evidence
```

Unknown numeric results serialize to **empty cells**, never zero. The engine
rounds lots down to the broker step, debits entry and closing costs once,
banks at most one rounded half-lot, propagates realized balance and sizes the
next trade from that balance. It enforces configurable concurrent position,
same-symbol, theme, cash-risk and margin gates. The reported drawdown is
**realized-balance drawdown**; true intratrade equity drawdown remains empty
without a complete independent equity trace. A modelled path is conditional
on all supplied admissions and fills, and should not be presented as an
observed or guaranteed trading result.

The frozen production manager has additional live dependencies: completed-bar
rescoring, cash-based Bank1R eligibility, one-time partial broker confirmation,
structure-based runner stop changes, ownership authorization, server stop/
freeze acceptance, and actual fill charges. The replay engine does not
replace any of those missing inputs with a four-hour expiry or zero-cost fill.
