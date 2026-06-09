import Foundation
@testable import JournalingCompanion

final class MockLLMService: LLMService {
    var stubbedResponse: String = "How does that make you feel?"
    var callCount: Int = 0
    var receivedContexts: [LLMContext] = []
    var shouldThrow: Error? = nil

    func loadModel() async throws {}

    func generate(
        context: LLMContext,
        thinkingEnabled: Bool,
        onEvent: @escaping (GenerationEvent) -> Void
    ) async throws -> String {
        if let error = shouldThrow { throw error }
        callCount += 1
        receivedContexts.append(context)
        if thinkingEnabled { onEvent(.thinking) }
        onEvent(.token(stubbedResponse))
        return stubbedResponse
    }
}
