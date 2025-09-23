import Foundation

@MainActor
final class LocationsViewModel: ObservableObject {
    @Published private(set) var locations: [LocationNode] = []
    @Published var selectedStoreID: UUID?
    private let activityLogger: ActivityLogViewModel
    let aisleOptions: [String]
    let shelfOptions: [String]
    let rowOptions: [String]
    let columnOptions: [String]

    init(activityLogger: ActivityLogViewModel) {
        self.activityLogger = activityLogger
        self.aisleOptions = (1...12).map { "Aisle \($0)" }
        self.shelfOptions = (1...10).map { "Shelf \($0)" }
        self.rowOptions = (1...10).map { "Row \($0)" }
        self.columnOptions = (1...10).map { "Column \($0)" }
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

    func storeName(for id: UUID?) -> String? {
        location(for: id)?.name
    }

    @discardableResult
    func createStore(named name: String) async -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        if stores.contains(where: { $0.name.caseInsensitiveCompare(trimmed) == .orderedSame }) { return false }
        let node = LocationNode(parentID: nil, kind: .store, name: trimmed, path: trimmed)
        await upsert(location: node)
        return true
    }

    var stores: [LocationNode] {
        locations.filter { $0.kind == .store }
    }
}
