# eval_pipeline

Off-device LLM-judge scoring and Pareto reporting for the on-device journaling model.

## Pipeline

1. On-device: run Model Lab -> produces `results.csv` (one row per case x repetition).
2. `judge.py`: read `results.csv`, call an LLM judge with versioned rubrics -> produces `results_scored.csv` and `scoring_meta.json`.
3. `report.py`: read one or more `results_scored.csv` files -> produces per-model tables, a Pareto plot, and a divergence appendix.

## Setup

```sh
python3.11 -m venv eval_pipeline/.venv
source eval_pipeline/.venv/bin/activate
pip install -r eval_pipeline/requirements.txt
export OPENAI_API_KEY=...
```

## Run

```sh
python eval_pipeline/judge.py path/to/results.csv --provider openai
python eval_pipeline/report.py path/to/run-a/results_scored.csv path/to/run-b/results_scored.csv
python -m eval_pipeline.calibration.check --provider openai
```

`--provider auto` is the default. It uses OpenAI when `OPENAI_API_KEY` is set,
otherwise Anthropic when `ANTHROPIC_API_KEY` is set. Anthropic remains available
with `--provider anthropic`.

## Versioning

- `JUDGE_PROMPT_VERSION` in `judge.py` - bump when any rubric file changes.
- Judge model ids are pinned in `judge.py` (`gpt-5.2` for OpenAI, `claude-sonnet-4-6` for Anthropic).
- Re-score every CSV in a comparison when either bumps.
