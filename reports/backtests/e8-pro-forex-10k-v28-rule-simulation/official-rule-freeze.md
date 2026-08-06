# Official E8 Pro Forex rule freeze

The bounded configuration is one USD 10,000 challenge phase on MT5, 80% payout selection, 8% closed-profit target (USD 800), 2.5% fixed daily drawdown (USD 250), 8% static drawdown (USD 800; floor USD 9,200), 2% daily profit cap (USD 200), unlimited days, no minimum days or consistency rule, 60-day inactivity, unrestricted news, and permitted overnight/weekend holding. Forex leverage is 1:30.

Performance resets to USD 10,000 and has no new target. Before first payout the floor remains USD 9,200. Official payout materials say at least 1% profit is required, profit is split 50% requestable/50% buffer, and the selected share applies to the requestable half. A general final payment minimum of USD 100 at 80% requires a requestable USD 125; therefore USD 250 accumulated profit is the derived minimum because USD 250 × 50% × 80% = USD 100. After first payout the floor moves to USD 10,000.

The daily cap and daily loss level are server-day rules. Cap excess is removed after rollover and must reduce later balance-dependent sizing. Balance or equity reaching the daily loss level or static floor is a breach. EAs are allowed, but risking the entire daily drawdown on one trade idea is prohibited; over 1% per idea is not a universal automatic hard limit.
