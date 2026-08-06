# FX fixing inventory-reversal economic hypothesis

Candidate: `LONDON_FIX_USD_INVENTORY_REVERSAL_1_0`

Status: `PREREGISTERED_BEFORE_SIGNAL_COUNTS_OR_PNL`

The hypothesis is that structural demand for U.S.-dollar immediacy around the 16:00 London WM/Reuters fixing causes dealers to accumulate and distribute dollar inventory before and at the benchmark. After the fixing window closes, dealer inventory unwinds and the U.S. dollar tends to depreciate. For EURUSD, this predicts a positive post-fix EURUSD return.

This is a scheduled liquidity/inventory hypothesis, not a price breakout, continuation, or breakout-retest hypothesis. It does not use Donchian channels, EMA distance, breakout boundaries, losing-trade filters, or any Trend Breakout parameter.

The rationale was frozen from published research before this repository inspected candidate signal counts or P&L. Krohn, Mueller, and Whelan document U.S.-dollar appreciation before major FX fixes and depreciation afterward across G9 currencies, with evidence consistent with structural dollar demand and dealer inventory management. The London benchmark is calculated around 16:00 London time, and the reported reversal persists for hours after the fix.

Primary sources:

- Krohn, Mueller, and Whelan, “Foreign Exchange Fixings and Returns around the Clock,” *Journal of Finance* 79(1), 2024, 541–578: https://onlinelibrary.wiley.com/doi/10.1111/jofi.13306
- Bank of Canada Staff Working Paper 2021-48 manuscript: https://www.bankofcanada.ca/wp-content/uploads/2021/10/swp2021-48.pdf

The published finding is not evidence that this particular retail implementation will be profitable after FP Markets execution and frozen costs. The V25 test is a falsification attempt.

