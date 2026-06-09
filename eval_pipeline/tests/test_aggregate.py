import pandas as pd

from eval_pipeline import aggregate


def test_weighted_mean_by_tier():
    df = pd.DataFrame(
        {
            "tier": ["easy", "easy", "hard", "hard"],
            "score": [5, 5, 3, 3],
        }
    )
    weights = {"easy": 1.0, "medium": 1.0, "hard": 2.0}
    mean = aggregate.weighted_mean(
        df,
        value_col="score",
        weight_col="tier",
        weights=weights,
    )
    assert round(mean, 3) == 3.667


def test_bootstrap_ci_is_symmetric_around_mean():
    df = pd.DataFrame({"score": [4, 4, 4, 4, 4]})
    lo, hi = aggregate.bootstrap_ci(df["score"], n_resamples=200, seed=42)
    assert lo == 4.0 and hi == 4.0


def test_per_model_per_task_summary():
    df = pd.DataFrame(
        {
            "model_id": ["A", "A", "B", "B"],
            "task": ["socraticResponse"] * 4,
            "tier": ["medium"] * 4,
            "specificity_score_median": [4, 5, 3, 2],
        }
    )
    summary = aggregate.per_model_quality(df, dimension="specificity_score_median")
    a_row = summary[
        (summary["model_id"] == "A") & (summary["task"] == "socraticResponse")
    ].iloc[0]
    assert a_row["mean"] == 4.5
