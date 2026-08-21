# SolTrade Fast Multi-Market V2 validation

Date: 2026-08-21

- Authorized execution account: `7404213 / FPMarketsSC-Demo` (demo mode verified at runtime)
- Explicitly blocked accounts: `7196820`, `2100139002`
- Non-demo account modes: blocked
- Source SHA-256: `82a9d23ae517c0684bb605b3a6ae7e653fcda733842bf661fd94190f9dd2c9c1`
- EX5 SHA-256: `812b28b87bc431d6eb2550f896bdb9838e9a8fb83a97453bf62704dd533afa52`
- Demo preset SHA-256: `472b78b0df8e6d8d5776af2b9c51a5acb66f3f63ce2fdea09a690e395f4eb735`
- MetaEditor result: `0 errors, 0 warnings`
- Deterministic policy regressions: `11 passed`
- Static safety checks: passed
- Connected initialization: passed
- Broker alias resolution: `USTEC -> US100`, `DE30 -> GER40`, `US500 -> US500`, `STOXX50 -> EURO50`, `UK100 -> UK100`
- Legacy Slow Demo V1 positions: closed, evidence retained, excluded from Fast Multi V2 performance
- Restart/reconciliation: passed; epoch `1787320873` and original stop-distance state persisted; no duplicate positions or orders
- Initial deployment defect: MT5 first looked in `MQL5/Presets`; corrected before V2 initialization, and no V2 order was submitted during the failed initialization
- V28: unchanged

The connected runtime is configured for active demo-only scanning. It does not force an entry: every order still requires the complete directional, no-trade, cost, structure, reversal, correlation, and portfolio-risk gates.
