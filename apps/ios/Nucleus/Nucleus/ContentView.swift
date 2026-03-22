import SwiftUI

enum RootTab: Hashable {
    case overview
    case sync
    case settings
}

struct ContentView: View {
    @EnvironmentObject private var model: AppModel
    @State private var selectedTab: RootTab = .overview

    var body: some View {
        TabView(selection: $selectedTab) {
            Tab("Home", systemImage: "house.fill", value: .overview) {
                NavigationStack {
                    OverviewView(selectedTab: $selectedTab)
                }
            }

            Tab("Sync", systemImage: "arrow.triangle.2.circlepath", value: .sync) {
                NavigationStack {
                    SyncView(selectedTab: $selectedTab)
                }
            }

            Tab("Settings", systemImage: "gearshape.fill", value: .settings) {
                NavigationStack {
                    SettingsView()
                }
            }
        }
        .sheet(isPresented: $model.isPresentingInitialSyncRangePicker) {
            InitialSyncRangeSheet()
                .environmentObject(model)
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        }
        .task {
            model.bootstrapIfNeeded()
        }
        .safeAreaInset(edge: .bottom) {
            if let progress = model.syncProgress {
                SyncProgressOverlay(progress: progress)
                    .padding(.horizontal, 16)
                    .padding(.top, 6)
                    .padding(.bottom, 60)
            }
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(AppModel())
}

private struct InitialSyncRangeSheet: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    NucleusCard("First Sync", systemImage: "calendar.badge.clock") {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Choose how much history to import on the first sync. Larger ranges take longer, and later syncs will stay incremental.")
                                .font(.system(.subheadline, design: .rounded))
                                .foregroundStyle(Color.secondary)
                                .fixedSize(horizontal: false, vertical: true)

                            ForEach(InitialSyncRangeOption.allCases) { option in
                                Button {
                                    model.startInitialSync(option: option)
                                } label: {
                                    NucleusInset {
                                        HStack(alignment: .firstTextBaseline, spacing: 12) {
                                            VStack(alignment: .leading, spacing: 4) {
                                                Text(option.title)
                                                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                                                    .foregroundStyle(.primary)
                                                Text(option.subtitle)
                                                    .font(.system(.footnote, design: .rounded))
                                                    .foregroundStyle(Color.secondary)
                                            }

                                            Spacer(minLength: 0)

                                            Text("\(option.days)d")
                                                .font(.system(.subheadline, design: .monospaced).weight(.semibold))
                                                .foregroundStyle(NucleusPalette.accentForeground(colorScheme))
                                        }
                                    }
                                }
                                .buttonStyle(.plain)
                            }

                            Button("Not now") {
                                model.dismissInitialSyncRangePicker()
                            }
                            .buttonStyle(NucleusButtonStyle(kind: .ghost))
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 18)
                .padding(.bottom, 14)
            }
            .scrollIndicators(.hidden)
            .background(NucleusBackground())
            .navigationTitle("Choose History")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
