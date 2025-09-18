//
//  Persistence.swift
//  ShelfTrack
//
//  Replaces the Core Data template with a lightweight wrapper around the
//  in-app DatabaseManager so Xcode projects referencing the original file
//  continue to compile without Core Data dependencies.
//

import Foundation

enum Persistence {
    static func bootstrapForPreview() -> AppEnvironment {
        AppEnvironment(preview: true)
    }
}
