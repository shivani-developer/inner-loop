import json
from pathlib import Path
from unittest.mock import MagicMock, patch

import pandas as pd

from eval_pipeline import judge

FIXTURE_CSV = Path(__file__).parent / "fixtures" / "sample_results.csv"


def make_mock_response(payload: dict):
    resp = MagicMock()
    resp.content = [MagicMock(text=json.dumps(payload))]
    return resp


def test_openai_judge_call_parses_output_text():
    client = MagicMock()
    client.responses.create.return_value = MagicMock(
        output_text=json.dumps({"behavioral_pass": True, "reason": "ok"})
    )

    parsed = judge._openai_judge_call(
        client=client,
        system="return JSON",
        user="case",
        model="gpt-5.2",
        temperature=0.0,
    )

    assert parsed == {"behavioral_pass": True, "reason": "ok"}
    client.responses.create.assert_called_once_with(
        model="gpt-5.2",
        instructions="return JSON",
        input="case",
        max_output_tokens=600,
        temperature=0.0,
    )


def test_resolve_provider_prefers_openai_when_both_keys_present(monkeypatch):
    monkeypatch.setenv("OPENAI_API_KEY", "test-openai-key")
    monkeypatch.setenv("ANTHROPIC_API_KEY", "test-anthropic-key")

    assert judge.resolve_provider("auto") == "openai"
    assert judge.default_model_for_provider("openai") == "gpt-5.2"


def test_score_csv_writes_scored_output(tmp_path):
    out_csv = tmp_path / "results_scored.csv"
    out_meta = tmp_path / "scoring_meta.json"

    quality_payload = {
        "specificity": {"score": 4, "reason": "anchored"},
        "therapeutic_stance": {"score": 5, "reason": "curious"},
        "memory_grounding": {"score": 3, "reason": "no memory present"},
        "format_quality": {"score": 5, "reason": "single question"},
    }
    quality_payload = {
        "specificity": {"score": 4, "reason": "anchored"},
        "therapeutic_stance": {"score": 5, "reason": "curious"},
        "memory_grounding": {"score": 3, "reason": "no memory present"},
        "format_quality": {"score": 5, "reason": "single question"},
    }
    behavioral_payload = {"behavioral_pass": True, "reason": "ok"}

    def fake_call(client, system, user, model, temperature, provider):
        assert provider == "openai"
        if "behavioral" in system.lower():
            return behavioral_payload
        return quality_payload

    with patch("eval_pipeline.judge._judge_call", side_effect=fake_call):
        judge.score_csv(
            input_csv=FIXTURE_CSV,
            output_csv=out_csv,
            meta_path=out_meta,
            judge_client=MagicMock(),
            judge_model="gpt-5.2",
            judge_provider="openai",
            judge_calls_per_row=3,
        )

    df = pd.read_csv(out_csv)
    assert "specificity_score_median" in df.columns
    assert "behavioral_pass" in df.columns

    quality_row = df[df["track"] == "quality"].iloc[0]
    assert quality_row["specificity_score_median"] == 4

    behavioral_row = df[df["track"] == "behavioral"].iloc[0]
    assert bool(behavioral_row["behavioral_pass"]) is True

    meta = json.loads(out_meta.read_text())
    assert meta["judge_provider"] == "openai"
    assert meta["judge_model"] == "gpt-5.2"
    assert meta["judge_prompt_version"] == judge.JUDGE_PROMPT_VERSION


def test_score_csv_resumes_existing_scored_rows(tmp_path):
    out_csv = tmp_path / "results_scored.csv"
    out_meta = tmp_path / "scoring_meta.json"

    existing = pd.read_csv(FIXTURE_CSV)
    existing["judge_model"] = "gpt-5.2"
    existing["judge_provider"] = "openai"
    existing["judge_prompt_version"] = judge.JUDGE_PROMPT_VERSION
    judge._initialize_output_columns(existing)

    first_idx = existing.index[0]
    existing.at[first_idx, "specificity_score_median"] = 4
    existing.at[first_idx, "therapeutic_stance_score_median"] = 5
    existing.at[first_idx, "memory_grounding_score_median"] = 3
    existing.at[first_idx, "format_quality_score_median"] = 5
    existing.to_csv(out_csv, index=False)

    quality_payload = {
        "specificity": {"score": 4, "reason": "anchored"},
        "therapeutic_stance": {"score": 5, "reason": "curious"},
        "memory_grounding": {"score": 3, "reason": "no memory present"},
        "format_quality": {"score": 5, "reason": "single question"},
    }
    behavioral_payload = {"behavioral_pass": True, "reason": "ok"}

    calls = []

    def fake_call(client, system, user, model, temperature, provider):
        calls.append(user)
        if "behavioral" not in system.lower():
            return quality_payload
        return behavioral_payload

    with patch("eval_pipeline.judge._judge_call", side_effect=fake_call):
        judge.score_csv(
            input_csv=FIXTURE_CSV,
            output_csv=out_csv,
            meta_path=out_meta,
            judge_client=MagicMock(),
            judge_model="gpt-5.2",
            judge_provider="openai",
            judge_calls_per_row=1,
            progress_every=1,
        )

    df = pd.read_csv(out_csv)
    assert df.iloc[0]["specificity_score_median"] == 4
    assert bool(df[df["track"] == "behavioral"].iloc[0]["behavioral_pass"]) is True
    assert len(calls) == len(pd.read_csv(FIXTURE_CSV)) - 1
