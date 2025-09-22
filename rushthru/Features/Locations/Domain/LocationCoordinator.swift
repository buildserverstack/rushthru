import Foundation

@MainActor
final class LocationCoordinator: ObservableObject {
    @Published private(set) var locations: [LocationNode] = []
    @Published var selectedStoreID: UUID?
    private let activityLogger: ActivityLogCoordinator

    init(activityLogger: ActivityLogCoordinator) {
        self.activityLogger = activityLogger
    }

    func bootstrap() async {
        if locations.isEmpty {
            let root = LocationNode(parentID: nil, kind: .store, name: "Store", path: "Store")
            locations.append(root)
            selectedStoreID = root.id
        } else if selectedStoreID == nil {
            selectedStoreID = stores.first?.id
        }
    }

    func upsert(location: LocationNode) async {
        if let index = locations.firstIndex(where: { $0.id == location.id }) {
            locations[index] = location
            activityLogger.log(action: .edit, entity: .location, entityID: location.id, before: nil, after: nil)
        } else {
            locations.append(location)
            activityLogger.log(action: .create, entity: .location, entityID: location.id, before: nil, after: nil)
            if location.kind == .store, selectedStoreID == nil {
                selectedStoreID = location.id
            }
        }
    }

    func delete(locationID: UUID) async {
        locations.removeAll { $0.id == locationID }
        activityLogger.log(action: .edit, entity: .location, entityID: locationID, before: nil, after: nil)
    }

    func location(for id: UUID?) -> LocationNode? {
        guard let id else { return nil }
        return locations.first { $0.id == id }
    }

    var stores: [LocationNode] {
        locations.filter { $0.kind == .store }
    }
}
