# InnerLoop

InnerLoop is a private, offline Socratic reflection agent for iOS. It runs speech, memory, and small-model inference on-device, then uses Model Lab to evaluate prompt/model quality and latency for a publishable technical case study.

The Xcode target is still named `JournalingCompanion` for now, but the public product name is InnerLoop.

## Phase 1 Result

The first physical-device evaluation compared three quantized Qwen3 models on
an iPhone using a 73-case synthetic eval suite with five repetitions per case.
Outputs were scored by a calibrated LLM judge and compared against on-device
latency.

Headline: **Qwen3 1.7B Q4_K_M is the best current Pareto choice for this app.**
It scored higher than 4B on the overall product-specific quality metric while
remaining materially faster.

| Model | Overall quality | Median latency ms | P95 latency ms | Behavioral pass rate |
| --- | ---: | ---: | ---: | ---: |
| Qwen3 0.6B Q4_K_M | 2.751 | 1554 | 2798 | 1.8% |
| Qwen3 1.7B Q4_K_M | 3.725 | 2524 | 5125 | 9.1% |
| Qwen3 4B Q4_K_M | 3.554 | 5114 | 9111 | 5.5% |

This is not a claim that 1.7B is generally more capable than 4B. It is a
product-specific result under this prompt, quantization, device, and eval suite.
The useful finding is that bigger was not automatically better for a narrow
Socratic reflection contract.

Phase 1 artifacts:

- Technical appendix: [`docs/phase-1-technical-appendix.md`](docs/phase-1-technical-appendix.md)
- Report summary: [`eval_pipeline/reports/0.6b_vs_1.7b_vs_4b/summary.md`](eval_pipeline/reports/0.6b_vs_1.7b_vs_4b/summary.md)
- TestFlight checklist: [`docs/testflight-release.md`](docs/testflight-release.md)

## Project Layout

This repo holds source files only. The `.xcodeproj` is generated from `project.yml` via XcodeGen so the build config is reviewable in version control.

```
project.yml                         # XcodeGen spec (generates .xcodeproj)
JournalingCompanion/                # main target
JournalingCompanionTests/           # test target
docs/innerloop-roadmap.md           # product, eval, and case-study roadmap
docs/phase-1-technical-appendix.md  # reproducible Phase 1 result details
docs/testflight-release.md          # TestFlight release checklist
```

## Benchmark Story

The current eval suite is `suite-v3`. Its examples use synthetic personas and
fictional journaling scenarios, including a senior-executive relocation decision,
parenting stress, grief, health-boundary concerns, prompt-injection attempts,
and profile-compression cases.

That makes exported CSV/JSON artifacts complete enough for analysis without exposing personal material.

## First-Time Setup

1. Install XcodeGen:
   ```
   brew install xcodegen
   ```
2. Generate the Xcode project:
   ```
   xcodegen generate
   ```
3. Open `JournalingCompanion.xcodeproj` in Xcode.
4. The first build will resolve Swift Package dependencies.

## Model Lab

Model Lab runs the local eval suite, records run metadata, and exports CSV/JSON with input, context, expected behavior, model output, latency, validator failures, and human-review columns.

Current selectable models:

- `Qwen3 0.6B (Q4_K_M)`: fast baseline
- `Qwen3 1.7B (Q4_K_M)`: current baseline
- `Qwen3 4B (Q4_K_M)`: quality stretch, device-dependent

Use it to compare:

- baseline prompt versus revised prompt
- warm-model latency across repeated runs
- response specificity and usefulness across small local models
- validator failures against human review notes

## Eval Pipeline

The off-device judge pipeline lives in `eval_pipeline/`.

```bash
eval_pipeline/.venv/bin/python -m pytest eval_pipeline/tests -v
eval_pipeline/.venv/bin/python -m eval_pipeline.report \
  eval_pipeline/runs/0.6b/results_scored.csv \
  eval_pipeline/runs/1.7b/results_scored.csv \
  eval_pipeline/runs/4b/results_scored.csv \
  --out eval_pipeline/reports/0.6b_vs_1.7b_vs_4b
```

The first broad comparison used one judge call per row to control API cost. The
calibration gate was run with three-call median/majority scoring.

## Device Testing

Unit and integration tests use mocks and an in-memory Core Data store. They do not require a loaded LLM model or microphone:

```
xcodebuild test \
  -scheme JournalingCompanion \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

Use a physical iPhone for end-to-end validation of:

- RunAnywhere model download/load and generation latency
- WhisperKit microphone recording/transcription
- AVSpeechSynthesizer playback
- Face ID / device authentication behavior
- file protection behavior while the device is locked

## Architecture

Four protocols keep the app swappable:

```
LLMService           <- RunAnywhereService
SpeechTranscriber    <- WhisperKitTranscriber
MemoryRepository     <- CoreDataMemoryRepo
SessionCoordinator   <- DefaultSessionCoord
```

UI code depends on protocols. Concrete SDK/Core Data types stay at service and app-wiring boundaries.
