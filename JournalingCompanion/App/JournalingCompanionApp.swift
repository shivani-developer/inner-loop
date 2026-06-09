import SwiftUI
import RunAnywhere
import LlamaCPPRuntime

@main
struct JournalingCompanionApp: App {
    let persistence = PersistenceController.shared

    init() {
        do {
            try RunAnywhere.initialize(environment: .development)
            LlamaCPP.register()

            for model in ModelConfig.availableModels {
                RunAnywhere.registerModel(
                    id: model.id,
                    name: model.displayName,
                    url: model.downloadURL,
                    framework: .llamaCpp,
                    memoryRequirement: model.memoryRequirement
                )
            }
        } catch {
            // SDK init failure surfaces at generate-time as a thrown LLMError. We don't
            // crash here so that UI surfaces (settings, history) still load.
            print("RunAnywhere init failed: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            AppRoot()
                .environment(\.managedObjectContext, persistence.container.viewContext)
        }
    }
}
