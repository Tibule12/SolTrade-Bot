#!/usr/bin/env python3
"""Build deterministic reports for the independent FXIFY inactivity guard."""
from __future__ import annotations

import argparse
import csv
import hashlib
import io
from pathlib import Path
import sys
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
sys.path.insert(0, str(ROOT / "tools"))

from fxify_inactivity_guard_model import simulate_historical_gap  # noqa: E402


OUT = ROOT / "reports/fxify-inactivity-guard"
EA = ROOT / "FXIFYInactivityGuard/MQL5/Experts/FXIFYInactivityGuard.mq5"
MODEL = ROOT / "tools/fxify_inactivity_guard_model.py"
TESTS = ROOT / "tests/test_fxify_inactivity_guard.py"
STATIC_TEST = ROOT / "tests/static-fxify-inactivity-guard.sh"
PRODUCTION = ROOT / "MQL5/Experts/SolTradeBot.mq5"
RAW_CAPTURE_ROOT = ROOT / "reports/backtests/fxify-2phase-pro-10k-v28-rule-simulation/final-raw-lifecycle-completion/raw-specification-capture"
RAW_SPECS = RAW_CAPTURE_ROOT / "raw-symbol-specifications.csv"
RAW_ACCOUNT = RAW_CAPTURE_ROOT / "raw-account-and-server.csv"
PRODUCTION_SHA = "261a9cfe1c1e8d84e2a2a468ac4d0775086b21c89824b117e5127697fd03ced3"
TOKEN = "FXIFY_INACTIVITY_GUARD_READY_FOR_DEPLOYMENT"


def sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def write_csv(path: Path, fieldnames: list[str], rows: list[dict]) -> None:
    with path.open("w", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=fieldnames, lineterminator="\n")
        writer.writeheader()
        writer.writerows(rows)


class RecordingResult(unittest.TextTestResult):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, **kwargs)
        self.records: list[dict[str, str]] = []

    def addSuccess(self, test):
        super().addSuccess(test)
        self.records.append({"test": test._testMethodName, "result": "PASS", "detail": ""})

    def addFailure(self, test, err):
        super().addFailure(test, err)
        self.records.append({"test": test._testMethodName, "result": "FAIL", "detail": self._exc_info_to_string(err, test)})

    def addError(self, test, err):
        super().addError(test, err)
        self.records.append({"test": test._testMethodName, "result": "ERROR", "detail": self._exc_info_to_string(err, test)})


def run_tests() -> tuple[RecordingResult, str]:
    suite = unittest.defaultTestLoader.loadTestsFromName("tests.test_fxify_inactivity_guard")
    stream = io.StringIO()
    runner = unittest.TextTestRunner(stream=stream, verbosity=2, resultclass=RecordingResult)
    result = runner.run(suite)
    return result, stream.getvalue()


def decode_compile_log(path: Path) -> str:
    raw = path.read_bytes()
    if raw.startswith(b"\xff\xfe"):
        text = raw.decode("utf-16")
    else:
        text = raw.decode("utf-8", errors="replace")
    return text.replace("\r\n", "\n")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--compile-log", type=Path, required=True)
    args = parser.parse_args()
    OUT.mkdir(parents=True, exist_ok=True)

    if sha(PRODUCTION) != PRODUCTION_SHA:
        raise SystemExit("Frozen production SHA mismatch")
    compile_text = decode_compile_log(args.compile_log)
    compile_pass = "Result: 0 errors, 0 warnings" in compile_text
    if not compile_pass:
        raise SystemExit("EA compile did not pass with zero errors and warnings")
    compile_lines = [
        line for line in compile_text.splitlines()
        if "compiling " in line or line.startswith("Result:")
    ]
    (OUT / "compile-result.txt").write_text("\n".join(compile_lines) + "\n")

    result, test_output = run_tests()
    if not result.wasSuccessful():
        raise SystemExit(test_output)
    records = sorted(result.records, key=lambda row: row["test"])
    write_csv(OUT / "deterministic-test-results.csv", ["test", "result", "detail"], records)

    gap_rows = simulate_historical_gap()
    write_csv(OUT / "synthetic-63-day-gap-events.csv", list(gap_rows[0]), gap_rows)
    historical_pass = (
        "DAY_45_WARNING" in gap_rows[0]["decision_events"]
        and "MAINTENANCE_ENTRY_INTENT" in gap_rows[1]["decision_events"]
        and gap_rows[2]["event"] == "GUARD_ENTRY_EXECUTED"
        and gap_rows[-1]["inactivity_breach"] == "NO"
        and float(gap_rows[-1]["elapsed_days_before_event"]) < 60
    )
    if not historical_pass:
        raise SystemExit("Historical gap simulation did not prevent inactivity breach")

    (OUT / "configuration.md").write_text(
        "# FXIFYInactivityGuard configuration\n\n"
        "This is a separate EA. It neither includes nor calls V28 code. The default symbol `EURUSD` resolves first as an exact broker symbol and then as `EURUSD.r`, matching the captured FXIFY RAW specification.\n\n"
        "Captured specification source: `reports/backtests/fxify-2phase-pro-10k-v28-rule-simulation/final-raw-lifecycle-completion/raw-specification-capture/raw-symbol-specifications.csv`. The EURUSD RAW snapshot records `.r`, 0.01 minimum/step volume, 100-lot maximum, 5 digits, 0.00001 point/tick size, USD 1 tick value per lot, zero stops/freeze levels, and a 0.6-pip snapshot spread. The live snapshot is not historical spread evidence.\n\n"
        "| Input | Default | Purpose |\n|---|---:|---|\n"
        "| `GuardEnabled` | `true` | Enables monitoring. |\n"
        "| `WarningDay` | `45` | First elapsed-calendar-day alert. |\n"
        "| `MaintenanceDay` | `50` | First safe maintenance-entry attempt. |\n"
        "| `CriticalAlertDay` | `55` | Critical escalation if no entry has executed. |\n"
        "| `MaintenanceSymbol` | `EURUSD` | Canonical symbol; `.r` is the captured RAW suffix fallback. |\n"
        "| `MaximumVolume` | `0.01` | Hard cap; broker minimum is used and must not exceed this. |\n"
        "| `StopLossPips` | `10.0` | Real server-side stop distance, rounded to tick size and broker minimum. |\n"
        "| `TakeProfitPips` | `5.0` | Small real server-side take-profit. |\n"
        "| `MaximumHoldingMinutes` | `60` | Time-based close trigger. |\n"
        "| `MaximumSpreadPips` | `1.5` | Entry refusal above this spread. |\n"
        "| `MaximumSlippagePips` | `1.0` | Deviation limit and projected-risk component. |\n"
        "| `EstimatedCommissionPerLot` | `6.0` | Official RAW Forex round-turn commission estimate. |\n"
        "| `MaximumStopRiskUSD` | `1.10` | Hard cap on stop-only risk after broker-distance adjustment. |\n"
        "| `MaximumProjectedLossUSD` | `2.0` | Cap including stop, spread, slippage, and commission. |\n"
        "| `ReferenceInitialBalance` | `10000.0` | FXIFY static-loss reference. |\n"
        "| `DailyLossLimitPercent` | `4.0` | Daily floor percentage at fixed 17:00 UTC-5 boundary. |\n"
        "| `MaximumLossLimitPercent` | `8.0` | Static maximum-loss percentage. |\n"
        "| `LossLimitSafetyBuffer` | `50.0` | USD clearance required above both loss floors. |\n"
        "| `GuardMagicNumber` | `608055001` | Dedicated order/deal identity. |\n"
        "| `GuardOrderComment` | `FXIFY_INACT_GUARD` | Dedicated order/deal/log comment. |\n"
        "| `RetryIntervalMinutes` | `15` | Safe-condition recheck interval after day 50. |\n"
        "| `DryRunMode` | `true` | Calculates and logs but cannot send orders. |\n\n"
        "Direction is independent of V28: BUY when the last completed EURUSD H1 candle closes at or above its open; otherwise SELL.\n"
    )

    (OUT / "deployment-instructions.md").write_text(
        "# Deployment instructions\n\n"
        "1. Copy `FXIFYInactivityGuard.mq5` into the terminal's `MQL5/Experts` directory and compile it in MetaEditor. Confirm zero errors and zero warnings.\n"
        "2. Keep `DryRunMode=true`, attach exactly one instance to any continuously open chart, and verify `GUARD_INITIALISED` plus history reconstruction in Experts and `MQL5/Files/FXIFYInactivityGuard/events.csv`. Chart symbol and timeframe do not control the guard.\n"
        "3. Confirm the intended FXIFY account is trade-enabled, uses USD, exposes the captured EURUSD RAW symbol, and has Algo Trading enabled. Never paste or archive credentials.\n"
        "4. Confirm FXIFY's written EA approval remains applicable to this exact guard. If the behavior changes, obtain renewed approval.\n"
        "5. Only after the dry-run and account checks, intentionally change `DryRunMode=false`. The guard then attempts a minimum-volume entry only at/after day 50 and only when every safety check passes.\n"
        "6. Keep the terminal/VPS running. Monitor day-45, blocked day-50, and day-55 alerts. A blocked attempt is never overridden automatically.\n\n"
        "Do not attach multiple instances. An atomic terminal-wide execution lock and account history prevent duplicates, but a single instance is the supported deployment. This work did not connect to or trade any funded/challenge account.\n"
    )

    (OUT / "safety-and-failure-modes.md").write_text(
        "# Safety and failure modes\n\n"
        "The guard resets its timer only from executed `DEAL_ENTRY_IN` or `DEAL_ENTRY_INOUT` BUY/SELL deals with positive volume. Submitted, rejected, or merely accepted orders never reset it. All account entries count; audit rows distinguish guard magic/comment from non-guard entries. State is rebuilt from complete account history after EA, chart, terminal, or VPS restart.\n\n"
        "Before entry it requires terminal, program, account, expert, symbol, session, tick, spread, volume, SL/TP, margin, daily-floor, static-floor, and projected-loss checks. Dry-run also performs broker `OrderCheck` preflight, which submits no order and provides a second read-only/account-permission rejection beyond MT5's account flags. Default projected risk at the captured 0.6-pip EURUSD RAW snapshot is USD 1.22: USD 1.00 stop + USD 0.06 spread + USD 0.10 configured slippage + USD 0.06 commission. This is an estimate; gaps and slippage can exceed it.\n\n"
        "The guard blocks when any position already exists on the maintenance symbol, avoiding V28 merge or hedge interference. In the captured FXIFY hedging mode the guard position retains its own ticket. In a netting account, if another strategy later changes ownership of the guard's position identifier, the guard raises a critical alert and refuses an automatic close rather than reducing V28 exposure. That mixed-ownership state requires manual review; the guard does not assume that its original stop remains attributable after a netting merge.\n\n"
        "A missing server-side stop causes an immediate critical alert and close attempt; the guard never removes or widens a stop. At the maximum holding time it requests a natural market close. Rejections are logged and retried only after the configured interval. Closed market, excessive spread, stale prices, read-only access, disabled Algo Trading, invalid specifications, insufficient margin, and loss-buffer proximity all block entry and alert. No check is bypassed near day 60.\n"
    )

    (OUT / "deterministic-test-results.md").write_text(
        "# Deterministic test results\n\n"
        f"Result: **{len(records)} passed, 0 failed**. MetaEditor compile: **0 errors, 0 warnings**.\n\n"
        "The suite covers all requested cases: V28/guard timer resets; day 45/50/55 scheduling; exact single-entry intent; restart reconstruction; weekends; spreads; read-only and Algo Trading blocks; rejection retry; existing exposure; invalid specifications; margin and both loss buffers; full cost composition; partial fills; netting/hedging; maximum hold; server stop; frozen production; and the historical gap. Exact case names and results are in `deterministic-test-results.csv`.\n"
    )

    (OUT / "synthetic-63-day-gap-simulation.md").write_text(
        "# Synthetic historical-gap simulation\n\n"
        "Original V28 entries are `2026-02-02 10:05:01` and `2026-04-06 10:05:00`, an interval of 62d 23:59:59. The guard warns at `2026-03-19 10:05:01` (day 45), calculates one safe maintenance entry at `2026-03-24 10:05:01` (day 50), and resets only after the synthetic executed guard `DEAL_ENTRY_IN`. At the next V28 entry, only 12d 23:59:59 has elapsed. The account never reaches 60 consecutive inactive calendar days.\n\n"
        "The default projected worst-case cost is USD 1.22 using the captured 0.6-pip EURUSD RAW snapshot, official USD 6/lot commission, 0.01 lot, 10-pip stop, and 1-pip configured slippage. The simulation does not claim this snapshot is historical FXIFY spread history.\n"
    )

    log_rows = [
        {"server_time": "2026.02.02 10:05:01", "event_type": "ACCOUNT_ENTRY_RECONSTRUCTED", "reason_code": "ACCOUNT_NON_GUARD", "elapsed_days": "0.00000000", "symbol": "EURUSD.r", "volume": "0.01000000", "projected_loss": "0.00000000", "magic_number": "608055001", "order_comment": "FXIFY_INACT_GUARD", "deal_source": "V28"},
        {"server_time": "2026.03.19 10:05:01", "event_type": "DAY_45_WARNING", "reason_code": "INACTIVITY_WARNING", "elapsed_days": "45.00000000", "symbol": "", "volume": "0.00000000", "projected_loss": "0.00000000", "magic_number": "608055001", "order_comment": "FXIFY_INACT_GUARD", "deal_source": "NONE"},
        {"server_time": "2026.03.24 10:05:01", "event_type": "ENTRY_PLAN_SAFE", "reason_code": "PLAN_SAFE", "elapsed_days": "50.00000000", "symbol": "EURUSD.r", "volume": "0.01000000", "projected_loss": "1.22000000", "magic_number": "608055001", "order_comment": "FXIFY_INACT_GUARD", "deal_source": "GUARD"},
        {"server_time": "2026.03.24 10:05:01", "event_type": "EXECUTED_ENTRY_CONFIRMED", "reason_code": "GUARD", "elapsed_days": "0.00000000", "symbol": "EURUSD.r", "volume": "0.01000000", "projected_loss": "1.22000000", "magic_number": "608055001", "order_comment": "FXIFY_INACT_GUARD", "deal_source": "GUARD"},
        {"server_time": "2026.03.24 10:05:01", "event_type": "SERVER_STOP_CONFIRMED", "reason_code": "SERVER_STOP_PRESENT", "elapsed_days": "0.00000000", "symbol": "EURUSD.r", "volume": "0.01000000", "projected_loss": "1.22000000", "magic_number": "608055001", "order_comment": "FXIFY_INACT_GUARD", "deal_source": "GUARD"},
    ]
    write_csv(OUT / "auditable-event-log-example.csv", list(log_rows[0]), log_rows)

    (OUT / "compliance-note.md").write_text(
        "# FXIFY compliance note\n\n"
        "The user records that FXIFY received the exact guard description and replied on 2026-08-05: **“The EA is fine.”** This repository stores that approval statement only; it stores no account credentials. Deployment remains limited to the approved behavior and the Two Phase Pro EA approval conditions.\n"
    )

    (OUT / "evidence-manifest.md").write_text(
        "# Evidence manifest\n\n"
        f"- Guard source SHA-256: `{sha(EA)}`\n"
        f"- Deterministic model SHA-256: `{sha(MODEL)}`\n"
        f"- Test suite SHA-256: `{sha(TESTS)}`\n"
        f"- FXIFY RAW symbol capture SHA-256: `{sha(RAW_SPECS)}`\n"
        f"- Credential-free RAW account/server capture SHA-256: `{sha(RAW_ACCOUNT)}`\n"
        f"- Frozen production SHA-256: `{sha(PRODUCTION)}`\n"
        "- MetaEditor compile: `0 errors / 0 warnings`\n"
        "- Development order submissions: `0`\n"
        "- Funded/challenge connection or trading: `NONE`\n"
        "- Credentials recorded: `NO`\n"
    )

    (OUT / "final-readiness-decision.md").write_text(
        "# Final readiness decision\n\n"
        f"- Deterministic tests: `{len(records)} PASS / 0 FAIL`\n"
        "- MetaEditor compile: `0 errors / 0 warnings`\n"
        "- Historical 62d 23:59:59 gap: `PREVENTED`; day-45 warning and day-50 executed-entry reset demonstrated\n"
        f"- Frozen production SHA-256: `{sha(PRODUCTION)}`\n"
        "- V28/production changes: `NONE`\n"
        "- Funded/challenge trades during development: `NONE`\n"
        "- Default deployment mode: `DRY RUN`\n\n"
        f"{TOKEN}\n"
    )

    manifest = [
        EA,
        MODEL,
        TESTS,
        STATIC_TEST,
        PRODUCTION,
        RAW_SPECS,
        RAW_ACCOUNT,
        Path(__file__),
        *sorted(path for path in OUT.iterdir() if path.is_file() and path.name != "complete-sha256-ledger.txt"),
    ]
    unique = sorted(set(manifest))
    (OUT / "complete-sha256-ledger.txt").write_text(
        "".join(f"{sha(path)}  {path.relative_to(ROOT)}\n" for path in unique)
    )


if __name__ == "__main__":
    main()
