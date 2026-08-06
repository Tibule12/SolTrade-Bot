#!/usr/bin/env python3
"""Seal V31 before data download when frozen V28 cannot address V31 custom symbols."""
from __future__ import annotations

import hashlib
import json
import subprocess
from datetime import datetime, timedelta, timezone
from pathlib import Path
from zoneinfo import ZoneInfo

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "reports/backtests/phase6-v31-v28-external-feed-replication"
BUNDLE = ROOT / "backups/phase6-v31-prerun-all-refs.bundle"
V28 = ROOT / "reports/backtests/phase6-v28-dollar-factor-momentum"
SOURCE = ROOT / "research/factor_momentum/SolTradeDollarFactorPerformanceHarness.mq5"
EX5 = Path("/home/tibule12/.wine-fpmarkets/drive_c/v28/SolTradeDollarFactorPerformanceHarness.ex5")
PRODUCTION = ROOT / "MQL5/Experts/SolTradeBot.mq5"
SYMBOLS = ("EURUSD", "GBPUSD", "AUDUSD", "NZDUSD", "USDCAD", "USDCHF", "USDJPY")
CUSTOM = tuple(symbol + ".V31" for symbol in SYMBOLS)
EXPECTED_BUNDLE = "75794a22a8b5abe5028c6be9c819d3d2f0cebfe9a430176bbe46f59f0cc1b4f2"
EXPECTED_SOURCE = "726273d332176ae3cb61c927c7959de12d947eed13c30cb2c080d95bc1f7f846"
EXPECTED_EX5 = "03f766bc7ab1cc2c3aed81f72f94f31cc5e122323357216f70ac3a50a5e043ca"
EXPECTED_PRODUCTION = "261a9cfe1c1e8d84e2a2a468ac4d0775086b21c89824b117e5127697fd03ced3"


def sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def write_json(name: str, value: object) -> None:
    (OUT / name).write_text(json.dumps(value, indent=2, allow_nan=False) + "\n")


def run(*args: str) -> str:
    return subprocess.run(args, cwd=ROOT, check=True, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT).stdout


def transition_tests(year: int) -> list[dict[str, object]]:
    ny = ZoneInfo("America/New_York")
    cursor = datetime(year, 1, 1, tzinfo=timezone.utc)
    end = datetime(year + 1, 1, 1, tzinfo=timezone.utc)
    previous = cursor.astimezone(ny).utcoffset()
    changes = []
    while cursor < end:
        current = cursor.astimezone(ny).utcoffset()
        if current != previous:
            before = cursor - timedelta(seconds=1)
            after = cursor
            before_offset = int(before.astimezone(ny).utcoffset().total_seconds() // 3600)
            after_offset = int(after.astimezone(ny).utcoffset().total_seconds() // 3600)
            changes.append({
                "transition_utc": after.isoformat(),
                "new_york_before": before.astimezone(ny).isoformat(),
                "new_york_after": after.astimezone(ny).isoformat(),
                "server_before": (before + timedelta(hours=before_offset + 7)).replace(tzinfo=None).isoformat(sep=" "),
                "server_after": (after + timedelta(hours=after_offset + 7)).replace(tzinfo=None).isoformat(sep=" "),
                "server_utc_offset_before_hours": before_offset + 7,
                "server_utc_offset_after_hours": after_offset + 7,
            })
            previous = current
        cursor += timedelta(hours=1)
    return changes


def main() -> None:
    if OUT.exists():
        raise SystemExit("REFUSE_EXISTING_V31_OUTPUT")
    OUT.mkdir(parents=True)
    verify = run("git", "bundle", "verify", str(BUNDLE))
    heads = run("git", "bundle", "list-heads", str(BUNDLE)).splitlines()
    bundle_hash = sha(BUNDLE)
    if bundle_hash != EXPECTED_BUNDLE or len(heads) != 40 or "complete history" not in verify:
        raise SystemExit("V31_REPOSITORY_SAFETY_INVALID")
    (ROOT / "backups/phase6-v31-bundle.sha256").write_text(f"{bundle_hash}  phase6-v31-prerun-all-refs.bundle\n")
    (ROOT / "backups/phase6-v31-bundle-verify.txt").write_text(verify + f"\nLISTED_REF_COUNT=40\nSHA256={bundle_hash}\n")
    write_json("repository-safety-gate.json", {
        "schema": "SOLTRADE_PHASE6_V31_REPOSITORY_SAFETY_GATE_V1",
        "status": "PASS",
        "worktree_clean_before_bundle": True,
        "source_head": "55672b7fcb4be06528a82444846e5f8d3d7dceca",
        "bundle_path": "backups/phase6-v31-prerun-all-refs.bundle",
        "bundle_sha256": bundle_hash,
        "bundle_size_bytes": BUNDLE.stat().st_size,
        "listed_ref_count": len(heads),
        "complete_history_verified": True,
        "current_branch_and_all_tags_included": True,
        "automatic_push": False,
    })
    write_json("v31-research-classification.json", {
        "schema": "SOLTRADE_PHASE6_V31_RESEARCH_CLASSIFICATION_V1",
        "classification": "INDEPENDENT_EXTERNAL_FEED_HISTORICAL_REPLICATION",
        "is_fp_markets_broker_native_replication": False,
        "is_exact_historical_fp_markets_execution": False,
        "is_untouched_forward_test": False,
        "is_demo_or_live_evidence": False,
        "cost_classification_if_execution_became_valid": "EXTERNAL_PRICE_FEED_WITH_FROZEN_CONTROLLED_COST_MODEL",
    })
    write_json("v31-external-source-freeze.json", {
        "schema": "SOLTRADE_PHASE6_V31_EXTERNAL_SOURCE_FREEZE_V1",
        "source": "Dukascopy Bank historical tick data",
        "official_history_documentation": "https://www.dukascopy.com/wiki/en/development/strategy-api/historical-data/history-ticks/",
        "official_hourly_archive_base": "https://datafeed.dukascopy.com/datafeed/",
        "requested_interval": "[2018-01-01 00:00:00, 2025-01-01 00:00:00)",
        "symbols": list(SYMBOLS),
        "required_fields": ["timestamp", "bid", "ask"],
        "providers_allowed": ["Dukascopy Bank"],
        "bar_midpoint_generated_interpolated_mixed_or_patched_data": "PROHIBITED",
        "source_probe_method": "HTTP HEAD only; no response body or raw tick file downloaded",
        "raw_files_downloaded": 0,
        "raw_data_manifest_status": "NOT_CREATED_BECAUSE_EXECUTION_EVIDENCE_CONTRACT_FAILED_BEFORE_DOWNLOAD",
        "provider_change_after_pnl": "PROHIBITED",
        "pnl_viewed": False,
    })
    timezone_rows = []
    for year in range(2018, 2025):
        transitions = transition_tests(year)
        if len(transitions) != 2:
            raise SystemExit(f"UNEXPECTED_NEW_YORK_TRANSITION_COUNT_{year}")
        timezone_rows.append({"year": year, "transitions": transitions})
    write_json("v31-timezone-and-calendar-audit.json", {
        "schema": "SOLTRADE_PHASE6_V31_TIMEZONE_AND_CALENDAR_AUDIT_V1",
        "status": "PASS_NOT_TERMINAL_BLOCKER",
        "v28_time_basis": "FP Markets broker-server civil time",
        "v28_evidence": {
            "candidate_rule": "first Monday 10:05 broker-server time; exact H1 closes at 09:00 broker-server time",
            "source_clock": "TimeCurrent() and server-timestamped MT5 H1/D1 series",
        },
        "fp_markets_official_rule": "Server time is UTC+2 in winter and UTC+3 during daylight saving so daily candles follow the 17:00 New York close.",
        "fp_markets_reference": "https://www.fpmarkets.com/en-au/education/faq/",
        "deterministic_conversion": "Convert Dukascopy UTC to America/New_York civil time using IANA tzdata, then add seven civil hours. Equivalent server UTC offset is +2 in New York standard time and +3 in New York daylight time.",
        "iana_zone": "America/New_York",
        "decision_examples": {"winter_server_10_05_utc": "08:05", "summer_server_10_05_utc": "07:05", "winter_server_09_00_utc": "07:00", "summer_server_09_00_utc": "06:00"},
        "dst_transition_tests": timezone_rows,
        "ambiguity_assessment": "The Sunday clock changes occur while FX is closed and do not make first-Monday 09:00/10:05 decisions ambiguous.",
        "weekly_and_daily_boundaries_reconstructable": True,
    })
    source_text = SOURCE.read_text()
    assertions = {
        "hardcoded_unsuffixed_symbol_array": 'string SYMBOLS[7]={"EURUSD","GBPUSD","AUDUSD","NZDUSD","USDCAD","USDCHF","USDJPY"};' in source_text,
        "main_tester_symbol_must_equal_unsuffixed_eurusd": '_Symbol!="EURUSD"' in source_text,
        "server_must_equal_fpmarkets_demo": 'AccountInfoString(ACCOUNT_SERVER)!="FPMarketsSC-Demo"' in source_text,
        "child_symbols_selected_from_hardcoded_array": "SymbolSelect(SYMBOLS[i],true)" in source_text,
        "market_config_uses_hardcoded_array": "g_config[i].symbol=SYMBOLS[i]" in source_text,
        "atr_uses_hardcoded_array": "iATR(SYMBOLS[i],PERIOD_D1,14)" in source_text,
        "no_v31_suffix_in_frozen_source": ".V31" not in source_text,
    }
    if not all(assertions.values()):
        raise SystemExit("V31_FROZEN_SOURCE_ASSERTION_FAILED")
    write_json("v31-v28-custom-symbol-compatibility-audit.json", {
        "schema": "SOLTRADE_PHASE6_V31_V28_CUSTOM_SYMBOL_COMPATIBILITY_AUDIT_V1",
        "status": "FAIL",
        "required_custom_symbols": list(CUSTOM),
        "frozen_v28_source_sha256": sha(SOURCE),
        "frozen_v28_ex5_sha256": sha(EX5),
        "candidate_specification_sha256": sha(V28 / "candidate-strategy-specification.json"),
        "gate_manifest_sha256": sha(V28 / "gate-manifest.json"),
        "source_assertions": assertions,
        "official_mt5_custom_symbol_reference": "https://www.mql5.com/en/docs/customsymbols/customsymbolcreate",
        "official_mt5_tick_import_reference": "https://www.mql5.com/en/docs/customsymbols/customticksreplace",
        "mt5_constraints": [
            "A custom symbol has a globally unique symbol name regardless of group.",
            "CustomTicksReplace writes to the explicitly named custom symbol.",
            "There is no frozen V28 input that aliases EURUSD to EURUSD.V31 or the other six names.",
        ],
        "evaluated_routes": [
            {"route": "Run frozen EX5 with EURUSD.V31 as tester symbol", "status": "INVALID", "reason": "Frozen preflight requires _Symbol == EURUSD."},
            {"route": "Run frozen EX5 on EURUSD and select .V31 child symbols", "status": "INVALID", "reason": "Frozen code selects, configures and computes ATR on the unsuffixed SYMBOLS array."},
            {"route": "Create custom symbols using the unsuffixed broker names", "status": "INVALID", "reason": "Names collide with broker symbols and violate the explicitly required .V31 isolated names."},
            {"route": "Change the source symbol array or preflight", "status": "INVALID", "reason": "Would change both the frozen source and executable hashes."},
            {"route": "Patch broker symbol history or redirect cache files", "status": "INVALID", "reason": "Violates isolated custom symbols, no broker-data patching and exact import-parity requirements."},
        ],
        "compliant_execution_route_exists": False,
        "terminal_reason": "The V31 custom-symbol requirement and the exact frozen V28 executable requirement cannot both be satisfied.",
    })
    write_json("v31-execution-stop-record.json", {
        "schema": "SOLTRADE_PHASE6_V31_EXECUTION_STOP_RECORD_V1",
        "terminal_outcome": "INVALID_TEST_EVIDENCE",
        "stopped_at": "PRE_DOWNLOAD_EXECUTABLE_TO_CUSTOM_SYMBOL_COMPATIBILITY_GATE",
        "raw_tick_files_downloaded": 0,
        "raw_or_normalized_ticks_transformed": 0,
        "custom_symbols_created": 0,
        "ticks_imported": 0,
        "qualification_runs": 0,
        "performance_runs": 0,
        "formal_performance_cells": 0,
        "combined_evidence_audit": "NOT_AUTHORIZED",
        "v28_pnl_viewed": False,
        "profitability_metrics_calculated": False,
        "orders_positions_demo_or_live_trades": 0,
        "v28_status": "UNCHANGED_AND_NOT_FAILED_REPLICATION",
    })
    if sha(SOURCE) != EXPECTED_SOURCE or sha(EX5) != EXPECTED_EX5 or sha(PRODUCTION) != EXPECTED_PRODUCTION:
        raise SystemExit("V31_IMMUTABILITY_HASH_FAILURE")
    write_json("v31-evidence-integrity.json", {
        "schema": "SOLTRADE_PHASE6_V31_EVIDENCE_INTEGRITY_V1",
        "status": "PASS",
        "terminal_outcome": "INVALID_TEST_EVIDENCE",
        "repository_safety_gate": "PASS",
        "frozen_v28_source_sha256": sha(SOURCE),
        "frozen_v28_source_unchanged": True,
        "frozen_v28_ex5_sha256": sha(EX5),
        "frozen_v28_ex5_unchanged": True,
        "production_phase1_5_sha256": sha(PRODUCTION),
        "production_phase1_5_unchanged": True,
        "earlier_evidence_changed": False,
        "raw_downloads": 0,
        "pnl_or_profitability_viewed": False,
        "optimization_or_tuning": False,
        "v29_used": False,
        "orders_or_positions": 0,
        "demo_or_live_trades": 0,
        "automatic_push": False,
    })
    (OUT / "phase6-v31-terminal-outcome.md").write_text(
        "# Phase 6 V31 terminal outcome\n\n"
        "`INVALID_TEST_EVIDENCE`\n\n"
        "Repository safety passed before any external-data action. The verified all-refs bundle contains 40 refs and complete history. V31 is classified as an independent external-feed historical replication, and the FP Markets New-York-close server-time basis can be reconstructed deterministically.\n\n"
        "Execution cannot proceed without violating a frozen requirement. V31 requires the seven isolated `.V31` custom symbols, while the exact frozen V28 source and EX5 hardcode the seven unsuffixed broker symbols. The preflight also requires `_Symbol == EURUSD` and `FPMarketsSC-Demo`. MT5 custom-symbol names are unique and tick import targets the explicitly named custom symbol, so no alias can make the unchanged V28 executable read the `.V31` histories. Changing the symbol array or preflight changes the frozen hashes; patching broker histories violates V31.\n\n"
        "The phase therefore stopped before raw tick download, transformation, custom-symbol creation, import, qualification or profitability. No P&L or profitability metric was viewed, no order or position was created, and no demo/live trade, optimization, tuning, V29 use or automatic push occurred. This is an invalid evidence design, not a V28 performance failure. V28 and production Phase 1-5 remain unchanged.\n"
    )
    checksum = OUT / "artifact-sha256-v31.txt"
    artifacts = sorted(path for path in OUT.rglob("*") if path.is_file() and path != checksum)
    checksum.write_text("".join(f"{sha(path)}  {path.relative_to(OUT).as_posix()}\n" for path in artifacts))
    print(json.dumps({
        "outcome": "INVALID_TEST_EVIDENCE",
        "bundle_sha256": bundle_hash,
        "bundle_refs": len(heads),
        "timezone_reconstructable": True,
        "compliant_execution_route": False,
        "raw_files_downloaded": 0,
        "performance_runs": 0,
    }, indent=2))


if __name__ == "__main__":
    main()
