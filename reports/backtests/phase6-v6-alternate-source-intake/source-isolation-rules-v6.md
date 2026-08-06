# Phase 6 V6 alternate-source isolation rules

Status: `AWAITING_ALTERNATE_MT5_SOURCE`

These rules prevent the alternate broker’s history or state from contaminating easyMarkets evidence or any future strategy result.

## 1. Source identity

Create a canonical source identity from broker name, exact MT5 server, reported company, terminal build, exact EURUSD symbol, symbol specification, observed timezone information, and captured session schedule. Do not use a raw account login in the identity.

The collection namespace must include a sanitized source key and unique non-trading acquisition instance ID. The instance ID isolates files only and must not alter data classification.

## 2. Terminal and cache isolation

- Use the connected second broker’s own MT5 terminal data and history directories.
- Never copy easyMarkets TKC, HCC, HC, session, symbol, or tester cache files into the alternate terminal.
- Never copy alternate-source files into easyMarkets cache directories.
- Do not merge monthly caches, patch missing months, or concatenate streams from different brokers.
- Record logical paths and hashes; do not commit raw broker cache files.
- Treat any source crossover as an invalidating collision.

## 3. Artifact isolation

All future V6 collection output must use a source-specific child directory under the V6 evidence area, for example:

`sources/<sanitized-broker-server>/<collection-instance-id>/`

That directory must contain its own metadata, real-tick inventory, M1/HCC inventory, session schedule, messages, gaps, qualification result, and aggregate hash manifest. No V4 or V5 artifact may be overwritten.

## 4. State isolation

- Use a new data-qualification marker namespace that is unrelated to execution, risk, one-shot, or position-manager markers.
- The qualification probe must not read or restore trading state.
- Existing V1/V2 connected markers must be hashed before and after any future probe.
- Orders, positions, trade-history files, and marker trees must reconcile unchanged.
- Any state collision invalidates the collection.

## 5. Evidence separation

- easyMarkets remains a separately adjudicated source with history identity `0360f7831290a6fc7bee78c8653c65056bfccbb58dca9f3d2bea8d83c64414b6`.
- The V5 outcome remains `INCONCLUSIVE_INSUFFICIENT_SAMPLE` for reason `INSUFFICIENT_INTERVAL_SPECIFIC_BROKER_EVIDENCE`.
- Alternate-source evidence cannot retroactively resolve or reclassify easyMarkets gaps.
- easyMarkets evidence cannot fill an alternate-source gap.
- Cross-source comparisons, if later authorized, must show separate native results and identities; they must never construct a blended tick stream.

## 6. Classification isolation

Use only the candidate broker’s applicable MT5 session schedule and broker evidence when classifying its gaps. A schedule or closure statement from another broker is inadmissible. General weekend assumptions are inadmissible without source-specific schedule support.

## 7. Code and execution boundary

The intake and qualification layer may observe metadata and history only. It must not alter or invoke:

- strategy signals or parameters;
- risk controls or sizing;
- execution planning or order submission;
- position management;
- reporting rules tied to profitability;
- Phase 1–5 persistence state.

Trade APIs, generated ticks, optimizations, replicas, and Phase 7 actions remain prohibited.

## 8. Invalidating conditions

Invalidate the affected V6 collection on any source ambiguity, cache crossover, missing artifact, hash mismatch, metadata omission, unrecorded terminal build change, session-schedule change, timezone inconsistency, marker change, trade-state change, retrieval failure, or inability to reproduce the same inventory from the frozen source cache.
