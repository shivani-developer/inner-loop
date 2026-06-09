import Foundation

struct SavedEvalRunFiles: Equatable {
    let runDirectory: URL
    let runJSONURL: URL
    let resultsJSONURL: URL
    let resultsCSVURL: URL
    let summaryJSONURL: URL
}

final class EvalLedgerStore {
    private let rootDirectory: URL
    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(
        rootDirectory: URL? = nil,
        fileManager: FileManager = .default
    ) {
        self.fileManager = fileManager
        if let rootDirectory {
            self.rootDirectory = rootDirectory
        } else {
            let documents = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
            self.rootDirectory = documents.appendingPathComponent("EvalRuns", isDirectory: true)
        }

        encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
    }

    func save(_ run: EvalRunRecord) throws -> SavedEvalRunFiles {
        try fileManager.createDirectory(at: rootDirectory, withIntermediateDirectories: true)
        let runDirectory = rootDirectory.appendingPathComponent(run.id, isDirectory: true)
        try fileManager.createDirectory(at: runDirectory, withIntermediateDirectories: true)

        let files = SavedEvalRunFiles(
            runDirectory: runDirectory,
            runJSONURL: runDirectory.appendingPathComponent("run.json"),
            resultsJSONURL: runDirectory.appendingPathComponent("results.json"),
            resultsCSVURL: runDirectory.appendingPathComponent("results.csv"),
            summaryJSONURL: runDirectory.appendingPathComponent("summary.json")
        )

        try encoder.encode(run).write(to: files.runJSONURL, options: .atomic)
        try EvalResultsExporter.data(for: run.results, format: .json)
            .write(to: files.resultsJSONURL, options: .atomic)
        try EvalResultsExporter.data(for: run.results, format: .csv)
            .write(to: files.resultsCSVURL, options: .atomic)
        try encoder.encode(run.summary).write(to: files.summaryJSONURL, options: .atomic)
        try upsertIndexEntry(for: run, files: files)

        return files
    }

    func loadIndex() throws -> [EvalRunIndexEntry] {
        let url = indexURL
        guard fileManager.fileExists(atPath: url.path) else { return [] }
        let data = try Data(contentsOf: url)
        return try decoder.decode([EvalRunIndexEntry].self, from: data)
    }

    func loadRun(id: String) throws -> EvalRunRecord {
        let url = rootDirectory
            .appendingPathComponent(id, isDirectory: true)
            .appendingPathComponent("run.json")
        let data = try Data(contentsOf: url)
        return try decoder.decode(EvalRunRecord.self, from: data)
    }

    private var indexURL: URL {
        rootDirectory.appendingPathComponent("index.json")
    }

    private func upsertIndexEntry(for run: EvalRunRecord, files: SavedEvalRunFiles) throws {
        var index = try loadIndex().filter { $0.id != run.id }
        index.insert(
            EvalRunIndexEntry(
                id: run.id,
                createdAt: run.createdAt,
                modelDisplayName: run.metadata.modelDisplayName,
                promptVersion: run.metadata.promptVersion,
                evalSuiteVersion: run.metadata.evalSuiteVersion,
                passRate: run.summary.passRate,
                averageTotalLatencyMs: run.summary.averageTotalLatencyMs,
                resultsCSVPath: files.resultsCSVURL.path,
                runJSONPath: files.runJSONURL.path
            ),
            at: 0
        )
        try fileManager.createDirectory(at: rootDirectory, withIntermediateDirectories: true)
        try encoder.encode(index).write(to: indexURL, options: .atomic)
    }
}
