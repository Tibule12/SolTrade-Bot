# V3 structural justification

V1's demonstrated failure mechanism was an unconfirmed Donchian breakout reversing to the full initial stop before trend follow-through. V2 added immediate continuation, but its continuation candle commonly moved farther from the slow EMA and then failed the absolute two-ATR distance cap. V17 measured that cap as the dominant total and exclusive rejection, making V2 operationally sample-infeasible.

V3 makes one structural change: it waits for price to revisit the frozen breakout boundary and then requires a completed close to hold beyond it. The touch establishes retest; the strict close establishes hold; the EMA-side and ATR-regime checks preserve trend and data sanity. This directly addresses unconfirmed breakout persistence without selecting a larger arbitrary EMA-distance number.

The six-candle window is fixed before V3 testing. It follows the V1 observation that 27 initial-stop losses occurred within six hours and that duration group contained zero winners. This is a mechanism-based timing choice, not a V3 result or parameter comparison.

The design does not assert profitability. It creates exactly one falsifiable V3, preserves the 50-cycle feasibility gate, and requires V19 to fail closed if qualified 2026 signal-only evidence cannot support that sample.
