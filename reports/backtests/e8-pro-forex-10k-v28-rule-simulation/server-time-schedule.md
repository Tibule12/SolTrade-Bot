# E8 server-time schedule

The official source says E8 server time changes to UTC+3 at the end of March and UTC+2 at the beginning of November. It does not give exact historical 2025 or 2026 transition dates/timestamps, and no authoritative mapping from the FP Markets source timestamps to E8 time exists.

Accordingly, every tested date from 2025-01-01 through 2026-07-31 is present in `server-time-date-coverage.csv` with exact offset `UNRESOLVED`. All server-day profit-cap, cap-removal, daily-drawdown, best-day and target-timestamp calculations remain unresolved. No DST transition is guessed.
