# Phase 6 V5 easyMarkets broker-evidence adjudication

Date: 2026-08-03

Scope: evidence adjudication only

Symbol: EURUSD

Broker server: easyMarkets-Live

V4 history identity: `0360f7831290a6fc7bee78c8653c65056bfccbb58dca9f3d2bea8d83c64414b6`

Immutable V4 commit reference: `366918a7a6216d80147ba7d5b233f19586e7260b`

## Terminal outcome

`INCONCLUSIVE_INSUFFICIENT_SAMPLE`

Reason: `INSUFFICIENT_INTERVAL_SPECIFIC_BROKER_EVIDENCE`

The authoritative strategy matrix remains unauthorized. Profitability remains unknown. No strategy run, optimization, replica, generated-tick substitution, connected trade, demo trade, live trade, or Phase 7 action was performed.

## Evidence basis and limitation

The adjudication uses the immutable V4 gap report and the user-supplied transcription in `easymarkets-response-transcription-v5.md`. The original broker email, headers, attachments, and screenshots were not supplied. Therefore the transcription is preserved as evidence of the information provided for review, but it is not represented as a primary email export.

The phrase “generally correspond” is general guidance. It is not interval-specific confirmation and does not establish the cause of any individual gap.

## Broker-confirmed facts

These are facts about what easyMarkets stated, not proof of the cause of a particular 2024 interval:

- easyMarkets stated that EURUSD is normally closed from Friday 21:00 until Sunday 21:10.
- easyMarkets stated that EURUSD has a daily break from 21:00 until 21:10.
- easyMarkets stated that the 17 intervals “generally correspond” with normal EURUSD market closures.
- easyMarkets declined a detailed retrospective technical investigation because the account is not currently trading.
- easyMarkets supplied no timezone for the stated hours.
- easyMarkets supplied no interval-by-interval confirmation.
- easyMarkets supplied no explanation for the conflict with the MT5 session API.
- easyMarkets supplied no determination of missing ticks, server maintenance, or another data issue for any interval.

## Likely interpretations

- Sixteen intervals occur around a Friday-to-Sunday boundary and may reflect ordinary weekend closure timing.
- The apparent one-hour seasonal shift in some tick boundaries may be consistent with an unspecified daylight-saving convention.
- These interpretations are plausible only. The missing timezone and MT5-open-session conflict prevent them from becoming confirmed classifications.
- Gap 11 is not adequately explained by the general weekend schedule because it extends until Monday `2024.11.11 00:13:00.130` and contains a V4 open-session segment of 10,200 seconds.

## Unsupported assumptions

The following assumptions are prohibited by the available evidence:

- that “generally correspond” confirms all 17 intervals individually;
- that the stated hours use the same timezone as the recorded MT5 tick timestamps;
- that the MT5 session API was wrong;
- that every interval was an official closure;
- that none of the intervals contains missing historical ticks;
- that server maintenance, a liquidity interruption, or another data issue can be ruled out;
- that M1-bar presence proves underlying real-tick completeness;
- that weekend proximity is sufficient to approve a gap.

## Unresolved questions

- What timezone and daylight-saving rules applied to the stated EURUSD hours in 2024?
- Why did the MT5 symbol-session API report each interval as open?
- What caused each individual interval?
- Did any interval contain missing historical ticks, maintenance, a feed interruption, or another data issue?
- Why did gap 11 extend through Monday 00:13 broker-server time?
- Can easyMarkets provide interval-specific schedules, maintenance records, or historical-feed confirmation?

## Adjudication

All 17 V4 gaps remain `UNRESOLVED`. No gap is reclassified as a scheduled weekend, declared closure, maintenance interval, or missing-data interval. M1 bars were present inside all 17 intervals, but that fact does not resolve real-tick completeness.

Because the evidence does not resolve the timezone, interval-specific causes, or MT5 session-status conflict, the historical dataset remains unauthorized for authoritative Phase 6 backtesting.

## Safety and scope confirmation

- Phase 1–5 trading logic was not changed.
- Strategy, risk, execution, and position-management code was not changed.
- Frozen dates, 15-minute gap threshold, and tick data were not changed.
- V4 evidence files and the V4 commit reference were not modified by this adjudication.
- No tests were run.
- No terminal, Strategy Tester, optimization, broker, order, deal, or position action was performed.
