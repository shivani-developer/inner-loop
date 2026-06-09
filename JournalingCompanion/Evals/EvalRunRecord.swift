import Foundation
import UIKit

enum EvalIsolationMode: String, Codable, Equatable {
    case warmModelFreshPrompt
}

struct EvalRunMetadata: Codable, Equatable {
    let appVersion: String
    let buildNumber: String
    let deviceName: String
    let osVersion: String
    let modelId: String
    let modelDisplayName: String
    let thinkingEnabled: Bool
    let temperatureLabel: String?
    let promptVersion: String
    let evalSuiteVersion: String
    let isolationMode: EvalIsolationMode
    let repetitionsPerCase: Int
    let caseCount: Int
    let notes: String?

    static func current(
        configuration: EvalRunConfiguration,
        repetitionsPerCase: Int,
        caseCount: Int,
        notes: String? = nil
    ) -> EvalRunMetadata {
        let bundle = Bundle.main
        return EvalRunMetadata(
            appVersion: bundle.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown",
            buildNumber: bundle.infoDictionary?["CFBundleVersion"] as? String ?? "unknown",
            deviceName: UIDevice.current.name,
            osVersion: UIDevice.current.systemVersion,
            modelId: configuration.modelId,
            modelDisplayName: configuration.modelDisplayName,
            thinkingEnabled: configuration.thinkingEnabled,
            temperatureLabel: configuration.temperatureLabel,
            promptVersion: EvalSuite.promptVersion,
            evalSuiteVersion: EvalSuite.version,
            isolationMode: .warmModelFreshPrompt,
            repetitionsPerCase: repetitionsPerCase,
            caseCount: caseCount,
            notes: notes
        )
    }
}

struct EvalRunSummary: Codable, Equatable {
    let totalAttempts: Int
    let passedAttempts: Int
    let passRate: Double
    let averageTimeToFirstTokenMs: Int?
    let averageTotalLatencyMs: Int?
    let averageEstimatedTokensPerSecond: Double?
    let averageEstimatedOutputTokens: Int?
    let failureCountsByViolationKind: [String: Int]
    let errorsCount: Int

    init(results: [EvalResult]) {
        totalAttempts = results.count
        passedAttempts = results.filter(\.passed).count
        passRate = results.isEmpty ? 0 : Double(passedAttempts) / Double(results.count)
        averageTimeToFirstTokenMs = Self.average(results.compactMap(\.metrics.timeToFirstTokenMs))
        averageTotalLatencyMs = Self.average(results.map(\.metrics.totalLatencyMs))
        averageEstimatedTokensPerSecond = Self.average(results.compactMap(\.metrics.estimatedTokensPerSecond))
        averageEstimatedOutputTokens = Self.average(results.map(\.metrics.estimatedOutputTokens))
        errorsCount = results.filter { $0.error != nil }.count

        var counts: [String: Int] = [:]
        for violation in results.flatMap(\.violations) {
            counts[violation.kind.rawValue, default: 0] += 1
        }
        failureCountsByViolationKind = counts
    }

    private static func average(_ values: [Int]) -> Int? {
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / values.count
    }

    private static func average(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }
}

struct EvalRunRecord: Identifiable, Codable, Equatable {
    let id: String
    let createdAt: Date
    let metadata: EvalRunMetadata
    let summary: EvalRunSummary
    let results: [EvalResult]

    init(
        id: String = UUID().uuidString,
        createdAt: Date = Date(),
        metadata: EvalRunMetadata,
        results: [EvalResult]
    ) {
        self.id = id
        self.createdAt = createdAt
        self.metadata = metadata
        self.results = results
        self.summary = EvalRunSummary(results: results)
    }
}

struct EvalRunIndexEntry: Identifiable, Codable, Equatable {
    let id: String
    let createdAt: Date
    let modelDisplayName: String
    let promptVersion: String
    let evalSuiteVersion: String
    let passRate: Double
    let averageTotalLatencyMs: Int?
    let resultsCSVPath: String
    let runJSONPath: String
}
