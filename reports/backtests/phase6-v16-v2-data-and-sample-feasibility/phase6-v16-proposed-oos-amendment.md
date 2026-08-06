# Proposed pre-results OOS sample amendment

Status: **PROPOSED FOR APPROVAL; NOT APPLIED**.

Preserve the OOS start at `2026-04-09 00:00:00` broker-server time and extend it forward chronologically until the close of the 50th naturally completed frozen-V2 position cycle. Do not inspect P&L while accumulating the sample, do not stop early because of profitability, and impose `2027-12-31` as the hard maximum date. If 50 cycles are not reached by then, return `INCONCLUSIVE_INSUFFICIENT_SAMPLE`. The separately labelled post-July sample in V16 is not combined with proposed OOS unless this amendment is approved.
