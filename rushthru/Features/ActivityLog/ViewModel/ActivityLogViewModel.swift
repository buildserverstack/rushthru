import Foundation

@MainActor
final class ActivityLogViewModel: ObservableObject {
    @Published private(set) var entries: [ActivityLogEntry] = []

    func bootstrap() async {
        // Placeholder for loading persisted activity log.
    }

    func log(action: ActivityLogEntry.Action, entity: ActivityLogEntry.Entity, entityID: UUID?, before: String? = nil, after: String? = nil, metadata: String? = nil) {
        let entry = ActivityLogEntry(action: action, entity: entity, entityID: entityID, beforeJSON: before, afterJSON: after, metadataJSON: metadata)
        entries.insert(entry, at: 0)
    }

    func compact(olderThan date: Date) {
        entries.removeAll { $0.createdAt < date }
    }
}
