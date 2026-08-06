# Restart and Recovery Cases

Phase 5 persists entry attempts and position-close claims, then reconciles them
with broker-authoritative exposure. Position management remains default-off.

| ID | Event | Current expectation |
|---|---|---|
| RR-01 | Remove and reattach EA | New init/shutdown events; bar detector seeds without a false old signal |
| RR-02 | Change an input | Clean deinit/reinit; updated config shown and journaled |
| RR-03 | Restart terminal | Account mode re-detected; consumed execution candle restored; no replay |
| RR-04 | Disconnect network | Market invalid/disconnected reason shown |
| RR-05 | Reconnect network | Validation recovers when a fresh tick/history arrive |
| RR-06 | Missing H1 history | Insufficient-history reason; no repeated tick spam |
| RR-07 | Journal path cannot open | Initialisation fails closed |
| RR-08 | Existing manual position on EURUSD | Detect conflict, lock new entry, never adopt or modify it |
| RR-09 | Existing SolTrade magic position | Detect, lock new entries, rebuild exact identity, and display stop-protection state |
| RR-10 | New bar after restart | Exactly one new-bar observation after seeding |
| RR-11 | Restart during a daily lock | Same daily baseline and lock restore from risk-state file |
| RR-12 | Restart during a weekly lock | Same weekly baseline and lock restore |
| RR-13 | Restart after emergency trigger | Emergency lock remains latched even if equity recovered |
| RR-14 | Corrupt risk-state schema/value | EA initialisation fails closed with exact state error |
| RR-15 | Set `ResetEmergencyLock=true` below threshold | Reset is recorded and emergency immediately re-latches |
| RR-16 | Set `ResetEmergencyLock=true` above threshold | Emergency clears explicitly; daily/weekly locks remain unchanged |
| RR-17 | Reattach between H1 boundaries | Strategy shows `WAITING`; no historical candle is misreported as new |
| RR-18 | First new H1 bar after reattach | Exactly one structured strategy evaluation is logged |
| RR-19 | Restart after an order attempt but before confirmed transaction logging | Persisted candle remains consumed; broker exposure is rescanned; no resubmission |
| RR-20 | Corrupt execution-state checksum/schema | EA initialisation fails closed with exact state error |
| RR-21 | Broker rejected the prior request | Restored candle remains consumed; no automatic retry |
| RR-22 | SolTrade position has no stop after restart | Visible unprotected-position alert; entries locked; no silent stop repair |
| RR-23 | Restart with an unclaimed owned position | Rebuild exact broker ticket/identifier, direction, volume, open price, and stop |
| RR-24 | Restart after persistent close claim but before broker call/result | Restore consumed claim; never replay the close |
| RR-25 | Restart after close rejection | Restore consumed claim and broker diagnostics; no retry |
| RR-26 | Broker position identifier changed | Treat it as a genuinely new position and clear only the prior position's claim |
| RR-27 | Manual volume or stop change | Detect and journal the changed broker snapshot; never redirect an existing claim |
| RR-28 | More than one SolTrade magic position | Position state invalid; fail closed |
| RR-29 | Corrupt position-state checksum/schema | EA initialisation fails closed; no entry or close broker call |
| RR-30 | Valid matching exit deal already recorded | Restore last deal ticket; duplicate transaction is ignored |
