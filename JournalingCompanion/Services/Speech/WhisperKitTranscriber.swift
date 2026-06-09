import Foundation
import WhisperKit

enum SpeechError: Error {
    case modelNotLoaded
    case recordingFailed(String)
    case noAudioCaptured
}

final class WhisperKitTranscriber: SpeechTranscriber {
    private var whisperKit: WhisperKit?
    private var preparationTask: Task<WhisperKit, Error>?
    private var partialCallback: ((String) -> Void)?
    private var partialUpdateTask: Task<Void, Never>?

    /// Loads the WhisperKit Core ML model (~140MB, downloaded on first use). Idempotent and safe to
    /// call concurrently — the second call awaits the in-flight task instead of starting a new one.
    func prepare() async throws {
        _ = try await loadedWhisperKit()
    }

    private func loadedWhisperKit() async throws -> WhisperKit {
        if let whisperKit { return whisperKit }
        if let preparationTask { return try await preparationTask.value }

        let task = Task<WhisperKit, Error> {
            // base.en is fast enough for live streaming on iPhone 16 Pro.
            let config = WhisperKitConfig(model: "openai_whisper-base.en")
            return try await WhisperKit(config)
        }
        preparationTask = task
        do {
            let kit = try await task.value
            whisperKit = kit
            return kit
        } catch {
            preparationTask = nil
            throw error
        }
    }

    func startTranscribing(onPartial: @escaping (String) -> Void) async throws {
        let whisperKit = try await loadedWhisperKit()
        self.partialCallback = onPartial

        // Reset any previously-buffered audio so we don't transcribe stale samples.
        whisperKit.audioProcessor.purgeAudioSamples(keepingLast: 0)

        try whisperKit.audioProcessor.startRecordingLive(callback: nil)

        // AudioProcessor delivers raw 16kHz mono Float samples continuously. We don't transcribe
        // inside the audio callback (it fires hundreds of times/sec); instead, a separate task
        // polls the accumulated buffer every 1.5s and runs incremental transcription.
        partialUpdateTask = Task { [weak self] in
            await self?.runPartialUpdates()
        }
    }

    func stopTranscribing() async throws -> String {
        partialUpdateTask?.cancel()
        partialUpdateTask = nil
        partialCallback = nil

        guard let whisperKit else { throw SpeechError.modelNotLoaded }
        whisperKit.audioProcessor.stopRecording()

        let samples = Array(whisperKit.audioProcessor.audioSamples)
        guard !samples.isEmpty else { throw SpeechError.noAudioCaptured }

        let results = try await whisperKit.transcribe(audioArray: samples)
        let text = results.map(\.text).joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw SpeechError.noAudioCaptured }
        return text
    }

    // MARK: - Partial transcription loop

    private func runPartialUpdates() async {
        let pollInterval: UInt64 = 1_500_000_000 // 1.5s
        let minSamplesForTranscribe = 16_000      // 1s of audio @ 16kHz

        while !Task.isCancelled {
            try? await Task.sleep(nanoseconds: pollInterval)
            guard !Task.isCancelled, let whisperKit else { return }

            let samples = Array(whisperKit.audioProcessor.audioSamples)
            guard samples.count >= minSamplesForTranscribe else { continue }

            do {
                let results = try await whisperKit.transcribe(audioArray: samples)
                let text = results.map(\.text).joined(separator: " ")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !text.isEmpty {
                    await MainActor.run { self.partialCallback?(text) }
                }
            } catch {
                // Transient transcription failures are fine; the next poll will retry.
            }
        }
    }
}
