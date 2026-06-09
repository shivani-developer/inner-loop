import json

from eval_pipeline.calibration import check


def test_compute_rmse_per_dimension():
    judge_scores = {
        "cal.a": {"specificity": 4, "therapeutic_stance": 5},
        "cal.b": {"specificity": 2, "therapeutic_stance": 4},
    }
    human_scores = {
        "cal.a": {"specificity": 5, "therapeutic_stance": 5},
        "cal.b": {"specificity": 3, "therapeutic_stance": 4},
    }
    rmse = check.compute_rmse(judge_scores, human_scores)
    assert round(rmse["specificity"], 3) == 1.000
    assert round(rmse["therapeutic_stance"], 3) == 0.000


def test_validate_judge_raises_when_drift_exceeds_threshold():
    judge = {"x": {"a": 1}}
    human = {"x": {"a": 5}}
    try:
        check.validate_judge_drift(judge, human, threshold=0.5)
    except check.JudgeDriftError:
        return
    raise AssertionError("expected JudgeDriftError")


def test_calibration_run_uses_median_scores(monkeypatch, tmp_path):
    calibration = [
        {
            "case_id": "cal.test",
            "task": "sessionTitle",
            "judge_track": "quality",
            "input": "user: I kept waiting for someone to notice.",
            "context": "(none)",
            "candidate_response": "Waiting to Be Seen",
        }
    ]
    human = [
        {
            "case_id": "cal.test",
            "scores": {"specificity": 4, "compression_quality": 5},
        }
    ]
    monkeypatch.setattr(check, "CALIBRATION_DIR", tmp_path)
    (tmp_path / "calibration_set.json").write_text(json.dumps(calibration))
    (tmp_path / "human_scores.json").write_text(json.dumps(human))

    calls = [
        {
            "specificity": {"score": 2, "reason": "low"},
            "compression_quality": {"score": 5, "reason": "ok"},
        },
        {
            "specificity": {"score": 4, "reason": "mid"},
            "compression_quality": {"score": 5, "reason": "ok"},
        },
        {
            "specificity": {"score": 5, "reason": "high"},
            "compression_quality": {"score": 5, "reason": "ok"},
        },
    ]

    def fake_judge_call(client, system, user, model, temperature, provider):
        return calls.pop(0)

    monkeypatch.setattr("eval_pipeline.judge._judge_call", fake_judge_call)

    result = check.run(
        client=object(),
        model="test-model",
        provider="openai",
        calls_per_case=3,
    )

    assert result["judge_scores"]["cal.test"] == {
        "specificity": 4,
        "compression_quality": 5,
    }
