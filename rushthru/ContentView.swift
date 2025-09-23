//
//  RootView.swift
//  rushthru
//
//  Created for ShelfTrack specification.
//

import SwiftUI

struct RootView: View {
    @EnvironmentObject private var environment: AppEnvironment
    @StateObject private var lockViewModel = LockViewModel()

    var body: some View {
        ZStack {
            if lockViewModel.state == .unlocked {
                MainTabView()
                    .environmentObject(environment)
                    .environmentObject(environment.inventory)
                    .environmentObject(environment.refill)
                    .environmentObject(environment.search)
                    .environmentObject(environment.locations)
                    .environmentObject(environment.csv)
                    .environmentObject(environment.activity)
                    .environmentObject(environment.capture)
                    .environmentObject(environment.bulkCounts)
                    .environmentObject(environment.auth)
                    .transition(.opacity)
                    .onReceive(environment.auth.$isLocked.dropFirst()) { locked in
                        if locked {
                            withAnimation(.easeInOut(duration: 0.25)) {
                                lockViewModel.lock()
                            }
                        }
                    }
            } else {
                AppLockView(viewModel: lockViewModel)
                    .environmentObject(environment.auth)
                    .transition(.opacity)
            }
        }
        .task {
            await environment.start()
            lockViewModel.bind(to: environment.auth)
        }
    }
}

#Preview {
    RootView()
        .environmentObject(AppEnvironment(preview: true))
}
