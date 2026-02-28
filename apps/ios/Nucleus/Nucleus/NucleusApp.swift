import SwiftUI

@main
struct NucleusApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(model)
                .tint(NucleusPalette.accent)
        }
    }
}
