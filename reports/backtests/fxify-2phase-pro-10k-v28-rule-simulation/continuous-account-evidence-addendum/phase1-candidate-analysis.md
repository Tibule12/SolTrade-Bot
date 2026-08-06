# Phase 1 candidate analysis

- NORMAL: `CONTINUOUS_PHASE1_PASS_CANDIDATE`; target `2025.06.02 10:05:00.273`; profitable days Fixed A/B `56/0`, New York A/B `57/0`; minimum equity `9848.03`; static margin `648.03`.
- HIGH: `CONTINUOUS_PHASE1_PASS_CANDIDATE`; target `2025.06.02 10:05:00.273`; profitable days Fixed A/B `56/0`, New York A/B `56/0`; minimum equity `9838.87`; static margin `638.87`.
- STRESS: `CONTINUOUS_PHASE1_FAIL`; target `NOT_REACHED`; profitable days Fixed A/B `299/0`, New York A/B `300/0`; minimum equity `9783.55`; static margin `583.55`.
- 200MS: `CONTINUOUS_PHASE1_PASS_CANDIDATE`; target `2025.06.02 10:05:01.673`; profitable days Fixed A/B `56/0`, New York A/B `57/0`; minimum equity `9847.28`; static margin `647.28`.

Interpretation A requires cumulative closing balance and equity of at least USD 10,050. Interpretation B requires both realised balance change and equity change of at least USD 50 during the individual trading day. Both are reported; neither timezone choice changes a condition result. Phase 2 is deliberately not entered.
