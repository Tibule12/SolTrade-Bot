#!/usr/bin/env python3
"""Build the Phase 6 V15 V1 forensic attribution from immutable V14 evidence."""

from __future__ import annotations

import csv
import hashlib
import json
import math
import statistics
from collections import defaultdict
from datetime import datetime
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
V14 = ROOT / "reports/backtests/phase6-v14-controlled-practical-backtest"
V15 = ROOT / "reports/backtests/phase6-v15-v1-postmortem-v2-design"
LEDGER = V14 / "phase6-v14-complete-trade-ledger.csv"


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def number(value: str | None) -> float | None:
    if value in (None, ""):
        return None
    return float(value)


def parse_details(details: str) -> dict[str, str]:
    values: dict[str, str] = {}
    for item in details.split("; "):
        if "=" in item:
            key, value = item.split("=", 1)
            values[key.strip()] = value.strip()
    return values


def load_entry_features(run_dir: Path) -> tuple[dict[str, dict], dict[str, int]]:
    signals: list[dict] = []
    with (run_dir / "events.csv").open(newline="", encoding="utf-8-sig") as handle:
        for row in csv.DictReader(handle):
            if row["event_type"] != "SIGNAL_EVALUATED":
                continue
            details = parse_details(row["details"])
            signal = {
                "event_time": row["time"],
                "signal_bar_time": details.get("signal_bar_time"),
                "entry_signal": details.get("entry_signal"),
                "close": number(details.get("close")),
                "ema_200": number(details.get("ema_200")),
                "entry_channel_high": number(details.get("entry_channel_high")),
                "entry_channel_low": number(details.get("entry_channel_low")),
                "atr_14": number(details.get("atr_14")),
            }
            signals.append(signal)

    entry_signals: dict[str, dict] = {}
    atr_history: list[float] = []
    for index, signal in enumerate(signals):
        atr = signal["atr_14"]
        previous_atr = atr_history[-100:]
        signal["atr_to_prior_100_mean"] = (
            atr / statistics.fmean(previous_atr)
            if atr is not None and len(previous_atr) == 100
            else None
        )
        if atr is not None:
            atr_history.append(atr)

        previous_ema = signals[index - 24]["ema_200"] if index >= 24 else None
        signal["ema_24bar_change"] = (
            signal["ema_200"] - previous_ema
            if signal["ema_200"] is not None and previous_ema is not None
            else None
        )
        if signal["entry_signal"] in ("BUY", "SELL"):
            entry_signals[signal["event_time"][:13]] = signal

    spreads: dict[str, int] = {}
    with (run_dir / "transactions.csv").open(newline="", encoding="utf-8-sig") as handle:
        for row in csv.DictReader(handle):
            if row["record_type"] != "ENTRY_ATTEMPT":
                continue
            if float(row["volume"]) <= 0.0 or float(row["requested_price"]) <= 0.0:
                continue
            spreads[row["time"][:13]] = int(row["spread_points"])
    return entry_signals, spreads


def classify_ratio(value: float | None, low: float, high: float) -> str:
    if value is None:
        return "UNAVAILABLE"
    if value < low:
        return "LOW"
    if value <= high:
        return "NORMAL"
    return "HIGH"


def enrich_ledger() -> list[dict]:
    with LEDGER.open(newline="", encoding="utf-8-sig") as handle:
        rows = list(csv.DictReader(handle))

    per_run: dict[str, tuple[dict[str, dict], dict[str, int]]] = {}
    for row in rows:
        run_id = row["run_id"]
        if run_id not in per_run:
            per_run[run_id] = load_entry_features(V14 / "physical-runs" / run_id)

        signals, spreads = per_run[run_id]
        entry_dt = datetime.fromisoformat(row["entry_time"])
        entry_key = entry_dt.strftime("%Y.%m.%d %H")
        signal = signals.get(entry_key)
        if signal is None:
            raise RuntimeError(f"Missing entry signal for {run_id} at {entry_key}")

        direction = row["direction"]
        close = signal["close"]
        ema = signal["ema_200"]
        atr = signal["atr_14"]
        boundary = (
            signal["entry_channel_high"]
            if direction == "LONG"
            else signal["entry_channel_low"]
        )
        breakout = close - boundary if direction == "LONG" else boundary - close
        ema_distance = abs(close - ema)
        slope = signal["ema_24bar_change"]
        if slope is None:
            slope_direction = "UNAVAILABLE"
            alignment = "UNAVAILABLE"
        elif slope > 0.0:
            slope_direction = "RISING"
            alignment = "ALIGNED" if direction == "LONG" else "COUNTER_SLOPE"
        elif slope < 0.0:
            slope_direction = "FALLING"
            alignment = "ALIGNED" if direction == "SHORT" else "COUNTER_SLOPE"
        else:
            slope_direction = "FLAT"
            alignment = "FLAT"

        r_value = float(row["realized_net_R"])
        net = float(row["adjusted_trade_net"])
        holding = float(row["holding_seconds"])
        row.update(
            {
                "entry_hour": entry_dt.hour,
                "entry_weekday": entry_dt.strftime("%A").upper(),
                "outcome": "WIN" if net > 0.0 else ("LOSS" if net < 0.0 else "BREAKEVEN"),
                "atr_14": atr,
                "atr_price_percent": atr / close * 100.0,
                "atr_to_prior_100_mean": signal["atr_to_prior_100_mean"],
                "volatility_regime": classify_ratio(signal["atr_to_prior_100_mean"], 0.80, 1.20),
                "trend_side": "ABOVE_EMA200" if direction == "LONG" else "BELOW_EMA200",
                "ema_24bar_change": slope,
                "ema_slope_direction": slope_direction,
                "trend_alignment": alignment,
                "ema_distance_price": ema_distance,
                "ema_distance_atr": ema_distance / atr,
                "ema_distance_band": (
                    "LT_1_ATR" if ema_distance / atr < 1.0
                    else ("1_TO_2_ATR" if ema_distance / atr < 2.0 else "GE_2_ATR")
                ),
                "breakout_distance_price": breakout,
                "breakout_distance_atr": breakout / atr,
                "breakout_distance_band": (
                    "LT_0.10_ATR" if breakout / atr < 0.10
                    else ("0.10_TO_0.25_ATR" if breakout / atr <= 0.25 else "GT_0.25_ATR")
                ),
                "spread_points_at_entry": spreads.get(entry_key),
                "spread_band": (
                    "LE_10_POINTS" if spreads.get(entry_key, 10**9) <= 10
                    else ("11_TO_15_POINTS" if spreads.get(entry_key, 10**9) <= 15 else "GT_15_POINTS")
                ),
                "holding_band": (
                    "LT_6_HOURS" if holding < 6 * 3600
                    else ("6_TO_24_HOURS" if holding <= 24 * 3600
                          else ("1_TO_3_DAYS" if holding <= 3 * 86400 else "GT_3_DAYS"))
                ),
                "rapid_stop_proxy": row["exit_reason"] == "STOP_LOSS_EXIT" and holding <= 24 * 3600,
                "r_value": r_value,
                "net_value": net,
                "holding_value": holding,
            }
        )
    return rows


def aggregate(rows: list[dict]) -> dict:
    wins = [row for row in rows if row["net_value"] > 0.0]
    losses = [row for row in rows if row["net_value"] < 0.0]
    gross_profit = sum(row["net_value"] for row in wins)
    gross_loss = sum(row["net_value"] for row in losses)
    average_win = statistics.fmean(row["net_value"] for row in wins) if wins else None
    average_loss = statistics.fmean(row["net_value"] for row in losses) if losses else None
    average_win_r = statistics.fmean(row["r_value"] for row in wins) if wins else None
    average_loss_r = statistics.fmean(row["r_value"] for row in losses) if losses else None
    return {
        "trades": len(rows),
        "wins": len(wins),
        "losses": len(losses),
        "breakeven": len(rows) - len(wins) - len(losses),
        "win_rate_percent": len(wins) / len(rows) * 100.0 if rows else None,
        "adjusted_net_profit": sum(row["net_value"] for row in rows),
        "gross_profit": gross_profit,
        "gross_loss": gross_loss,
        "profit_factor": gross_profit / abs(gross_loss) if gross_loss else None,
        "average_win": average_win,
        "average_loss": average_loss,
        "average_win_R": average_win_r,
        "average_loss_R": average_loss_r,
        "payoff_ratio_money": average_win / abs(average_loss) if average_win is not None and average_loss else None,
        "payoff_ratio_R": average_win_r / abs(average_loss_r) if average_win_r is not None and average_loss_r else None,
        "expectancy_R": statistics.fmean(row["r_value"] for row in rows) if rows else None,
        "average_holding_seconds": statistics.fmean(row["holding_value"] for row in rows) if rows else None,
        "median_holding_seconds": statistics.median(row["holding_value"] for row in rows) if rows else None,
        "rapid_stop_count": sum(bool(row["rapid_stop_proxy"]) for row in rows),
    }


def breakdown(rows: list[dict], field: str) -> list[dict]:
    groups: dict[str, list[dict]] = defaultdict(list)
    for row in rows:
        groups[str(row[field])].append(row)
    return [
        {"group": key, **aggregate(group_rows)}
        for key, group_rows in sorted(groups.items(), key=lambda item: item[0])
    ]


def write_attribution(rows: list[dict], reference: list[dict], output: Path) -> None:
    dimensions = {
        "direction": "direction",
        "exit_reason": "exit_reason",
        "outcome": "outcome",
        "holding_band": "holding_band",
        "entry_hour": "entry_hour",
        "entry_weekday": "entry_weekday",
        "volatility_regime": "volatility_regime",
        "trend_side": "trend_side",
        "ema_slope_direction": "ema_slope_direction",
        "trend_alignment": "trend_alignment",
        "ema_distance_band": "ema_distance_band",
        "breakout_distance_band": "breakout_distance_band",
        "spread_band": "spread_band",
        "segment": "segment",
        "dataset": "dataset",
    }
    records: list[dict] = []
    for label, field in dimensions.items():
        for item in breakdown(reference, field):
            records.append({"population": "NORMAL_NATIVE_REFERENCE", "dimension": label, **item})

    for label, field in {"cost_profile": "cost_profile", "execution_layer": "execution_layer"}.items():
        for item in breakdown(rows, field):
            records.append({"population": "ALL_FORMAL_LAYERS", "dimension": label, **item})

    headers = [
        "population", "dimension", "group", "trades", "wins", "losses", "breakeven",
        "win_rate_percent", "adjusted_net_profit", "gross_profit", "gross_loss",
        "profit_factor", "average_win", "average_loss", "average_win_R", "average_loss_R",
        "payoff_ratio_money", "payoff_ratio_R", "expectancy_R", "average_holding_seconds",
        "median_holding_seconds", "rapid_stop_count",
    ]
    with output.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=headers, lineterminator="\n")
        writer.writeheader()
        writer.writerows(records)


def main() -> None:
    V15.mkdir(parents=True, exist_ok=True)
    rows = enrich_ledger()
    reference = [
        row for row in rows
        if row["cost_profile"] == "NORMAL"
        and row["execution_layer"] == "NATIVE_NORMAL_EXECUTION"
    ]
    if len(reference) != 94:
        raise RuntimeError(f"Expected 94 non-duplicated reference trades, found {len(reference)}")

    by_exit = {item["group"]: item for item in breakdown(reference, "exit_reason")}
    by_direction = {item["group"]: item for item in breakdown(reference, "direction")}
    by_ema_distance = {
        item["group"]: item for item in breakdown(reference, "ema_distance_band")
    }
    stops = by_exit["STOP_LOSS_EXIT"]
    rapid_stops = sum(bool(row["rapid_stop_proxy"]) for row in reference)
    overall = aggregate(reference)
    breakeven_win_rate = (
        abs(overall["average_loss_R"])
        / (overall["average_win_R"] + abs(overall["average_loss_R"]))
        * 100.0
    )
    with (V14 / "phase6-v14-formal-cell-metrics.csv").open(
        newline="", encoding="utf-8-sig"
    ) as handle:
        formal_cells = [
            {
                key: row[key]
                for key in (
                    "cell_id", "dataset", "cost_profile", "execution_layer",
                    "adjusted_net_profit", "profit_factor", "expectancy_R",
                    "naturally_closed_trades", "relative_drawdown_percent",
                )
            }
            for row in csv.DictReader(handle)
        ]

    report = {
        "schema": "SOLTRADE_PHASE6_V15_V1_FAILURE_ANALYSIS_V1",
        "analysis_only": True,
        "new_backtest_performed": False,
        "source_evidence": {
            "v14_commit": "433d976d8041c5e107fead3c41d411059894bbf5",
            "v14_ledger": str(LEDGER.relative_to(ROOT)),
            "v14_ledger_sha256": sha256(LEDGER),
            "v14_checksum_manifest_sha256": sha256(V14 / "artifact-sha256-v14.txt"),
            "production_ea_sha256": sha256(ROOT / "MQL5/Experts/SolTradeBot.mq5"),
        },
        "population_semantics": {
            "reference": "94 naturally closed NORMAL + NATIVE trades; each underlying V1 trade appears once; money attribution uses the ledger's adjusted_trade_net and R attribution uses realized_net_R",
            "layer_comparison": "All 564 cost/execution rows are used only where the cost or execution axis is explicitly compared",
            "right_censored_positions": "Excluded exactly as frozen in V14; separately reported by V14",
        },
        "feature_definitions": {
            "entry_hour_and_weekday": "Broker-server timestamp of actual entry",
            "volatility_regime": "ATR14 divided by the mean ATR14 of the preceding 100 logged completed H1 evaluations: LOW < 0.80; NORMAL 0.80 to 1.20 inclusive; HIGH > 1.20; unavailable until 100 observations exist",
            "trend_direction": "Sign of EMA200 change versus 24 logged completed-H1 evaluations earlier; alignment compares that sign with trade direction",
            "ema_distance": "Absolute completed signal-bar close minus EMA200, divided by ATR14",
            "breakout_distance": "Directional completed signal-bar close penetration beyond the preceding Donchian-20 boundary, divided by ATR14",
            "spread": "Entry-attempt spread in symbol points",
            "rapid_stop_proxy": "Broker stop-loss exit no more than 24 hours after entry",
        },
        "reference_overall": overall,
        "formal_cell_results_from_v14": formal_cells,
        "breakdowns": {
            "direction": breakdown(reference, "direction"),
            "exit_reason": breakdown(reference, "exit_reason"),
            "outcome": breakdown(reference, "outcome"),
            "holding_band": breakdown(reference, "holding_band"),
            "entry_hour": breakdown(reference, "entry_hour"),
            "entry_weekday": breakdown(reference, "entry_weekday"),
            "volatility_regime": breakdown(reference, "volatility_regime"),
            "trend_side": breakdown(reference, "trend_side"),
            "ema_slope_direction": breakdown(reference, "ema_slope_direction"),
            "trend_alignment": breakdown(reference, "trend_alignment"),
            "ema_distance_band": breakdown(reference, "ema_distance_band"),
            "breakout_distance_band": breakdown(reference, "breakout_distance_band"),
            "spread_band": breakdown(reference, "spread_band"),
            "development_segment": breakdown([row for row in reference if row["dataset"] == "DEVELOPMENT"], "segment"),
            "validation_segment": breakdown([row for row in reference if row["dataset"] == "VALIDATION"], "segment"),
            "oos_segment": breakdown([row for row in reference if row["dataset"] == "OUT_OF_SAMPLE"], "segment"),
            "dataset": breakdown(reference, "dataset"),
            "cost_profile_all_layers": breakdown(rows, "cost_profile"),
            "execution_layer_all_costs": breakdown(rows, "execution_layer"),
        },
        "structural_conclusion": {
            "main_failure_mechanism": "UNCONFIRMED_DONCHIAN_BREAKOUTS_FREQUENTLY_REVERSED_TO_FULL_INITIAL_STOP_BEFORE_TREND_FOLLOW_THROUGH",
            "evidence": {
                "reference_trades": len(reference),
                "stop_loss_exits": stops["trades"],
                "stop_loss_share_percent": stops["trades"] / len(reference) * 100.0,
                "stop_loss_expectancy_R": stops["expectancy_R"],
                "rapid_stop_exits_within_24h": rapid_stops,
                "rapid_stop_share_of_all_trades_percent": rapid_stops / len(reference) * 100.0,
                "rapid_stop_share_of_stop_exits_percent": rapid_stops / stops["trades"] * 100.0,
                "overall_win_rate_percent": aggregate(reference)["win_rate_percent"],
                "overall_payoff_ratio_R": aggregate(reference)["payoff_ratio_R"],
                "overall_expectancy_R": aggregate(reference)["expectancy_R"],
                "breakeven_win_rate_at_observed_R_payoff_percent": breakeven_win_rate,
                "win_rate_shortfall_percentage_points": overall["win_rate_percent"] - breakeven_win_rate,
                "long_expectancy_R": by_direction["LONG"]["expectancy_R"],
                "short_expectancy_R": by_direction["SHORT"]["expectancy_R"],
                "ema_distance_ge_2_atr_trades": by_ema_distance["GE_2_ATR"]["trades"],
                "ema_distance_ge_2_atr_expectancy_R": by_ema_distance["GE_2_ATR"]["expectancy_R"],
            },
            "interpretation": "The 20-bar close breakout plus price-side EMA filter admitted too many one-bar breakout events without persistence confirmation. The resulting full-stop frequency overwhelmed the positive tail from Donchian exits in both directions and all datasets.",
            "causal_limits": "The ledger proves the loss-path pattern and its persistence; it does not prove an unobserved counterfactual profit for any proposed filter. V2 remains untested.",
        },
        "alternative_hypotheses": [
            {
                "hypothesis": "DONCHIAN_EXIT_RETURNED_TOO_MUCH_OPEN_PROFIT",
                "assessment": "CONTRADICTED_AS_PRIMARY_CAUSE",
                "evidence": "Long and short Donchian-exit subsets were positive at +0.815R and +0.381R expectancy respectively; together they generated positive adjusted net before the stop-loss subset overwhelmed them."
            },
            {
                "hypothesis": "COST_OR_200MS_DELAY_CREATED_THE_LOSS",
                "assessment": "CONTRADICTED_AS_PRIMARY_CAUSE",
                "evidence": "Every Normal/native dataset was already negative; the fixed-delay layer preserved the same outcome and had zero OOS net difference."
            },
            {
                "hypothesis": "LONG_SHORT_ASYMMETRY",
                "assessment": "SUPPORTED_AS_SECONDARY_AMPLIFIER",
                "evidence": "Short expectancy was -0.408R versus long expectancy -0.038R, but both directions remained negative and both contained rapid stops."
            },
            {
                "hypothesis": "ENTRY_ALREADY_OVEREXTENDED_FROM_EMA200",
                "assessment": "SUPPORTED_AS_SECONDARY_AMPLIFIER",
                "evidence": "73 of 94 entries were at least 2 ATR from EMA200 and returned -0.271R expectancy. This supports a bounded extension guard but does not prove its counterfactual profitability."
            },
            {
                "hypothesis": "ONE_SPECIFIC_VOLATILITY_OR_SESSION_REGIME",
                "assessment": "INSUFFICIENT_FOR_SELECTIVE_FILTERING",
                "evidence": "Known low, normal and high ATR regimes were all negative; hour and weekday cells were small and heterogeneous. No session exclusion is justified."
            },
            {
                "hypothesis": "EMA200_SLOPE_FILTER_WOULD_FIX_V1",
                "assessment": "NOT_SUPPORTED",
                "evidence": "Trades aligned with the descriptive 24-evaluation EMA slope were worse than counter-slope trades. V2 therefore does not add a slope-direction filter."
            },
            {
                "hypothesis": "TWO_ATR_STOP_WIDTH_WAS_INCORRECT",
                "assessment": "NOT_PROVEN",
                "evidence": "The ledger identifies rapid full-stop outcomes but contains no valid counterfactual for another stop multiple. The frozen 2 ATR stop is retained to avoid stop-width optimization."
            }
        ]
    }

    with (V15 / "trend-breakout-v1-failure-analysis.json").open("w", encoding="utf-8") as handle:
        json.dump(report, handle, indent=2, sort_keys=False, allow_nan=False)
        handle.write("\n")
    write_attribution(rows, reference, V15 / "v1-loss-attribution.csv")


if __name__ == "__main__":
    main()
