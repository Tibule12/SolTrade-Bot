#!/usr/bin/env python3
"""Fail-closed reconciliation for a fixed-delay authoritative/replica pair.

The tool is reporting-only. It reads exported artifacts and never launches MT5
or changes trading state.
"""

from __future__ import annotations

import argparse
import csv
import hashlib
import json
import sys
from pathlib import Path
from tempfile import TemporaryDirectory


class InvalidReplica(RuntimeError):
    """Raised when a replica cannot reproduce its authoritative run."""


def sha256(path: Path) -> str:
    if not path.is_file():
        raise InvalidReplica(f"missing artifact: {path}")
    return hashlib.sha256(path.read_bytes()).hexdigest()


def key_values(path: Path) -> dict[str, str]:
    with path.open(newline="", encoding="utf-8-sig") as handle:
        reader = csv.DictReader(handle)
        if reader.fieldnames != ["field", "value"]:
            raise InvalidReplica(f"invalid key/value artifact: {path}")
        return {row["field"]: row["value"] for row in reader}


def require_native_report(directory: Path) -> Path:
    candidates = sorted(
        path
        for pattern in ("*.html", "*.htm", "*.xml")
        for path in directory.rglob(pattern)
        if "native" in path.name.lower() or "strategy" in path.name.lower()
    )
    if len(candidates) != 1:
        raise InvalidReplica(
            f"exactly one exported native MT5 report is required in {directory}"
        )
    return candidates[0]


def require_journal(directory: Path) -> Path:
    candidates = sorted(directory.rglob("soltrade_*.csv"))
    if len(candidates) != 1:
        raise InvalidReplica(
            f"exactly one SolTrade journal is required in {directory}"
        )
    return candidates[0]


def normalized_journal(path: Path, instance_id: str) -> bytes:
    text = path.read_text(encoding="utf-8-sig")
    return text.replace(instance_id, "<EXECUTION_INSTANCE_ID>").encode("utf-8")


def compare_pair(authoritative: Path, replica: Path) -> dict[str, object]:
    required = (
        "run_manifest.csv",
        "canonical_trading_inputs.txt",
        "trade_cashflows.csv",
        "native_mt5_summary.csv",
        "supplementary_adjusted_summary.csv",
        "reconciliation.csv",
    )
    for name in required:
        if not (authoritative / name).is_file():
            raise InvalidReplica(f"missing authoritative artifact: {name}")
        if not (replica / name).is_file():
            raise InvalidReplica(f"missing replica artifact: {name}")

    auth_manifest = key_values(authoritative / "run_manifest.csv")
    replica_manifest = key_values(replica / "run_manifest.csv")
    auth_hash = auth_manifest.get("trading_input_hash", "")
    replica_hash = replica_manifest.get("trading_input_hash", "")
    auth_instance = auth_manifest.get("execution_instance_id", "")
    replica_instance = replica_manifest.get("execution_instance_id", "")
    if len(auth_hash) != 64 or auth_hash != replica_hash:
        raise InvalidReplica("canonical trading-input hashes differ")
    if not auth_instance or not replica_instance or auth_instance == replica_instance:
        raise InvalidReplica("ExecutionInstanceId must differ between pair members")
    if auth_manifest.get("execution_instance_affects_trading_hash") != "NO":
        raise InvalidReplica("authoritative instance/hash isolation declaration missing")
    if replica_manifest.get("execution_instance_affects_trading_hash") != "NO":
        raise InvalidReplica("replica instance/hash isolation declaration missing")

    auth_material = authoritative / "canonical_trading_inputs.txt"
    replica_material = replica / "canonical_trading_inputs.txt"
    if auth_material.read_bytes() != replica_material.read_bytes():
        raise InvalidReplica("canonical trading-input material differs")
    if sha256(auth_material) != auth_hash:
        raise InvalidReplica("canonical material does not hash to registered input hash")

    # The instance-specific fields are deliberately excluded. Every other
    # runtime metadata value, including actual first/final ticks, must match.
    ignored_manifest_fields = {"execution_instance_id", "journal_filename"}
    comparable_auth = {
        key: value
        for key, value in auth_manifest.items()
        if key not in ignored_manifest_fields
    }
    comparable_replica = {
        key: value
        for key, value in replica_manifest.items()
        if key not in ignored_manifest_fields
    }
    if comparable_auth != comparable_replica:
        raise InvalidReplica("authoritative and replica runtime metadata differ")

    identical_files: dict[str, str] = {}
    for name in (
        "trade_cashflows.csv",
        "native_mt5_summary.csv",
        "supplementary_adjusted_summary.csv",
        "reconciliation.csv",
    ):
        auth_digest = sha256(authoritative / name)
        replica_digest = sha256(replica / name)
        if auth_digest != replica_digest:
            raise InvalidReplica(f"fixed-delay result mismatch: {name}")
        identical_files[name] = auth_digest

    for directory in (authoritative, replica):
        reconciliation = key_values(directory / "reconciliation.csv")
        if reconciliation.get("status") != "PASS":
            raise InvalidReplica(f"reconciliation is not PASS: {directory}")

    auth_journal = require_journal(authoritative)
    replica_journal = require_journal(replica)
    auth_journal_normalized = normalized_journal(auth_journal, auth_instance)
    replica_journal_normalized = normalized_journal(replica_journal, replica_instance)
    if auth_journal_normalized != replica_journal_normalized:
        raise InvalidReplica("normalized authoritative/replica journals differ")

    # Native reports contain platform presentation metadata and the different
    # instance input, so byte identity is not claimed. Presence is mandatory;
    # the exact exported native statistics are compared via native_mt5_summary.
    auth_native_report = require_native_report(authoritative)
    replica_native_report = require_native_report(replica)
    return {
        "schema": "SOLTRADE_PHASE6_REPLICA_RECONCILIATION_V1",
        "status": "PASS",
        "trading_input_hash": auth_hash,
        "authoritative_execution_instance_id": auth_instance,
        "replica_execution_instance_id": replica_instance,
        "set_files_byte_identical_claimed": False,
        "canonical_material_byte_identical": True,
        "fixed_delay_economic_results_identical": True,
        "normalized_journals_identical": True,
        "identical_artifact_hashes": identical_files,
        "authoritative_native_report": str(auth_native_report),
        "replica_native_report": str(replica_native_report),
        "native_report_byte_identity_claimed": False,
    }


def self_test() -> None:
    sample = "instance=P6-DEV-NORMAL-AUTH-01\n"
    normalized = sample.replace(
        "P6-DEV-NORMAL-AUTH-01", "<EXECUTION_INSTANCE_ID>"
    )
    assert normalized == "instance=<EXECUTION_INSTANCE_ID>\n"
    assert hashlib.sha256(b"abc").hexdigest() == (
        "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
    )
    with TemporaryDirectory(prefix="soltrade-phase6-pair-") as temporary:
        root = Path(temporary)
        authoritative = root / "authoritative"
        replica = root / "replica"
        authoritative.mkdir()
        replica.mkdir()
        material = b"canonical=true\n"
        trading_hash = hashlib.sha256(material).hexdigest()
        for directory, instance in (
            (authoritative, "P6-DEV-NORMAL-AUTH-01"),
            (replica, "P6-DEV-NORMAL-REPLICA-01"),
        ):
            (directory / "canonical_trading_inputs.txt").write_bytes(material)
            with (directory / "run_manifest.csv").open(
                "w", newline="", encoding="utf-8"
            ) as handle:
                writer = csv.writer(handle)
                writer.writerow(("field", "value"))
                writer.writerow(("trading_input_hash", trading_hash))
                writer.writerow(("execution_instance_id", instance))
                writer.writerow(("execution_instance_affects_trading_hash", "NO"))
                writer.writerow(("journal_filename", f"{instance}/journal.csv"))
                writer.writerow(("actual_first_tick", "2026.01.01 00:00:01"))
                writer.writerow(("actual_final_tick", "2026.01.31 23:59:59"))
            for name in (
                "trade_cashflows.csv",
                "native_mt5_summary.csv",
                "supplementary_adjusted_summary.csv",
            ):
                (directory / name).write_text("a,b\n1,2\n", encoding="utf-8")
            (directory / "reconciliation.csv").write_text(
                "field,value\nstatus,PASS\n",
                encoding="utf-8",
            )
            (directory / f"soltrade_{instance}.csv").write_text(
                f"event,details\nSTART,{instance}\n",
                encoding="utf-8",
            )
            (directory / "native_strategy_report.html").write_text(
                "<html>native report</html>\n",
                encoding="utf-8",
            )
        result = compare_pair(authoritative, replica)
        assert result["status"] == "PASS"
        (replica / "trade_cashflows.csv").write_text(
            "a,b\n1,3\n", encoding="utf-8"
        )
        try:
            compare_pair(authoritative, replica)
        except InvalidReplica:
            pass
        else:
            raise AssertionError("mismatched fixed-delay cash flows must fail")
    print("Phase 6 replica reconciliation pure checks passed.")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--self-test", action="store_true")
    parser.add_argument("--authoritative", type=Path)
    parser.add_argument("--replica", type=Path)
    parser.add_argument("--output", type=Path)
    arguments = parser.parse_args()
    if arguments.self_test:
        self_test()
        return 0
    if not arguments.authoritative or not arguments.replica or not arguments.output:
        parser.error("--authoritative, --replica, and --output are required")
    try:
        result = compare_pair(arguments.authoritative, arguments.replica)
    except (InvalidReplica, OSError, UnicodeError, ValueError) as exc:
        print(f"INVALID_TEST_EVIDENCE: {exc}", file=sys.stderr)
        return 1
    arguments.output.parent.mkdir(parents=True, exist_ok=True)
    arguments.output.write_text(
        json.dumps(result, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )
    print(f"Phase 6 replica reconciliation written to {arguments.output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
