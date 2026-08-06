# Unused OOS reserve governance

Administrative classification: `UNASSIGNED_SINGLE_USE_FUTURE_OOS_RESERVE`

Seal status: `SEALED_UNOPENED`

The sealed broker-server interval remains start-inclusive `2026-08-01 00:00:00` and hard-maximum-end-exclusive `2027-08-01 00:00:00`. V24 makes an administrative reassignment only. It does not modify the original seal, open the reserve, or retrieve, inspect, count, copy, or summarize post-seal market data.

The reserve is governed by these binding rules:

1. It may be assigned to exactly one future strategy family.
2. That family and its complete candidate strategy must be fully specified and committed before any reserve data is accessed.
3. The candidate must first pass its frozen pre-seal development screen.
4. The reserve may not compare several strategies, variants, configurations, or parameter choices.
5. Once any OOS result is viewed, the reserve may not be reopened or reassigned to another strategy.
6. If the assigned strategy fails sealed OOS, another OOS test requires newly accumulated untouched future data.
7. Assignment or opening requires separate explicit authorization; V24 grants neither.

The original V3.1 seal manifest, its SHA-256, and the complete V21–V23 access-audit history remain immutable evidence.

