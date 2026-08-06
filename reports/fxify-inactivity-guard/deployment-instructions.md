# Deployment instructions

1. Copy `FXIFYInactivityGuard.mq5` into the terminal's `MQL5/Experts` directory and compile it in MetaEditor. Confirm zero errors and zero warnings.
2. Keep `DryRunMode=true`, attach exactly one instance to any continuously open chart, and verify `GUARD_INITIALISED` plus history reconstruction in Experts and `MQL5/Files/FXIFYInactivityGuard/events.csv`. Chart symbol and timeframe do not control the guard.
3. Confirm the intended FXIFY account is trade-enabled, uses USD, exposes the captured EURUSD RAW symbol, and has Algo Trading enabled. Never paste or archive credentials.
4. Confirm FXIFY's written EA approval remains applicable to this exact guard. If the behavior changes, obtain renewed approval.
5. Only after the dry-run and account checks, intentionally change `DryRunMode=false`. The guard then attempts a minimum-volume entry only at/after day 50 and only when every safety check passes.
6. Keep the terminal/VPS running. Monitor day-45, blocked day-50, and day-55 alerts. A blocked attempt is never overridden automatically.

Do not attach multiple instances. An atomic terminal-wide execution lock and account history prevent duplicates, but a single instance is the supported deployment. This work did not connect to or trade any funded/challenge account.
