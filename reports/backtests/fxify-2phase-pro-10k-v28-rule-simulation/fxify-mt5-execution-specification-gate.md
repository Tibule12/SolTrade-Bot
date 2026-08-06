# FXIFY MT5 RAW execution-specification gate

Gate: `INSUFFICIENT_FOR_EXACT_FXIFY_REPLICATION`.

Official evidence establishes RAW symbols EURUSD.r, GBPUSD.r, AUDUSD.r, NZDUSD.r, USDCAD.r, USDCHF.r and USDJPY.r; Forex contract size 100,000; five display digits except three for USDJPY.r; 30:1 leverage; and USD 6 per lot round-trip RAW commission. RAW spreads are described as close to zero and an official read-only account is published, but no historical spread series is supplied.

Exact trade tick size/value, minimum volume, volume step, maximum volume, per-symbol margin flags, historical spreads, swap-long/short, triple-swap day, server timezone and historical execution/slippage configuration were not established for all seven symbols. FXIFY is not assumed identical to FP Markets. Normal, High, Stress and 200 ms remain qualified sensitivity evidence, not exact FXIFY-feed replication.
