import Foundation
@testable import JournalingCompanion

final class MockSpeechTranscriber: SpeechTranscriber {
    var stubbedTranscription: String = "I've been feeling anxious lately."
    var partialResults: [String] = []
    var shouldThrow: Error? = nil

    func prepare() async throws {
        if let error = shouldThrow { throw error }
    }

    func startTranscribing(onPartial: @escaping (String) -> Void) async throws {
        if let error = shouldThrow { throw error }
        for partial in partialResults { onPartial(partial) }
        onPartial(stubbedTranscription)
    }

    func stopTranscribing() async throws -> String {
        if let error = shouldThrow { throw error }
        return stubbedTranscription
    }
}
