# 200MS condition result

`FAIL`

This is a hard E8 prohibited-practice failure. V28 implements one common USD-factor trade idea with seven simultaneous correlated Forex legs. In the qualified FIXED_DELAY_200_MS transaction stream, 12 of 15 cohorts have aggregate initial stop risk at or above the entire USD 250 E8 daily drawdown. The maximum is USD 320.42994455, 3.204299% of the source USD 10,000 starting balance and 128.171978% of the E8 daily limit, at `2025.11.03 10:05:00`.

The exact continuous raw and counted closed profit, target timestamp, daily drawdown, minimum balance/equity, static-floor margin, best E8 server day and daily-cap removals are unresolved. The qualified evidence resets 2026 to USD 10,000, contains no timestamped intraday equity stream, and cannot be mapped to exact historical E8 server-day boundaries. These gaps do not reverse the confirmed hard prohibited-practice failure.

Source-segment profits are retained separately and are not added: 2025 USD 491.50973033; 2026 through July USD 258.79011960. The challenge target is not validly simulated, so no performance or payout stage is run.

The first 2025 cohort alone is sufficient: before any prior trade or cost overlay could change the initial USD 10,000 balance, its aggregate risk is USD 264.92095102, or 105.968380% of the daily drawdown. High and Stress share that native entry stream; the delayed stream's first cohort is independently above USD 250.

Other supported diagnostics: 105 trades (54 BUY, 51 SELL); largest source-segment trade USD 146.11695854 (USDCHF, `2025.04.07 10:05:01`); largest loss USD -62.14457355 (USDJPY, `2025.10.06 07:37:36`); maximum 7 simultaneous and USD-correlated positions; maximum ticket 0.04 lots; maximum interval between completed-trade executions 52.24127315 days (below 60); 0 trades under one minute; visible stop coverage 105/105. The frozen runs processed 119/119 scheduled symbol-signals, with 119 entry attempts, 105 fills, 0 missed signals, 14 pre-order risk blocks, and 0 execution blocks. Exact per-segment direction, symbol, best source-date and concentration diagnostics are in the adjacent CSV files.
