# V23 technical failure attempt 001

Run `001-2025-s1-normal-native` produced no valid complete performance result. Its evidence status failed because the pre-run inventory counted 277 indicator-eligible H1 opening timestamps, while only 276 can become completed candles before the segment's exclusive boundary. The final `2025-02-04 23:00:00` H1 candle cannot be processed without observing a tick at or after `2025-02-05 00:00:00`.

This matches the V22 access semantics: the final H1 opening timestamp may be loaded, but the maximum completed H1 processed is one hour earlier. The retained attempt used rendered INI SHA-256 `997e15752312292951e3f748663f694ece0e684d00bed6393b7241519b54eec5` and frozen complete-run configuration SHA-256 `4d2245f7359a552981e50db6ac1e0990ab2282b71d2e35a6979fb6561d9ef880`.

The replacement preserves both hashes, every strategy/cost/execution input, and all segment boundaries. Only the evidence validator is corrected to distinguish loaded indicator-eligible H1 openings from completed H1 candles processable before the exclusive boundary. No valid losing or low-profit result is being rerun.
