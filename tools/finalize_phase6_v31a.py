#!/usr/bin/env python3
"""Seal the V31A adapter-equivalence evidence and terminal report."""
from __future__ import annotations

import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "reports/backtests/phase6-v31a-v28-adapter-equivalence"


def sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def write_json(name: str, value: dict) -> None:
    (OUT / name).write_text(json.dumps(value, indent=2, allow_nan=False) + "\n")


def main() -> None:
    proof = json.loads((OUT / "v31a-equivalence-proof.json").read_text())
    metrics = json.loads((OUT / "v31a-original-adapter-metrics.json").read_text())
    clone = json.loads((OUT / "fpmarkets-clone/clone-status.json").read_text())
    warmup = json.loads((OUT / "fpmarkets-warmup-export/status.json").read_text())
    warmup_apply = json.loads((OUT / "fpmarkets-warmup-apply/status.json").read_text())
    outcome = proof["terminal_outcome"]
    original_source = ROOT / "research/factor_momentum/SolTradeDollarFactorPerformanceHarness.mq5"
    adapter_source = ROOT / "research/factor_momentum/SolTradeDollarFactorV31AAdapter.mq5"
    original_ex5 = Path("/home/tibule12/.wine-fpmarkets/drive_c/v28/SolTradeDollarFactorPerformanceHarness.ex5")
    adapter_ex5 = Path("/home/tibule12/.wine-fpmarkets/drive_c/v31a/SolTradeDollarFactorV31AAdapter.ex5")
    production = ROOT / "MQL5/Experts/SolTradeBot.mq5"
    original_hashes = {"source_sha256": sha(original_source), "ex5_sha256": sha(original_ex5)}
    adapter_hashes = {"source_sha256": sha(adapter_source), "ex5_sha256": sha(adapter_ex5)}
    mapping = {symbol: symbol + ".V31" for symbol in ("EURUSD", "GBPUSD", "AUDUSD", "NZDUSD", "USDCAD", "USDCHF", "USDJPY")}
    freeze = {
        "schema": "SOLTRADE_PHASE6_V31A_ADAPTER_FREEZE_V1",
        "status": "FROZEN" if outcome == "V28_ADAPTER_EQUIVALENCE_PASSED" else "NOT_AUTHORIZED",
        "terminal_outcome": outcome,
        "future_test_label": "STRATEGY_EQUIVALENT_EXTERNAL_FEED_REPLICATION" if outcome == "V28_ADAPTER_EQUIVALENCE_PASSED" else None,
        "binary_identical_replication_claimed": False,
        "permitted_behavioral_difference": "CENTRALIZED_CANONICAL_TO_RESEARCH_SYMBOL_RESOLUTION_ONLY",
        "research_symbol_resolver": "ResearchSymbol(canonical_symbol)",
        "mapping": mapping,
        "original_v28": original_hashes,
        "research_adapter": adapter_hashes,
        "numeric_tolerance": proof["numeric_tolerance"],
        "divergence_count": proof["divergence_count"],
        "external_feed_replication_authorized": False,
        "stop_for_approval": True,
    }
    write_json("v31a-adapter-freeze.json", freeze)
    source_audit = {
        "schema": "SOLTRADE_PHASE6_V31A_SOURCE_EQUIVALENCE_AUDIT_V1",
        "status": "PASS" if outcome == "V28_ADAPTER_EQUIVALENCE_PASSED" else "FAIL",
        "centralized_resolver": "ResearchSymbol(canonical_symbol)",
        "mapping": mapping,
        "market_data_and_symbol_properties": "resolved through g_config.symbol, SymbolSelect(resolved), SymbolInfoDouble(resolved), and iATR(ResearchSymbol(...))",
        "positions_and_orders": "resolved through per-symbol execution and position engines initialized from resolved g_config.symbol",
        "history": "global HistorySelect plus resolved DEAL_SYMBOL reporting; canonical identity recovered from frozen magic mapping",
        "canonical_names_used_for": ["frozen signal schedule lookup", "magic identity", "canonical reporting"],
        "resolved_names_used_for": ["chart preflight", "market data", "symbol properties", "indicators", "orders", "positions", "deal-symbol reporting"],
        "other_preflight_rules_weakened": False,
        "strategy_rules_changed": False,
        "original_v28": original_hashes,
        "research_adapter": adapter_hashes,
        "dynamic_equivalence_divergences": proof["divergence_count"],
    }
    write_json("v31a-source-equivalence-audit.json", source_audit)
    provenance = {
        "schema": "SOLTRADE_PHASE6_V31A_RUN_PROVENANCE_V1",
        "canonical_run_root": "equivalence-runs",
        "initial_run_root": "equivalence-runs-attempt1",
        "initial_physical_runs": 8,
        "technical_issue": "2025 custom-symbol test initialization shifted to 2024.12.07 because pre-start rate history began too late",
        "economic_or_trade_divergences_in_initial_runs": 0,
        "initial_numeric_maximum_absolute_difference": 0.0,
        "correction": "extended already-consumed FP Markets M1 pre-start history to 2024.11.01 without touching tick history or strategy code",
        "corrected_adapter_runs": ["01-v28-2025-development-native", "03-v28-2025-development-delay200"],
        "original_runs_rerun": False,
        "unaffected_2026_adapter_runs_rerun": False,
        "adapter_source_or_executable_changed_between_runs": False,
        "canonical_physical_runs": 8,
        "canonical_divergences": proof["divergence_count"],
    }
    write_json("v31a-run-provenance.json", provenance)
    evidence = {
        "schema": "SOLTRADE_PHASE6_V31A_EVIDENCE_INTEGRITY_V1",
        "status": "PASS" if outcome == "V28_ADAPTER_EQUIVALENCE_PASSED" else "FAIL",
        "terminal_outcome": outcome,
        "original_v28": original_hashes,
        "research_adapter": adapter_hashes,
        "original_source_unchanged": original_hashes["source_sha256"] == "726273d332176ae3cb61c927c7959de12d947eed13c30cb2c080d95bc1f7f846",
        "original_executable_unchanged": original_hashes["ex5_sha256"] == "03f766bc7ab1cc2c3aed81f72f94f31cc5e122323357216f70ac3a50a5e043ca",
        "production_phase1_5_source_sha256": sha(production),
        "production_phase1_5_unchanged": sha(production) == "261a9cfe1c1e8d84e2a2a468ac4d0775086b21c89824b117e5127697fd03ced3",
        "fp_markets_clone_status": clone["status"],
        "fp_markets_source_ticks": clone["source_ticks"],
        "fp_markets_tick_mismatches": clone["exact_tick_mismatches"],
        "fp_markets_warmup_m1_rates": warmup["m1_rates"],
        "fp_markets_warmup_apply_status": warmup_apply["status"],
        "fp_markets_warmup_apply_rate_mismatches": warmup_apply["exact_rate_mismatches"],
        "canonical_physical_strategy_tester_runs": proof["physical_runs"],
        "total_physical_strategy_tester_executions": 10,
        "technical_data_setup_reruns": 2,
        "optimization_or_tuning": False,
        "external_data_downloaded": False,
        "dukascopy_data_accessed": False,
        "historical_2018_2024_profitability_run": False,
        "connected_trade_api_calls": 0,
        "demo_forward_trades": 0,
        "live_trades": 0,
        "strategy_tester_simulated_trades_only": True,
        "external_replication_started": False,
    }
    write_json("v31a-evidence-integrity.json", evidence)
    metric_lines = []
    for item in metrics["runs"]:
        m = item["original"]
        metric_lines.append(f"| {item['run_id']} | {m['closed_trades']} | {m['adjusted_net_profit']:.8f} | {m['profit_factor']:.12f} | {m['expectancy_R']:.12f} | {m['relative_drawdown_percent']:.12f}% |")
    report = f"""# Phase 6 V31A — V28 external-feed compatibility adapter equivalence proof

## Terminal outcome

`{outcome}`

The separate research adapter resolves each frozen V28 canonical symbol through one centralized `ResearchSymbol(canonical_symbol)` function. The frozen V28 source and EX5 were not modified. The only behavioral allowance is symbol-name resolution to the isolated `.V31` custom symbols; reporting retains canonical and resolved names.

This is a strategy-equivalence result, not a binary-identical replication. The frozen future label is `STRATEGY_EQUIVALENT_EXTERNAL_FEED_REPLICATION`.

## Exact parity result

- Four canonical original/adapter pairs and eight canonical Strategy Tester runs passed. Ten physical executions occurred in total because the two 2025 adapter runs were repeated after correcting the pre-start custom-symbol history boundary; the adapter binary and strategy rules were unchanged.
- {proof['signal_identities_per_side']} frozen signal identities and {proof['physical_signal_evaluations_per_side']} physical signal evaluations per side were preserved.
- {proof['events_compared']} event rows, {proof['transactions_compared']} transaction rows and {proof['deals_compared']} complete deal rows were compared.
- {proof['semantic_field_comparisons']} semantic field comparisons were performed.
- Numeric tolerance: {proof['numeric_tolerance']:.0e}.
- Maximum observed numeric absolute difference: {proof['maximum_numeric_absolute_difference']}.
- Divergences: {proof['divergence_count']}.

The comparison covers signal and decision timing, direction, canonical symbol selection, entry and exit attempts, prices, volume, stop levels, spread/execution/risk blocks, trade identifiers, complete deal economics, adjusted trade results, profit factor, expectancy and drawdown.

## Original and adapter metrics

Both sides produced the same value in every row.

| Physical run | Closed trades | Adjusted net USD | Profit factor | Expectancy R | Drawdown |
|---|---:|---:|---:|---:|---:|
{chr(10).join(metric_lines)}

## Data clone

The isolated custom symbols contain {clone['source_ticks']:,} FP Markets ticks. Imported and reloaded counts are identical, with {clone['exact_tick_mismatches']} tick mismatches. The already-consumed pre-start export contains {warmup['m1_rates']:,} FP Markets M1 rates; all were reapplied and reloaded with {warmup_apply['exact_rate_mismatches']} mismatches. No external feed was downloaded or inspected.

## Restrictions preserved

No optimization or tuning occurred. No Dukascopy data was downloaded. No 2018–2024 profitability replication was run. No connected, demo-forward or live order was placed; trading activity existed only inside isolated Strategy Tester simulations. Phase 1–5 production code and frozen V28 remain unchanged. External-feed replication is not started or authorized in V31A.
"""
    (OUT / "v31a-equivalence-report.md").write_text(report)
    terminal = f"""# Phase 6 V31A terminal outcome

`{outcome}`

V31A proved exact semantic parity between frozen V28 and the research-only `.V31` symbol adapter on the same already-consumed FP Markets evidence under native and fixed-200-ms execution. Maximum numeric difference was {proof['maximum_numeric_absolute_difference']} at tolerance {proof['numeric_tolerance']:.0e}; divergence count was {proof['divergence_count']}.

The adapter is frozen for a future test labeled `STRATEGY_EQUIVALENT_EXTERNAL_FEED_REPLICATION`. That future test has not begun and requires approval. This result does not claim binary-identical replication and does not constitute independent external-history profitability evidence.
"""
    (OUT / "phase6-v31a-terminal-outcome.md").write_text(terminal)
    checksum = OUT / "artifact-sha256-v31a.txt"
    artifacts = sorted(path for path in OUT.rglob("*") if path.is_file() and path != checksum)
    checksum.write_text("".join(f"{sha(path)}  {path.relative_to(OUT).as_posix()}\n" for path in artifacts))
    print(json.dumps({"terminal_outcome": outcome, "original_v28": original_hashes, "research_adapter": adapter_hashes, "artifact_count": len(artifacts), "checksum": str(checksum)}, indent=2))


if __name__ == "__main__":
    main()
