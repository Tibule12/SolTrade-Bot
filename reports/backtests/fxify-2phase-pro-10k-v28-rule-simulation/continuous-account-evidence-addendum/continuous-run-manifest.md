# Continuous run manifest

One USD 10,000 account was tested from 2025-01-01 inclusive through 2026-08-01 exclusive, with warm-up beginning 2024-12-01 and no warm-up trades. Each run processed 133 scheduled legs across 19 natural cohorts, executed 119 entries, rejected 14 entries under the unchanged consecutive-loss risk lock, missed zero signals, and recorded zero execution blocks. The account state was not reset on 2026-01-01. Four July positions remained naturally open at the last pre-cutoff tick; MT5's post-test teardown state is excluded from Phase 1 calculations.

Physical runs: Normal/High/Stress use native zero-delay FP execution plus their frozen reporting cost profiles; 200 ms uses fixed tester delay 200. The retained `technical-failures/reference-normal-attempt1/` run failed only the first addendum cutoff bookkeeping assertion; its trading artifacts match the corrected reference and are not used for metrics.
