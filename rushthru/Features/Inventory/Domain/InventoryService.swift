import Foundation
import Combine

@MainActor
final class InventoryService: ObservableObject {
    @Published private(set) var items: [InventoryItem] = []
    @Published private(set) var lastUpdated: Date = Date()
    @Published private(set) var selectedStoreID: UUID?
    @Published private(set) var availableTypes: [String] = InventoryItem.defaultTypes
    @Published private(set) var availableSizes: [Int] = InventoryItem.defaultSizes.sorted()
    @Published private(set) var customTypeOptions: [String] = []
    @Published private(set) var customSizeOptions: [Int] = []

    private let activityLogger: ActivityLogCoordinator
    private let locationCoordinator: LocationCoordinator
    private var cancellables = Set<AnyCancellable>()
    private var storage: [UUID: [InventoryItem]] = [:]
    private var customTypeStore: [String] = []
    private var customSizeSet: Set<Int> = []

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
            let store = locationCoordinator.selectedStoreID
            if selectedStoreID != store {
                selectedStoreID = store
            }
            reloadItems(for: store)
            refreshAvailableSizes()
        }
    }

    func item(id: UUID) -> InventoryItem? {
        items.first { $0.id == id }
    }

    func create(item: InventoryItem) async {
        guard let storeID = ensureStoreID() else { return }
        var storedItem = item
        storedItem.storeID = storeID
        storedItem.type = canonicalTypeName(for: storedItem.type)
        _ = registerType(storedItem.type)
        storage[storeID, default: []].append(storedItem)
        if storeID == selectedStoreID {
            items.append(storedItem)
        }
        lastUpdated = Date()
        activityLogger.log(action: .create, entity: .item, entityID: storedItem.id, before: nil, after: encode(storedItem))
        registerSize(storedItem.sizeML)
    }

    func existingItem(matching identity: ItemIdentity) -> InventoryItem? {
        items.first { $0.normalizedIdentity == identity }
    }

    func replaceAll(with newItems: [InventoryItem]) async {
        guard let storeID = ensureStoreID() else { return }
        let reassigned = newItems.map { item -> InventoryItem in
            var mutable = item
            mutable.storeID = storeID
            mutable.type = canonicalTypeName(for: mutable.type)
            return mutable
        }
        storage[storeID] = reassigned
        if storeID == selectedStoreID {
            items = reassigned
        }
        refreshAvailableTypes()
        refreshAvailableSizes()
        lastUpdated = Date()
        activityLogger.log(action: .import, entity: .batch, entityID: nil, before: nil, after: "Replaced with \(reassigned.count) items")
    }

    func update(item: InventoryItem) async {
        guard let storeID = ensureStoreID() else { return }
        guard var storeItems = storage[storeID], let index = storeItems.firstIndex(where: { $0.id == item.id }) else { return }
        let before = storeItems[index]
        var updated = item
        updated.storeID = storeID
        updated.type = canonicalTypeName(for: updated.type)
        storeItems[index] = updated
        storage[storeID] = storeItems
        if storeID == selectedStoreID, let currentIndex = items.firstIndex(where: { $0.id == item.id }) {
            items[currentIndex] = updated
        }
        _ = registerType(updated.type)
        registerSize(updated.sizeML)
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

    @discardableResult
    func addCustomType(_ name: String) -> Bool {
        return registerType(name)
    }

    func removeCustomType(_ name: String) -> (removed: Bool, message: String?) {
        let normalized = ItemIdentity.normalizeType(name)
        guard customTypeStore.contains(where: { ItemIdentity.normalizeType($0) == normalized }) else {
            return (false, "Only custom types can be removed.")
        }
        let inUse = storage.values.flatMap { $0 }.contains { ItemIdentity.normalizeType($0.type) == normalized }
        guard !inUse else {
            return (false, "Type is still used by inventory items.")
        }
        customTypeStore.removeAll { ItemIdentity.normalizeType($0) == normalized }
        refreshAvailableTypes()
        return (true, nil)
    }

    func matchingType(for value: String) -> String? {
        let normalized = ItemIdentity.normalizeType(value)
        return availableTypes.first { ItemIdentity.normalizeType($0) == normalized }
    }

    @discardableResult
    func addCustomSize(_ value: Int) -> Bool {
        guard value > 0 else { return false }
        if InventoryItem.defaultSizes.contains(value) || customSizeSet.contains(value) {
            return false
        }
        customSizeSet.insert(value)
        refreshAvailableSizes()
        return true
    }

    func removeCustomSize(_ value: Int) -> (removed: Bool, message: String?) {
        guard customSizeSet.contains(value) else {
            return (false, "Only custom sizes can be removed.")
        }
        let inUse = storage.values.flatMap { $0 }.contains { $0.sizeML == value }
        guard !inUse else {
            return (false, "Size is still used by inventory items.")
        }
        customSizeSet.remove(value)
        refreshAvailableSizes()
        return (true, nil)
    }

    func ensureActiveStoreID() -> UUID? {
        ensureStoreID()
    }

    private func reloadItems(for storeID: UUID?) {
        if let storeID {
            items = storage[storeID] ?? []
        } else {
            let flattened = storage.values.flatMap { $0 }
            items = flattened.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        }
        refreshAvailableTypes()
        refreshAvailableSizes()
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

    private func canonicalTypeName(for value: String) -> String {
        if let existing = matchingType(for: value) {
            return existing
        }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "Other" }
        registerType(trimmed)
        return matchingType(for: trimmed) ?? trimmed
    }

    @discardableResult
    private func registerType(_ type: String) -> Bool {
        let trimmed = type.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        let normalized = ItemIdentity.normalizeType(trimmed)
        if availableTypes.contains(where: { ItemIdentity.normalizeType($0) == normalized }) {
            return false
        }
        if !InventoryItem.defaultTypes.contains(where: { ItemIdentity.normalizeType($0) == normalized }) {
            if !customTypeStore.contains(where: { ItemIdentity.normalizeType($0) == normalized }) {
                customTypeStore.append(trimmed)
            }
        }
        refreshAvailableTypes()
        return true
    }

    private func refreshAvailableTypes() {
        customTypeStore = dedupeTypes(customTypeStore.filter { type in
            let normalized = ItemIdentity.normalizeType(type)
            return !InventoryItem.defaultTypes.contains { ItemIdentity.normalizeType($0) == normalized }
        })

        let currentItems = storage.values.flatMap { $0 }
        for item in currentItems {
            let trimmed = item.type.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let normalized = ItemIdentity.normalizeType(trimmed)
            if !InventoryItem.defaultTypes.contains(where: { ItemIdentity.normalizeType($0) == normalized }) &&
                !customTypeStore.contains(where: { ItemIdentity.normalizeType($0) == normalized }) {
                customTypeStore.append(trimmed)
            }
        }

        customTypeStore = dedupeTypes(customTypeStore)
        customTypeStore.sort { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        customTypeOptions = customTypeStore

        var combined = InventoryItem.defaultTypes
        combined.append(contentsOf: customTypeStore)
        combined = dedupeTypes(combined)
        combined.sort { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        availableTypes = combined
    }

    private func refreshAvailableSizes() {
        var sizes = Set(InventoryItem.defaultSizes)
        sizes.formUnion(customSizeSet)
        for storeItems in storage.values {
            for item in storeItems {
                sizes.insert(item.sizeML)
            }
        }
        availableSizes = sizes.sorted()
        customSizeOptions = customSizeSet.sorted()
    }

    private func registerSize(_ size: Int) {
        guard size > 0 else { return }
        if !InventoryItem.defaultSizes.contains(size) {
            customSizeSet.insert(size)
        }
        refreshAvailableSizes()
    }

    private func dedupeTypes(_ types: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for type in types {
            let normalized = ItemIdentity.normalizeType(type)
            if seen.insert(normalized).inserted {
                result.append(type)
            }
        }
        return result
    }

    private func encode(_ item: InventoryItem) -> String? {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(item) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
