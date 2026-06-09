"""Stage 3: aggregate per-model scored CSVs into tables and a Pareto plot."""
from __future__ import annotations

import argparse
import sys
from pathlib import Path

import matplotlib.pyplot as plt
import pandas as pd

from eval_pipeline import aggregate

QUALITY_DIMENSIONS = {
    "socraticResponse": [
        "specificity_score_median",
        "therapeutic_stance_score_median",
        "memory_grounding_score_median",
        "format_quality_score_median",
    ],
    "openingPrompt": [
        "specificity_score_median",
        "invitingness_score_median",
        "memory_use_score_median",
    ],
    "sessionSummary": [
        "factual_accuracy_score_median",
        "emotional_arc_score_median",
        "compression_quality_score_median",
    ],
    "sessionTitle": ["specificity_score_median", "compression_quality_score_median"],
    "profileCompression": [
        "factual_accuracy_score_median",
        "compression_quality_score_median",
        "usefulness_score_median",
    ],
}


def load_scored(paths: list[Path]) -> pd.DataFrame:
    frames = [pd.read_csv(path) for path in paths]
    return pd.concat(frames, ignore_index=True)


def overall_quality_score(df: pd.DataFrame) -> pd.DataFrame:
    """Average all per-dimension scores into one number per model for Pareto y-axis."""
    rows = []
    quality = df[df["track"] == "quality"] if "track" in df.columns else df
    for model_id, group in quality.groupby("model_id"):
        score_cols = [col for col in group.columns if col.endswith("_score_median")]
        all_scores = group[score_cols].stack().dropna().astype(float)
        rows.append(
            {
                "model_id": model_id,
                "overall_quality": all_scores.mean(),
                "n": len(all_scores),
            }
        )
    return pd.DataFrame(rows)


def write_tables(df: pd.DataFrame, out_dir: Path) -> None:
    out_dir.mkdir(parents=True, exist_ok=True)

    overall = overall_quality_score(df)
    overall.to_csv(out_dir / "overall_quality.csv", index=False)

    behavioral = aggregate.behavioral_violation_rate(df)
    if not behavioral.empty:
        behavioral.to_csv(out_dir / "behavioral_violations.csv", index=False)

    per_task_rows = []
    for task, dims in QUALITY_DIMENSIONS.items():
        task_df = df[df["task"] == task]
        for dim in dims:
            if dim not in task_df.columns:
                continue
            summary = aggregate.per_model_quality(task_df, dimension=dim)
            if not summary.empty:
                per_task_rows.append(summary)
    if per_task_rows:
        pd.concat(per_task_rows, ignore_index=True).to_csv(
            out_dir / "per_task_dimensions.csv",
            index=False,
        )


def write_pareto_plot(df: pd.DataFrame, out_dir: Path) -> None:
    out_dir.mkdir(parents=True, exist_ok=True)
    if "total_latency_ms" not in df.columns:
        return

    overall = overall_quality_score(df)
    latency = (
        df.groupby("model_id")["total_latency_ms"]
        .median()
        .reset_index()
        .rename(columns={"total_latency_ms": "median_latency_ms"})
    )
    merged = overall.merge(latency, on="model_id")
    if merged.empty:
        return

    fig, ax = plt.subplots(figsize=(7, 5))
    ax.scatter(merged["median_latency_ms"], merged["overall_quality"], s=80)
    for _, row in merged.iterrows():
        ax.annotate(
            row["model_id"],
            (row["median_latency_ms"], row["overall_quality"]),
            xytext=(6, 4),
            textcoords="offset points",
        )
    ax.set_xlabel("Median total latency (ms)")
    ax.set_ylabel("Overall judge quality (1-5)")
    ax.set_title("Quality vs Latency Pareto Frontier")
    ax.grid(True, alpha=0.3)
    fig.tight_layout()
    fig.savefig(out_dir / "pareto.png", dpi=150)
    plt.close(fig)


def write_divergence_appendix(df: pd.DataFrame, out_dir: Path, top_n: int = 10) -> None:
    """Cases where two models differ by >= 1 score point on any dimension."""
    out_dir.mkdir(parents=True, exist_ok=True)
    score_cols = [col for col in df.columns if col.endswith("_score_median")]
    if not score_cols or df["model_id"].nunique() < 2:
        return

    rows = []
    for col in score_cols:
        pivot = df.pivot_table(index="id", columns="model_id", values=col, aggfunc="mean")
        if pivot.shape[1] < 2:
            continue
        pivot["spread"] = pivot.max(axis=1) - pivot.min(axis=1)
        top = pivot.sort_values("spread", ascending=False).head(top_n)
        for case_id, vals in top.iterrows():
            if vals["spread"] < 1:
                continue
            case_rows = df[df["id"] == case_id]
            user_input = case_rows["input"].iloc[0] if not case_rows.empty else ""
            for model_id in vals.index:
                if model_id == "spread":
                    continue
                model_rows = case_rows[case_rows["model_id"] == model_id]
                if model_rows.empty:
                    continue
                rows.append(
                    {
                        "dimension": col,
                        "case_id": case_id,
                        "spread": vals["spread"],
                        "model_id": model_id,
                        "score": vals[model_id],
                        "input": user_input,
                        "output": model_rows["output"].iloc[0],
                    }
                )

    if rows:
        pd.DataFrame(rows).to_csv(out_dir / "divergence_appendix.csv", index=False)


def main(argv=None) -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("scored_csvs", nargs="+", type=Path)
    parser.add_argument("--out", type=Path, default=Path("eval_pipeline/reports/latest"))
    args = parser.parse_args(argv)

    df = load_scored(args.scored_csvs)
    write_tables(df, args.out)
    write_pareto_plot(df, args.out)
    write_divergence_appendix(df, args.out)
    print(f"Wrote report to {args.out}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
