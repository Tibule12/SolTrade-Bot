# V23 technical failure attempt 002

Run `004-2025-s2-normal-native` produced no valid complete performance result. MetaTrader interprets an INI `ToDate` as the exclusive start of that calendar date. Because segment `2025_S2` ends intraday at `2025-03-07 23:00:00`, the initial wrapper value `ToDate=2025.03.07` truncated the test at `2025-03-07 00:00:00`, yielding only 27 of the required 50 processable completed H1 candles.

The replacement preserves frozen complete-run configuration SHA-256 `a87bbd1b3974d776656f1b5a5b744d577df1981f9057a577caf6e08fbe6ea46f`, all strategy inputs, and the exact exclusive research boundary. The wrapper advances `ToDate` by one calendar day only for intraday boundaries; the harness continues to stop at the unchanged `EligibleTo`. The failed attempt and its native evidence are retained. No valid losing or low-profit result is being rerun.
