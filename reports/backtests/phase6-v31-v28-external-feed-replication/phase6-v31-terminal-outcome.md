# Phase 6 V31 terminal outcome

`INVALID_TEST_EVIDENCE`

Repository safety passed before any external-data action. The verified all-refs bundle contains 40 refs and complete history. V31 is classified as an independent external-feed historical replication, and the FP Markets New-York-close server-time basis can be reconstructed deterministically.

Execution cannot proceed without violating a frozen requirement. V31 requires the seven isolated `.V31` custom symbols, while the exact frozen V28 source and EX5 hardcode the seven unsuffixed broker symbols. The preflight also requires `_Symbol == EURUSD` and `FPMarketsSC-Demo`. MT5 custom-symbol names are unique and tick import targets the explicitly named custom symbol, so no alias can make the unchanged V28 executable read the `.V31` histories. Changing the symbol array or preflight changes the frozen hashes; patching broker histories violates V31.

The phase therefore stopped before raw tick download, transformation, custom-symbol creation, import, qualification or profitability. No P&L or profitability metric was viewed, no order or position was created, and no demo/live trade, optimization, tuning, V29 use or automatic push occurred. This is an invalid evidence design, not a V28 performance failure. V28 and production Phase 1-5 remain unchanged.
