# V29 performance attempt 1 technical diagnosis

Attempt 1 is retained and excluded from financial evaluation. No attempt-1 P&L was inspected or used.

- The 2025 Native run was technically complete, but it is superseded so every authoritative run uses one identical corrected executable.
- The 2026 Native run processed all 116 signals and accepted 74 entries, but only 72 position identifiers had exported exit deals.
- The two unmatched entries belonged to the final July 20 cohort and had frozen scheduled exits on July 27.
- The inherited V26 tester harness returned from its schedule processor once the last entry group had been consumed, so it never invoked the final cohort's scheduled-exit lifecycle.

Attempt 2 adds only the omitted final-cohort scheduled-exit path. It does not change any signal identity, entry, ranking, direction, symbol, position size, stop, holding rule, cost, gate, or dataset. All four physical runs are repeated under the corrected executable; no attempt-1 financial output is eligible.
