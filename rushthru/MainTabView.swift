import SwiftUI

struct MainTabView: View {
    @EnvironmentObject private var refillViewModel: RefillViewModel
    @EnvironmentObject private var searchViewModel: SearchViewModel
    @EnvironmentObject private var captureViewModel: CaptureViewModel

    var body: some View {
        TabView {
            DashboardView()
                .tabItem {
                    Label("Dashboard", systemImage: "square.grid.2x2")
                }
            CaptureView()
                .tabItem {
                    Label("Capture", systemImage: "camera")
                }
            SearchView()
                .tabItem {
                    Label("Search", systemImage: "magnifyingglass")
                }
            RefillView()
                .tabItem {
                    Label("Refill", systemImage: "cart")
                }
            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gear")
                }
        }
        .task {
            await captureViewModel.bootstrap()
            await searchViewModel.bootstrap()
            await refillViewModel.bootstrap()
        }
    }
}

#Preview {
    let environment = AppEnvironment(preview: true)
    return MainTabView()
        .environmentObject(environment.inventory)
        .environmentObject(environment.refill)
        .environmentObject(environment.search)
        .environmentObject(environment.locations)
        .environmentObject(environment.activity)
        .environmentObject(environment.csv)
        .environmentObject(environment.capture)
        .environmentObject(environment.bulkCounts)
        .environmentObject(environment.auth)
}
