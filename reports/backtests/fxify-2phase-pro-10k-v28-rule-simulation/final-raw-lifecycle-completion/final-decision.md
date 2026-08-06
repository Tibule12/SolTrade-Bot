# Final FXIFY RAW lifecycle decision

`PURCHASE_NOT_AUTHORIZED`

Actual RAW candidate, Normal support, High support, and 200 ms support all pass Phase 1 on the conservative common evidence transition and remain in Phase 2 during the confirmed no-entry interval. Phase 2 never reaches its USD 10,800 target before the inactivity deadline. The last entry is `2026.02.02 10:05:01` (200 ms: `10:05:02`); the next is `2026.04.06 10:05:00`. The exact gaps are 62d 23:59:59 and 62d 23:59:58 respectively, with no executed entry inside. The 60-day hard breach occurs at `2026.04.03 10:05:01` (200 ms: `10:05:02`).

| Profile | Phase 1 outcome / timestamp | P1 profitable days A | P1 daily / static margin (USD) | Phase 2 outcome / timestamp | P2 profitable days A | P2 daily / static margin (USD) | Funded / payout |
|---|---|---:|---|---|---:|---|---|
| ACTUAL_RAW_CANDIDATE | PASS_SUPPORTED / 2025.06.02 10:05:00.273 | 56_SUPPORT_CONSENSUS | >=178.31299771_SUPPORT_ENVELOPE / >=638.87050896_SUPPORT_ENVELOPE | FAIL_INACTIVITY / 2026.04.03 10:05:01 | 28 | >=158.04299105_SUPPORT_ENVELOPE / >=308.69035761_SUPPORT_ENVELOPE | NOT_ENTERED / USD 0 gross, USD 0 trader share |
| NORMAL | PASS / 2025.06.02 10:05:00.273 | 56 | 178.94959999999992 / 648.0299999999988 | FAIL_INACTIVITY / 2026.04.03 10:05:01 | 60 | 162.27360000000036 / 324.03999999999905 | NOT_ENTERED / USD 0 gross, USD 0 trader share |
| HIGH | PASS / 2025.06.02 10:05:00.273 | 56 | 178.3129977113531 / 638.8705089583218 | FAIL_INACTIVITY / 2026.04.03 10:05:01 | 28 | 158.0429910452495 / 308.69035761455416 | NOT_ENTERED / USD 0 gross, USD 0 trader share |
| 200MS | PASS / 2025.06.02 10:05:01.673 | 56 | 178.6252000000004 / 647.2799999999988 | FAIL_INACTIVITY / 2026.04.03 10:05:02 | 60 | 163.65600000000086 / 355.9599999999991 | NOT_ENTERED / USD 0 gross, USD 0 trader share |

Funded status is never entered. First payout eligibility is none, gross payout is USD 0, and the 80% trader share is USD 0. Stress is supplementary and fails while still in Phase 1; it is not used as the automatic actual-RAW programme decision. The pre-tax NEW30 price is USD 90.30, but no checkout total is established and the strategy has already failed a required programme rule. V28 and production are unchanged; no purchase and no push occurred.

V28_FXIFY_2PHASE_PRO_10K_FAILS_REQUIRED_RULES
