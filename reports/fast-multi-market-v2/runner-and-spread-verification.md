# SolTrade Fast Multi-Market V2 runner and spread verification

Date: 2026-08-21

Scope: demo account `7404213 / FPMarketsSC-Demo` only. The entry intelligence,
market-path logic, reversal rules, risk settings, symbol universe, correlation
rules, and initial stop-loss methodology were not changed.

## Runner

- There is no fixed take-profit. Entry and stop-modification calls retain a zero TP.
- `0.25R` remains a conditional reassessment point.
- `0.50R` remains the meaningful-profit protection point.
- `0.75R` now persistently activates `RUNNER_MODE`.
- A runner stays open beyond `1R`, `2R`, and `3R` while its thesis remains valid.
- Completed M5/M15 structure and volatility-aware breathing room determine runner
  trail candidates.
- BUY stops can only increase; SELL stops can only decrease.
- Structural thesis invalidation remains an immediate deterministic exit.
- Runner state is atomically persisted per broker position identifier.
- Exit evidence contains runner peak, protected profit, update count, and final
  capture ratio.

The previous V2 had no fixed TP and could trail a winner past `1R`, but it did not
have a persistent, explicit runner state or the required runner audit telemetry.

## Spread verification

The rejection calculation remains:

`100 * (ask - bid) / completed-M5 ATR`

Because both numerator and denominator are broker-price units, the actual filter
does not convert pips or points and therefore did not contain a cross-asset unit
conversion defect. A separate audit now records broker point, trade tick size,
digits, raw bid/ask spread, FX pips where applicable, a one-hour median spread,
the current/median ratio, and the unchanged ATR-relative filter result. The audit
uses FX, metal, and index-specific representations. It does not weaken or bypass
the existing `8% of M5 ATR` threshold.

At the post-restart snapshot, all 19 symbols had auditable specifications. Six
passed and thirteen were rejected. The simultaneous rejections were attributable
to spread cost being large relative to unusually small recent M5 ranges, not to a
shared pip/point conversion.

## Verification

- Deterministic Python tests: 21 passed.
- Static safety checks: passed.
- MetaEditor: 0 errors, 0 warnings.
- Autonomous service: active and connected after restart.
- Account: exact demo login `7404213`, `FPMarketsSC-Demo`.
- Exposure after restart: 0 positions, 0 pending orders.
- No trade was forced.
- Real login `7196820` and observation login `2100139002` remain hard-blocked.

Artifacts at validation:

- Source SHA-256: `a62a3121711933a4c10ad61d00aa578e8f551eecbd5b53d92fd881759286f69f`
- EX5 SHA-256: `0ab4f97f8febb1ff7b8b797bf90d32715fc5b6af0c6b5d299aad0e7a6fb17939`
