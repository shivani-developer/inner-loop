import Foundation
import UIKit

enum EvalExportFormat {
    case json
    case csv

    var fileExtension: String {
        switch self {
        case .json: "json"
        case .csv: "csv"
        }
    }
}

enum EvalResultsExporter {
    static func data(for results: [EvalResult], format: EvalExportFormat) throws -> Data {
        switch format {
        case .json:
            let rows = results.map { EvalExportRow(result: $0) }
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            return try encoder.encode(rows)
        case .csv:
            return Data(csv(for: results).utf8)
        }
    }

    private static func csv(for results: [EvalResult]) -> String {
        let header = [
            "run_id",
            "case_index",
            "repetition_index",
            "id",
            "task",
            "scenario",
            "passed",
            "input",
            "context",
            "expected_behavior",
            "tier",
            "track",
            "reference_response",
            "validator_names",
            "model_id",
            "model_display_name",
            "device_name",
            "os_version",
            "app_version",
            "build_number",
            "repetitions_per_case",
            "thinking_enabled",
            "temperature",
            "prompt_version",
            "eval_suite_version",
            "isolation_mode",
            "time_to_first_token_ms",
            "total_latency_ms",
            "estimated_output_tokens",
            "estimated_tokens_per_second",
            "human_score",
            "specificity_score",
            "usefulness_score",
            "human_notes",
            "violations",
            "error",
            "output",
        ]

        let repetitionsPerCase = results.compactMap(\.repetitionIndex).max().map { $0 + 1 } ?? 1
        let bundle = Bundle.main
        let appVersion = bundle.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
        let buildNumber = bundle.infoDictionary?["CFBundleVersion"] as? String ?? "unknown"
        let deviceName = UIDevice.current.name
        let osVersion = UIDevice.current.systemVersion

        let rows: [[String]] = results.map { result in
            let violations = result.violations
                .map { violation in "\(violation.kind.rawValue): \(violation.detail)" }
                .joined(separator: " | ")
            return [
                result.runId ?? "",
                result.caseIndex.map(String.init) ?? "",
                result.repetitionIndex.map(String.init) ?? "",
                result.id,
                result.task.rawValue,
                result.scenario,
                String(result.passed),
                result.input,
                result.contextSummary,
                result.expectedBehavior,
                result.tier?.rawValue ?? "",
                result.track?.rawValue ?? "",
                result.referenceResponse ?? "",
                result.validatorNames,
                result.metrics.modelId,
                modelDisplayName(for: result.metrics.modelId),
                deviceName,
                osVersion,
                appVersion,
                buildNumber,
                String(repetitionsPerCase),
                String(result.metrics.thinkingEnabled),
                result.metrics.temperatureLabel ?? "",
                result.promptVersion ?? "",
                result.evalSuiteVersion ?? "",
                result.isolationMode?.rawValue ?? "",
                result.metrics.timeToFirstTokenMs.map(String.init) ?? "",
                String(result.metrics.totalLatencyMs),
                String(result.metrics.estimatedOutputTokens),
                result.metrics.estimatedTokensPerSecond.map { String(format: "%.2f", $0) } ?? "",
                result.humanScore.map(String.init) ?? "",
                result.specificityScore.map(String.init) ?? "",
                result.usefulnessScore.map(String.init) ?? "",
                result.humanNotes ?? "",
                violations,
                result.error ?? "",
                result.output,
            ]
        }

        return ([header] + rows)
            .map { $0.map(escapeCSVField).joined(separator: ",") }
            .joined(separator: "\n")
            + "\n"
    }

    private static func escapeCSVField(_ field: String) -> String {
        guard field.contains(",") || field.contains("\"") || field.contains("\n") else {
            return field
        }
        return "\"\(field.replacingOccurrences(of: "\"", with: "\"\""))\""
    }

    private static func modelDisplayName(for modelId: String) -> String {
        ModelConfig.availableModels.first { $0.id == modelId }?.displayName ?? modelId
    }
}

private struct EvalExportRow: Encodable {
    let id: String
    let task: String
    let scenario: String
    let input: String
    let context: String
    let expectedBehavior: String
    let tier: String?
    let track: String?
    let referenceResponse: String?
    let validatorNames: String
    let output: String
    let passed: Bool
    let modelId: String
    let thinkingEnabled: Bool
    let temperatureLabel: String?
    let timeToFirstTokenMs: Int?
    let totalLatencyMs: Int
    let estimatedOutputTokens: Int
    let estimatedTokensPerSecond: Double?
    let violations: [ViolationRow]
    let error: String?

    init(result: EvalResult) {
        id = result.id
        task = result.task.rawValue
        scenario = result.scenario
        input = result.input
        context = result.contextSummary
        expectedBehavior = result.expectedBehavior
        tier = result.tier?.rawValue
        track = result.track?.rawValue
        referenceResponse = result.referenceResponse
        validatorNames = result.validatorNames
        output = result.output
        passed = result.passed
        modelId = result.metrics.modelId
        thinkingEnabled = result.metrics.thinkingEnabled
        temperatureLabel = result.metrics.temperatureLabel
        timeToFirstTokenMs = result.metrics.timeToFirstTokenMs
        totalLatencyMs = result.metrics.totalLatencyMs
        estimatedOutputTokens = result.metrics.estimatedOutputTokens
        estimatedTokensPerSecond = result.metrics.estimatedTokensPerSecond
        violations = result.violations.map { ViolationRow(violation: $0) }
        error = result.error
    }

    struct ViolationRow: Encodable {
        let kind: String
        let detail: String

        init(violation: ResponseValidators.Violation) {
            kind = violation.kind.rawValue
            detail = violation.detail
        }
    }
}
