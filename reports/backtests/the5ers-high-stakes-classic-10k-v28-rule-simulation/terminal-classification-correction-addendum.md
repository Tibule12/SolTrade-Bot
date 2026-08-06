# Terminal classification correction addendum

## Scope and preservation

This addendum reviews only the completed audit's inactivity evidence and terminal classification. It does not rerun a backtest, calculate new P&L, redesign or modify V28, modify Phase 1–5 production code, restart V31, or perform new strategy research.

The original evidence is retained byte-for-byte. In particular, the original `terminal-outcome.md` remains at SHA-256 `3e3a03a94b01249fe2bb46cf99f51dffa1f7d169e319e832895eeffd347405ec`, and the original `sha256-ledger.txt` remains at SHA-256 `525de9b3f02f41b61a9976067d81afddb7424500d302d43f546b3c8d79f4b110`. This addendum supersedes only the original terminal classification.

## Exact interpretation of an execution gap

An execution gap is the elapsed broker-server time between two consecutive rows in the qualified V28 `deals.csv` execution stream after sorting executed deals chronologically. The previous endpoint is the last executed deal before the gap; the next endpoint is the first executed deal after it. Therefore, by construction and by an independent row-count check, there are zero executed deals strictly inside every listed gap.

An unchanged open position does not create an executed trade. Entry and exit deals both count as trading activity. Normal, High and Stress share the same native physical execution stream because High and Stress are supplementary cost reconstructions; their costs do not add, remove or retime executions. The 200 ms condition uses its separate fixed-delay physical stream.

The companion `inactivity-gap-terminal-correction.csv` records all 16 condition-level gap observations, their exact endpoints and durations. They represent eight unique physical-stream gaps because the four native gaps are inherited by Normal, High and Stress.

## Coverage classification

Every gap is genuine V28 inactivity, not missing evidence or missing test coverage:

- The 2025 native and 200 ms gaps from March to April occur wholly inside qualified PASS real-tick runs covering `2024.12.01` through `2026.01.01`. Each run processed all 77 scheduled signals with zero missed signals.
- The December 2025 to January 2026 gaps are covered without a hole by overlapping qualified PASS runs: the 2025 runs continue through `2026.01.01`, while the 2026 runs begin at `2025.12.01`.
- The 2026 March-to-April and June-to-July gaps occur wholly inside qualified PASS real-tick runs covering `2025.12.01` through `2026.08.01`. Each run processed all 42 scheduled signals with zero missed signals.

The first breach alone is dispositive: the native stream has no execution for `32 days 04:27:01` from `2025.03.03 10:05:00` to `2025.04.04 14:32:01`, and the 200 ms stream has no execution for `32 days 04:27:00` from `2025.03.03 10:05:01` to `2025.04.04 14:32:01`. Both are fully covered within their respective 2025 runs.

## Corrected programme conclusion

At least one genuine period of more than 30 consecutive days without a V28 trade execution is proven in every execution condition. The frozen The5ers rule says that the account expires after more than 30 consecutive days without trading. A hard inactivity-rule breach is therefore established, so missing evidence for other rules can no longer support an overall insufficient-evidence classification.

This is a The5ers programme-rule failure caused, at minimum, by the confirmed inactivity breach. Missing full intraday-equity and historical high-impact-news evidence means the daily-loss, profitable-day and news-window rules remain unresolved. This failure is not proof that V28 lacks a trading edge. V28 remains unchanged, Phase 1–5 production remains unchanged at SHA-256 `261a9cfe1c1e8d84e2a2a468ac4d0775086b21c89824b117e5127697fd03ced3`, and V31 remains closed and untouched.

V28_THE5ERS_10K_CLASSIC_FAILS_REQUIRED_RULES
