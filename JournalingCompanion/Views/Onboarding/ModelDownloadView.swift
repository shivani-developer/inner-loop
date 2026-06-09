import SwiftUI
import RunAnywhere

@MainActor
final class ModelDownloadViewModel: ObservableObject {
    @Published var progress: Double = 0.0
    @Published var statusText: String = "Preparing..."
    @Published var isComplete: Bool = false
    @Published var error: String? = nil

    func startDownload() async {
        let model = ModelConfig.selectedModel
        error = nil
        progress = 0
        statusText = "Checking model..."

        // If a previous launch already loaded the model, skip straight through.
        if (try? await RunAnywhere.loadModel(model.id)) != nil {
            progress = 1.0
            statusText = "Model loaded"
            isComplete = true
            return
        }

        statusText = "Downloading \(model.displayName)..."
        do {
            let progressStream = try await RunAnywhere.downloadModel(model.id)
            for await update in progressStream {
                progress = update.overallProgress
                if update.stage == .completed { break }
            }
        } catch {
            self.error = "Download failed. Check your network. (\(error.localizedDescription))"
            return
        }

        statusText = "Loading model..."
        do {
            try await RunAnywhere.loadModel(model.id)
            isComplete = true
        } catch {
            self.error = "Couldn't load model. (\(error.localizedDescription))"
        }
    }
}

struct ModelDownloadView: View {
    @StateObject private var viewModel = ModelDownloadViewModel()
    let onComplete: () -> Void

    var body: some View {
        VStack(spacing: 32) {
            Spacer()
            AppLogoMark()
            Spacer()

            VStack(spacing: 14) {
                Text("First-time setup")
                    .font(.body)
                    .fontWeight(.medium)
                Text("Downloading \(ModelConfig.displayName) (~\(ModelConfig.approximateSizeMB)MB). This happens once and runs entirely on your phone.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)

                ProgressView(value: viewModel.progress)
                    .progressViewStyle(.linear)
                    .padding(.horizontal, 40)

                Text("\(viewModel.statusText) — \(Int(viewModel.progress * 100))%")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let error = viewModel.error {
                VStack(spacing: 12) {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                    Button("Retry") {
                        Task { await viewModel.startDownload() }
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            Spacer().frame(height: 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
        .task { await viewModel.startDownload() }
        .onChange(of: viewModel.isComplete) { _, complete in
            if complete { onComplete() }
        }
    }
}
