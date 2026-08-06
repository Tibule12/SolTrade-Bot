# Phase 6 V13 methodology amendment

The future study is named **CONTROLLED_PRACTICAL_BACKTEST**. It is not an exact reconstruction of historical 2025 execution costs. V13 is a pre-run freeze only: no profitability matrix, strategy trade, optimization or fixed-delay replica was run.

V13 replaces clock-hour warm-up estimates with 221 completed H1 bars counted independently inside each clean segment. The tester envelope may use dates, but `ResetAt`, `EligibleFrom`, `EligibleTo`, `ResearchCutoff` and `SegmentId` enforce exact broker-server datetimes. No bar before a reset is exposed to EMA 200, Donchian 20/10 or ATR 14. State is reset across every quarantined gap.

At the first tick at or after `EligibleTo`, the harness freezes the last pre-cutoff position and strategy snapshot before any later action. An open position is `RIGHT_CENSORED_OPEN_POSITION`; every later close is `POST_CUTOFF_EXCLUDED`. Six signal-only real-tick tester runs passed with 5186 evaluations and zero orders, positions or trade transactions.

The future result layers must distinguish native MT5 market simulation, frozen external commission, fixed current swap assumptions and supplementary friction. Native and replica execution modes are explicit experimental axes. The matrix remains unexecuted and requires separate authorization.
