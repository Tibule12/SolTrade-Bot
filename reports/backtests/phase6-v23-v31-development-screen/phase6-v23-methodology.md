# Phase 6 V23 methodology

All evidence is `CONTROLLED_PRESEAL_DEVELOPMENT_EVIDENCE`. The 2025 cell remains `DEVELOPMENT_REUSE_DATA`; the 2026 cell remains `DESIGN_AND_OPERATIONAL_FEASIBILITY_DATA`. Neither is untouched validation, OOS, forward testing, or proof of live profitability.

The frozen V3.1 implementation is executed in 42 isolated Strategy Tester runs: seven clean segments by three cost profiles by two execution modes. Every run uses real ticks, EURUSD H1, one position maximum, 0.25% current-equity risk, the complete Phase 1–5 risk state, natural exits, and fail-closed censoring. Segment balances are never summed. Formal cells reconstruct USD 10,000 synthetic equity chronologically from adjusted realized R.

The OOS cutoff is exclusive at `2026-08-01 00:00:00`. No record at or after that timestamp may be retrieved or parsed. Right-censored positions receive no P&L. The 12 formal cells and all sample, performance, concentration, and cross-dataset gates are frozen in the companion manifests before run 1. No optimization, tuning, parameter sweep, selective rerun, connected-chart, demo-forward, or live trading is permitted.
