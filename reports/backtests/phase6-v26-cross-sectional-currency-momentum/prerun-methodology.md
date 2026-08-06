# V26 preregistered methodology

Exactly one seven-currency, top-two/bottom-two, three-week/one-week cross-sectional momentum portfolio is permitted. The 2025 and pre-seal 2026 datasets are separate Development cells. No sealed OOS data is assigned or accessed.

Signal generation is evaluated before P&L and must produce identical schedules across isolated symbol executions. Performance uses real ticks, three frozen cost profiles and Native versus fixed-200-ms execution. Formal portfolio equity starts at USD 10,000; each leg risks 0.05% and at most four legs risk 0.20%. Segment balances are not summed. Commission and frozen point-mode swap are reconciled without double counting.

No optimization, parameter sweep, selective rerun, competing portfolio, connected-chart order, demo order, or live order is permitted. Demo becomes authorized only if every frozen Development gate passes.
