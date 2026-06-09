import XCTest
@testable import JournalingCompanion

final class EvalSuiteTests: XCTestCase {

    func testBaselineSuiteIncludesConcreteSocraticFailureModes() {
        let ids = Set(EvalSuite.allCases.map(\.id))

        XCTAssertTrue(ids.contains("socratic.relocation_generic_response"))
        XCTAssertTrue(ids.contains("socratic.executive_self_doubt"))
        XCTAssertTrue(ids.contains("socratic.health_routines_deferred"))
    }

    func testSocraticHardRulesNoLongerFlagGenericResponses() {
        let genericResponse = "How does that feel?"
        let socraticCases = EvalSuite.allCases.filter { $0.task == .socraticResponse }

        XCTAssertGreaterThanOrEqual(socraticCases.count, 5)
        for evalCase in socraticCases {
            let violationKinds = Set(evalCase.validators(genericResponse).map(\.kind))
            XCTAssertFalse(
                violationKinds.contains(.genericResponse),
                "\(evalCase.id): specificity moved to the LLM judge; hard rules must not flag generic phrasing"
            )
            XCTAssertFalse(
                violationKinds.contains(.notAnchoredToUserInput),
                "\(evalCase.id): anchoring moved to the LLM judge; hard rules must not flag it"
            )
        }
    }

    func testEvalSuiteV3HasEnoughCasesForAnalysis() {
        XCTAssertEqual(EvalSuite.version, "suite-v3")
        XCTAssertGreaterThanOrEqual(EvalSuite.allCases.count, 25)
    }

    func testEvalSuiteIncludesCoreAnalysisCategories() {
        let ids = Set(EvalSuite.allCases.map(\.id))
        XCTAssertTrue(ids.contains("socratic.prompt_injection_ignore_role"))
        XCTAssertTrue(ids.contains("socratic.no_hallucinated_memory"))
        XCTAssertTrue(ids.contains("socratic.multi_turn_latest_user_focus"))
        XCTAssertTrue(ids.contains("opening.memory_personalized"))
        XCTAssertTrue(ids.contains("summary.emotional_shift"))
    }

    func testEvalSuiteUsesSyntheticSeniorExecutiveRelocationPersona() {
        let exportedText = EvalSuite.allCases
            .map { "\($0.id)\n\($0.scenario)\n\($0.input)\n\($0.contextSummary)" }
            .joined(separator: "\n")

        XCTAssertTrue(exportedText.localizedCaseInsensitiveContains("senior executive"))
        XCTAssertTrue(exportedText.localizedCaseInsensitiveContains("relocat"))
        XCTAssertTrue(exportedText.localizedCaseInsensitiveContains("family"))
        XCTAssertTrue(exportedText.localizedCaseInsensitiveContains("health"))
        XCTAssertTrue(exportedText.localizedCaseInsensitiveContains("Europe"))
        XCTAssertTrue(exportedText.localizedCaseInsensitiveContains("US"))
    }

    func testEvalCasesIncludeHumanReviewFields() {
        for evalCase in EvalSuite.allCases {
            XCTAssertFalse(evalCase.input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, evalCase.id)
            XCTAssertFalse(evalCase.expectedBehavior.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, evalCase.id)
            XCTAssertFalse(evalCase.validatorNames.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, evalCase.id)
        }
    }

    func testPublishableEvalExamplesAvoidPersonalNamesAndAges() {
        let exportedText = EvalSuite.allCases
            .map { "\($0.id)\n\($0.scenario)\n\($0.input)\n\($0.contextSummary)\n\($0.expectedBehavior)" }
            .joined(separator: "\n")

        XCTAssertFalse(exportedText.localizedCaseInsensitiveContains("Shivani"))
        XCTAssertFalse(exportedText.localizedCaseInsensitiveContains("Amazon"))
        XCTAssertFalse(exportedText.contains("29F"))
        XCTAssertFalse(exportedText.contains("I'm 29"))
        XCTAssertFalse(exportedText.contains("I am 28"))
        XCTAssertFalse(exportedText.localizedCaseInsensitiveContains("portfolio"))
        XCTAssertFalse(exportedText.localizedCaseInsensitiveContains("mobile app"))
        XCTAssertFalse(exportedText.localizedCaseInsensitiveContains("on-device AI"))
        XCTAssertFalse(exportedText.localizedCaseInsensitiveContains("Xcode"))
        XCTAssertFalse(exportedText.localizedCaseInsensitiveContains("job search"))
        XCTAssertFalse(exportedText.localizedCaseInsensitiveContains("resume"))
    }
}
