import Foundation
import Combine

@MainActor
final class InventoryService: ObservableObject {
    @Published private(set) var items: [InventoryItem] = []
    @Published private(set) var lastUpdated: Date = Date()

    private let activityLogger: ActivityLogCoordinator
    private let locationCoordinator: LocationCoordinator

    init(activityLogger: ActivityLogCoordinator, locationCoordinator: LocationCoordinator) {
        self.activityLogger = activityLogger
        self.locationCoordinator = locationCoordinator
    }

    func bootstrap() async {
        // Load persisted inventory if available.
    }

    func item(id: UUID) -> InventoryItem? {
        items.first { $0.id == id }
    }

    func create(item: InventoryItem) async {
        items.append(item)
        lastUpdated = Date()
        activityLogger.log(action: .create, entity: .item, entityID: item.id, before: nil, after: encode(item))
    }

    func replaceAll(with newItems: [InventoryItem]) async {
        items = newItems
        lastUpdated = Date()
        activityLogger.log(action: .import, entity: .batch, entityID: nil, before: nil, after: "Replaced with \(newItems.count) items")
    }

    func update(item: InventoryItem) async {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        let before = items[index]
        items[index] = item
        lastUpdated = Date()
        activityLogger.log(action: .edit, entity: .item, entityID: item.id, before: encode(before), after: encode(item))
    }

    func incrementQuantity(itemID: UUID, delta: Int) async {
        guard let index = items.firstIndex(where: { $0.id == itemID }) else { return }
        var item = items[index]
        let before = item
        item.quantity = max(0, item.quantity + delta)
        item.updatedAt = Date()
        items[index] = item
        lastUpdated = Date()
        activityLogger.log(action: .edit, entity: .item, entityID: itemID, before: encode(before), after: encode(item))
    }

    func adjustQuantity(itemID: UUID, to quantity: Int) async {
        guard let index = items.firstIndex(where: { $0.id == itemID }) else { return }
        var item = items[index]
        let before = item
        item.quantity = max(0, quantity)
        item.updatedAt = Date()
        items[index] = item
        lastUpdated = Date()
        activityLogger.log(action: .count, entity: .item, entityID: itemID, before: encode(before), after: encode(item))
    }

    func items(belowMinimumOnly: Bool) -> [InventoryItem] {
        if belowMinimumOnly {
            return items.filter { $0.isBelowMinimum }
        } else {
            return items
        }
    }

    private func encode(_ item: InventoryItem) -> String? {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(item) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
