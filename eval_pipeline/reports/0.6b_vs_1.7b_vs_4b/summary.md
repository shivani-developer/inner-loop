# Qwen3 On-Device Eval Report: 0.6B vs 1.7B vs 4B

Date: 2026-06-03

This report summarizes the first physical-device InnerLoop Model Lab comparison
scored by the calibrated LLM judge.

## Inputs

- Device source: physical iPhone Model Lab exports.
- Eval suite: 73 cases x 5 repetitions = 365 rows per model.
- Judge provider: OpenAI.
- Judge model: `gpt-5.2`.
- Judge prompt version: `judge-v2`.
- Judge calls per row: 1 for this production comparison.

The 4B model was run as five separate one-repetition exports because full
five-repetition runs were too slow to complete reliably in one app session. The
five exports were combined into `eval_pipeline/runs/4b/results.csv`; the
`source_run_id` column preserves the original source run for each row.

## Headline Result

The 1.7B model is the best current Pareto choice for this app. It is much better
than 0.6B on quality, materially faster than 4B, and scored higher than 4B
overall in this first judged comparison.

| Model | Overall quality | Median latency ms | P95 latency ms | Median tokens/s | Behavioral pass rate |
| --- | ---: | ---: | ---: | ---: | ---: |
| Qwen3 0.6B Q4_K_M | 2.751 | 1554 | 2798 | 42.97 | 1.8% |
| Qwen3 1.7B Q4_K_M | 3.725 | 2524 | 5125 | 22.79 | 9.1% |
| Qwen3 4B Q4_K_M | 3.554 | 5114 | 9111 | 16.99 | 5.5% |

Interpretation:

- 0.6B is fast but too weak for the target Socratic reflection behavior.
- 1.7B gives the strongest overall judged quality and remains usable on-device.
- 4B is slower and did not produce a quality gain over 1.7B in this suite.

## Quality By Task

| Task | 0.6B | 1.7B | 4B | Best model |
| --- | ---: | ---: | ---: | --- |
| Socratic response | 2.759 | 4.070 | 3.791 | 1.7B |
| Opening prompt | 3.017 | 3.850 | 3.825 | 1.7B |
| Session summary | 2.475 | 2.783 | 2.508 | 1.7B |
| Session title | 3.400 | 3.633 | 3.983 | 4B |
| Profile compression | 2.173 | 1.880 | 2.240 | 4B |

The largest practical win is on Socratic response quality. 1.7B scored higher
than 4B on therapeutic stance, memory grounding, and format quality, while 4B
was slightly more specific.

## Behavioral Gate

The behavioral pass rate is very low for all models:

- 0.6B: 1 pass out of 55 behavioral rows.
- 1.7B: 5 passes out of 55 behavioral rows.
- 4B: 3 passes out of 55 behavioral rows.

This is a strict gate. For Socratic behavioral cases, the judge requires the
model to satisfy both the boundary behavior and the product's target response
shape: one short Socratic question, no advice, no clinical language, no invented
memory, and tight anchoring to concrete user wording.

Examples of common failures:

- Giving advice after the user asks "what should I do?"
- Using generic questions like "what feels most important?"
- Asking two questions.
- Declining a role-play or diagnostic request but then asking an unanchored
  follow-up.
- Adding inferred emotional states not present in the user's input.

The behavioral result should be treated as a product-design finding: the models
can often sound plausible, but they do not reliably stay inside the app's narrow
reflection contract under boundary pressure.

## Divergence Review

The top divergence appendix looks directionally reasonable for the highest
spread Socratic and opening-prompt cases:

- `opening.memory_personalized`: 4B was judged most specific, 1.7B strong, 0.6B
  verbose and less targeted.
- `socratic.multi_turn_latest_user_focus`: 1.7B had a generic response in the
  sampled row, while 0.6B and 4B referenced the spouse/family isolation concern.
- `opening.weekly_and_recent_sessions`: 1.7B and 4B used supplied memory more
  concretely than 0.6B.

Some title-specificity divergences are more subjective. They are useful as
examples, but not strong enough alone to change the model decision.

## Limitations

- The calibration gate passed with three judge calls and median/majority
  aggregation. This broad comparison used one judge call per row to control API
  cost.
- The 4B result combines five one-repetition physical runs instead of one
  continuous five-repetition run.
- The overall quality score is an average of judge dimension cells, not a
  user-study outcome.
- Behavioral pass rates are strict by design and should be interpreted with
  examples, not only as percentages.
- Title scoring has subjective cases where one-point differences should not be
  overinterpreted.

## Generated Artifacts

- `overall_quality.csv`
- `per_task_dimensions.csv`
- `behavioral_violations.csv`
- `divergence_appendix.csv`
- `pareto.png`
