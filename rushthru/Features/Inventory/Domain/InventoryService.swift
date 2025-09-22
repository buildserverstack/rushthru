import Foundation
import Combine

@MainActor
final class InventoryService: ObservableObject {
    @Published private(set) var items: [InventoryItem] = []
    @Published private(set) var lastUpdated: Date = Date()
    @Published private(set) var selectedStoreID: UUID?

    private let activityLogger: ActivityLogCoordinator
    private let locationCoordinator: LocationCoordinator
    private var cancellables = Set<AnyCancellable>()
    private var storage: [UUID: [InventoryItem]] = [:]

    init(activityLogger: ActivityLogCoordinator, locationCoordinator: LocationCoordinator) {
        self.activityLogger = activityLogger
        self.locationCoordinator = locationCoordinator
        self.selectedStoreID = locationCoordinator.selectedStoreID
        locationCoordinator.$selectedStoreID
            .receive(on: DispatchQueue.main)
            .sink { [weak self] storeID in
                self?.selectedStoreID = storeID
                self?.reloadItems(for: storeID)
            }
            .store(in: &cancellables)
    }

    func bootstrap() async {
        await MainActor.run {
            let store = locationCoordinator.selectedStoreID ?? locationCoordinator.stores.first?.id
            if selectedStoreID != store {
                selectedStoreID = store
            }
            reloadItems(for: store)
        }
    }

    func item(id: UUID) -> InventoryItem? {
        items.first { $0.id == id }
    }

    func create(item: InventoryItem) async {
        guard let storeID = ensureStoreID() else { return }
        var storedItem = item
        storedItem.storeID = storeID
        storage[storeID, default: []].append(storedItem)
        if storeID == selectedStoreID {
            items.append(storedItem)
        }
        lastUpdated = Date()
        activityLogger.log(action: .create, entity: .item, entityID: storedItem.id, before: nil, after: encode(storedItem))
    }

    func existingItem(matching identity: ItemIdentity) -> InventoryItem? {
        items.first { $0.normalizedIdentity == identity }
    }

    func replaceAll(with newItems: [InventoryItem]) async {
        guard let storeID = ensureStoreID() else { return }
        let reassigned = newItems.map { item -> InventoryItem in
            var mutable = item
            mutable.storeID = storeID
            return mutable
        }
        storage[storeID] = reassigned
        if storeID == selectedStoreID {
            items = reassigned
        }
        lastUpdated = Date()
        activityLogger.log(action: .import, entity: .batch, entityID: nil, before: nil, after: "Replaced with \(reassigned.count) items")
    }

    func update(item: InventoryItem) async {
        guard let storeID = ensureStoreID() else { return }
        guard var storeItems = storage[storeID], let index = storeItems.firstIndex(where: { $0.id == item.id }) else { return }
        let before = storeItems[index]
        var updated = item
        updated.storeID = storeID
        storeItems[index] = updated
        storage[storeID] = storeItems
        if storeID == selectedStoreID, let currentIndex = items.firstIndex(where: { $0.id == item.id }) {
            items[currentIndex] = updated
        }
        lastUpdated = Date()
        activityLogger.log(action: .edit, entity: .item, entityID: updated.id, before: encode(before), after: encode(updated))
    }

    func incrementQuantity(itemID: UUID, delta: Int) async {
        guard let storeID = ensureStoreID() else { return }
        guard var storeItems = storage[storeID], let index = storeItems.firstIndex(where: { $0.id == itemID }) else { return }
        var item = storeItems[index]
        let before = item
        item.quantity = max(0, item.quantity + delta)
        item.updatedAt = Date()
        storeItems[index] = item
        storage[storeID] = storeItems
        if storeID == selectedStoreID, let currentIndex = items.firstIndex(where: { $0.id == itemID }) {
            items[currentIndex] = item
        }
        lastUpdated = Date()
        activityLogger.log(action: .edit, entity: .item, entityID: itemID, before: encode(before), after: encode(item))
    }

    func adjustQuantity(itemID: UUID, to quantity: Int) async {
        guard let storeID = ensureStoreID() else { return }
        guard var storeItems = storage[storeID], let index = storeItems.firstIndex(where: { $0.id == itemID }) else { return }
        var item = storeItems[index]
        let before = item
        item.quantity = max(0, quantity)
        item.updatedAt = Date()
        storeItems[index] = item
        storage[storeID] = storeItems
        if storeID == selectedStoreID, let currentIndex = items.firstIndex(where: { $0.id == itemID }) {
            items[currentIndex] = item
        }
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

    private func reloadItems(for storeID: UUID?) {
        guard let storeID else {
            items = []
            return
        }
        items = storage[storeID] ?? []
    }

    private func ensureStoreID() -> UUID? {
        if let selectedStoreID = locationCoordinator.selectedStoreID {
            return selectedStoreID
        }
        if let fallback = locationCoordinator.stores.first?.id {
            locationCoordinator.selectedStoreID = fallback
            return fallback
        }
        return nil
    }

    private func encode(_ item: InventoryItem) -> String? {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(item) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
