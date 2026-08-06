# V26 availability-only data qualification

Candidate broker symbols are `EURUSD`, `GBPUSD`, `AUDUSD`, `NZDUSD`, `USDCAD`, `USDCHF`, and `USDJPY`, representing seven liquid non-USD currencies against USD.

Qualification may retrieve only H1 timestamps from `2024-12-01 00:00:00` through the exclusive pre-seal cutoff `2026-08-01 00:00:00`. Prices, returns, rankings, signal counts, hypothetical positions, and P&L must not be written or analyzed during qualification.

The purpose is limited to determining symbol availability, common timestamp coverage, and clean common segments. A symbol may be excluded only for insufficient timestamp coverage or incompatible broker specification, never for its returns. The final fixed universe must contain at least four currencies; otherwise V26 is operationally infeasible and no profitability test may run.

The sealed period beginning `2026-08-01 00:00:00` remains inaccessible. No trade is permitted during qualification.
