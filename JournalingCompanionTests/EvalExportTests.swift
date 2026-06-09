import XCTest
@testable import JournalingCompanion

final class EvalExportTests: XCTestCase {

    func testJSONExportIncludesMetricsAndViolations() throws {
        let data = try EvalResultsExporter.data(for: [Self.sampleResult], format: .json)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [[String: Any]])
        let row = try XCTUnwrap(object.first)

        XCTAssertEqual(row["id"] as? String, "socratic.sample")
        XCTAssertEqual(row["modelId"] as? String, "qwen-test")
        XCTAssertEqual(row["thinkingEnabled"] as? Bool, true)
        XCTAssertEqual(row["timeToFirstTokenMs"] as? Int, 120)
        XCTAssertEqual(row["totalLatencyMs"] as? Int, 900)
        XCTAssertEqual(row["estimatedOutputTokens"] as? Int, 12)
        XCTAssertEqual(row["temperatureLabel"] as? String, "0.7")

        let violations = try XCTUnwrap(row["violations"] as? [[String: Any]])
        XCTAssertEqual(violations.first?["kind"] as? String, "genericResponse")
    }

    func testCSVExportIncludesStableColumnsAndEscapesFields() throws {
        let data = try EvalResultsExporter.data(for: [Self.sampleResult], format: .csv)
        let csv = String(decoding: data, as: UTF8.self)

        XCTAssertTrue(csv.hasPrefix("run_id,case_index,repetition_index,id,task,scenario,passed,input,context,expected_behavior,tier,track,reference_response,validator_names,model_id,model_display_name,device_name,os_version,app_version,build_number,repetitions_per_case"))
        XCTAssertTrue(csv.contains(",input,context,expected_behavior,tier,track,reference_response,validator_names,"))
        XCTAssertTrue(csv.contains(",model_id,model_display_name,device_name,os_version,app_version,build_number,repetitions_per_case,"))
        XCTAssertTrue(csv.contains(",human_score,specificity_score,usefulness_score,human_notes,"))
        XCTAssertTrue(csv.contains("\"A scenario, with comma\""))
        XCTAssertTrue(csv.contains("\"Latest input, with comma\""))
        XCTAssertTrue(csv.contains("Ask one anchored question."))
        XCTAssertTrue(csv.contains("socraticResponseViolations"))
        XCTAssertTrue(csv.contains("\"A response with \"\"quotes\"\"\""))
        XCTAssertTrue(csv.contains("genericResponse: Too vague"))
    }

    func testJSONExportIncludesHumanReviewContext() throws {
        let data = try EvalResultsExporter.data(for: [Self.sampleResult], format: .json)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [[String: Any]])
        let row = try XCTUnwrap(object.first)

        XCTAssertEqual(row["input"] as? String, "Latest input, with comma")
        XCTAssertEqual(row["context"] as? String, "Synthetic profile context")
        XCTAssertEqual(row["expectedBehavior"] as? String, "Ask one anchored question.")
        XCTAssertEqual(row["validatorNames"] as? String, "socraticResponseViolations")
    }

    func testRunJSONEncodesRunAwareResultFields() throws {
        let result = Self.sampleResult.withRunContext(
            runId: "run-1",
            caseIndex: 2,
            repetitionIndex: 1,
            promptVersion: "prompt-v1",
            evalSuiteVersion: "suite-v2",
            isolationMode: .warmModelFreshPrompt
        )
        let metadata = EvalRunMetadata(
            appVersion: "1.0",
            buildNumber: "1",
            deviceName: "Test Device",
            osVersion: "26.0",
            modelId: "qwen-test",
            modelDisplayName: "Qwen Test",
            thinkingEnabled: true,
            temperatureLabel: "0.7",
            promptVersion: "prompt-v1",
            evalSuiteVersion: "suite-v2",
            isolationMode: .warmModelFreshPrompt,
            repetitionsPerCase: 1,
            caseCount: 1,
            notes: nil
        )
        let run = EvalRunRecord(
            id: "run-1",
            createdAt: Date(timeIntervalSince1970: 0),
            metadata: metadata,
            results: [result]
        )

        let data = try JSONEncoder().encode(run)
        let json = String(decoding: data, as: UTF8.self)

        XCTAssertTrue(json.contains("\"runId\":\"run-1\""))
        XCTAssertTrue(json.contains("\"caseIndex\":2"))
        XCTAssertTrue(json.contains("\"humanScore\":null"))
    }

    private static let sampleResult = EvalResult(
        id: "socratic.sample",
        task: .socraticResponse,
        scenario: "A scenario, with comma",
        input: "Latest input, with comma",
        context: "Synthetic profile context",
        expectedBehavior: "Ask one anchored question.",
        validatorNames: "socraticResponseViolations",
        output: "A response with \"quotes\"",
        violations: [
            ResponseValidators.Violation(kind: .genericResponse, detail: "Too vague"),
        ],
        metrics: EvalMetrics(
            modelId: "qwen-test",
            thinkingEnabled: true,
            temperatureLabel: "0.7",
            timeToFirstTokenMs: 120,
            totalLatencyMs: 900,
            estimatedOutputTokens: 12,
            estimatedTokensPerSecond: 15.5
        ),
        error: nil
    )
}
