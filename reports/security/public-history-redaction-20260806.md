# Public-history security redaction

The unpublished commit range was scanned before publication. Secret values are intentionally absent from this record.

The public tree excludes account-bound deployment exports, live terminal screenshots, connected-terminal screenshots, account-specific MT5 input files, Git bundle backups capable of carrying compressed historical objects, and an archived broker page that embedded MT5 access data. Ephemeral web nonces were removed from retained broker-page archives. Public example input files use a non-runnable account lock.

Retained strategy, guard, test, and equivalence artifacts were preserved. Account-lock values were replaced with a disabled public default, and terminal authorization identities and originating addresses were replaced with explicit redaction markers. The `SolTradeV28` strategy change is limited to its deployment account default; signal, sizing, stop, exit, pair, and risk logic are unchanged.

Historical checksum ledgers that cover redacted evidence are archival records and may not validate against security-redacted copies. Quantitative equivalence results and trade evidence were not recomputed or rewritten.
