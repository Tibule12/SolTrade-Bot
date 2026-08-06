# V28 attempt 1 technical diagnosis

Attempt 1 is retained as invalid technical evidence and is ineligible for financial evaluation.

- All 77 scheduled 2025 signals were processed.
- The harness accepted 33 entries, but only 26 position identifiers had an exit deal in the exported ledger.
- Monthly exit submissions and replacement entries occurred on the same tester tick.
- Delayed exit callbacks could therefore clear the scheduled exit timestamp belonging to a newly opened replacement position.
- Later signals for affected symbols were rejected as `EXISTING_SOLTRADE_POSITION`.

Attempt 2 changes only tester-event serialization: after any accepted scheduled exit submission, replacement entries wait until a later tick within the unchanged five-minute entry window. Signal generation, direction, risk, stops, costs, datasets, and profitability gates remain frozen.
