# V25 preregistered methodology

V25 evaluates exactly one strategy configuration: `LONDON_FIX_USD_INVENTORY_REVERSAL_1_0`. The rationale and all rules are frozen before candidate signal counts or P&L are viewed. No competing clock, holding-period, direction, stop, spread, weekday, volatility, or move-threshold variant may be run.

Only the seven V22/V23-qualified clean segments ending strictly before `2026-08-01 00:00:00` may be used. The four 2025 segments remain `DEVELOPMENT_REUSE_DATA`; the three 2026 pre-seal segments remain `DESIGN_AND_OPERATIONAL_FEASIBILITY_DATA`. For this candidate, both are Development evidence. The unused OOS reserve remains sealed during the Development screen.

Each segment is a separate real-tick Strategy Tester run. Three frozen cost profiles and Native versus fixed-200-ms execution produce 42 physical runs and 12 formal dataset/cost/execution cells. Formal equity begins at USD 10,000 and applies 0.25% current-equity risk to chronological adjusted realized R. Segment account balances are not summed. Open positions at boundaries are right-censored with no unrealized P&L.

Commission is USD 3 per side per standard lot, applied externally if native tester commission is zero and reconciled without double counting. Frozen FP Markets point-mode swaps are long -9.71 and short +4.50 with Wednesday triple rollover. Supplementary friction multipliers are Normal 0.00, High 0.50, and Stress 1.00 using the V13/V14 native-friction formula.

No optimization, selective rerun, sealed-OOS access, connected-chart order, or live order is permitted. Demo-forward execution is conditional on every frozen Development gate passing and requires isolated demo-only configuration.

