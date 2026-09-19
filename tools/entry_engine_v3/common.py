from __future__ import annotations

import math
from datetime import datetime, timezone
from dataclasses import dataclass
from typing import Any, Iterable

import numpy as np


HORIZON_SECONDS = 4 * 60 * 60
WAIT_SECONDS = 15 * 60
EPISODE_COOLDOWN_SECONDS = HORIZON_SECONDS


def utc_seconds(value: Any) -> int:
    """Parse collector UTC fields without applying the workstation timezone."""
    text = str(value or "").strip()
    if not text:
        raise ValueError("empty UTC timestamp")
    if text.isdigit():
        raw = int(text)
        return raw // 1000 if raw > 10_000_000_000 else raw
    return int(datetime.strptime(text, "%Y.%m.%d %H:%M:%S").replace(tzinfo=timezone.utc).timestamp())


def number(value: Any, default: float = 0.0) -> float:
    try:
        result = float(value)
        return result if math.isfinite(result) else default
    except (TypeError, ValueError):
        return default


def parse_state(value: str) -> dict[str, float]:
    result: dict[str, float] = {}
    for item in (value or "").split(";"):
        if "=" not in item:
            continue
        key, raw = item.split("=", 1)
        if raw.lower() in ("true", "false"):
            result[key] = 1.0 if raw.lower() == "true" else 0.0
        else:
            result[key] = number(raw)
    return result


def max_drawdown(values: Iterable[float]) -> float:
    equity = peak = drawdown = 0.0
    for value in values:
        equity += value
        peak = max(peak, equity)
        drawdown = max(drawdown, peak - equity)
    return drawdown


@dataclass
class RidgeLogistic:
    means: np.ndarray
    scales: np.ndarray
    weights: np.ndarray
    l2: float

    def predict(self, x: np.ndarray) -> np.ndarray:
        z = (x - self.means) / self.scales
        logits = np.clip(self.weights[0] + z @ self.weights[1:], -35, 35)
        return 1.0 / (1.0 + np.exp(-logits))

    def payload(self, names: list[str]) -> dict[str, Any]:
        return {
            "kind": "RIDGE_LOGISTIC",
            "l2": self.l2,
            "intercept": float(self.weights[0]),
            "means": dict(zip(names, self.means.tolist())),
            "scales": dict(zip(names, self.scales.tolist())),
            "coefficients": dict(zip(names, self.weights[1:].tolist())),
        }


def fit_logistic(x: np.ndarray, y: np.ndarray, sample_weight: np.ndarray, l2: float) -> RidgeLogistic:
    means = x.mean(axis=0)
    scales = x.std(axis=0)
    scales[scales < 1e-9] = 1.0
    z = (x - means) / scales
    design = np.column_stack([np.ones(len(z)), z])
    w = np.zeros(design.shape[1])
    for _ in range(80):
        p = 1.0 / (1.0 + np.exp(-np.clip(design @ w, -35, 35)))
        gradient = design.T @ (sample_weight * (p - y))
        gradient[1:] += l2 * w[1:]
        curvature = sample_weight * p * (1.0 - p)
        hessian = design.T @ (design * curvature[:, None])
        hessian[1:, 1:] += l2 * np.eye(len(w) - 1)
        step = np.linalg.solve(hessian + 1e-8 * np.eye(len(w)), gradient)
        w -= step
        if float(np.max(np.abs(step))) < 1e-8:
            break
    return RidgeLogistic(means, scales, w, l2)


@dataclass
class RidgeRegression:
    means: np.ndarray
    scales: np.ndarray
    weights: np.ndarray
    l2: float

    def predict(self, x: np.ndarray) -> np.ndarray:
        z = (x - self.means) / self.scales
        return self.weights[0] + z @ self.weights[1:]

    def payload(self, names: list[str]) -> dict[str, Any]:
        return {
            "kind": "RIDGE_REGRESSION",
            "l2": self.l2,
            "intercept": float(self.weights[0]),
            "means": dict(zip(names, self.means.tolist())),
            "scales": dict(zip(names, self.scales.tolist())),
            "coefficients": dict(zip(names, self.weights[1:].tolist())),
        }


def fit_regression(x: np.ndarray, y: np.ndarray, sample_weight: np.ndarray, l2: float) -> RidgeRegression:
    means = x.mean(axis=0)
    scales = x.std(axis=0)
    scales[scales < 1e-9] = 1.0
    z = (x - means) / scales
    design = np.column_stack([np.ones(len(z)), z])
    weighted = design * sample_weight[:, None]
    penalty = np.eye(design.shape[1]) * l2
    penalty[0, 0] = 0.0
    weights = np.linalg.solve(design.T @ weighted + penalty, design.T @ (sample_weight * y))
    return RidgeRegression(means, scales, weights, l2)
