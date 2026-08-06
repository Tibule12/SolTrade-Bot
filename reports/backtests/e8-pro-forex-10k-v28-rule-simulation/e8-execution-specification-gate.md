# E8 execution-specification gate

Gate result: `FAIL_INSUFFICIENT_E8_SPECIFICATIONS`.

| Field | Evidence | Status |
|---|---|---|
| Seven marketing symbols | EURUSD, GBPUSD, AUDUSD, NZDUSD, USDCAD, USDCHF, USDJPY appear publicly | Partial; exact MT5 suffixes unresolved |
| Forex contract size | 100,000 units | Established generally |
| Forex leverage | 1:30 | Established |
| Ticket cap | 50 lots ordinary symbols | Established |
| Tick size/value | No public seven-symbol MT5 table obtained | Unresolved |
| Minimum volume/step/symbol maximum | Protected live-symbol endpoint; no public table obtained | Unresolved |
| Margin calculation | General leverage/equity formula published | Partial; exact MT5 calculation/spec flags unresolved |
| Commission/spread selection | E8 Pro offers raw or no-commission choices | Unresolved for the requested preset |
| Typical spreads | Protected live-symbol endpoint returned HTTP 403 | Unresolved |
| Swap long/short and triple-swap day | No complete official table found | Unresolved |
| Server timezone | Broad UTC+2/UTC+3 seasons only | Exact historical transitions unresolved |
| Execution restrictions/slippage | General simulated slippage and limits published | Exact per-symbol MT5 execution configuration unresolved |

FP Markets specifications are not substituted for E8. The qualified Normal, High, Stress and 200 ms streams remain sensitivity evidence, not an exact E8 execution replication. These limitations could change continuous sizing, costs, rollover grouping and drawdown; they independently block a PASS, but do not undo the hard correlated-risk policy failure.
