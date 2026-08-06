# Phase 6 V6 status

## Current status

`AWAITING_ALTERNATE_MT5_SOURCE`

The V6 repository preparation is documentation and manifest templating only. No second broker terminal has been connected or qualified under V6.

## Preserved prior outcome

- V5 adjudication commit: `240bd837a98a5526711bae25376ee01e540193a9`
- easyMarkets V4 history identity: `0360f7831290a6fc7bee78c8653c65056bfccbb58dca9f3d2bea8d83c64414b6`
- easyMarkets outcome: `INCONCLUSIVE_INSUFFICIENT_SAMPLE`
- easyMarkets reason: `INSUFFICIENT_INTERVAL_SPECIFIC_BROKER_EVIDENCE`

The alternate-source intake does not modify, replace, combine with, or resolve that evidence.

## Frozen V6 intake boundaries

- Warm-up: `[2024-01-02, 2024-01-16)`
- Research: `[2024-01-16, 2024-12-24)`
- Development: `[2024-01-16, 2024-07-05)`
- Validation: `[2024-07-05, 2024-09-29)`
- Out-of-sample: `[2024-09-29, 2024-12-24)`
- Open-session gap threshold: strictly longer than 15 minutes.
- Data model: broker-native real ticks only.

## Pending gate

Before any qualification run, a second MT5 demo source must be connected and every mandatory field in `alternate-source-manifest-template-v6.json` must be populated and reviewed. The first authorized connected V6 run, if later approved, will be data qualification only and must stop after producing its evidence package.

## Activity confirmation

- No strategy run occurred.
- No profitability calculation occurred.
- No optimization occurred.
- No authoritative matrix or replica occurred.
- No generated, synthetic, interpolated, or cross-broker ticks were used.
- No connected, demo, or live trade occurred.
- No Phase 7 action occurred; Phase 7 remains unauthorized.
- No test was run.
- Phase 1–5 code remained unchanged.
- Strategy parameters and frozen Phase 6 research gates remained unchanged.
