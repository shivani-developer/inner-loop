# InnerLoop Roadmap

## North Star

Build InnerLoop: an on-device Socratic reflection agent for iOS, plus a public technical case study showing how small local models behave under prompt, model, latency, and quality constraints.

The app is useful as a private reflection tool, but the portfolio value comes from the experimentation system and the analysis it enables.

## Phase 1: Stabilize Current App

Goal: make the current app reliable enough to test.

- Fix obvious response-quality prompt issues.
- Clean up runtime bugs found during device testing.
- Keep onboarding, model download, session flow, save/history, TTS, and voice input working.
- Add lightweight logging for model response time and failures.
- Keep simulator tests passing.

Output: baseline app works on iPhone.

## Phase 2: Experimentation Framework

Goal: turn the app into a measurement tool.

- Expand `EvalSuite` with realistic Socratic scenarios.
- Add metrics: time to first token, total response time, estimated tokens/sec, response length, pass/fail validator result, and manual quality score.
- Add validators for generic responses, lack of anchoring to user input, repeated questions, unsolicited advice, and irrelevant responses.
- Export eval results as JSON and CSV.
- Add a Model Lab screen in Settings.

Output: repeatable eval runs on-device.

## Phase 3: Baseline Experiments

Goal: learn from the current model before changing model weights.

- Current Qwen3-1.7B with current prompt.
- Qwen3-1.7B with improved Socratic prompt.
- Thinking mode on vs off.
- Temperature presets such as `0.3`, `0.5`, and `0.7`.
- Different max-token budgets.
- Multiple runs of the same eval suite to measure variance.

Output: first real analysis table.

## Phase 4: Model Comparison

Goal: compare model size and quality trade-offs.

- Qwen3-0.6B as a speed baseline.
- Qwen3-1.7B as the current baseline.
- Qwen3-4B as a quality test if the phone can handle it.
- Optional later comparison with Gemma 3n or Apple Foundation Models if integration is feasible.

Metrics:

- Download size.
- Memory pressure or crashes.
- Load time.
- First-token latency.
- Total latency.
- Quality score.
- Failure modes.

Output: evidence for which model is viable on iPhone 16 Pro.

## Phase 5: Branding and Distribution

Goal: make the project accessible without presenting it as a clinical mental-health product.

- Name: InnerLoop.
- Subtitle: An on-device Socratic reflection agent.
- Positioning: privacy-first AI experiment, not therapy and not clinical advice.
- Distribution: TestFlight first, App Store later only if review/privacy/disclaimer text is solid.

Output: TestFlight link plus public GitHub/blog.

## Phase 6: Public Case Study

Goal: make the work resume-ready.

README/blog structure:

- Problem: private reflective AI on phone.
- Architecture: SwiftUI, Core Data, WhisperKit, RunAnywhere, GGUF.
- Evaluation harness: prompts, validators, metrics.
- Results: model, latency, and quality tables.
- Failure modes: generic questions, irrelevant responses, repetition.
- Improvements: prompt tuning, parameter tuning, model choice.
- Future work: LoRA fine-tune, RAG memory, richer eval rubric.

Output: polished GitHub README, blog post, and resume bullet.

## Phase 7: Optional LoRA Project

Goal: answer whether a small LoRA-tuned model produces more specific Socratic questions than prompt tuning alone.

This should happen after baseline evaluation, so the project has a clear before/after story.

