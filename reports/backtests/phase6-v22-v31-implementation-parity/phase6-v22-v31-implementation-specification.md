# V3.1 isolated implementation

The independent Python reference and MQL5 tester harness implement `TREND_BREAKOUT_V3_RETEST_HOLD_1_1` without shared decision code. Both consume the same qualified raw inputs and frozen constants; their indicator and state-machine decision code is independent.

The MQL5 implementation is confined to `research/v31/`, requires Strategy Tester, EURUSD, H1, zero pre-existing orders and positions, and contains no trade API. It records signal state, one-shot first-tick spread decisions, theoretical stops and structural exits only. The reference implementation is `tools/build_phase6_v22.py`.

The research cutoff is exclusive at `2026-08-01 00:00:00` broker-server time. Segment-local history resets, the 300-bar minimum, event ordering, six-candle retest lifetime, equality-pass spread comparison, and no-retry consumption are explicit in both evaluators. Numeric evidence is serialized to sufficient precision and compared at the frozen `1e-12` indicator tolerance; state and timestamps compare exactly.

Persistence fixtures use the separate `TREND_BREAKOUT_V3_RETEST_HOLD_1_1` namespace and cover setup, retest, confirmation, spread-decision, theoretical-position, exit, completion, and reset checkpoints. No Phase 1–5 production source is reused or modified.
