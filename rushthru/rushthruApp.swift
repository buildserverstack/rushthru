//
//  rushthruApp.swift
//  rushthru
//
//  Created by sujay Chandra on 9/15/25.
//

import SwiftUI

@main
struct rushthruApp: App {
    let persistenceController = PersistenceController.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
        }
    }
}
