# Phase 3 Connected MetaTrader Verification

## Install and compile

1. Copy `MQL5/Experts/SolTradeBot.mq5` into the connected terminal data
   directory under `MQL5/Experts`.
2. Replace the complete terminal `MQL5/Include/SolTrade` folder with the
   repository folder.
3. Copy `MQL5/Scripts/SolTradeStrategyTests.mq5` into `MQL5/Scripts`.
4. Compile `SolTradeBot.mq5` and `SolTradeStrategyTests.mq5` in MetaEditor.
5. Require `0 errors, 0 warnings` for both and confirm both `.ex5` files exist.

## Deterministic script

On a connected demo terminal, run `SolTradeStrategyTests` from
Navigator → Scripts. The script uses only in-memory historical H1 fixtures and
does not submit trade requests.

Required Experts-log ending:

```text
SolTrade Strategy tests complete: 61 passed, 0 failed
ALL SOLTRADE PHASE 3 STRATEGY TESTS PASSED
```

## EA signal-only observation

Attach `SolTradeBot` to an EURUSD H1 demo chart.

Before the first post-attachment H1 boundary, the dashboard must show:

```text
Build scope: SIGNAL DISPLAY ONLY - PHASE 3
Entry signal: WAITING
Exit signal: WAITING
```

At the next completed H1 candle, it must show:

- signal bar time;
- entry signal `BUY`, `SELL`, or `NONE`;
- entry reason code and description;
- exit signal `EXIT_LONG`, `EXIT_SHORT`, or `NONE`;
- exit reason code and description;
- completed-candle close, EMA 200, ATR 14;
- Donchian 20 entry high/low;
- Donchian 10 exit high/low;
- `2 × ATR` initial-stop distance.

The CSV must contain one `STRATEGY_SIGNAL_EVALUATED` row for that candle.
`signal_result` contains the entry signal. `rejection_reason` contains the
structured no-signal reason when the result is `NONE`. `details` contains the
signal bar, all indicator/channel values, entry/exit signals, and both reason
codes and descriptions.

## Safety confirmation

During the script and EA observation:

- no order or deal may be created;
- no position may open or close;
- no stop-loss request may be sent;
- existing positions must not be inspected, adopted, or modified.

Phase 3 source contains no execution or position-management module and no MQL5
trading API call.
