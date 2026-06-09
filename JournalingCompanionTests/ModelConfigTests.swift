import XCTest
@testable import JournalingCompanion

final class ModelConfigTests: XCTestCase {
    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: ModelConfig.selectedModelIdKey)
        super.tearDown()
    }

    func testCatalogContainsComparisonModels() {
        let ids = ModelConfig.availableModels.map(\.id)

        XCTAssertEqual(ModelConfig.availableModels.count, 3)
        XCTAssertTrue(ids.contains("qwen3-0.6b-q4_k_m"))
        XCTAssertTrue(ids.contains("qwen3-1.7b-q4_k_m"))
        XCTAssertTrue(ids.contains("qwen3-4b-q4_k_m"))
    }

    func testSelectedModelDefaultsToCurrentBaseline() {
        XCTAssertEqual(ModelConfig.selectedModel.id, "qwen3-1.7b-q4_k_m")
        XCTAssertEqual(ModelConfig.modelId, ModelConfig.selectedModel.id)
        XCTAssertEqual(ModelConfig.displayName, ModelConfig.selectedModel.displayName)
    }

    func testSelectedModelCanChangeForMainAppAndModelLab() {
        ModelConfig.selectModel(id: "qwen3-0.6b-q4_k_m")

        XCTAssertEqual(ModelConfig.selectedModel.id, "qwen3-0.6b-q4_k_m")
        XCTAssertEqual(EvalRunConfiguration.baseline.modelId, "qwen3-0.6b-q4_k_m")
        XCTAssertEqual(EvalRunConfiguration.baseline.modelDisplayName, "Qwen3 0.6B (Q4_K_M)")
    }

    func testUnknownSelectionFallsBackToDefault() {
        ModelConfig.selectModel(id: "missing-model")

        XCTAssertEqual(ModelConfig.selectedModel.id, "qwen3-1.7b-q4_k_m")
    }
}
