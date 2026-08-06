#!/usr/bin/env python3
"""Preserve and freeze the Dukascopy instrument/session metadata used by V31."""
from __future__ import annotations

import gzip
import hashlib
import json
import time
from datetime import datetime, timezone
from pathlib import Path

import httpx


ROOT = Path(__file__).resolve().parents[1]
RAW_ROOT = Path("/home/tibule12/Datasets/SolTrade/V31/dukascopy-jetta-gzip-raw/_metadata")
DATASET_MANIFEST = Path("/home/tibule12/Datasets/SolTrade/V31/manifests/v31-source-metadata-manifest.json")
REPORT_MANIFEST = ROOT / "reports/backtests/phase6-v31-v28-external-feed-replication-attempt2/v31-source-metadata-manifest.json"
SYMBOLS = ("EURUSD", "GBPUSD", "AUDUSD", "NZDUSD", "USDCAD", "USDCHF", "USDJPY")
BASE = "https://jetta.dukascopy.com/v1/instruments"


def sha_bytes(value: bytes) -> str:
    return hashlib.sha256(value).hexdigest()


def first_session(schedule: dict, day: str) -> dict:
    sessions = schedule.get("sessions", {}).get(day) or []
    return sessions[0] if sessions else {}


def main() -> None:
    if DATASET_MANIFEST.exists() or REPORT_MANIFEST.exists():
        raise SystemExit("REFUSE_EXISTING_V31_SOURCE_METADATA_MANIFEST")
    RAW_ROOT.mkdir(parents=True, exist_ok=True)
    DATASET_MANIFEST.parent.mkdir(parents=True, exist_ok=True)
    rows = []
    timeout = httpx.Timeout(connect=30.0, read=60.0, write=30.0, pool=60.0)
    with httpx.Client(http2=False, timeout=timeout, headers={"User-Agent": "SolTrade-V31-independent-replication/1.0", "Accept-Encoding": "gzip"}) as client:
        for symbol in SYMBOLS:
            code = symbol[:3] + "-" + symbol[3:]
            url = f"{BASE}/{code}"
            result = None
            for attempt in range(1, 11):
                retrieved = datetime.now(timezone.utc).isoformat()
                try:
                    with client.stream("GET", url) as response:
                        body = b"".join(response.iter_raw())
                    if response.status_code != 200:
                        raise RuntimeError(f"HTTP {response.status_code}")
                    encoding = response.headers.get("content-encoding", "identity").lower()
                    decoded = gzip.decompress(body) if encoding == "gzip" else body
                    document = json.loads(decoded)
                    if document.get("code") != code or document.get("defaultTimezone") != "America/New_York":
                        raise RuntimeError("unexpected instrument identity or timezone")
                    schedules = document.get("tradeSchedule") or []
                    if not schedules:
                        raise RuntimeError("missing trade schedule")
                    suffix = ".json.gz" if encoding == "gzip" else ".json"
                    path = RAW_ROOT / (code + suffix)
                    if path.exists():
                        raise RuntimeError("refuse existing raw metadata file")
                    path.write_bytes(body)
                    result = {
                        "provider": "Dukascopy Bank",
                        "symbol": symbol,
                        "provider_code": code,
                        "url": url,
                        "retrieved_at_utc": retrieved,
                        "raw_path": str(path),
                        "raw_bytes": len(body),
                        "raw_sha256": sha_bytes(body),
                        "content_encoding": encoding,
                        "decoded_json_bytes": len(decoded),
                        "default_timezone": document["defaultTimezone"],
                        "trade_schedule": schedules,
                        "holiday_records": len(document.get("holidays") or []),
                        "attempt": attempt,
                    }
                    break
                except Exception as exc:
                    if attempt == 10:
                        raise SystemExit(f"V31_SOURCE_METADATA_FAILED_{symbol}_{type(exc).__name__}_{exc}")
                    time.sleep(min(2 ** (attempt - 1), 20))
            rows.append(result)
    schedule_exact = all(
        any(
            first_session(schedule, "FRIDAY").get("end") == "17:00:00"
            and first_session(schedule, "MONDAY").get("start") == "17:00:00"
            and first_session(schedule, "MONDAY").get("previousDayStart") is True
            for schedule in row["trade_schedule"]
        )
        for row in rows
    )
    manifest = {
        "schema": "SOLTRADE_PHASE6_V31_SOURCE_METADATA_MANIFEST_V1",
        "status": "PASS" if len(rows) == 7 and schedule_exact else "FAIL",
        "source": "Dukascopy Bank Jetta instrument service",
        "single_provider": True,
        "metadata_files_preserved_unchanged": True,
        "session_timezone_all_symbols": "America/New_York",
        "weekly_session_rule_verified": "Sunday 17:00 through Friday 17:00 America/New_York",
        "weekly_session_rule_exact_all_symbols": schedule_exact,
        "symbols": rows,
        "pnl_viewed": False,
    }
    text = json.dumps(manifest, indent=2) + "\n"
    DATASET_MANIFEST.write_text(text)
    REPORT_MANIFEST.write_text(text)
    if manifest["status"] != "PASS":
        raise SystemExit("V31_SOURCE_METADATA_QUALIFICATION_FAILED")
    print(json.dumps({"status": "PASS", "symbols": len(rows), "schedule_exact": schedule_exact}, sort_keys=True))


if __name__ == "__main__":
    main()
