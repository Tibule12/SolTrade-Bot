#!/usr/bin/env python3
"""Close V31 at the frozen external-data qualification gate."""
from __future__ import annotations

import gzip
import hashlib
import json
from datetime import datetime, timezone
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "reports/backtests/phase6-v31-v28-external-feed-replication-attempt2"
DATASET = Path("/home/tibule12/Datasets/SolTrade/V31")
RAW = DATASET / "dukascopy-jetta-gzip-raw"
MANIFESTS = DATASET / "manifests"
BUNDLE = Path("/home/tibule12/Backups/SolTrade-Bot-phase6-v31-external-start-431ac5a-20260804.bundle")
PRODUCTION = ROOT / "MQL5/Experts/SolTradeBot.mq5"
V28_SOURCE = ROOT / "research/factor_momentum/SolTradeDollarFactorPerformanceHarness.mq5"
V28_EX5 = Path("/home/tibule12/.wine-fpmarkets/drive_c/v28/SolTradeDollarFactorPerformanceHarness.ex5")
V31A_SOURCE = ROOT / "research/factor_momentum/SolTradeDollarFactorV31AAdapter.mq5"
V31A_EX5 = Path("/home/tibule12/.wine-fpmarkets/drive_c/v31a/SolTradeDollarFactorV31AAdapter.ex5")
SYMBOLS = ("EURUSD", "GBPUSD", "AUDUSD", "NZDUSD", "USDCAD", "USDCHF", "USDJPY")
EXPECTED = {
    "production": "261a9cfe1c1e8d84e2a2a468ac4d0775086b21c89824b117e5127697fd03ced3",
    "v28_source": "726273d332176ae3cb61c927c7959de12d947eed13c30cb2c080d95bc1f7f846",
    "v28_ex5": "03f766bc7ab1cc2c3aed81f72f94f31cc5e122323357216f70ac3a50a5e043ca",
    "v31a_source": "c16c13ff9642faee88424ab7477e7cdf873164210e185ae257d7e61cab0cfca1",
    "v31a_ex5": "92bf94431803c0213b1d796c3a412b581978c680869b20de299bcef90ec8e886",
    "bundle": "bda8dd5144fb97583b9b6f6010df14e899942c44f29984588c10645afd6712fb",
}


def sha(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def write_json(name: str, value: object) -> None:
    (OUT / name).write_text(json.dumps(value, indent=2, allow_nan=False) + "\n")


def iso_msc(value: int | None) -> str | None:
    if value is None:
        return None
    base = datetime.fromtimestamp(value // 1000, timezone.utc)
    return base.strftime("%Y-%m-%dT%H:%M:%S") + f".{value % 1000:03d}Z"


def load_ticks(path: Path):
    document = json.loads(gzip.decompress(path.read_bytes()))
    multiplier = float(document["multiplier"])
    scale = round(1.0 / multiplier)
    timestamp = int(document["timestamp"])
    if not document["times"]:
        return []
    bid = round(float(document["bid"]) * scale)
    ask = round(float(document["ask"]) * scale)
    rows = []
    for delta_time, delta_bid, delta_ask, bid_volume, ask_volume in zip(
        document["times"], document["bids"], document["asks"],
        document["bidVolumes"], document["askVolumes"],
    ):
        timestamp += int(delta_time)
        bid += int(delta_bid)
        ask += int(delta_ask)
        rows.append((timestamp, bid, ask, float(bid_volume), float(ask_volume), multiplier))
    return rows


def crossed_quote_audit(summary: dict) -> dict:
    # The preliminary complete scan located every crossing in these two UTC
    # hours. Recount the complete provider rows in the enclosing three dates
    # and require exact reconciliation to the full-manifest counts.
    results = []
    total = total_both_zero = 0
    for symbol in SYMBOLS:
        count = both_zero = 0
        first = final = None
        affected_files: set[str] = set()
        maximum_inversion = 0
        example = None
        for day in ("09", "10", "11"):
            for path in sorted((RAW / symbol / "2024" / "10" / day).glob("*h_ticks.json.gz")):
                for timestamp, bid, ask, bid_volume, ask_volume, multiplier in load_ticks(path):
                    if bid <= ask:
                        continue
                    count += 1
                    total += 1
                    if bid_volume == 0 and ask_volume == 0:
                        both_zero += 1
                        total_both_zero += 1
                    if first is None:
                        first = timestamp
                        example = {
                            "raw_file": str(path.relative_to(RAW)),
                            "timestamp_utc": iso_msc(timestamp),
                            "bid": bid * multiplier,
                            "ask": ask * multiplier,
                            "bid_points": bid,
                            "ask_points": ask,
                            "bid_volume": bid_volume,
                            "ask_volume": ask_volume,
                        }
                    final = timestamp
                    maximum_inversion = max(maximum_inversion, bid - ask)
                    affected_files.add(str(path.relative_to(RAW)))
        expected_count = int(summary["symbols"][symbol]["crossed_quote_count"])
        if count != expected_count:
            raise SystemExit(f"V31_CROSSED_QUOTE_RECONCILIATION_FAILED_{symbol}_{count}_{expected_count}")
        results.append({
            "symbol": symbol,
            "crossed_quote_count": count,
            "both_reported_volumes_zero_count": both_zero,
            "first_crossed_quote_utc": iso_msc(first),
            "final_crossed_quote_utc": iso_msc(final),
            "affected_raw_files": sorted(affected_files),
            "maximum_bid_above_ask_points": maximum_inversion,
            "first_example": example,
        })
    expected_total = sum(int(summary["symbols"][symbol]["crossed_quote_count"]) for symbol in SYMBOLS)
    if total != expected_total:
        raise SystemExit("V31_CROSSED_QUOTE_TOTAL_RECONCILIATION_FAILED")
    return {
        "schema": "SOLTRADE_PHASE6_V31_CROSSED_QUOTE_AUDIT_V1",
        "status": "FAIL",
        "source": "Dukascopy Bank Jetta historical tick service",
        "parser_semantics": "Initial bid and ask plus provider-supplied per-tick bid/ask deltas; previously matched the Dukascopy BI5 archive exactly on all 4,343 equivalence rows.",
        "crossed_quote_count": total,
        "both_reported_volumes_zero_count": total_both_zero,
        "affected_symbol_count": sum(item["crossed_quote_count"] > 0 for item in results),
        "unaffected_symbols": [item["symbol"] for item in results if item["crossed_quote_count"] == 0],
        "all_crossings_reconciled_to_frozen_raw_summary": True,
        "all_crossings_confined_to_2024_10_09_23_and_2024_10_10_00_utc": True,
        "interpretation": "The preserved provider payload contains bid-above-ask rows. They cannot represent a valid historical market spread and cannot be patched, filtered, interpolated or replaced under the frozen V31 rules.",
        "symbols": results,
    }


def main() -> None:
    raw_summary_path = MANIFESTS / "v31-raw-qualification-summary.json"
    raw = json.loads(raw_summary_path.read_text())
    if raw.get("status") != "FAIL" or raw.get("failure_count") != 6:
        raise SystemExit("V31_EXPECTED_RAW_QUALIFICATION_FAILURE_NOT_ESTABLISHED")
    if any(item.get("reason") != "INVALID_TICK_VALUES" for item in raw["failures"]):
        raise SystemExit("V31_UNEXPECTED_RAW_FAILURE_REASON")
    if any(int(item.get("zero_or_negative", 0)) or int(item.get("backward", 0)) for item in raw["failures"]):
        raise SystemExit("V31_UNEXPECTED_NON_CROSSED_RAW_FAILURE")

    hashes = {
        "production_phase1_5_sha256": sha(PRODUCTION),
        "frozen_v28_source_sha256": sha(V28_SOURCE),
        "frozen_v28_ex5_sha256": sha(V28_EX5),
        "v31a_adapter_source_sha256": sha(V31A_SOURCE),
        "v31a_adapter_ex5_sha256": sha(V31A_EX5),
        "repository_bundle_sha256": sha(BUNDLE),
        "raw_qualification_summary_sha256": sha(raw_summary_path),
        "raw_data_manifest_sha256": sha(MANIFESTS / "v31-raw-data-manifest.jsonl.gz"),
        "predictable_closure_manifest_sha256": sha(MANIFESTS / "v31-predictable-closed-session-hours.jsonl.gz"),
        "tick_gap_audit_sha256": sha(MANIFESTS / "v31-tick-gap-audit.jsonl.gz"),
        "download_run_sha256": sha(RAW / "download-run.json"),
    }
    expected_actual = {
        "production": hashes["production_phase1_5_sha256"],
        "v28_source": hashes["frozen_v28_source_sha256"],
        "v28_ex5": hashes["frozen_v28_ex5_sha256"],
        "v31a_source": hashes["v31a_adapter_source_sha256"],
        "v31a_ex5": hashes["v31a_adapter_ex5_sha256"],
        "bundle": hashes["repository_bundle_sha256"],
    }
    if expected_actual != EXPECTED:
        raise SystemExit(f"V31_IMMUTABILITY_HASH_FAILURE_{expected_actual}")

    crossing = crossed_quote_audit(raw)
    write_json("v31-crossed-quote-audit.json", crossing)
    (OUT / "v31-raw-qualification-summary.json").write_bytes(raw_summary_path.read_bytes())
    write_json("v31-source-data-inventory.json", {
        "schema": "SOLTRADE_PHASE6_V31_SOURCE_DATA_INVENTORY_V1",
        "status": "COMPLETE_DOWNLOAD_QUALIFICATION_FAILED",
        "provider": "Dukascopy Bank",
        "requested_evaluation_interval": "[2018-01-01 00:00:00, 2025-01-01 00:00:00) FP Markets server-civil",
        "source_support_interval_utc": raw["requested_interval_utc"],
        "symbols": list(SYMBOLS),
        "required_open_session_hourly_files": raw["required_open_session_hourly_files"],
        "manifested_hourly_files": raw["manifested_hourly_files"],
        "raw_tick_count": raw["total_tick_count"],
        "raw_bytes": raw["total_raw_bytes"],
        "raw_manifest": {"path": raw["raw_manifest_path"], "sha256": raw["raw_manifest_sha256"]},
        "closure_manifest": {"path": raw["predictable_closed_session_manifest_path"], "sha256": raw["predictable_closed_session_manifest_sha256"]},
        "gap_audit": {"path": raw["tick_gap_audit_path"], "sha256": raw["tick_gap_audit_sha256"], "unresolved_open_session_gap_count": raw["unresolved_open_session_gap_count"], "unresolved_open_session_gap_minutes": raw["unresolved_open_session_gap_minutes"]},
        "raw_files_preserved_unchanged": True,
        "normalized_files_created": 0,
        "custom_symbols_imported": 0,
        "pnl_viewed": False,
    })
    write_json("v31-data-qualification-result.json", {
        "schema": "SOLTRADE_PHASE6_V31_DATA_QUALIFICATION_RESULT_V1",
        "terminal_outcome": "V31_DATA_INSUFFICIENT_OR_INVALID",
        "status": "FAIL",
        "reason": "The single frozen provider contains 12,208 crossed bid/ask ticks across six required symbols during a synchronized 2024-10-09/10 episode.",
        "provider_payload_defect_not_decoder_error": True,
        "decoder_equivalence_checkpoint": {"bi5_rows": 4343, "jetta_rows": 4343, "exact_timestamp_bid_ask_matches": 4343, "mismatches": 0},
        "crossed_quotes": crossing["crossed_quote_count"],
        "affected_symbols": crossing["affected_symbol_count"],
        "zero_or_negative_prices": 0,
        "backward_timestamps": 0,
        "duplicate_timestamps": raw["duplicate_timestamp_count_retained"],
        "missing_required_open_session_files": 0,
        "normalization_authorized": False,
        "mt5_import_authorized": False,
        "profitability_execution_authorized": False,
        "performance_physical_runs": 0,
        "formal_performance_cells": 0,
        "combined_evidence_audit_authorized": False,
        "profitability_metrics_calculated_or_viewed": False,
        "data_failure_not_v28_performance_failure": True,
        "v28_status": "UNCHANGED_AND_NOT_FAILED_EXTERNAL_REPLICATION",
    })
    write_json("v31-execution-stop-record.json", {
        "schema": "SOLTRADE_PHASE6_V31_EXECUTION_STOP_RECORD_V1",
        "terminal_outcome": "V31_DATA_INSUFFICIENT_OR_INVALID",
        "stopped_at": "RAW_EXTERNAL_DATA_QUALIFICATION",
        "normalization": "NOT_RUN_AFTER_FAILED_RAW_GATE",
        "mt5_custom_symbol_import": "NOT_RUN",
        "mt5_qualification_runs": 0,
        "signal_generation_runs": 0,
        "normal_native": "NOT_RUN",
        "high_native": "NOT_RUN",
        "stress_native": "NOT_RUN",
        "normal_fixed_200ms": "NOT_RUN",
        "high_fixed_200ms": "NOT_RUN",
        "stress_fixed_200ms": "NOT_RUN",
        "combined_evidence_audit": "NOT_RUN",
        "tester_simulated_trades": 0,
        "connected_chart_trades": 0,
        "demo_forward_trades": 0,
        "live_trades": 0,
    })
    write_json("v31-evidence-integrity.json", {
        "schema": "SOLTRADE_PHASE6_V31_EVIDENCE_INTEGRITY_V1",
        "status": "PASS",
        "terminal_outcome": "V31_DATA_INSUFFICIENT_OR_INVALID",
        "classification": "INDEPENDENT_EXTERNAL_FEED_HISTORICAL_REPLICATION",
        "repository_safety_gate": "PASS",
        "complete_download": True,
        "raw_manifest_frozen_before_transformation": True,
        "raw_manifest_status": "FAIL_CROSSED_QUOTES",
        "performance_evidence_exists": False,
        "v28_performance_failure": False,
        "optimization_or_tuning": False,
        "provider_change": False,
        "source_rows_filtered_patched_interpolated_or_replaced": False,
        "symbol_or_direction_exclusion": False,
        "v29_used_or_combined": False,
        "orders_or_positions": 0,
        "demo_or_live_trades": 0,
        "automatic_push": False,
        "hashes": hashes,
        "production_phase1_5_unchanged": True,
        "frozen_v28_unchanged": True,
        "v31a_equivalent_adapter_unchanged": True,
        "earlier_evidence_changed": False,
    })
    (OUT / "v31-external-replication-report.md").write_text(
        "# Phase 6 V31 — V28 independent external-feed historical replication\n\n"
        "## Terminal outcome\n\n"
        "`V31_DATA_INSUFFICIENT_OR_INVALID`\n\n"
        "The complete Dukascopy acquisition produced 328,975 preserved hourly files containing 1,128,565,591 bid/ask ticks. Every mandatory open-session hourly response was present, the raw immutable manifest was written, and no zero/negative price or backward timestamp was found.\n\n"
        "Raw qualification nevertheless failed before transformation. The preserved source payload contains 12,208 bid-above-ask ticks across EURUSD, AUDUSD, NZDUSD, USDCAD, USDCHF and USDJPY, all within the two UTC source hours spanning 2024-10-09 23:00 and 2024-10-10 00:00. GBPUSD has no crossing. Of those rows, 8,698 report both bid and ask volume as zero. The decoder is not the cause: the frozen Jetta/BI5 checkpoint matched all 4,343 timestamps, bids and asks exactly.\n\n"
        "V31 requires the imported Dukascopy bid and ask to be used as historical market spread and prohibits filtering, patching, interpolation, provider changes or symbol exclusion. A bid above ask is not a valid market spread. The frozen fail-closed qualification therefore stopped normalization, MT5 import and profitability execution.\n\n"
        "No V28 P&L, profit factor, expectancy, drawdown or profitability classification was calculated or viewed. This is an external-data qualification failure, not a V28 performance failure. V28 remains unchanged and has not failed external replication. No optimization, tuning, tester trade, connected trade, demo-forward trade, live trade, V29 use, symbol exclusion, direction exclusion, or automatic push occurred. Phase 1–5 production code and all earlier evidence remain unchanged.\n"
    )
    (OUT / "phase6-v31-terminal-outcome.md").write_text(
        "# Phase 6 V31 terminal outcome\n\n"
        "`V31_DATA_INSUFFICIENT_OR_INVALID`\n\n"
        "The complete external download and immutable raw manifest cover 328,975 hourly files and 1,128,565,591 ticks. Qualification found 12,208 crossed bid/ask rows in six required symbols during a synchronized two-hour Dukascopy source episode. V31 forbids repairing or excluding those rows, so execution stopped before normalization, MT5 import and profitability.\n\n"
        "No V28 P&L was viewed. V28 remains unchanged and has not failed replication. No optimization, tester/demo/live trade, or Phase 1–5 production-code change occurred.\n"
    )
    checksum = OUT / "artifact-sha256-v31-attempt2.txt"
    artifacts = sorted(path for path in OUT.rglob("*") if path.is_file() and path != checksum)
    checksum.write_text("".join(f"{sha(path)}  {path.relative_to(OUT).as_posix()}\n" for path in artifacts))
    print(json.dumps({
        "terminal_outcome": "V31_DATA_INSUFFICIENT_OR_INVALID",
        "raw_hourly_files": raw["manifested_hourly_files"],
        "raw_ticks": raw["total_tick_count"],
        "crossed_quotes": crossing["crossed_quote_count"],
        "affected_symbols": crossing["affected_symbol_count"],
        "performance_runs": 0,
        "artifact_count": len(artifacts),
        "checksum": str(checksum),
    }, indent=2))


if __name__ == "__main__":
    main()
