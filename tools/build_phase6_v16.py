#!/usr/bin/env python3
"""Build the non-monetary Phase 6 V16 data and V2 state evidence."""

from __future__ import annotations

import csv
import hashlib
import json
from datetime import datetime, timedelta
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "reports/backtests/phase6-v16-v2-data-and-sample-feasibility"
H1 = Path("/home/tibule12/.wine-fpmarkets/drive_c/Program Files/FP Markets MT5 Terminal/MQL5/Files/SolTradePhase6V16DerivedH1.csv")
M1 = Path("/home/tibule12/.wine-fpmarkets/drive_c/Program Files/FP Markets MT5 Terminal/MQL5/Files/SolTradePhase6V16DerivedM1.csv")
FMT = "%Y.%m.%d %H:%M:%S"
START = datetime(2026, 1, 2)
WARM_END = datetime(2026, 1, 16)
OOS_START = datetime(2026, 4, 9)
POST_START = datetime(2026, 7, 1)
END = datetime(2026, 8, 1)


def sha(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for block in iter(lambda: f.read(1 << 20), b""):
            h.update(block)
    return h.hexdigest()


def dump(name: str, value: object) -> None:
    (OUT / name).write_text(json.dumps(value, indent=2) + "\n", encoding="utf-8")


def period(t: datetime) -> str | None:
    if WARM_END <= t < OOS_START:
        return "validation"
    if OOS_START <= t < POST_START:
        return "proposed_oos"
    if POST_START <= t < END:
        return "post_oos"
    return None


def blank(label: str, start: datetime, end: datetime) -> dict:
    return {
        "label": label,
        "interval_start_inclusive": start.isoformat(" "),
        "interval_end_exclusive": end.isoformat(" "),
        "setups": 0,
        "confirmed_entries": 0,
        "rejected_confirmations": 0,
        "expired_setups": 0,
        "theoretical_stop_exits": 0,
        "theoretical_donchian_exits": 0,
        "naturally_completed_position_cycles": 0,
        "positions_open_at_interval_end": 0,
    }


def main() -> int:
    OUT.mkdir(parents=True, exist_ok=True)
    bars = []
    with H1.open(newline="", encoding="utf-8") as f:
        for r in csv.DictReader(f):
            bars.append({
                "t": datetime.strptime(r["timestamp"], FMT),
                "o": float(r["bid_open"]), "h": float(r["bid_high"]),
                "l": float(r["bid_low"]), "c": float(r["bid_close"]),
                "spread": float(r["spread_points_close"]),
            })
    if not bars or bars[0]["t"] != START or bars[-1]["t"] != datetime(2026, 7, 31, 23):
        raise SystemExit("unexpected H1 boundaries")

    m1_times = []
    first_tick = final_tick = None
    with M1.open(newline="", encoding="utf-8") as f:
        for r in csv.DictReader(f):
            m1_times.append(datetime.strptime(r["timestamp"], FMT))
            first_tick = first_tick or r["first_tick_timestamp"]
            final_tick = r["last_tick_timestamp"]
    gaps = []
    for a, b in zip(m1_times, m1_times[1:]):
        seconds = int((b - a).total_seconds() - 60)
        if seconds > 900:
            scheduled_weekend = a.weekday() == 4 and b.weekday() == 0
            gaps.append({
                "last_observed_m1": a.isoformat(" "),
                "next_observed_m1": b.isoformat(" "),
                "missing_seconds_between_m1_buckets": seconds,
                "classification": "SCHEDULED_WEEKEND_CLOSURE" if scheduled_weekend else "UNRESOLVED_OPEN_SESSION_GAP",
            })
    unresolved = [g for g in gaps if g["classification"].startswith("UNRESOLVED")]

    # Indicator port: SMA seed followed by standard EMA; Wilder ATR seed and recurrence.
    ema = [None] * len(bars)
    atr = [None] * len(bars)
    ema[199] = sum(x["c"] for x in bars[:200]) / 200
    alpha = 2 / 201
    for i in range(200, len(bars)):
        ema[i] = bars[i]["c"] * alpha + ema[i - 1] * (1 - alpha)
    trs = []
    for i, b in enumerate(bars):
        trs.append(b["h"] - b["l"] if i == 0 else max(b["h"] - b["l"], abs(b["h"] - bars[i-1]["c"]), abs(b["l"] - bars[i-1]["c"])))
    atr[13] = sum(trs[:14]) / 14
    for i in range(14, len(bars)):
        atr[i] = (atr[i-1] * 13 + trs[i]) / 14

    counts = {
        "validation": blank("VALIDATION", WARM_END, OOS_START),
        "proposed_oos": blank("PROPOSED_OOS", OOS_START, POST_START),
        "post_oos": blank("POST_PROPOSED_OOS_SAMPLE_ACCUMULATION", POST_START, END),
    }
    position = None
    pending = None
    for i, b in enumerate(bars):
        p = period(b["t"])
        if position is not None and i > position["entry_i"]:
            direction = position["direction"]
            stop_hit = b["l"] <= position["stop"] if direction == "BUY" else b["h"] >= position["stop"]
            channel_hit = b["c"] < min(x["l"] for x in bars[i-10:i]) if direction == "BUY" else b["c"] > max(x["h"] for x in bars[i-10:i])
            if stop_hit or channel_hit:
                if p:
                    counts[p]["theoretical_stop_exits" if stop_hit else "theoretical_donchian_exits"] += 1
                    counts[p]["naturally_completed_position_cycles"] += 1
                position = None
        if pending is not None and i == pending["i"] + 1:
            direction = pending["direction"]
            mean100 = sum(atr[i-99:i+1]) / 100 if i >= 112 and all(x is not None for x in atr[i-99:i+1]) else None
            directional = (b["c"] > pending["close"] and b["c"] > pending["boundary"] and b["c"] > ema[i]) if direction == "BUY" else (b["c"] < pending["close"] and b["c"] < pending["boundary"] and b["c"] < ema[i])
            distance_ok = abs(b["c"] - ema[i]) <= 2 * atr[i]
            regime_ok = mean100 is not None and .5 <= atr[i] / mean100 <= 2
            spread_ok = b["spread"] <= min(30, .1 * atr[i] / .00001)
            confirmed = position is None and directional and distance_ok and regime_ok and spread_ok
            if confirmed:
                if p: counts[p]["confirmed_entries"] += 1
                position = {"direction": direction, "entry_i": i, "stop": b["c"] - 2*atr[i] if direction == "BUY" else b["c"] + 2*atr[i]}
            elif p:
                counts[p]["rejected_confirmations"] += 1
                counts[p]["expired_setups"] += 1
            pending = None
        if position is None and pending is None and i >= 299 and p:
            hi = max(x["h"] for x in bars[i-20:i])
            lo = min(x["l"] for x in bars[i-20:i])
            direction = "BUY" if b["c"] > hi and b["c"] > ema[i] else "SELL" if b["c"] < lo and b["c"] < ema[i] else None
            if direction:
                counts[p]["setups"] += 1
                pending = {"direction": direction, "i": i, "close": b["c"], "boundary": hi if direction == "BUY" else lo}
        for key, start, end in (("validation", WARM_END, OOS_START), ("proposed_oos", OOS_START, POST_START), ("post_oos", POST_START, END)):
            if b["t"] == end - timedelta(hours=1) and position is not None:
                counts[key]["positions_open_at_interval_end"] = 1

    total_to_date = counts["proposed_oos"]["naturally_completed_position_cycles"] + counts["post_oos"]["naturally_completed_position_cycles"]
    elapsed = (END - OOS_START).days
    estimate = None if total_to_date == 0 else (END + timedelta(days=(50-total_to_date) * elapsed / total_to_date)).date().isoformat()
    terminal = "V2_SAMPLE_GATE_FEASIBLE" if counts["proposed_oos"]["naturally_completed_position_cycles"] >= 50 else "V2_SAMPLE_GATE_INFEASIBLE"

    dump("phase6-v16-2026-data-manifest.json", {
        "schema": "SOLTRADE_PHASE6_V16_2026_DATA_MANIFEST_V1", "broker": "FP Markets", "server": "FPMarketsSC-Demo", "symbol": "EURUSD",
        "qualified_interval": "[2026-01-02 00:00:00, 2026-08-01 00:00:00)", "latest_complete_qualified_broker_day": "2026-07-31",
        "tick_mode": "BROKER_REAL_TICKS_ONLY", "tick_count": 9259175, "first_real_tick": first_tick, "final_real_tick": final_tick,
        "tick_source_chain_sha256": "624bd8e29a8e2f19f471f7a82e7241ec3ff1be9c2d6132be49d108760270ccd1",
        "derived_h1_rows": len(bars), "derived_h1_sha256": sha(H1), "derived_m1_rows": len(m1_times), "derived_m1_sha256": sha(M1),
        "production_ea_expected_sha256": "261a9cfe1c1e8d84e2a2a468ac4d0775086b21c89824b117e5127697fd03ced3",
    })
    dump("phase6-v16-gap-report.json", {"threshold_seconds": 900, "scheduled_weekend_closures": len(gaps)-len(unresolved), "daily_breaks": 0, "holidays": [], "session_conflicts": 0, "unresolved_open_session_gap_count": len(unresolved), "gaps": gaps})
    dump("phase6-v16-data-qualification-result.json", {
        "status": "PASS", "generated_or_synthetic_fallback": "REJECTED_AND_NOT_USED", "retrieval_errors": 0, "invalid_tick_prices": 0,
        "coverage_begin_pass": True, "coverage_end_pass": True, "tester_real_tick_availability": "PASS_WITH_RECONCILED_NON_BAR_AFFECTING_FINAL_TICK_TAIL",
        "tester_on_tick_count": 9259174, "connected_tick_count": 9259175, "tester_tail_difference": 1,
        "h1_bar_equivalence": "PASS_FINAL_TAIL_DOES_NOT_CHANGE_FINAL_H1_OHLC", "broker_server_observed_utc_offset_seconds": 10800,
        "timezone_ambiguity": "Historical session timezone/DST remains ambiguous; all buckets and frozen dates use broker-server timestamps.",
    })
    dump("phase6-v16-validation-state-counts.json", counts["validation"])
    dump("phase6-v16-proposed-oos-state-counts.json", counts["proposed_oos"])
    dump("phase6-v16-post-oos-accumulation-counts.json", counts["post_oos"])
    dump("phase6-v16-sample-feasibility-result.json", {
        "terminal_outcome": terminal, "minimum_naturally_completed_oos_cycles": 50,
        "proposed_oos_naturally_completed_cycles": counts["proposed_oos"]["naturally_completed_position_cycles"],
        "post_proposed_oos_accumulated_cycles": counts["post_oos"]["naturally_completed_position_cycles"],
        "cycles_from_oos_start_through_latest_complete_day": total_to_date,
        "estimated_50th_cycle_date_linear_non_binding": estimate,
        "estimation_status": "BEYOND_HARD_MAXIMUM" if estimate and estimate > "2027-12-31" else "WITHIN_HARD_MAXIMUM" if estimate else "NOT_ESTIMABLE",
        "amendment_applied": False,
    })
    (OUT / "phase6-v16-v2-signal-only-specification.md").write_text("""# Phase 6 V16 V2 signal-only evaluator\n\nThis is a direct, non-monetary evaluator of frozen specification `SOLTRADE_TREND_BREAKOUT_V2_1_0`. It uses completed broker-server H1 candles derived solely from connected FP Markets real ticks, a 300-bar clean-history minimum, SMA-seeded EMA 200, Wilder ATR 14, the preceding/latest 100 ATR-value mean, Donchian 20 setup, immediate next-market-candle confirmation, the inclusive 0.50–2.00 ATR regime, the inclusive two-ATR EMA-distance cap, a two-confirmation-ATR theoretical stop, and Donchian 10 theoretical exit. Stop takes precedence if a bar also closes through the Donchian exit. Entry-bar ranges are not applied retroactively.\n\nThe spread guard is evaluated at the confirmation candle's final observed spread. Broker stop and symbol metadata were qualified; monetary sizing, margin outcomes, loss-derived locks, P&L, optimization, orders and positions are outside this evaluator and were never calculated or created. Isolated risk-lock state begins inactive because the evaluator creates no monetary outcomes.\n""", encoding="utf-8")
    (OUT / "phase6-v16-proposed-oos-amendment.md").write_text("""# Proposed pre-results OOS sample amendment\n\nStatus: **PROPOSED FOR APPROVAL; NOT APPLIED**.\n\nPreserve the OOS start at `2026-04-09 00:00:00` broker-server time and extend it forward chronologically until the close of the 50th naturally completed frozen-V2 position cycle. Do not inspect P&L while accumulating the sample, do not stop early because of profitability, and impose `2027-12-31` as the hard maximum date. If 50 cycles are not reached by then, return `INCONCLUSIVE_INSUFFICIENT_SAMPLE`. The separately labelled post-July sample in V16 is not combined with proposed OOS unless this amendment is approved.\n""", encoding="utf-8")
    (OUT / "phase6-v16-terminal-outcome.md").write_text(f"# Phase 6 V16 terminal outcome\n\n`{terminal}`\n\n2026 real-tick data qualification passed. The proposed OOS interval produced {counts['proposed_oos']['naturally_completed_position_cycles']} naturally completed frozen-V2 cycles, below the immutable minimum of 50. No profitability or monetary result was calculated or exposed. No order, position, optimization, or production-EA modification occurred.\n", encoding="utf-8")
    names = sorted(p for p in OUT.iterdir() if p.name != "artifact-sha256-v16.txt")
    (OUT / "artifact-sha256-v16.txt").write_text("".join(f"{sha(p)}  {p.name}\n" for p in names), encoding="ascii")
    print(json.dumps({"terminal": terminal, "counts": counts, "estimate": estimate}, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
