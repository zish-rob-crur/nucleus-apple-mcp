import SwiftUI

enum RootTab: Hashable {
    case overview
    case sync
    case settings
}

struct ContentView: View {
    @State private var selectedTab: RootTab = .overview

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                OverviewView(selectedTab: $selectedTab)
            }
            .tabItem {
                Label("Home", systemImage: "house.fill")
            }
            .tag(RootTab.overview)

            NavigationStack {
                SyncView(selectedTab: $selectedTab)
            }
            .tabItem {
                Label("Sync", systemImage: "arrow.triangle.2.circlepath")
            }
            .tag(RootTab.sync)

            NavigationStack {
                SettingsView()
            }
            .tabItem {
                Label("Settings", systemImage: "gearshape.fill")
            }
            .tag(RootTab.settings)
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(AppModel())
}

