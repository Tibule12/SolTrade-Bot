# V3.1 sample-gate amendment

The former proposed OOS interval `[2026-04-09 00:00:00, 2026-07-01 00:00:00)` is retired as a V3.1 acceptance window. It contained only 45 structural confirmations, so even removing every spread block could not yield 50 completed cycles.

All data through `2026-07-31 23:59:59.143` is classified `DESIGN_AND_OPERATIONAL_FEASIBILITY_DATA`. It may support development screening and implementation verification only; it is not untouched V3.1 OOS evidence.

Fresh OOS starts at `2026-08-01 00:00:00` FP Markets broker-server time. It completes immediately after the exit of the 50th naturally completed V3.1 cycle, or at the hard maximum end-exclusive `2027-08-01 00:00:00`, whichever occurs first.

Blocked confirmations and right-censored positions do not count. Performance-dependent risk pauses remain active in a future production-equivalent test. The interval cannot stop early for performance, extend beyond the hard maximum, or lower the 50-cycle gate. Fewer than 50 cycles by the hard maximum returns `INCONCLUSIVE_INSUFFICIENT_SAMPLE`.
