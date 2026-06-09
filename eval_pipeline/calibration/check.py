"""Judge calibration: re-score the calibration set and compare to human ground truth."""
from __future__ import annotations

import argparse
import json
import math
import sys
from pathlib import Path
from typing import Any

import pandas as pd

from eval_pipeline import judge

CALIBRATION_DIR = Path(__file__).parent
RMSE_THRESHOLD = 0.5


class JudgeDriftError(RuntimeError):
    pass


def compute_rmse(judge_scores: dict, human_scores: dict) -> dict:
    """Per-dimension RMSE across case ids that appear in both maps."""
    dims_to_errors: dict[str, list[float]] = {}
    for case_id, human in human_scores.items():
        if case_id not in judge_scores:
            continue
        for dim, human_val in human.items():
            if isinstance(human_val, bool):
                judge_val = 1 if judge_scores[case_id].get(dim) else 0
                human_val_num = 1 if human_val else 0
            else:
                judge_val = float(judge_scores[case_id].get(dim, 0))
                human_val_num = float(human_val)
            dims_to_errors.setdefault(dim, []).append((judge_val - human_val_num) ** 2)

    return {
        dim: math.sqrt(sum(errors) / len(errors))
        for dim, errors in dims_to_errors.items()
    }


def validate_judge_drift(
    judge_scores: dict,
    human_scores: dict,
    threshold: float = RMSE_THRESHOLD,
) -> None:
    rmse = compute_rmse(judge_scores, human_scores)
    bad = {dim: err for dim, err in rmse.items() if err > threshold}
    if bad:
        raise JudgeDriftError(f"RMSE exceeds {threshold} on: {bad}")


def run(
    client: Any,
    model: str = judge.DEFAULT_ANTHROPIC_MODEL,
    provider: str = "anthropic",
    calls_per_case: int = 3,
) -> dict:
    calibration_set = json.loads((CALIBRATION_DIR / "calibration_set.json").read_text())
    human = {
        entry["case_id"]: entry["scores"]
        for entry in json.loads((CALIBRATION_DIR / "human_scores.json").read_text())
    }

    judge_scores: dict = {}
    for entry in calibration_set:
        task = entry["task"]
        track = entry["judge_track"]
        rubric = judge.load_rubric(task, track)
        row = pd.Series(
            {
                "task": task,
                "context": entry.get("context", ""),
                "input": entry["input"],
                "output": entry["candidate_response"],
                "expected_behavior": entry.get("expected_behavior", ""),
                "reference_response": entry.get("reference_response", ""),
            }
        )
        user_msg = judge.build_user_message(row)

        parsed_calls = [
            judge._judge_call(
                client,
                rubric,
                user_msg,
                model,
                temperature=0.0,
                provider=provider,
            )
            for _ in range(calls_per_case)
        ]
        if track == "behavioral":
            decision = judge._majority_behavioral(parsed_calls)
            judge_scores[entry["case_id"]] = {
                "behavioral_pass": decision["behavioral_pass"]
            }
        else:
            decision = judge._median_quality_scores(
                parsed_calls,
                judge.QUALITY_DIMENSIONS[task],
            )
            judge_scores[entry["case_id"]] = {
                dim: int(decision["medians"][dim])
                for dim in judge.QUALITY_DIMENSIONS[task]
            }

    rmse = compute_rmse(judge_scores, human)
    return {"rmse": rmse, "judge_scores": judge_scores, "human_scores": human}


def main(argv=None) -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--provider",
        choices=["auto", *sorted(judge.SUPPORTED_PROVIDERS)],
        default=judge.DEFAULT_PROVIDER,
    )
    parser.add_argument("--model")
    parser.add_argument("--calls", type=int, default=3)
    parser.add_argument("--threshold", type=float, default=RMSE_THRESHOLD)
    args = parser.parse_args(argv)

    provider = judge.resolve_provider(args.provider)
    model = args.model or judge.default_model_for_provider(provider)
    client = judge.make_judge_client(provider)
    result = run(client, model=model, provider=provider, calls_per_case=args.calls)
    print(json.dumps(result["rmse"], indent=2))
    try:
        validate_judge_drift(
            result["judge_scores"],
            result["human_scores"],
            threshold=args.threshold,
        )
    except JudgeDriftError as exc:
        print(f"FAIL: {exc}", file=sys.stderr)
        return 1
    print("OK: judge agrees with human within threshold")
    return 0


if __name__ == "__main__":
    sys.exit(main())
