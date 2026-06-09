import Foundation

protocol SpeechTranscriber {
    func prepare() async throws
    func startTranscribing(onPartial: @escaping (String) -> Void) async throws
    func stopTranscribing() async throws -> String
}
