import SwiftUI
import LocalAuthentication
import CoreData

@MainActor
final class ServiceContainer: ObservableObject {
    let llmService: LLMService
    let memoryRepository: MemoryRepository
    let transcriber: SpeechTranscriber
    let ttsService: TTSService

    init() {
        let llm = RunAnywhereService()
        self.llmService = llm
        self.memoryRepository = CoreDataMemoryRepo(llmService: llm)
        self.transcriber = WhisperKitTranscriber()
        self.ttsService = TTSService()
    }
}

struct AppRoot: View {
    @Environment(\.managedObjectContext) private var viewContext
    @StateObject private var services = ServiceContainer()
    @State private var appState: AppState = .checkingFirstLaunch
    @State private var authError: String? = nil
    @State private var loadError: String? = nil

    enum AppState {
        case checkingFirstLaunch
        case downloadingModel
        case preparingServices
        case onboarding
        case locking
        case unlocked
    }

    var body: some View {
        Group {
            switch appState {
            case .checkingFirstLaunch:
                SplashView()
                    .task { await checkFirstLaunch() }
            case .downloadingModel:
                ModelDownloadView { appState = .onboarding }
            case .preparingServices:
                ModelLoadView(error: loadError, onRetry: prepareServices)
                    .task { await prepareServices() }
            case .onboarding:
                OnboardingView(
                    llmService: services.llmService,
                    memoryRepository: services.memoryRepository
                ) {
                    appState = .preparingServices
                }
            case .locking:
                LockView(error: authError, onRetry: authenticate)
                    .task { await authenticate() }
            case .unlocked:
                MainTabView(services: services)
            }
        }
    }

    private func checkFirstLaunch() async {
        let request: NSFetchRequest<CDUserProfile> = CDUserProfile.fetchRequest()
        let hasProfile = ((try? viewContext.fetch(request))?.count ?? 0) > 0

        if !hasProfile {
            appState = .downloadingModel
        } else {
            appState = .preparingServices
        }
    }

    private func prepareServices() async {
        loadError = nil
        do {
            // Load LLM and prepare WhisperKit in parallel. Both are idempotent: loadModel is a
            // fast no-op if RunAnywhere already has the model resident, and prepare reuses an
            // in-flight WhisperKit load if one is running.
            try await withThrowingTaskGroup(of: Void.self) { group in
                group.addTask { try await self.services.llmService.loadModel() }
                group.addTask { try await self.services.transcriber.prepare() }
                try await group.waitForAll()
            }
            appState = .locking
        } catch {
            print("[AppRoot] prepareServices failed:", error)
            loadError = error.localizedDescription
        }
    }

    private func authenticate() async {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            await MainActor.run { appState = .unlocked }
            return
        }
        do {
            let success = try await context.evaluatePolicy(
                .deviceOwnerAuthentication,
                localizedReason: "Unlock your journal"
            )
            await MainActor.run {
                if success { appState = .unlocked }
            }
        } catch {
            await MainActor.run { authError = error.localizedDescription }
        }
    }
}

/// Visual mark used across launch / lock / load screens to keep the InnerLoop brand consistent
/// before the user reaches the main UI.
struct AppLogoMark: View {
    var body: some View {
        VStack(spacing: 16) {
            InnerLoopAppIconPreview()
                .frame(width: 96, height: 96)
            Text(AppBrand.displayName)
                .font(.title3)
                .fontWeight(.medium)
                .foregroundStyle(.primary)
            Text(AppBrand.subtitle)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }
}

struct SplashView: View {
    var body: some View {
        VStack(spacing: 32) {
            Spacer()
            AppLogoMark()
            Spacer()
            ProgressView()
                .scaleEffect(0.9)
            Spacer().frame(height: 60)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
    }
}

struct ModelLoadView: View {
    let error: String?
    let onRetry: () async -> Void

    var body: some View {
        VStack(spacing: 32) {
            Spacer()
            AppLogoMark()
            Spacer()
            if error == nil {
                VStack(spacing: 12) {
                    ProgressView()
                        .scaleEffect(0.9)
                    Text("Getting things ready")
                        .font(.body)
                        .foregroundStyle(.secondary)
                    Text("Loading the language model and voice transcription. This takes a few seconds.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                }
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 36))
                        .foregroundStyle(.secondary)
                    Text("Couldn't get ready")
                        .font(.body)
                        .fontWeight(.medium)
                    if let error {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                    Button("Retry") {
                        Task { await onRetry() }
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            Spacer().frame(height: 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
        .padding()
    }
}

struct LockView: View {
    let error: String?
    let onRetry: () async -> Void

    var body: some View {
        VStack(spacing: 32) {
            Spacer()
            AppLogoMark()
            Spacer()
            VStack(spacing: 16) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(.secondary)
                Text("Journal locked")
                    .font(.body)
                    .fontWeight(.medium)
                if let error {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                Button("Unlock") {
                    Task { await onRetry() }
                }
                .buttonStyle(.borderedProminent)
            }
            Spacer().frame(height: 60)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
        .padding()
    }
}
