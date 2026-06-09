import SwiftUI

struct MainTabView: View {
    @ObservedObject var services: ServiceContainer

    var body: some View {
        TabView {
            HomeView(
                llmService: services.llmService,
                memoryRepository: services.memoryRepository,
                transcriber: services.transcriber,
                ttsService: services.ttsService
            )
            .tabItem { Label("Home", systemImage: "house") }

            PastSessionsView()
                .tabItem { Label("Sessions", systemImage: "book") }

            SettingsView(llmService: services.llmService, memoryRepository: services.memoryRepository)
                .tabItem { Label("Settings", systemImage: "gearshape") }
        }
    }
}
