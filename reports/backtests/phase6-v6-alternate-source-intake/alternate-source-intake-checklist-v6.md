# Phase 6 V6 alternate-source intake checklist

Status: `AWAITING_ALTERNATE_MT5_SOURCE`

This checklist is preparation for a second MT5 demo broker. It does not authorize a qualification run, strategy run, order, or trade.

## 1. Source eligibility

- [ ] A second MT5 terminal is connected to the candidate broker.
- [ ] The account is confirmed by MT5 as a demo account.
- [ ] The source is not easyMarkets and does not reuse easyMarkets tick files.
- [ ] EURUSD real-tick history is offered by this broker and terminal.
- [ ] Algo Trading is off.
- [ ] The Trade tab has no orders or positions.
- [ ] The production SolTrade EA is detached.
- [ ] Demo execution, position management, and live trading are disabled.
- [ ] No credentials or raw account login will be written to repository artifacts.

Any failed item stops intake. A real account is never eligible.

## 2. Mandatory source metadata

Every field below must be recorded before qualification. Blank, `null`, assumed, or copied-from-easyMarkets values are invalid.

- [ ] Broker name.
- [ ] Exact MT5 server name.
- [ ] Demo-account indicator reported by MT5.
- [ ] Account currency.
- [ ] Account leverage.
- [ ] Exact broker symbol used for EURUSD, including any prefix or suffix.
- [ ] Symbol digits.
- [ ] Point size.
- [ ] Tick size.
- [ ] Tick value, including profit/loss variants when MT5 exposes both.
- [ ] Contract size.
- [ ] Broker-server current time at collection.
- [ ] Simultaneously observed UTC time.
- [ ] UTC offset observed at collection time.
- [ ] Daylight-saving status: `STANDARD`, `DAYLIGHT`, or `UNDETERMINED`, with evidence.
- [ ] Complete EURUSD session schedule returned by MT5 for every weekday.
- [ ] First available real tick.
- [ ] Last available real tick.
- [ ] First available M1 bar.
- [ ] Last available M1 bar.
- [ ] Terminal build and broker company/server strings.
- [ ] Collection timestamp and non-trading acquisition instance identifier.

## 3. Frozen dates and semantics

The following boundaries are immutable for V6 intake. Starts are inclusive and ends are exclusive.

- Warm-up: `[2024-01-02, 2024-01-16)`
- Research: `[2024-01-16, 2024-12-24)`
- Development: `[2024-01-16, 2024-07-05)`
- Validation: `[2024-07-05, 2024-09-29)`
- Out-of-sample: `[2024-09-29, 2024-12-24)`

Warm-up data is verified separately. Warm-up events cannot enter research statistics. Positions and trading statistics are outside the V6 intake scope because no strategy may run.

## 4. Data-model gate

- [ ] MT5 mode is `Every tick based on real ticks` or an equivalent broker-native real-tick retrieval path.
- [ ] Generated ticks are disabled.
- [ ] Synthetic ticks are disabled.
- [ ] M1 interpolation is disabled.
- [ ] No tick stream from another broker is copied, merged, patched, or substituted.
- [ ] Tick retrieval covers `[2024-01-02, 2024-12-24)` or the result is immediately incomplete.
- [ ] Exact first and final processed ticks are recorded.
- [ ] Exact first and final M1 bars are recorded.
- [ ] Retrieval errors, retries, broker messages, and terminal history-quality messages are retained verbatim.

## 5. Qualification-only controls

- [ ] The probe contains no strategy signal evaluation.
- [ ] Entry and execution permissions are false.
- [ ] Position-management permission is false.
- [ ] Trade API calls are absent.
- [ ] Optimization and replica modes are absent.
- [ ] Profitability and research-decision calculations are absent.
- [ ] Unique source and acquisition namespaces are active.
- [ ] Pre-run orders, deals, positions, marker-tree, and history-cache identities are captured read-only.
- [ ] Post-run state is reconciled against the pre-run snapshot.

## 6. Required detections

- [ ] Missing tick ranges.
- [ ] Gaps longer than 900 seconds while the MT5 session schedule says open.
- [ ] Scheduled weekend closures.
- [ ] Daily scheduled breaks.
- [ ] Holidays, with cited evidence.
- [ ] Conflicts between observed ticks and the captured MT5 session schedule.
- [ ] Missing M1 bars during scheduled-open minutes.
- [ ] Timezone or daylight-saving ambiguity.
- [ ] Tick retrieval failures or incomplete chunks.
- [ ] Incomplete start or end coverage.

## 7. Gap evidence rules

A gap may be classified as an official closure only when supported by at least one frozen evidence artifact from:

1. the captured MT5 session schedule applicable to the interval;
2. broker-published trading hours with timezone and effective date; or
3. interval-specific broker evidence.

Weekend proximity alone is insufficient. General broker wording is not interval-specific evidence. M1 bars do not replace or prove the completeness of real ticks. Unexplained conflicts remain `UNRESOLVED` and disqualify the interval.

## 8. Stop conditions

Stop without producing a qualification pass if any mandatory metadata is absent, real ticks are unavailable, source isolation fails, the timezone cannot be reconciled, beginning or ending coverage is incomplete, a retrieval error prevents complete inventory, or any open-session gap over 900 seconds remains unresolved.

The first connected V6 action must stop after data qualification artifacts are generated. It cannot proceed into the Phase 6 strategy matrix without a separate review and authorization.
