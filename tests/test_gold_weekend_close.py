"""Meaningful boundary checks for the orderless weekend-close analysis."""

import importlib.util
import math
from datetime import datetime, timedelta
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "tools/analyze_gold_weekend_close.py"
SPEC = importlib.util.spec_from_file_location("gold_weekend_close", SOURCE)
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


def bar(time, opening, high, low, closing, spread=0.1):
    return {"time": time, "open": opening, "high": high, "low": low, "close": closing,
            "spread": spread, "ticks": 2}


def test_same_bar_boundary_is_ambiguous():
    t = datetime(2026, 9, 28, 1)
    bars = [bar(t, 100, 111, 89, 100)]
    assert MODULE.first_barrier(bars, 0, 0, "BUY", 100) == "AMBIGUOUS_SAME_BAR"
    assert MODULE.first_barrier(bars, 0, 0, "SELL", 100) == "AMBIGUOUS_SAME_BAR"


def test_weekend_direction_uses_only_friday_close_and_reopen_cost():
    friday = datetime(2026, 9, 25, 23, 58)
    monday = datetime(2026, 9, 28, 1)
    bars = [bar(friday, 99, 100, 99, 100), bar(friday + timedelta(minutes=1), 100, 102, 100, 101),
            bar(monday, 105, 105, 104, 105)]
    bars += [bar(monday + timedelta(minutes=i), 105, 106, 104, 105) for i in range(1, 242)]
    assert MODULE.endpoint(bars, [item["time"] for item in bars], 2, 240) is not None
    assert MODULE.direction(bars[1]["open"], bars[1]["close"]) == "BUY"
    assert bars[2]["open"] - bars[1]["close"] == 4
    assert math.isclose(bars[2]["close"] - (bars[2]["open"] + bars[2]["spread"]), -0.1)


def test_no_invented_endpoint_across_missing_market_data():
    monday = datetime(2026, 9, 28, 1)
    bars = [bar(monday, 100, 100, 100, 100), bar(monday + timedelta(hours=6), 102, 102, 102, 102)]
    assert MODULE.endpoint(bars, [item["time"] for item in bars], 0, 240) is None


def test_research_export_contains_no_order_api():
    source = (ROOT / "tools/mql/SolTradeGoldWeekendReadOnly.mq5").read_text()
    for token in ("OrderSend(", "OrderSendAsync(", "CTrade", "PositionClose(", ".Buy(", ".Sell("):
        assert token not in source
