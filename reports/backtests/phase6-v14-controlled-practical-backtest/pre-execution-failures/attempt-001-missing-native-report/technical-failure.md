# V14 pre-execution technical failure

The first D1/Normal/native pilot produced otherwise valid tester results, but the configured absolute Windows report path did not produce the mandatory native MT5 HTML report. Under the frozen evidence rules this attempt has no valid profitability result and is excluded from the 36-run matrix.

The complete runtime files, tester cache, tester logs and isolated engine state are preserved here. The one permitted technical rerun retains the identical trading configuration and execution instance. Only the non-trading report destination is corrected to an MT5-supported relative path, and the tester evidence counter is corrected to count the synchronous accepted entry deal returned by the unchanged ExecutionEngine.
