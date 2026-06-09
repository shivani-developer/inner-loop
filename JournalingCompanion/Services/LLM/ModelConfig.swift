import Foundation

struct ModelCandidate: Identifiable, Equatable {
    let id: String
    let displayName: String
    let downloadURL: URL
    let memoryRequirement: Int64
    let approximateSizeMB: Int
    let role: String
}

/// Single source of truth for available on-device models.
enum ModelConfig {
    static let selectedModelIdKey = "selectedModelId"
    static let defaultModelId = "qwen3-1.7b-q4_k_m"

    static let availableModels: [ModelCandidate] = [
        ModelCandidate(
            id: "qwen3-0.6b-q4_k_m",
            displayName: "Qwen3 0.6B (Q4_K_M)",
            downloadURL: URL(string: "https://huggingface.co/unsloth/Qwen3-0.6B-GGUF/resolve/main/Qwen3-0.6B-Q4_K_M.gguf")!,
            memoryRequirement: 800_000_000,
            approximateSizeMB: 450,
            role: "Fast baseline"
        ),
        ModelCandidate(
            id: "qwen3-1.7b-q4_k_m",
            displayName: "Qwen3 1.7B (Q4_K_M)",
            downloadURL: URL(string: "https://huggingface.co/unsloth/Qwen3-1.7B-GGUF/resolve/main/Qwen3-1.7B-Q4_K_M.gguf")!,
            memoryRequirement: 1_500_000_000,
            approximateSizeMB: 1100,
            role: "Current baseline"
        ),
        ModelCandidate(
            id: "qwen3-4b-q4_k_m",
            displayName: "Qwen3 4B (Q4_K_M)",
            downloadURL: URL(string: "https://huggingface.co/unsloth/Qwen3-4B-GGUF/resolve/main/Qwen3-4B-Q4_K_M.gguf")!,
            memoryRequirement: 3_500_000_000,
            approximateSizeMB: 2500,
            role: "Quality stretch"
        ),
    ]

    static var selectedModel: ModelCandidate {
        let selectedId = UserDefaults.standard.string(forKey: selectedModelIdKey) ?? defaultModelId
        return availableModels.first { $0.id == selectedId } ?? defaultModel
    }

    static var defaultModel: ModelCandidate {
        availableModels.first { $0.id == defaultModelId } ?? availableModels[0]
    }

    static func selectModel(id: String) {
        UserDefaults.standard.set(id, forKey: selectedModelIdKey)
    }

    static var modelId: String { selectedModel.id }
    static var displayName: String { selectedModel.displayName }
    static var downloadURL: URL { selectedModel.downloadURL }
    static var memoryRequirement: Int64 { selectedModel.memoryRequirement }
    static var approximateSizeMB: Int { selectedModel.approximateSizeMB }
}
