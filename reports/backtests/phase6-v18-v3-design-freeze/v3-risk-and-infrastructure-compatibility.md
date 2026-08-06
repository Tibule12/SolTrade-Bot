# V3 risk and infrastructure compatibility

V3 changes setup-state timing, not the approved Phase 1–5 risk or execution architecture.

- Existing equity-risk sizing remains 0.25% with unchanged tick-economics and downward volume normalization.
- The initial stop remains exactly two confirmation-candle ATR; only the confirmation candle is now a retest-hold candle.
- Daily 1.0%, weekly 2.5%, emergency 5.0%, and three-loss pause controls remain authoritative.
- The spread threshold remains the stricter of 30 points and 10% of confirmation ATR.
- Existing symbol, timeframe, account, tick freshness, stops, volume, margin, one-position, magic-number, duplicate-candle, session, return-code, and environment checks remain mandatory.
- Donchian-10 completed-close position management and the attached initial stop remain unchanged.
- Real accounts and live trading remain disabled.

Compatibility requires a future tester-only V3 module and a new state namespace; it does not authorize editing the production EA. The V3 namespace must never read or overwrite V1/V2 state, and corrupt or mismatched persisted state must fail closed. Risk or spread rejection of an otherwise valid retest cancels the setup immediately, preserving exactly one submission attempt and preventing uncontrolled retry.
