# InnerLoop TestFlight Release Checklist

This document tracks the repo and App Store Connect work needed to make InnerLoop available as a public TestFlight artifact.

## Goal

Ship a TestFlight build that can be linked from GitHub, a blog post, and a resume project entry. The first public artifact should be framed as an on-device AI experiment, not a polished therapy or mental-health product.

## Distribution Path

Use TestFlight first.

- Internal TestFlight is useful for the first upload and your own device checks.
- External TestFlight is the public-link path. It requires App Store Connect setup and may require Beta App Review before testers outside your App Store Connect team can install it.
- App Store release can come later after privacy copy, screenshots, support links, and review positioning are solid.

## App Store Connect Setup

Create a new app in App Store Connect:

- Name: `InnerLoop`
- Bundle ID: `com.shivani.JournalingCompanion`
- SKU: `innerloop-ios`
- Primary language: English
- Platform: iOS

Required access from you:

- Apple Developer Program membership.
- App Store Connect access with permission to create apps and manage TestFlight.
- Your Apple Development Team ID selected in Xcode signing settings.

## Repo Readiness

Already present:

- Display name: `InnerLoop`
- Bundle version: `1.0`
- Build number: `1`
- App icon: reflection spiral mark
- Usage descriptions:
  - Microphone
  - Speech recognition
  - Face ID
- Privacy manifest:
  - No tracking domains
  - No declared collected data
  - UserDefaults required-reason API declared for app-only preferences

Before every upload:

1. Run tests.
2. Build on a real iPhone.
3. Increment `CURRENT_PROJECT_VERSION` in `project.yml`.
4. Regenerate the Xcode project with `xcodegen generate`.
5. Archive using a physical-device destination.

## Suggested TestFlight Metadata

Beta app description:

InnerLoop is an on-device AI experiment for Socratic reflection. It compares small local language models on latency, specificity, and response quality while keeping journal content on the device.

What to test:

- Start a short reflection session using text or voice.
- Try Model Lab with one downloaded model.
- Export eval results and check whether the output feels specific, concise, and anchored to the prompt.
- Watch for slow model loading, irrelevant questions, transcription issues, or crashes.

Beta app review notes:

This is a local-first journaling and evaluation prototype. The app uses on-device speech transcription and local language models. It is not a medical, therapy, or crisis-support app. Testers can skip onboarding or use fictional profile details. Some model downloads are large and may take time on first launch.

## App Privacy Notes

Use this as the starting point for the App Store Connect privacy questionnaire:

- Data is stored locally on device for journaling and model evaluation.
- The app does not intentionally collect personal data for developer analytics or tracking.
- Audio is used for on-device transcription.
- Local journal text and eval results are not uploaded by the app.
- Model files may be downloaded from remote model-hosting URLs.

Review this before submission because third-party SDK behavior can change. If RunAnywhere, WhisperKit, Sentry, or another dependency starts collecting telemetry or transmitting diagnostics, App Store Connect privacy answers and the privacy manifest must be updated.

## Local Commands

Generate project:

```bash
xcodegen generate
```

Run simulator tests:

```bash
xcodebuild test -scheme JournalingCompanion -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

Build for generic iOS without signing:

```bash
xcodebuild build -scheme JournalingCompanion -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO
```

Archive after selecting your Apple team in Xcode:

```bash
xcodebuild archive \
  -scheme JournalingCompanion \
  -destination 'generic/platform=iOS' \
  -archivePath build/InnerLoop.xcarchive
```

For the first upload, Xcode Organizer is the simplest path:

1. Open `JournalingCompanion.xcodeproj`.
2. Select the app target.
3. Set Signing & Capabilities to your Apple Developer team.
4. Product > Archive.
5. In Organizer, validate the archive.
6. Distribute App > App Store Connect > Upload.

## Public Link Flow

After the build finishes processing in App Store Connect:

1. Open the app in App Store Connect.
2. Go to TestFlight.
3. Add internal testers first and install it yourself.
4. Create an external tester group.
5. Add the processed build to the external group.
6. Fill beta review info and submit if prompted.
7. Enable the public link for the external group.
8. Put that TestFlight link in the README and blog.

## Pre-Public Smoke Test

On a physical iPhone:

- Fresh install opens with the InnerLoop icon and splash mark.
- First model download completes.
- Onboarding can be completed or skipped.
- Text session produces a response.
- Voice transcription starts and stops.
- Settings model picker can select a model.
- Model Lab runs and exports CSV.
- No personal sample data appears in the shipped eval persona.
