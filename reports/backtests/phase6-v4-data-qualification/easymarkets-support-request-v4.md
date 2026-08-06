Subject: Clarification requested for 17 EURUSD historical-feed intervals (easyMarkets-Live, MT5)

Hello easyMarkets Support,

We are qualifying EURUSD real-tick history from your easyMarkets-Live MT5 server. For each broker-server-time interval below, MT5 reported the EURUSD trading session as open for more than 15 minutes but the historical feed contained no ticks. Please classify each interval individually as one of:

- official EURUSD trading closure;
- scheduled server maintenance;
- liquidity interruption reflected in your historical feed; or
- missing historical tick data.

A general statement that markets can be quiet will not resolve the qualification. Please provide the applicable server-time schedule, maintenance notice, or feed/data record for each interval.

Intervals (previous tick exclusive to next tick inclusive; easyMarkets-Live server time):
1. 2024.01.05 21:58:59.797 -> 2024.01.07 22:10:27.919 (MT5-open segment 3627 seconds; feed gap 173488122 ms)
2. 2024.01.12 21:59:58.975 -> 2024.01.14 22:10:00.046 (MT5-open segment 3600 seconds; feed gap 173401071 ms)
3. 2024.01.19 21:59:56.091 -> 2024.01.21 22:10:34.698 (MT5-open segment 3634 seconds; feed gap 173438607 ms)
4. 2024.01.26 21:59:58.136 -> 2024.01.28 22:10:00.050 (MT5-open segment 3600 seconds; feed gap 173401914 ms)
5. 2024.02.02 21:59:58.737 -> 2024.02.04 22:10:00.483 (MT5-open segment 3600 seconds; feed gap 173401746 ms)
6. 2024.02.09 21:59:58.610 -> 2024.02.11 22:17:50.652 (MT5-open segment 4070 seconds; feed gap 173872042 ms)
7. 2024.02.16 21:59:58.174 -> 2024.02.18 22:10:08.506 (MT5-open segment 3608 seconds; feed gap 173410332 ms)
8. 2024.02.23 21:59:49.023 -> 2024.02.25 22:10:37.660 (MT5-open segment 3637 seconds; feed gap 173448637 ms)
9. 2024.03.01 21:59:57.096 -> 2024.03.03 22:10:00.037 (MT5-open segment 3600 seconds; feed gap 173402941 ms)
10. 2024.11.01 20:59:58.805 -> 2024.11.03 22:10:00.086 (MT5-open segment 3600 seconds; feed gap 177001281 ms)
11. 2024.11.08 21:59:58.856 -> 2024.11.11 00:13:00.130 (MT5-open segment 10200 seconds; feed gap 180781274 ms)
12. 2024.11.15 21:59:56.198 -> 2024.11.17 22:12:08.374 (MT5-open segment 3728 seconds; feed gap 173532176 ms)
13. 2024.11.22 21:59:58.760 -> 2024.11.24 22:10:00.238 (MT5-open segment 3600 seconds; feed gap 173401478 ms)
14. 2024.11.29 21:55:21.477 -> 2024.12.01 22:10:09.318 (MT5-open segment 3609 seconds; feed gap 173687841 ms)
15. 2024.12.06 21:59:56.301 -> 2024.12.08 22:11:14.109 (MT5-open segment 3674 seconds; feed gap 173477808 ms)
16. 2024.12.13 21:59:56.363 -> 2024.12.15 22:10:00.118 (MT5-open segment 3600 seconds; feed gap 173403755 ms)
17. 2024.12.20 21:54:49.030 -> 2024.12.22 22:10:13.272 (MT5-open segment 3613 seconds; feed gap 173724242 ms)

Context: EURUSD, H1 tester, real ticks, requested interval [2024-01-02 00:00:00, 2024-12-24 00:00:00). This was an inert data-qualification probe; no strategy, orders, deals, positions, or performance result was generated.

Please identify the evidence/source for each answer. Thank you.
