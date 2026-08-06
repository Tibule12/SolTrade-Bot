# Synthetic historical-gap simulation

Original V28 entries are `2026-02-02 10:05:01` and `2026-04-06 10:05:00`, an interval of 62d 23:59:59. The guard warns at `2026-03-19 10:05:01` (day 45), calculates one safe maintenance entry at `2026-03-24 10:05:01` (day 50), and resets only after the synthetic executed guard `DEAL_ENTRY_IN`. At the next V28 entry, only 12d 23:59:59 has elapsed. The account never reaches 60 consecutive inactive calendar days.

The default projected worst-case cost is USD 1.22 using the captured 0.6-pip EURUSD RAW snapshot, official USD 6/lot commission, 0.01 lot, 10-pip stop, and 1-pip configured slippage. The simulation does not claim this snapshot is historical FXIFY spread history.
