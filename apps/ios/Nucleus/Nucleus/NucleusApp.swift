import SwiftUI
import BackgroundTasks

@main
struct NucleusApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(model)
                .tint(NucleusPalette.accent)
                .onChange(of: scenePhase) { _, newPhase in
                    model.handleScenePhase(newPhase)
                }
        }
        .backgroundTask(.appRefresh(NucleusBackgroundRefresh.identifier)) {
            await model.handleBackgroundRefreshTask()
        }
    }
}
