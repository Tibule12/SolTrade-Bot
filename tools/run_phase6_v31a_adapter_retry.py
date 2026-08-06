#!/usr/bin/env python3
"""Rerun only the two V31A 2025 adapter cells after the pre-start history fix."""
from __future__ import annotations

import importlib.util
import shutil
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "tools/run_phase6_v31a_equivalence.py"
SPEC = importlib.util.spec_from_file_location("v31a_runner", SOURCE)
assert SPEC and SPEC.loader
RUNNER = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(RUNNER)


def main() -> None:
    if RUNNER.sha(RUNNER.ORIGINAL_EX5) != RUNNER.ORIGINAL_SHA256 or RUNNER.sha(RUNNER.ADAPTER_EX5) != RUNNER.ADAPTER_SHA256:
        raise SystemExit("V31A_PARITY_EXECUTABLE_HASH_MISMATCH")
    RUNNER.RUN_ROOT = RUNNER.OUT / "equivalence-runs-attempt2"
    if RUNNER.RUN_ROOT.exists():
        raise SystemExit("REFUSE_EXISTING_V31A_ADAPTER_RETRY_ROOT")
    RUNNER.REPORTS.mkdir(parents=True, exist_ok=True)
    shutil.copy2(RUNNER.ADAPTER_EX5, RUNNER.TERMINAL / "MQL5/Experts/SolTradeDollarFactorV31AAdapter.ex5")
    RUNNER.execute(RUNNER.PLAN[0], "adapter", 9)
    RUNNER.execute(RUNNER.PLAN[2], "adapter", 10)


if __name__ == "__main__":
    main()
