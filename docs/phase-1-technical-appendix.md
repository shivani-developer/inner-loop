# InnerLoop Phase 1 Technical Appendix

This appendix supports the Phase 1 blog post and GitHub project page. It is
intended to be factual, compact, and reproducible.

## Scope

Phase 1 answers one question:

Which currently integrated Qwen3 quantized model is the best practical choice
for InnerLoop's on-device Socratic reflection loop?

The answer from this run is Qwen3 1.7B Q4_K_M.

## App Context

InnerLoop is a private, offline iOS reflection app. The core loop is:

1. Load on-device memory.
2. Generate a contextual opening prompt.
3. Run a text or voice reflection session.
4. Ask short Socratic follow-up questions.
5. Summarize the session and persist local memory.
6. Use Model Lab to evaluate model/prompt behavior.

Service boundaries:

| Protocol | Concrete implementation |
| --- | --- |
| `LLMService` | `RunAnywhereService` |
| `SpeechTranscriber` | `WhisperKitTranscriber` |
| `MemoryRepository` | `CoreDataMemoryRepo` |
| `SessionCoordinator` | `DefaultSessionCoord` |

## Models Compared

| Model ID | Display name | Role |
| --- | --- | --- |
| `qwen3-0.6b-q4_k_m` | Qwen3 0.6B Q4_K_M | speed baseline |
| `qwen3-1.7b-q4_k_m` | Qwen3 1.7B Q4_K_M | current baseline |
| `qwen3-4b-q4_k_m` | Qwen3 4B Q4_K_M | quality stretch |

## Eval Suite

- Suite: `suite-v3`
- Cases: 73
- Repetitions per model: 5
- Rows per model: 365
- Total scored rows: 1095

Task distribution per model:

| Task | Rows |
| --- | ---: |
| Socratic response | 225 |
| Opening prompt | 40 |
| Session summary | 40 |
| Session title | 30 |
| Profile compression | 30 |

Track distribution per model:

| Track | Rows |
| --- | ---: |
| Quality | 310 |
| Behavioral | 55 |

## Judge Setup

- Provider: OpenAI
- Judge model: `gpt-5.2`
- Judge prompt version: `judge-v2`
- Production comparison judge calls per row: 1
- Calibration judge calls: 3, using median for quality dimensions and majority
  vote for behavioral pass/fail

Calibration result:

- All dimensions passed the RMSE threshold of `0.5`.
- Highest final RMSE was approximately `0.4472`.

## Run Provenance

The 0.6B and 1.7B models completed one five-repetition Model Lab run each.

The 4B model was run as five one-repetition exports because a full
five-repetition run was too slow to complete reliably in one app session. The
exports were combined into one normalized CSV. The combined file preserves
`source_run_id` for each row.

Repository artifacts:

| Artifact | Path |
| --- | --- |
| Raw/scored run files | `eval_pipeline/runs/` |
| Report tables and plot | `eval_pipeline/reports/0.6b_vs_1.7b_vs_4b/` |
| Report summary | `eval_pipeline/reports/0.6b_vs_1.7b_vs_4b/summary.md` |

## Headline Results

| Model | Overall quality | Median latency ms | P95 latency ms | Median tokens/s | Behavioral pass rate |
| --- | ---: | ---: | ---: | ---: | ---: |
| Qwen3 0.6B Q4_K_M | 2.751 | 1554 | 2798 | 42.97 | 1.8% |
| Qwen3 1.7B Q4_K_M | 3.725 | 2524 | 5125 | 22.79 | 9.1% |
| Qwen3 4B Q4_K_M | 3.554 | 5114 | 9111 | 16.99 | 5.5% |

Task-level quality:

| Task | 0.6B | 1.7B | 4B | Best |
| --- | ---: | ---: | ---: | --- |
| Socratic response | 2.759 | 4.070 | 3.791 | 1.7B |
| Opening prompt | 3.017 | 3.850 | 3.825 | 1.7B |
| Session summary | 2.475 | 2.783 | 2.508 | 1.7B |
| Session title | 3.400 | 3.633 | 3.983 | 4B |
| Profile compression | 2.173 | 1.880 | 2.240 | 4B |

## Interpretation

Qwen3 1.7B Q4_K_M is the best Phase 1 Pareto choice because:

- It has the highest overall judged quality.
- It wins the most important app surface: Socratic response.
- It is materially faster than 4B.
- 4B's gains in title/profile areas do not outweigh its latency cost.

The surprising result should be phrased narrowly:

This run does not show that 1.7B is generally more capable than 4B. It shows
that 1.7B was better matched to InnerLoop's current prompt and response contract
on this eval suite.

## Limitations

- This is a synthetic eval, not a user study.
- The broad comparison used one judge call per row for cost control.
- The 4B dataset combines five one-repetition runs.
- Behavioral pass rate is intentionally strict.
- Some title scoring examples are subjective.
- The result should be rechecked after prompt-v2.

## Commands

Run Python tests:

```bash
eval_pipeline/.venv/bin/python -m pytest eval_pipeline/tests -v
```

Run iOS tests:

```bash
xcodebuild test -scheme JournalingCompanion -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

Regenerate the report:

```bash
eval_pipeline/.venv/bin/python -m eval_pipeline.report \
  eval_pipeline/runs/0.6b/results_scored.csv \
  eval_pipeline/runs/1.7b/results_scored.csv \
  eval_pipeline/runs/4b/results_scored.csv \
  --out eval_pipeline/reports/0.6b_vs_1.7b_vs_4b
```
