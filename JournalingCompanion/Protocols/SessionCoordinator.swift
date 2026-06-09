import Foundation

protocol SessionCoordinator: AnyObject {
    func startSession(with prompt: String) async
    func send(
        message: String,
        thinkingEnabled: Bool,
        onEvent: @escaping (GenerationEvent) -> Void
    ) async throws -> String
    func endSession() async throws -> SessionSummary
}
