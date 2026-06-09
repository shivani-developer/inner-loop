"""Aggregation helpers: weighted means, bootstrap CIs, per-model summaries."""
from __future__ import annotations

import numpy as np
import pandas as pd

DEFAULT_TIER_WEIGHTS = {"easy": 1.0, "medium": 1.5, "hard": 2.0}


def weighted_mean(
    df: pd.DataFrame,
    value_col: str,
    weight_col: str,
    weights: dict,
) -> float:
    w = df[weight_col].map(weights).astype(float)
    v = df[value_col].astype(float)
    if w.sum() == 0:
        return float("nan")
    return float((v * w).sum() / w.sum())


def bootstrap_ci(
    series: pd.Series,
    n_resamples: int = 2000,
    ci: float = 0.95,
    seed: int = 0,
) -> tuple[float, float]:
    arr = series.dropna().to_numpy(dtype=float)
    if len(arr) == 0:
        return float("nan"), float("nan")
    rng = np.random.default_rng(seed)
    means = np.array(
        [rng.choice(arr, size=len(arr), replace=True).mean() for _ in range(n_resamples)]
    )
    lo, hi = np.quantile(means, [(1 - ci) / 2, 1 - (1 - ci) / 2])
    return float(lo), float(hi)


def per_model_quality(
    df: pd.DataFrame,
    dimension: str,
    tier_weights: dict = DEFAULT_TIER_WEIGHTS,
) -> pd.DataFrame:
    """One row per (model_id, task): mean dimension score with bootstrap CI."""
    quality_df = df[df["track"] == "quality"] if "track" in df.columns else df
    rows = []
    for (model_id, task), group in quality_df.groupby(["model_id", "task"]):
        if dimension not in group.columns or group[dimension].dropna().empty:
            continue
        mean = weighted_mean(
            group,
            value_col=dimension,
            weight_col="tier",
            weights=tier_weights,
        )
        lo, hi = bootstrap_ci(group[dimension])
        rows.append(
            {
                "model_id": model_id,
                "task": task,
                "dimension": dimension,
                "mean": mean,
                "ci_lo": lo,
                "ci_hi": hi,
                "n": len(group),
            }
        )
    return pd.DataFrame(rows)


def behavioral_violation_rate(df: pd.DataFrame) -> pd.DataFrame:
    if "track" not in df.columns:
        return pd.DataFrame()
    behavioral = df[df["track"] == "behavioral"]
    if behavioral.empty:
        return pd.DataFrame()

    rows = []
    for model_id, group in behavioral.groupby("model_id"):
        total = len(group)
        violations = int((group["behavioral_pass"] == False).sum())  # noqa: E712
        rows.append(
            {
                "model_id": model_id,
                "total": total,
                "violations": violations,
                "rate": violations / total,
            }
        )
    return pd.DataFrame(rows)
