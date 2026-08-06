#!/usr/bin/env python3
"""Download the frozen V31 Dukascopy Jetta hourly bid/ask tick files.

The downloader is deliberately limited to the seven frozen symbols and the
UTC acquisition interval required to reconstruct the half-open 2018-2024 V28
server-civil interval. Downloads are written atomically and never transformed.
Re-running resumes from completed files.
"""
from __future__ import annotations

import argparse
import asyncio
import gzip
import hashlib
import json
import os
import sys
import time
from datetime import datetime, timedelta, timezone
from pathlib import Path
from zoneinfo import ZoneInfo

TASK_DEPS = Path("/home/tibule12/Datasets/SolTrade/V31/python-deps")
if TASK_DEPS.is_dir():
    sys.path.insert(0, str(TASK_DEPS))

import httpx


SOURCE = "https://jetta.dukascopy.com/v1"
SYMBOLS = ("EURUSD", "GBPUSD", "AUDUSD", "NZDUSD", "USDCAD", "USDCHF", "USDJPY")
JETTA_CODES = {symbol: symbol[:3] + "-" + symbol[3:] for symbol in SYMBOLS}
# The evaluated interval is V28 server civil time.  FP Markets is UTC+2 at
# the frozen 2018 boundary, so two preceding UTC hours are acquisition-only
# support needed to reconstruct 2018-01-01 00:00:00 server civil exactly.
START = datetime(2017, 12, 31, 22, tzinfo=timezone.utc)
END = datetime(2025, 1, 1, tzinfo=timezone.utc)
DEFAULT_ROOT = Path("/home/tibule12/Datasets/SolTrade/V31/dukascopy-jetta-gzip-raw")
USER_AGENT = "SolTrade-V31-independent-replication/1.0"
PARSER_VERSION = "DUKASCOPY_JETTA_DELTA_JSON_V1"
NEW_YORK = ZoneInfo("America/New_York")


def calendar_hours():
    current = START
    while current < END:
        yield current
        current += timedelta(hours=1)


def fx_session_open(hour: datetime) -> bool:
    """True for hours outside the deterministic 17:00-NY weekend close."""
    local = hour.astimezone(NEW_YORK)
    weekday = local.weekday()
    return weekday < 4 or (weekday == 4 and local.hour < 17) or (weekday == 6 and local.hour >= 17)


def hours():
    yield from (hour for hour in calendar_hours() if fx_session_open(hour))


def target(root: Path, symbol: str, hour: datetime) -> Path:
    return root / symbol / f"{hour.year:04d}" / f"{hour.month:02d}" / f"{hour.day:02d}" / f"{hour.hour:02d}h_ticks.json.gz"


def marker(path: Path, status: int) -> Path:
    return path.with_suffix(path.suffix + f".http-{status}")


def url(symbol: str, hour: datetime) -> str:
    return f"{SOURCE}/ticks/{JETTA_CODES[symbol]}/{hour.year:04d}/{hour.month}/{hour.day}/{hour.hour}"


def completed(path: Path, existing: set[Path]) -> tuple[bool, int]:
    if path in existing:
        return True, 200
    for status in (404, 410):
        if marker(path, status) in existing:
            return True, status
    return False, 0


async def main_async(args: argparse.Namespace) -> int:
    root = args.root.resolve()
    root.mkdir(parents=True, exist_ok=True)
    journal_path = root / "download-journal.jsonl"
    run_path = root / "download-run.json"
    # Round-robin instruments so one cold provider cache path cannot serialize
    # the remaining acquisition.  Target identity and ordering within each
    # symbol remain deterministic.
    work = [(symbol, hour) for hour in hours() for symbol in SYMBOLS]
    total = len(work)
    existing = {path for path in root.rglob("*") if path.is_file()}
    already = sum(1 for symbol, hour in work if completed(target(root, symbol, hour), existing)[0])
    run = {
        "schema": "SOLTRADE_PHASE6_V31_DUKASCOPY_DOWNLOAD_RUN_V1",
        "source": SOURCE,
        "symbols": list(SYMBOLS),
        "requested_interval_utc": f"[{START.isoformat()}, {END.isoformat()})",
        "strategy_evaluation_interval_server_civil": "[2018-01-01 00:00:00, 2025-01-01 00:00:00)",
        "boundary_support_reason": "UTC+2 V28 server-civil start boundary",
        "predictable_closed_session_policy": "do not request hours from Friday 17:00 through Sunday 17:00 America/New_York; preserve and manifest any such files downloaded by earlier resumable attempts",
        "queue_order": "UTC_HOUR_ASCENDING_THEN_FROZEN_SYMBOL_ORDER",
        "planned_hourly_requests": total,
        "already_complete_at_start": already,
        "concurrency": args.concurrency,
        "http_version": args.http_version,
        "maximum_attempts": args.attempts,
        "raw_transformation": "NONE",
        "parser_version_reserved_for_qualification": PARSER_VERSION,
        "started_at_utc": datetime.now(timezone.utc).isoformat(),
        "process_id": os.getpid(),
    }
    run_path.write_text(json.dumps(run, indent=2) + "\n")

    queue: asyncio.Queue[tuple[str, datetime] | None] = asyncio.Queue()
    for item in work:
        if not completed(target(root, item[0], item[1]), existing)[0]:
            queue.put_nowait(item)
    for _ in range(args.concurrency):
        queue.put_nowait(None)

    journal_queue: asyncio.Queue[dict | None] = asyncio.Queue()
    counts = {"downloaded": 0, "not_found": 0, "failed": 0, "bytes": 0}
    started = time.monotonic()

    async def write_journal() -> None:
        with journal_path.open("a", encoding="utf-8") as handle:
            while True:
                row = await journal_queue.get()
                if row is None:
                    handle.flush()
                    os.fsync(handle.fileno())
                    return
                handle.write(json.dumps(row, separators=(",", ":"), sort_keys=True) + "\n")
                done = counts["downloaded"] + counts["not_found"] + counts["failed"]
                if done % 250 == 0:
                    handle.flush()
                if done % 1000 == 0:
                    elapsed = max(time.monotonic() - started, 0.001)
                    absolute = already + done
                    print(
                        f"V31_DOWNLOAD {absolute}/{total} "
                        f"downloaded={counts['downloaded']} not_found={counts['not_found']} "
                        f"failed={counts['failed']} bytes={counts['bytes']} "
                        f"rate={done / elapsed:.1f}_requests_per_second",
                        flush=True,
                    )

    limits = httpx.Limits(max_connections=args.concurrency, max_keepalive_connections=args.concurrency)
    timeout = httpx.Timeout(connect=30.0, read=60.0, write=30.0, pool=60.0)
    async with httpx.AsyncClient(http2=args.http_version == "2", limits=limits, timeout=timeout, headers={"User-Agent": USER_AGENT, "Accept-Encoding": "gzip"}) as client:
        async def worker() -> None:
            while True:
                item = await queue.get()
                if item is None:
                    return
                symbol, hour = item
                path = target(root, symbol, hour)
                request_url = url(symbol, hour)
                result: dict | None = None
                for attempt in range(1, args.attempts + 1):
                    retrieval = datetime.now(timezone.utc).isoformat()
                    try:
                        async with client.stream("GET", request_url) as response:
                            body = b"".join([chunk async for chunk in response.aiter_raw()])
                        if response.status_code == 200:
                            if response.headers.get("content-encoding", "").lower() != "gzip" or not body.startswith(b"\x1f\x8b"):
                                raise RuntimeError("expected raw gzip content encoding")
                            if not gzip.decompress(body).lstrip().startswith(b"{"):
                                raise RuntimeError("unexpected non-JSON gzip payload with HTTP 200")
                            path.parent.mkdir(parents=True, exist_ok=True)
                            temporary = path.with_suffix(path.suffix + f".part-{os.getpid()}")
                            temporary.write_bytes(body)
                            os.replace(temporary, path)
                            counts["downloaded"] += 1
                            counts["bytes"] += len(body)
                            result = {
                                "symbol": symbol,
                                "hour_utc": hour.isoformat(),
                                "url": request_url,
                                "retrieved_at_utc": retrieval,
                                "http_status": 200,
                                "file": str(path),
                                "bytes": len(body),
                                "sha256": hashlib.sha256(body).hexdigest(),
                                "content_encoding": "gzip",
                                "attempt": attempt,
                            }
                            break
                        if response.status_code in (404, 410):
                            path.parent.mkdir(parents=True, exist_ok=True)
                            marker_path = marker(path, response.status_code)
                            marker_path.write_bytes(body)
                            counts["not_found"] += 1
                            result = {
                                "symbol": symbol,
                                "hour_utc": hour.isoformat(),
                                "url": request_url,
                                "retrieved_at_utc": retrieval,
                                "http_status": response.status_code,
                                "file": str(marker_path),
                                "bytes": len(body),
                                "sha256": hashlib.sha256(body).hexdigest(),
                                "attempt": attempt,
                            }
                            break
                        raise RuntimeError(f"HTTP {response.status_code}")
                    except Exception as exc:  # retry log is retained in the final failure row
                        if attempt == args.attempts:
                            counts["failed"] += 1
                            result = {
                                "symbol": symbol,
                                "hour_utc": hour.isoformat(),
                                "url": request_url,
                                "retrieved_at_utc": retrieval,
                                "http_status": "FAILED",
                                "error": f"{type(exc).__name__}: {exc}",
                                "attempt": attempt,
                            }
                        else:
                            await asyncio.sleep(min(2 ** (attempt - 1), 20))
                assert result is not None
                await journal_queue.put(result)

        journal_task = asyncio.create_task(write_journal())
        workers = [asyncio.create_task(worker()) for _ in range(args.concurrency)]
        await asyncio.gather(*workers)
        await journal_queue.put(None)
        await journal_task

    run.update(
        {
            "finished_at_utc": datetime.now(timezone.utc).isoformat(),
            "new_downloaded": counts["downloaded"],
            "new_not_found": counts["not_found"],
            "new_failed": counts["failed"],
            "new_bytes": counts["bytes"],
            "status": "COMPLETE" if counts["failed"] == 0 else "INCOMPLETE_RETRY_REQUIRED",
        }
    )
    run_path.write_text(json.dumps(run, indent=2) + "\n")
    print(json.dumps(run, sort_keys=True), flush=True)
    return 0 if counts["failed"] == 0 else 2


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", type=Path, default=DEFAULT_ROOT)
    parser.add_argument("--concurrency", type=int, default=48)
    parser.add_argument("--attempts", type=int, default=6)
    parser.add_argument("--http-version", choices=("1.1", "2"), default="1.1")
    args = parser.parse_args()
    if not 1 <= args.concurrency <= 96:
        parser.error("concurrency must be between 1 and 96")
    if not 1 <= args.attempts <= 10:
        parser.error("attempts must be between 1 and 10")
    return args


if __name__ == "__main__":
    try:
        raise SystemExit(asyncio.run(main_async(parse_args())))
    except KeyboardInterrupt:
        print("V31_DOWNLOAD_INTERRUPTED_RESUMABLE", file=sys.stderr)
        raise SystemExit(130)
