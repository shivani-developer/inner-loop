"""LLM-judge scoring stage for the journaling-companion eval pipeline."""
from __future__ import annotations

import argparse
import json
import os
import statistics
import sys
import time
from pathlib import Path

import pandas as pd
from anthropic import Anthropic
from openai import OpenAI

JUDGE_PROMPT_VERSION = "judge-v2"
DEFAULT_PROVIDER = "auto"
DEFAULT_ANTHROPIC_MODEL = "claude-sonnet-4-6"
DEFAULT_OPENAI_MODEL = "gpt-5.2"
DEFAULT_MODEL = DEFAULT_ANTHROPIC_MODEL
SUPPORTED_PROVIDERS = {"anthropic", "openai"}

RUBRIC_DIR = Path(__file__).parent / "rubrics"

QUALITY_DIMENSIONS = {
    "socraticResponse": [
        "specificity",
        "therapeutic_stance",
        "memory_grounding",
        "format_quality",
    ],
    "openingPrompt": ["specificity", "invitingness", "memory_use"],
    "sessionSummary": ["factual_accuracy", "emotional_arc", "compression_quality"],
    "sessionTitle": ["specificity", "compression_quality"],
    "profileCompression": ["factual_accuracy", "compression_quality", "usefulness"],
}

RUBRIC_FILES = {
    "socraticResponse": "socratic.md",
    "openingPrompt": "opening.md",
    "sessionSummary": "summary.md",
    "sessionTitle": "title.md",
    "profileCompression": "profile.md",
}


def load_rubric(task: str, track: str) -> str:
    if track == "behavioral":
        return (RUBRIC_DIR / "behavioral.md").read_text()
    return (RUBRIC_DIR / RUBRIC_FILES[task]).read_text()


def build_user_message(row: pd.Series) -> str:
    parts = [
        f"### Task\n{row['task']}",
        f"### Supplied context\n{row.get('context', '') or '(none)'}",
        f"### User input\n{row.get('input', '')}",
        f"### Assistant response\n{row.get('output', '')}",
        f"### Expected behavior\n{row.get('expected_behavior', '') or '(none)'}",
    ]
    reference = row.get("reference_response")
    if isinstance(reference, str) and reference.strip():
        parts.append(f"### Reference example of a good response\n{reference}")
    return "\n\n".join(parts)


def _strip_json_fence(raw: str) -> str:
    raw = raw.strip()
    if not raw.startswith("```"):
        return raw

    lines = raw.splitlines()
    if lines and lines[0].startswith("```"):
        lines = lines[1:]
    if lines and lines[-1].strip() == "```":
        lines = lines[:-1]
    return "\n".join(lines).strip()


def resolve_provider(provider: str = DEFAULT_PROVIDER) -> str:
    if provider != "auto":
        if provider not in SUPPORTED_PROVIDERS:
            raise ValueError(f"Unsupported judge provider: {provider}")
        return provider

    if os.environ.get("OPENAI_API_KEY"):
        return "openai"
    if os.environ.get("ANTHROPIC_API_KEY"):
        return "anthropic"
    raise RuntimeError("Set OPENAI_API_KEY or ANTHROPIC_API_KEY, or pass --provider.")


def default_model_for_provider(provider: str) -> str:
    if provider == "openai":
        return DEFAULT_OPENAI_MODEL
    if provider == "anthropic":
        return DEFAULT_ANTHROPIC_MODEL
    raise ValueError(f"Unsupported judge provider: {provider}")


def make_judge_client(provider: str):
    if provider == "openai":
        return OpenAI(api_key=os.environ["OPENAI_API_KEY"])
    if provider == "anthropic":
        return Anthropic(api_key=os.environ["ANTHROPIC_API_KEY"])
    raise ValueError(f"Unsupported judge provider: {provider}")


def _anthropic_judge_call(
    client: Anthropic,
    system: str,
    user: str,
    model: str,
    temperature: float,
) -> dict:
    """Single judge call. Returns parsed JSON dict."""
    resp = client.messages.create(
        model=model,
        max_tokens=600,
        temperature=temperature,
        system=[
            {
                "type": "text",
                "text": system,
                "cache_control": {"type": "ephemeral"},
            }
        ],
        messages=[{"role": "user", "content": user}],
    )
    raw = _strip_json_fence(resp.content[0].text)
    return json.loads(raw)


def _openai_judge_call(
    client: OpenAI,
    system: str,
    user: str,
    model: str,
    temperature: float,
) -> dict:
    """Single OpenAI judge call. Returns parsed JSON dict."""
    resp = client.responses.create(
        model=model,
        instructions=system,
        input=user,
        max_output_tokens=600,
        temperature=temperature,
    )
    raw = _strip_json_fence(resp.output_text)
    return json.loads(raw)


def _judge_call(
    client,
    system: str,
    user: str,
    model: str,
    temperature: float,
    provider: str,
) -> dict:
    if provider == "openai":
        return _openai_judge_call(client, system, user, model, temperature)
    if provider == "anthropic":
        return _anthropic_judge_call(client, system, user, model, temperature)
    raise ValueError(f"Unsupported judge provider: {provider}")


def _median_quality_scores(parsed_calls: list[dict], dimensions: list[str]) -> dict:
    medians = {}
    reasons = {}
    raw_scores = {dim: [] for dim in dimensions}

    for parsed in parsed_calls:
        for dim in dimensions:
            raw_scores[dim].append(int(parsed[dim]["score"]))

    for dim in dimensions:
        median = statistics.median(raw_scores[dim])
        medians[dim] = median
        chosen_idx = raw_scores[dim].index(int(median))
        reasons[dim] = parsed_calls[chosen_idx][dim]["reason"]

    return {"medians": medians, "reasons": reasons, "raw": raw_scores}


def _majority_behavioral(parsed_calls: list[dict]) -> dict:
    passes = sum(1 for parsed in parsed_calls if parsed.get("behavioral_pass"))
    overall_pass = passes > len(parsed_calls) / 2
    chosen = next(
        (
            parsed
            for parsed in parsed_calls
            if bool(parsed.get("behavioral_pass")) == overall_pass
        ),
        parsed_calls[0],
    )
    return {"behavioral_pass": overall_pass, "reason": chosen.get("reason", "")}


def _initialize_output_columns(df: pd.DataFrame) -> None:
    for dim_set in QUALITY_DIMENSIONS.values():
        for dim in dim_set:
            for suffix in ("_score_median", "_score_reason", "_score_raw"):
                col = f"{dim}{suffix}"
                if col not in df.columns:
                    df[col] = None
                if suffix in ("_score_reason", "_score_raw"):
                    df[col] = df[col].astype("object")
    for col in ("behavioral_pass", "behavioral_reason"):
        if col not in df.columns:
            df[col] = None
        df[col] = df[col].astype("object")


def _row_is_scored(row: pd.Series) -> bool:
    track = row.get("track") or "quality"
    if track == "behavioral":
        return pd.notna(row.get("behavioral_pass"))

    task = row["task"]
    return all(
        pd.notna(row.get(f"{dim}_score_median"))
        for dim in QUALITY_DIMENSIONS[task]
    )


def _load_or_initialize_scored_frame(input_csv: Path, output_csv: Path) -> pd.DataFrame:
    input_df = pd.read_csv(input_csv)
    if output_csv.exists():
        output_df = pd.read_csv(output_csv)
        if len(output_df) == len(input_df) and list(input_df["id"]) == list(output_df["id"]):
            return output_df
    return input_df


def _write_progress(
    idx: int,
    total: int,
    row: pd.Series,
    started_at: float,
    skipped: bool = False,
) -> None:
    completed = idx + 1
    elapsed = time.monotonic() - started_at
    per_row = elapsed / completed if completed else 0
    remaining = max(0, total - completed)
    eta_seconds = int(per_row * remaining)
    status = "skip" if skipped else "score"
    print(
        f"[{status}] {completed}/{total} "
        f"case={row.get('id', '')} rep={row.get('repetition_index', '')} "
        f"task={row.get('task', '')} elapsed={int(elapsed)}s eta={eta_seconds}s",
        flush=True,
    )


def score_csv(
    input_csv: Path,
    output_csv: Path,
    meta_path: Path,
    judge_client,
    judge_model: str = DEFAULT_ANTHROPIC_MODEL,
    judge_provider: str = "anthropic",
    judge_calls_per_row: int = 3,
    judge_temperature: float = 0.2,
    progress_every: int = 5,
) -> None:
    df = _load_or_initialize_scored_frame(input_csv, output_csv)
    df["judge_model"] = judge_model
    df["judge_provider"] = judge_provider
    df["judge_prompt_version"] = JUDGE_PROMPT_VERSION
    _initialize_output_columns(df)

    started_at = time.monotonic()
    total = len(df)
    for idx, row in df.iterrows():
        if _row_is_scored(row):
            if idx % progress_every == 0:
                _write_progress(idx, total, row, started_at, skipped=True)
            continue

        track = row.get("track") or "quality"
        task = row["task"]
        system = load_rubric(task, track)
        user = build_user_message(row)

        parsed_calls = [
            _judge_call(
                judge_client,
                system,
                user,
                judge_model,
                judge_temperature,
                judge_provider,
            )
            for _ in range(judge_calls_per_row)
        ]

        if track == "behavioral":
            decision = _majority_behavioral(parsed_calls)
            df.at[idx, "behavioral_pass"] = decision["behavioral_pass"]
            df.at[idx, "behavioral_reason"] = decision["reason"]
        else:
            decision = _median_quality_scores(parsed_calls, QUALITY_DIMENSIONS[task])
            for dim in QUALITY_DIMENSIONS[task]:
                df.at[idx, f"{dim}_score_median"] = decision["medians"][dim]
                df.at[idx, f"{dim}_score_reason"] = decision["reasons"][dim]
                df.at[idx, f"{dim}_score_raw"] = json.dumps(decision["raw"][dim])

        df.to_csv(output_csv, index=False)
        if idx % progress_every == 0 or idx == total - 1:
            _write_progress(idx, total, row, started_at)

    df.to_csv(output_csv, index=False)
    meta = {
        "judge_provider": judge_provider,
        "judge_model": judge_model,
        "judge_prompt_version": JUDGE_PROMPT_VERSION,
        "judge_calls_per_row": judge_calls_per_row,
        "judge_temperature": judge_temperature,
        "input_csv": str(input_csv),
        "output_csv": str(output_csv),
        "progress_every": progress_every,
    }
    meta_path.write_text(json.dumps(meta, indent=2))


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("input_csv", type=Path)
    parser.add_argument(
        "--provider",
        choices=["auto", *sorted(SUPPORTED_PROVIDERS)],
        default=DEFAULT_PROVIDER,
    )
    parser.add_argument("--model")
    parser.add_argument("--calls", type=int, default=3)
    parser.add_argument("--progress-every", type=int, default=5)
    args = parser.parse_args(argv)

    provider = resolve_provider(args.provider)
    model = args.model or default_model_for_provider(provider)
    client = make_judge_client(provider)
    output_csv = args.input_csv.with_name("results_scored.csv")
    meta_path = args.input_csv.with_name("scoring_meta.json")
    score_csv(
        input_csv=args.input_csv,
        output_csv=output_csv,
        meta_path=meta_path,
        judge_client=client,
        judge_model=model,
        judge_provider=provider,
        judge_calls_per_row=args.calls,
        progress_every=args.progress_every,
    )
    print(f"Wrote {output_csv} and {meta_path}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
