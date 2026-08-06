#!/usr/bin/env python3
"""Create the terminal V31 external-replication report and checksum ledger."""
from __future__ import annotations

import hashlib
import json
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "reports/backtests/phase6-v31-v28-external-feed-replication-attempt2"
DATASET = Path("/home/tibule12/Datasets/SolTrade/V31")
PRODUCTION = ROOT / "MQL5/Experts/SolTradeBot.mq5"
V28_SOURCE = ROOT / "research/factor_momentum/SolTradeDollarFactorPerformanceHarness.mq5"
V31A_EX5 = Path("/home/tibule12/.wine-fpmarkets/drive_c/v31a/SolTradeDollarFactorV31AAdapter.ex5")
EXPECTED_PRODUCTION = "261a9cfe1c1e8d84e2a2a468ac4d0775086b21c89824b117e5127697fd03ced3"
EXPECTED_V28_SOURCE = "726273d332176ae3cb61c927c7959de12d947eed13c30cb2c080d95bc1f7f846"
EXPECTED_V31A_EX5 = "92bf94431803c0213b1d796c3a412b581978c680869b20de299bcef90ec8e886"


def sha(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def load(name: str):
    return json.loads((OUT / name).read_text())


def write(name: str, value) -> None:
    (OUT / name).write_text(json.dumps(value, indent=2, allow_nan=False) + "\n")


def format_metric(value) -> str:
    return "undefined" if value is None else f"{value:.6f}"


def main() -> None:
    gate = load("v31-gate-evaluation.json")
    cells = load("v31-formal-cell-inventory.json")["cells"]
    combined = load("v31-combined-evidence-audit.json")
    raw = load("v31-raw-qualification-summary.json")
    normalized = load("v31-normalized-data-manifest.json")
    qualification = load("data-qualification/qualification-physical-run-inventory.json")
    imports = load("mt5-custom-symbol-import/aggregate-status.json")
    signals = load("signal-generation/signal-generation-status.json")
    runs = load("v31-physical-run-inventory.json")
    integrity = load("v31-evidence-integrity.json")
    safety = load("repository-safety-gate.json")
    outcome = gate["terminal_outcome"]
    allowed = {
        "V31_EXTERNAL_REPLICATION_AND_COMBINED_GATES_PASSED",
        "V31_EXTERNAL_REPLICATION_FAILED",
        "V31_COMBINED_GATES_FAILED",
    }
    if outcome not in allowed:
        raise SystemExit("V31_FINALIZER_UNEXPECTED_OUTCOME")
    required_pass = (
        raw.get("status") == "PASS"
        and normalized.get("status") == "PASS"
        and qualification.get("status") == "PASS"
        and imports.get("status") == "PASS"
        and signals.get("status") == "PASS"
        and runs.get("status") == "PASS"
        and integrity.get("status") == "PASS"
    )
    if not required_pass:
        raise SystemExit("V31_FINALIZER_INVALID_EVIDENCE")
    hashes = {
        "production_phase1_5_sha256": sha(PRODUCTION),
        "frozen_v28_source_sha256": sha(V28_SOURCE),
        "v31a_strategy_equivalent_adapter_ex5_sha256": sha(V31A_EX5),
        "raw_data_manifest_path": str(DATASET / "manifests/v31-raw-data-manifest.jsonl.gz"),
        "raw_data_manifest_sha256": sha(DATASET / "manifests/v31-raw-data-manifest.jsonl.gz"),
        "normalized_data_manifest_sha256": sha(DATASET / "manifests/v31-normalized-data-manifest.json"),
    }
    immutable = (
        hashes["production_phase1_5_sha256"] == EXPECTED_PRODUCTION
        and hashes["frozen_v28_source_sha256"] == EXPECTED_V28_SOURCE
        and hashes["v31a_strategy_equivalent_adapter_ex5_sha256"] == EXPECTED_V31A_EX5
    )
    if not immutable:
        raise SystemExit("V31_FINALIZER_IMMUTABILITY_FAILURE")
    normal_native = next(
        item for item in cells
        if item["cost_profile"] == "NORMAL" and item["execution_layer"] == "NATIVE_NORMAL_EXECUTION"
    )
    failed_independent = gate["failed_independent_gates"]
    failed_combined = [item for item in combined["gates"] if item["status"] == "FAIL"]
    terminal = {
        "schema": "SOLTRADE_PHASE6_V31_TERMINAL_SUMMARY_V1",
        "terminal_outcome": outcome,
        "classification": "INDEPENDENT_EXTERNAL_FEED_HISTORICAL_REPLICATION",
        "cost_model": "EXTERNAL_PRICE_FEED_WITH_FROZEN_CONTROLLED_COST_MODEL",
        "repository_backup": safety,
        "data": {
            "provider": "Dukascopy Bank",
            "symbols": list(normalized["symbols"]),
            "raw_hourly_files": raw["manifested_hourly_files"],
            "raw_ticks": raw["total_tick_count"],
            "normalized_ticks": sum(item["record_count"] for item in normalized["symbols"].values()),
            "mt5_imported_ticks": imports["total_imported_ticks"],
            "mt5_tick_mismatches": imports["exact_timestamp_bid_ask_mismatches"],
            "qualification_runs": len(qualification["runs"]),
            "normalized_interval_server_civil": normalized["normalized_interval_server_civil"],
        },
        "execution": {
            "signals": signals["signals"],
            "cohorts": signals["cohorts"],
            "physical_runs": len(runs["runs"]),
            "formal_cells": len(cells),
            "normal_native": normal_native,
        },
        "sample": gate["sample_summary"],
        "independent_pass": gate["independent_pass"],
        "combined_pass": gate["combined_pass"],
        "failed_independent_gate_count": len(failed_independent),
        "failed_combined_gate_count": len(failed_combined),
        "failed_independent_gates": failed_independent,
        "failed_combined_gates": failed_combined,
        "hashes": hashes,
        "controls": {
            "optimization_or_tuning": False,
            "v29_used": False,
            "connected_chart_trades": 0,
            "demo_forward_trades": 0,
            "live_trades": 0,
            "strategy_tester_simulated_trades_only": True,
            "automatic_push": False,
            "production_phase1_5_unchanged": True,
            "frozen_v28_unchanged": True,
        },
    }
    write("v31-terminal-summary.json", terminal)
    lines = []
    for item in cells:
        lines.append(
            f"| {item['cost_profile']} | {item['execution_layer']} | {item['naturally_closed_trades']} | "
            f"{item['adjusted_net_profit']:.2f} | {format_metric(item['profit_factor'])} | "
            f"{format_metric(item['expectancy_R'])} | {item['relative_drawdown_percent']:.6f}% |"
        )
    failure_text = "None." if not failed_independent else "\n".join(
        f"- `{item.get('cell_id', item.get('scope', 'independent'))}` — {item['gate']}: "
        f"actual `{item.get('actual')}`, required `{item.get('rule', 'frozen rule')}`."
        for item in failed_independent
    )
    report = f"""# Phase 6 V31 — V28 independent external-feed historical replication

## Terminal outcome

`{outcome}`

V31 used only Dukascopy Bank tick-by-tick bid/ask history, converted deterministically into the frozen V28 FP Markets server-civil clock and imported into the seven isolated `.V31` symbols. The raw, normalized and imported histories passed qualification before profitability was exposed. Imported tick mismatches: {imports['exact_timestamp_bid_ask_mismatches']}.

The research classification is `INDEPENDENT_EXTERNAL_FEED_HISTORICAL_REPLICATION`. Costs are labeled `EXTERNAL_PRICE_FEED_WITH_FROZEN_CONTROLLED_COST_MODEL`; they are not claimed to reproduce historical Dukascopy or FP Markets account charges.

## Independent result

The authoritative Normal/Native sample contains {gate['sample_summary']['closed']} closed trades: {gate['sample_summary']['BUY']} BUY and {gate['sample_summary']['SELL']} SELL. The frozen signal schedule contains {signals['signals']} signals in {signals['cohorts']} cohorts.

| Cost profile | Execution | Closed trades | Adjusted net USD | Profit factor | Expectancy R | Drawdown |
|---|---|---:|---:|---:|---:|---:|
{chr(10).join(lines)}

Failed independent gates:

{failure_text}

## Combined-evidence audit

The combined ledger appends preserved V28 2025 and January–July 2026 evidence in chronological order with the original 0.5% risk weighting. It does not alter or reweight either source, and it cannot override an independent V31 failure. Combined status: `{'PASS' if gate['combined_pass'] else 'FAIL'}`; failed combined gates: {len(failed_combined)}.

## Integrity and restrictions

The raw manifest covers {raw['manifested_hourly_files']:,} Dukascopy source files and {raw['total_tick_count']:,} raw ticks. MT5 imported {imports['total_imported_ticks']:,} normalized ticks, with zero exact timestamp/bid/ask mismatches. Seven no-trade qualification runs and two frozen performance runs produced six formal cells.

Frozen V28 and Phase 1–5 production code remained unchanged. No optimization, parameter tuning, symbol or direction exclusion, V29 use, connected-chart trade, demo-forward trade or live trade occurred. Trading activity was confined to isolated Strategy Tester simulations. No automatic push or demo authorization occurred.
"""
    (OUT / "v31-external-replication-report.md").write_text(report)
    retirement = (
        "V28 is permanently retired without tuning because complete valid independent performance evidence failed one or more mandatory gates."
        if outcome == "V31_EXTERNAL_REPLICATION_FAILED"
        else (
            "V28 is retired as unsuitable for demo because the independent replication passed but the combined mandatory gates failed."
            if outcome == "V31_COMBINED_GATES_FAILED"
            else "Every independent and combined gate passed. V31 stops for approval; demo and live trading remain unauthorized."
        )
    )
    (OUT / "phase6-v31-terminal-outcome.md").write_text(
        "# Phase 6 V31 terminal outcome\n\n"
        f"`{outcome}`\n\n"
        f"{retirement}\n\n"
        f"Normal/Native: {normal_native['naturally_closed_trades']} closed trades, net USD {normal_native['adjusted_net_profit']:.2f}, "
        f"PF {format_metric(normal_native['profit_factor'])}, expectancy {format_metric(normal_native['expectancy_R'])} R, "
        f"drawdown {normal_native['relative_drawdown_percent']:.6f}%. Independent failed gates: {len(failed_independent)}; "
        f"combined failed gates: {len(failed_combined)}.\n\n"
        "No optimization, tuning, connected, demo-forward or live trade occurred. Phase 1–5 production code and frozen V28 remained unchanged.\n"
    )
    checksum = OUT / "artifact-sha256-v31-attempt2.txt"
    artifacts = sorted(path for path in OUT.rglob("*") if path.is_file() and path != checksum)
    checksum.write_text("".join(f"{sha(path)}  {path.relative_to(OUT).as_posix()}\n" for path in artifacts))
    print(json.dumps({
        "terminal_outcome": outcome,
        "normal_native": {
            "closed_trades": normal_native["naturally_closed_trades"],
            "net_profit": normal_native["adjusted_net_profit"],
            "profit_factor": normal_native["profit_factor"],
            "expectancy_R": normal_native["expectancy_R"],
            "drawdown_percent": normal_native["relative_drawdown_percent"],
        },
        "failed_independent_gates": len(failed_independent),
        "failed_combined_gates": len(failed_combined),
        "artifact_count": len(artifacts),
        "checksum": str(checksum),
    }, indent=2))


if __name__ == "__main__":
    main()
