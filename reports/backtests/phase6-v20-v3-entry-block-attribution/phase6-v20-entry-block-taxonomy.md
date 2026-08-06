# Phase 6 V20 entry-block taxonomy

Primary reasons follow the frozen execution order: existing-position, first-tick availability and interval validity, data/segment validity, spread, non-performance risk availability, duplicate protection, and submission state. Every blocked confirmation receives exactly one primary reason; independently failing later checks are retained as secondary reasons. Performance-dependent loss state remains unevaluated and is not treated as a failure.

The spread formula is `min(30 points, 0.10 * ATR_price / 0.00001)`. A later acceptable tick is diagnostic only and never creates an entry or retry.
