import SwiftUI

struct MainTabView: View {
    @EnvironmentObject private var refillService: RefillService
    @EnvironmentObject private var searchCoordinator: SearchCoordinator
    @EnvironmentObject private var captureCoordinator: CaptureCoordinator

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
            await captureCoordinator.bootstrap()
            await searchCoordinator.bootstrap()
            await refillService.bootstrap()
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
