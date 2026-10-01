# FXIFY recorded ENTRY/EXIT and score diagnostic

These are descriptive EA-event results, not an independent broker ledger or a counterfactual strategy run. The two logins are kept separate because many entries are copies of one signal. Scores are recorded at entry; realized R uses recorded net cash divided by the entry's initial dollar risk.

| Login | Closed positions | W / L | All recorded net | Sep 13–16 exits/net | Sep 13 flat equity → Sep 16 paused equity | Reconciliation gap |
|---|---:|---:|---:|---:|---:|---:|
| 7196820 | 22 | 10 / 12 | −$336.99 | 4 / −$379.17 | $10,039.41 → $9,660.24 | $0.00 |
| 7198096 | 22 | 10 / 12 | −$3,594.40 | 4 / −$3,915.76 | $100,321.36 → $96,405.60 | $0.00 |

The baseline bridge posts each post-September-13 whole-position net at its recorded EA `EXIT` UTC. No Bank1R partial was confirmed in that cohort. This reconstructs a closed-balance path at exits, not intratrade equity or provider daily-loss enforcement. The September 16 pause runtime is the last preserved FXIFY account-state row; it does not prove present broker exposure.

## Recorded admission-score association

| Login / cohort | Scored trades | Pearson score vs net R | Spearman score vs net R |
|---|---:|---:|---:|
| 7196820 / all_recorded_mixed_managers | 22 | -0.250 | -0.252 |
| 7196820 / bank1r_from_2026_09_13 | 4 | -0.460 | 0.000 |
| 7198096 / all_recorded_mixed_managers | 22 | -0.318 | -0.389 |
| 7198096 / bank1r_from_2026_09_13 | 4 | -0.440 | 0.400 |

### Admission-score bins

| Login / cohort | Score interval | Trades | W / L | Net R |
|---|---|---:|---:|---:|
| 7196820 / all_recorded_mixed_managers | 60-62.5 | 8 | 5 / 3 | +2.074 |
| 7196820 / all_recorded_mixed_managers | 62.5-65 | 3 | 1 / 2 | -0.909 |
| 7196820 / all_recorded_mixed_managers | 65-67.5 | 4 | 1 / 3 | -1.954 |
| 7196820 / all_recorded_mixed_managers | 67.5-70 | 1 | 0 / 1 | -1.005 |
| 7196820 / all_recorded_mixed_managers | 70-72.5 | 3 | 2 / 1 | +0.343 |
| 7196820 / all_recorded_mixed_managers | 75-77.5 | 1 | 1 / 0 | +0.206 |
| 7196820 / all_recorded_mixed_managers | 77.5+ | 2 | 0 / 2 | -1.016 |
| 7196820 / bank1r_from_2026_09_13 | 60-62.5 | 1 | 0 / 1 | -1.009 |
| 7196820 / bank1r_from_2026_09_13 | 62.5-65 | 1 | 0 / 1 | -0.967 |
| 7196820 / bank1r_from_2026_09_13 | 65-67.5 | 1 | 0 / 1 | -1.020 |
| 7196820 / bank1r_from_2026_09_13 | 67.5-70 | 1 | 0 / 1 | -1.005 |
| 7198096 / all_recorded_mixed_managers | 60-62.5 | 9 | 6 / 3 | +2.799 |
| 7198096 / all_recorded_mixed_managers | 62.5-65 | 2 | 0 / 2 | -1.030 |
| 7198096 / all_recorded_mixed_managers | 65-67.5 | 5 | 1 / 4 | -2.943 |
| 7198096 / all_recorded_mixed_managers | 67.5-70 | 1 | 0 / 1 | -1.005 |
| 7198096 / all_recorded_mixed_managers | 70-72.5 | 3 | 2 / 1 | +0.346 |
| 7198096 / all_recorded_mixed_managers | 75-77.5 | 1 | 1 / 0 | +0.206 |
| 7198096 / all_recorded_mixed_managers | 77.5+ | 1 | 0 / 1 | -1.071 |
| 7198096 / bank1r_from_2026_09_13 | 60-62.5 | 1 | 0 / 1 | -1.009 |
| 7198096 / bank1r_from_2026_09_13 | 62.5-65 | 1 | 0 / 1 | -0.967 |
| 7198096 / bank1r_from_2026_09_13 | 65-67.5 | 1 | 0 / 1 | -1.006 |
| 7198096 / bank1r_from_2026_09_13 | 67.5-70 | 1 | 0 / 1 | -1.005 |

Bins are fixed at 2.5 score points. Directional/opposite score associations and every trade are in `fxify-event-diagnostic.json` and the account-specific CSVs. Four Bank1R-era observations per login cannot validate a score threshold; paired signals across accounts are not independent confirmations. The earlier cohort mixes manager versions and 0.25%/1.00% sizing.

The nominal-inception arithmetic gap is −$2.77 on 10K and $0.00 on 100K, and the 10K difference is explained by two earlier local August pilot EA closes (−$1.72 and −$1.05; `fxify-august-pilot-bridge.json`). Neither account has independently exported complete inception broker-deal/cash-flow history here. Missing FXIFY broker deals/orders and continuous bid/ask/equity paths prevent independent settlement, daily drawdown, or exact challenge-counterfactual claims.
