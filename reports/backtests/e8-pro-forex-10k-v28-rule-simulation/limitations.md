# Limitations

- No technically valid continuous 2025–2026 account exists; source periods reset independently.
- No timestamped full intraday equity/balance stream exists.
- Exact historical E8 UTC+2/UTC+3 transition instants are unpublished.
- FP Markets source timestamps have no authoritative conversion to E8 server time.
- Complete E8 MT5 specifications for all seven symbols were unavailable; the protected endpoint returned HTTP 403.
- High/Stress costs are closed-trade sensitivity overlays and cannot drive native subsequent sizing or intraday equity.
- Server request CSVs are not complete network traces.
- Source-segment P&L and symbol/direction contributions are reported separately and never added into a purported continuous result.
- No checkout, purchase, registration, V31 restart, V29 use, strategy change, optimization, production change, performance simulation, demo trade or live trade occurred.
