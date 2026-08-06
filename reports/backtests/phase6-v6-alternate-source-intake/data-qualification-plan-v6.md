# Phase 6 V6 alternate-source data-qualification plan

Current status: `AWAITING_ALTERNATE_MT5_SOURCE`

This plan begins only after a second MT5 demo broker terminal is connected and the intake checklist is complete. It authorizes no action by itself. The initial V6 connected run is data qualification only.

## Frozen scope

- Warm-up: `[2024-01-02, 2024-01-16)`
- Research: `[2024-01-16, 2024-12-24)`
- Development: `[2024-01-16, 2024-07-05)`
- Validation: `[2024-07-05, 2024-09-29)`
- Out-of-sample: `[2024-09-29, 2024-12-24)`
- Gap threshold: strictly longer than 900 seconds.
- Tick model: broker-native real ticks only.

All starts are inclusive and all ends are exclusive. These dates and gates cannot be adjusted in response to data availability or future performance.

## Stage 0 — authorization boundary

Before any connected qualification run, stop for review of the populated intake manifest. Required conditions are:

1. second-broker source identity completed;
2. MT5 demo-account status confirmed;
3. all mandatory symbol, time, session, tick, and M1 fields populated from that terminal;
4. source-specific state and artifact namespace selected;
5. real-tick availability spanning the full warm-up and research interval established preliminarily;
6. Algo Trading off, Trade tab empty, production EA detached, and all execution permissions disabled.

Missing or assumed values leave the status `AWAITING_ALTERNATE_MT5_SOURCE`.

## Stage 1 — read-only source capture

Capture without trade APIs:

- broker, server, demo-account indicator, account currency, and leverage;
- terminal build and exact EURUSD symbol name;
- digits, point, tick size, tick value, tick-value variants, and contract size;
- broker-server time and simultaneous UTC time;
- observed UTC offset and daylight-saving determination or explicit ambiguity;
- every EURUSD trade session returned by MT5 for all seven weekdays;
- first and last available real ticks;
- first and last available M1 bars;
- broker download, synchronization, and history-quality messages.

Raw account login and credentials must never enter an artifact or commit.

## Stage 2 — non-trading real-tick inventory

Retrieve the candidate broker’s real ticks in bounded chronological chunks covering `[2024-01-02, 2024-12-24)`. Record each request, result count, exact first/final tick, error code, retry, and missing chunk. Retain cross-chunk boundary ticks to detect gaps without loading the full interval into a single array.

The acquisition must not:

- request or generate synthetic ticks;
- interpolate ticks from M1 bars;
- merge data from easyMarkets or any other source;
- repair a missing interval;
- call order, position, or trade APIs.

Any unrecovered retrieval failure makes coverage incomplete.

## Stage 3 — schedule-aware gap detection

For every adjacent tick pair:

1. calculate elapsed time using the captured broker-server timestamps;
2. intersect the interval with the frozen MT5 session schedule;
3. identify scheduled-open segments strictly longer than 900 seconds;
4. report the full raw gap and the open-session portion separately;
5. retain tick prices around the boundary and any M1 bars inside the interval;
6. report discrepancies between ticks, M1 bars, and session status.

Detect and report these classes without assuming their cause:

- `SCHEDULED_WEEKEND_CLOSURE`;
- `SCHEDULED_DAILY_BREAK`;
- `DOCUMENTED_HOLIDAY_CLOSURE`;
- `BROKER_CONFIRMED_INTERVAL_CLOSURE`;
- `SESSION_SCHEDULE_CONFLICT`;
- `MISSING_TICK_RANGE`;
- `TICK_RETRIEVAL_FAILURE`;
- `TIMEZONE_AMBIGUITY`;
- `UNRESOLVED`.

An official-closure classification requires frozen supporting evidence from the MT5 schedule, broker-published hours with timezone/effective date, or interval-specific broker evidence. Weekend proximity is not evidence by itself.

## Stage 4 — M1/HCC verification

Inventory broker-specific M1/HCC files and use `CopyRates` to enumerate M1 coverage. Report:

- exact first and final bars;
- missing scheduled-open minutes;
- bars appearing inside real-tick gaps;
- synchronization state and errors;
- file sizes and SHA-256 hashes.

M1 data is corroborating evidence only. It cannot create, interpolate, replace, or validate absent real ticks by itself.

## Stage 5 — boundary and timezone qualification

The dataset fails qualification if:

- the first real tick does not establish complete beginning coverage from `2024-01-02 00:00:00` under the captured schedule;
- the final real tick does not establish complete ending coverage through `2024-12-24 00:00:00` exclusive;
- the broker-server timezone or daylight-saving transition cannot be reconciled with the captured schedule;
- any scheduled-open gap over 900 seconds remains unresolved;
- any retrieval chunk is missing or unverifiable;
- tick order, duplication, or boundary invariants fail.

## Stage 6 — immutable identity and report

Generate a new alternate-source identity covering:

- canonical real-tick files and chronological tick-stream fingerprint;
- relevant M1/HCC files;
- symbol specification;
- complete MT5 session schedule;
- broker/server metadata and terminal build;
- timezone observations;
- collection messages and gap classifications;
- aggregate SHA-256 manifest.

The identity must be new and source-specific. It must never replace, extend, or combine with easyMarkets history identity `0360f7831290a6fc7bee78c8653c65056bfccbb58dca9f3d2bea8d83c64414b6`.

## Stage 7 — mandatory stop

After the qualification report and immutable identity are produced, stop for review. Do not load the strategy, calculate profitability, run the matrix, optimize, run replicas, trade, or begin Phase 7.

Only a separately reviewed result with complete coverage, no unresolved scheduled-open gap over 900 seconds, reconciled timezone/session evidence, and clean state isolation could be considered for a later authorization request.
