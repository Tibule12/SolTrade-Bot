#!/usr/bin/env python3
"""Verify the frozen MT5 history inventory without starting MetaTrader."""

from __future__ import annotations

import argparse
import hashlib
import sys
from pathlib import Path


def verify(inventory: Path, base: Path) -> int:
    checked = 0
    for line_number, raw_line in enumerate(
        inventory.read_text(encoding="utf-8").splitlines(), start=1
    ):
        line = raw_line.strip()
        if not line or line.startswith("#"):
            continue
        parts = line.split(maxsplit=2)
        if len(parts) != 3:
            print(f"INVALID_HISTORY_INVENTORY: line {line_number}", file=sys.stderr)
            return 1
        expected_hash, expected_size_text, relative_name = parts
        path = base / relative_name
        if not path.is_file():
            print(f"HISTORY_CHANGED: missing {relative_name}", file=sys.stderr)
            return 1
        data = path.read_bytes()
        if len(data) != int(expected_size_text):
            print(f"HISTORY_CHANGED: size {relative_name}", file=sys.stderr)
            return 1
        if hashlib.sha256(data).hexdigest() != expected_hash:
            print(f"HISTORY_CHANGED: hash {relative_name}", file=sys.stderr)
            return 1
        checked += 1
    if checked == 0:
        print("INVALID_HISTORY_INVENTORY: no entries", file=sys.stderr)
        return 1
    print(f"Frozen history inventory verified: {checked} files unchanged.")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--inventory", type=Path, required=True)
    parser.add_argument("--base", type=Path, required=True)
    arguments = parser.parse_args()
    return verify(arguments.inventory, arguments.base)


if __name__ == "__main__":
    raise SystemExit(main())
