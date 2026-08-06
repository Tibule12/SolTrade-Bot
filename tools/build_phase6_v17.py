#!/usr/bin/env python3
"""Build Phase 6 V17 non-profitability V2 confirmation-filter attribution."""

from __future__ import annotations

import csv
import hashlib
import json
from collections import Counter, defaultdict
from datetime import datetime
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "reports/backtests/phase6-v17-v2-feasibility-postmortem"
H1 = Path("/home/tibule12/.wine-fpmarkets/drive_c/v8/derived/SolTradePhase6V8DerivedH1.csv")
FMT = "%Y.%m.%d %H:%M:%S"
PRODUCTION_HASH = "261a9cfe1c1e8d84e2a2a468ac4d0775086b21c89824b117e5127697fd03ced3"

CONDITIONS = [
    ("immediate_next_completed_h1", "Immediate next completed market H1 candle is available in the same clean segment"),
    ("continued_direction_beyond_setup_close", "Confirmation close continues strictly beyond setup close"),
    ("beyond_frozen_donchian_boundary", "Confirmation close remains strictly beyond the frozen Donchian boundary"),
    ("correct_side_ema200", "Confirmation close remains strictly on the directional side of EMA 200"),
    ("ema_distance_at_most_2_atr", "Absolute EMA distance is no greater than two ATR"),
    ("atr_regime_0_50_to_2_00", "ATR/ATR mean 100 is within the inclusive frozen band"),
    ("strict_equality_rejection", "No strict directional condition is met only by equality"),
    ("minimum_300_clean_segment_h1", "At least 300 clean segment-local completed H1 bars are available"),
    ("no_position_already_open", "No canonical simulated V2 position is already open"),
    ("risk_or_spread_entry_state", "Observable spread/risk entry state permits entry"),
    ("other_frozen_no_trade_conditions", "All other observable frozen no-trade conditions pass"),
]
KEYS = [x[0] for x in CONDITIONS]

SEGMENTS = [
    ("SEGMENT_1", datetime(2025, 1, 2), datetime(2025, 2, 5, 0)),
    ("SEGMENT_2", datetime(2025, 2, 17, 9), datetime(2025, 3, 7, 23)),
    ("SEGMENT_3", datetime(2025, 3, 20, 8), datetime(2025, 8, 6, 16)),
    ("SEGMENT_4", datetime(2025, 8, 19, 2), datetime(2025, 12, 24)),
]


def sha(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for block in iter(lambda: f.read(1 << 20), b""):
            h.update(block)
    return h.hexdigest()


def dump(name: str, value: object) -> None:
    (OUT / name).write_text(json.dumps(value, indent=2) + "\n", encoding="utf-8")


def partition(t: datetime) -> str | None:
    if datetime(2025, 1, 16) <= t < datetime(2025, 7, 5):
        return "DEVELOPMENT_2025"
    if datetime(2025, 7, 5) <= t < datetime(2025, 9, 29):
        return "VALIDATION_EQUIVALENT_2025"
    if datetime(2025, 9, 29) <= t < datetime(2025, 12, 24):
        return "OOS_EQUIVALENT_2025"
    return None


def indicators(bars: list[dict]) -> None:
    ema = [None] * len(bars)
    atr = [None] * len(bars)
    if len(bars) >= 200:
        ema[199] = sum(x["c"] for x in bars[:200]) / 200
        alpha = 2 / 201
        for i in range(200, len(bars)):
            ema[i] = bars[i]["c"] * alpha + ema[i-1] * (1-alpha)
    tr = []
    for i, b in enumerate(bars):
        tr.append(b["h"]-b["l"] if i == 0 else max(b["h"]-b["l"], abs(b["h"]-bars[i-1]["c"]), abs(b["l"]-bars[i-1]["c"])))
    if len(bars) >= 14:
        atr[13] = sum(tr[:14]) / 14
        for i in range(14, len(bars)):
            atr[i] = (atr[i-1]*13 + tr[i]) / 14
    for i, b in enumerate(bars):
        b["ema"] = ema[i]
        b["atr"] = atr[i]
        b["atr_mean"] = sum(atr[i-99:i+1])/100 if i >= 112 and all(x is not None for x in atr[i-99:i+1]) else None


def bucket_ratio(value: float | None) -> str:
    if value is None: return "UNAVAILABLE"
    if value < .5: return "BELOW_0_50"
    if value <= 2: return "WITHIN_0_50_TO_2_00"
    return "ABOVE_2_00"


def bucket_distance(value: float | None) -> str:
    if value is None: return "UNAVAILABLE"
    if value <= 1: return "AT_MOST_1_ATR"
    if value <= 2: return "OVER_1_TO_2_ATR"
    return "OVER_2_ATR"


def nested_counts(rows: list[dict], field: str) -> dict:
    result = {}
    for label in sorted({r[field] for r in rows}):
        subset = [r for r in rows if r[field] == label]
        result[label] = {
            "setups": len(subset), "confirmations": sum(r["confirmed"] for r in subset),
            "rejections": sum(not r["confirmed"] for r in subset),
            "failure_counts": {k: sum(not r[f"pass_{k}"] for r in subset) for k in KEYS},
            "first_failure_counts": dict(Counter(r["first_failing_condition"] for r in subset if r["first_failing_condition"])),
        }
    return result


def main() -> int:
    OUT.mkdir(parents=True, exist_ok=True)
    all_bars = []
    with H1.open(newline="", encoding="utf-8") as f:
        for r in csv.DictReader(f):
            all_bars.append({
                "t": datetime.strptime(r["timestamp"], FMT), "o": float(r["bid_open"]),
                "h": float(r["bid_high"]), "l": float(r["bid_low"]), "c": float(r["bid_close"]),
                "ask_o": float(r["ask_open"]), "spread_o": float(r["spread_points_open"]),
                "ticks": int(r["tick_count"]),
            })

    ledger = []
    position = None
    for segment_name, start, end in SEGMENTS:
        bars = [dict(x) for x in all_bars if start <= x["t"] < end]
        indicators(bars)
        position = None
        for i, s in enumerate(bars):
            # Canonical state exit is used solely for position-availability state.
            if position and i > position["entry_i"]:
                stop = s["l"] <= position["stop"] if position["direction"] == "BUY" else s["h"] >= position["stop"]
                channel = i >= 10 and (s["c"] < min(x["l"] for x in bars[i-10:i]) if position["direction"] == "BUY" else s["c"] > max(x["h"] for x in bars[i-10:i]))
                if stop or channel:
                    position = None
            part = partition(s["t"])
            if part is None or i < 20 or s["ema"] is None:
                continue
            high20 = max(x["h"] for x in bars[i-20:i])
            low20 = min(x["l"] for x in bars[i-20:i])
            direction = "BUY" if s["c"] > high20 and s["c"] > s["ema"] else "SELL" if s["c"] < low20 and s["c"] < s["ema"] else None
            if direction is None:
                continue
            c = bars[i+1] if i+1 < len(bars) else None
            immediate = c is not None
            beyond_close = immediate and (c["c"] > s["c"] if direction == "BUY" else c["c"] < s["c"])
            boundary = high20 if direction == "BUY" else low20
            beyond_boundary = immediate and (c["c"] > boundary if direction == "BUY" else c["c"] < boundary)
            correct_ema = immediate and c["ema"] is not None and (c["c"] > c["ema"] if direction == "BUY" else c["c"] < c["ema"])
            distance_ratio = abs(c["c"]-c["ema"])/c["atr"] if immediate and c["ema"] is not None and c["atr"] else None
            distance_ok = distance_ratio is not None and distance_ratio <= 2
            atr_ratio = c["atr"]/c["atr_mean"] if immediate and c["atr"] and c["atr_mean"] else None
            regime_ok = atr_ratio is not None and .5 <= atr_ratio <= 2
            equality = immediate and not (c["c"] == s["c"] or c["c"] == boundary or c["c"] == c["ema"])
            history_ok = i+1 >= 300
            no_position = position is None
            # Entry is at the first tradable tick after C, represented by the next bar's observed opening spread.
            entry_bar = bars[i+2] if i+2 < len(bars) else None
            spread_limit = min(30.0, .1*c["atr"]/.00001) if immediate and c["atr"] else None
            risk_spread_ok = entry_bar is not None and spread_limit is not None and entry_bar["spread_o"] <= spread_limit
            other_ok = immediate and c["ticks"] > 0 and c["atr"] is not None and c["ema"] is not None and c["atr_mean"] is not None
            passes = dict(zip(KEYS, [immediate, beyond_close, beyond_boundary, correct_ema, distance_ok, regime_ok, equality, history_ok, no_position, risk_spread_ok, other_ok]))
            failed = [k for k in KEYS if not passes[k]]
            confirmed = not failed
            if confirmed:
                # Non-monetary canonical position state; no result classification is retained.
                entry_price = entry_bar["ask_o"] if direction == "BUY" else entry_bar["o"]
                position = {"direction": direction, "entry_i": i+2, "stop": entry_price-2*c["atr"] if direction == "BUY" else entry_price+2*c["atr"]}
            row = {
                "timestamp": s["t"].isoformat(" "), "direction": direction,
                "clean_segment": segment_name, "partition": part,
                "setup_close": f"{s['c']:.10f}", "frozen_donchian_boundary": f"{boundary:.10f}",
                "confirmation_timestamp": c["t"].isoformat(" ") if c else "",
                "volatility_regime": bucket_ratio(atr_ratio), "distance_from_ema_bucket": bucket_distance(distance_ratio),
                "all_conditions_passed": "|".join(k for k in KEYS if passes[k]),
                "all_conditions_failed": "|".join(failed), "first_failing_condition": failed[0] if failed else "",
                "multiple_conditions_failed": len(failed) > 1, "confirmed": confirmed,
            }
            row.update({f"pass_{k}": passes[k] for k in KEYS})
            row.update({f"would_confirm_without_{k}": len(failed) == 1 and failed[0] == k for k in KEYS})
            ledger.append(row)

    fields = list(ledger[0])
    with (OUT / "v2-setup-level-filter-ledger.csv").open("w", newline="", encoding="utf-8") as f:
        w = csv.DictWriter(f, fieldnames=fields, lineterminator="\n")
        w.writeheader(); w.writerows(ledger)

    failures = {k: sum(not r[f"pass_{k}"] for r in ledger) for k in KEYS}
    passes = {k: len(ledger)-failures[k] for k in KEYS}
    first = Counter(r["first_failing_condition"] for r in ledger if r["first_failing_condition"])
    combinations = Counter(r["all_conditions_failed"] or "NONE_CONFIRMED" for r in ledger)
    exclusive = {k: sum(r["all_conditions_failed"] == k for r in ledger) for k in KEYS}
    removals = {k: sum(r[f"would_confirm_without_{k}"] for r in ledger) for k in KEYS}
    confirmed_n = sum(r["confirmed"] for r in ledger)
    dominant_failure = max(failures, key=failures.get)
    dominant_exclusive = max(exclusive, key=exclusive.get)
    dominant_combo, dominant_combo_n = max(((k, v) for k, v in combinations.items() if "|" in k), key=lambda x: x[1])

    attribution = {
        "schema": "SOLTRADE_PHASE6_V17_V2_FILTER_ATTRIBUTION_V1",
        "status": "PASS", "strategy": "SOLTRADE_TREND_BREAKOUT_V2_1_0", "source_role": "PREVIOUSLY_QUALIFIED_2025_DATA_ONLY",
        "source_h1_path": str(H1), "source_h1_sha256": sha(H1), "total_setups": len(ledger), "total_confirmations": confirmed_n,
        "confirmation_rate_descriptive_non_profitability": confirmed_n/len(ledger),
        "conditions": {k: {"description": d, "pass_count": passes[k], "failure_count": failures[k], "exclusive_failure_count": exclusive[k], "would_confirm_if_removed_alone": removals[k]} for k, d in CONDITIONS},
        "first_failure_counts": dict(first), "partition_counts": nested_counts(ledger, "partition"),
        "volatility_regime_counts": nested_counts(ledger, "volatility_regime"), "distance_bucket_counts": nested_counts(ledger, "distance_from_ema_bucket"),
        "guardrails": {"pnl_calculated": False, "profitability_tested": False, "optimization_run": False, "orders_or_positions_placed": False, "2026_used_for_design_or_tuning": False},
    }
    dump("v2-confirmation-filter-attribution.json", attribution)
    dump("v2-filter-overlap-report.json", {
        "total_rejected_setups": len(ledger)-confirmed_n, "single_failure_setups": sum(len(r["all_conditions_failed"].split("|")) == 1 for r in ledger if not r["confirmed"]),
        "multiple_failure_setups": sum(r["multiple_conditions_failed"] for r in ledger), "failure_combinations": dict(combinations),
        "individual_failure_counts": failures, "exclusive_failure_counts": exclusive, "first_failure_counts": dict(first),
        "dominant_individual_failure": {"condition": dominant_failure, "count": failures[dominant_failure]},
        "dominant_exclusive_failure": {"condition": dominant_exclusive, "count": exclusive[dominant_exclusive]},
        "dominant_overlapping_combination": {"conditions": dominant_combo.split("|"), "count": dominant_combo_n},
    })
    dump("v2-long-short-feasibility-report.json", {"BUY": nested_counts(ledger, "direction")["BUY"], "SELL": nested_counts(ledger, "direction")["SELL"]})

    buy = [r for r in ledger if r["direction"] == "BUY"]
    sell = [r for r in ledger if r["direction"] == "SELL"]
    def top_fail(rows):
        vals = {k: sum(not r[f"pass_{k}"] for r in rows) for k in KEYS}
        return max(vals, key=vals.get), max(vals.values())
    buy_top, buy_top_n = top_fail(buy); sell_top, sell_top_n = top_fail(sell)
    next_fail = failures["continued_direction_beyond_setup_close"]
    main_cause = dominant_failure

    (OUT / "trend-breakout-v2-closure-report.md").write_text(f"""# Trend Breakout V2 formal closure\n\nFinal V2 status: `RETIRED_SAMPLE_INFEASIBLE`.\n\nV2 was never profitability-tested and was not rejected because of financial performance. It is retired as operationally infeasible because its frozen confirmation rules produced an insufficient research sample: only 3 of 268 V16 setups confirmed, and the proposed 2026 OOS interval produced only 2 naturally completed cycles against the immutable minimum of 50. Extending the same design toward approximately 2034 is not a practical validation plan.\n\nV2 must not proceed to profitability testing, demo forward testing, live trading, production implementation, or Phase 7. The V16 extension amendment remains unapplied.\n""", encoding="utf-8")
    (OUT / "v2-bottleneck-analysis.md").write_text(f"""# V2 confirmation-filter bottleneck analysis\n\nThis attribution uses only previously qualified 2025 tick-derived data. The historical date slices are partition equivalents for comparison, not unseen V2 evidence. No rejected setup was evaluated as a winner or loser.\n\n- Largest individual rejection: `{dominant_failure}` ({failures[dominant_failure]} setups).\n- Largest exclusive rejection: `{dominant_exclusive}` ({exclusive[dominant_exclusive]} setups).\n- Most common failed-condition combination: `{dominant_combo}` ({dominant_combo_n} setups).\n- Continued next-candle direction failed {next_fail} setups. The dominant measured bottleneck is `{main_cause}`; therefore the immediate confirmation persistence requirement is {'the main reason' if main_cause == 'continued_direction_beyond_setup_close' else 'not the sole main reason'} for the low confirmation rate.\n- BUY's largest failure is `{buy_top}` ({buy_top_n}/{len(buy)}); SELL's is `{sell_top}` ({sell_top_n}/{len(sell)}). This shows {'a shared dominant mechanism' if buy_top == sell_top else 'directionally different dominant mechanisms'}.\n- Multiple filters failed together on {sum(r['multiple_conditions_failed'] for r in ledger)} rejected setups, while {sum(len(r['all_conditions_failed'].split('|')) == 1 for r in ledger if not r['confirmed'])} had one exclusive failure. Overlap demonstrates partial redundancy; non-zero exclusive counts demonstrate that independently restrictive filters also remain.\n\n## Structural connection to the V1 failure mechanism\n\nThe immediate-next-candle and continued-direction tests are directly connected: they demand immediate persistence after breakouts that previously reversed before follow-through. Remaining beyond the frozen Donchian boundary is also direct persistence evidence. The EMA-side test preserves trend direction and is indirectly connected. The two-ATR EMA-distance cap limits overextended entries and is indirectly connected to reversal risk. The ATR-regime band is a market-data/volatility sanity guard rather than direct proof of persistence. Equality rejection supplies deterministic strictness rather than a separate economic hypothesis. The 300-bar rule protects indicator integrity, not the reversal mechanism. Position, spread/risk, and other no-trade guards protect operational and risk integrity rather than confirming follow-through.\n\nNo condition change is recommended here. Removing a condition to increase signals would be strategy redesign and is outside V17.\n""", encoding="utf-8")
    (OUT / "phase6-v17-terminal-outcome.md").write_text(f"""# Phase 6 V17 terminal outcome\n\n`V2_RETIRED_FILTER_ATTRIBUTION_COMPLETE`\n\nV2 final status: `RETIRED_SAMPLE_INFEASIBLE`. Attribution completed for {len(ledger)} qualified-2025 candidate setups with {confirmed_n} full confirmations. No P&L, profitability metric, optimization, order, position, V3 design, production implementation, or Phase 7 work occurred.\n""", encoding="utf-8")
    files = sorted(p for p in OUT.iterdir() if p.name != "artifact-sha256-v17.txt")
    (OUT / "artifact-sha256-v17.txt").write_text("".join(f"{sha(p)}  {p.name}\n" for p in files), encoding="ascii")
    print(json.dumps({"setups": len(ledger), "confirmations": confirmed_n, "failures": failures, "exclusive": exclusive, "first": first, "combination": [dominant_combo, dominant_combo_n], "buy": len(buy), "sell": len(sell)}, indent=2, default=dict))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
