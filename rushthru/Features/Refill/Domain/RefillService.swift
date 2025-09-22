import Foundation
import Combine

@MainActor
final class RefillService: ObservableObject {
    @Published private(set) var refillItems: [InventoryItem] = []
    @Published private(set) var manualTasks: [ManualRefillTask] = []
    @Published private(set) var shelfSuggestions: [ShelfSuggestion] = []
    @Published private(set) var isScanningShelf: Bool = false
    @Published private(set) var shelfScanError: String?

    private var cancellables = Set<AnyCancellable>()
    private let inventoryService: InventoryService
    private let shelfRecognizer: ShelfRecognizing
    private var manualTaskStorage: [UUID: [ManualRefillTask]] = [:]

    init(inventoryService: InventoryService, shelfRecognizer: ShelfRecognizing) {
        self.inventoryService = inventoryService
        self.shelfRecognizer = shelfRecognizer
        inventoryService.$items
            .receive(on: DispatchQueue.main)
            .sink { [weak self] items in
                self?.updateState(with: items)
            }
            .store(in: &cancellables)
        inventoryService.$selectedStoreID
            .receive(on: DispatchQueue.main)
            .sink { [weak self] storeID in
                guard let self else { return }
                self.manualTasks = storeID.flatMap { self.manualTaskStorage[$0] } ?? []
                self.shelfSuggestions = []
                self.shelfScanError = nil
            }
            .store(in: &cancellables)
    }

    func bootstrap() async {}

    func strike(itemID: UUID, movedQuantity: Int) async {
        guard movedQuantity > 0 else { return }
        await inventoryService.incrementQuantity(itemID: itemID, delta: -movedQuantity)
    }

    func addManualTask(name: String, quantity: Int, linkedItem: InventoryItem? = nil) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard let storeID = inventoryService.selectedStoreID else { return }

        let normalizedQuery = trimmed.lowercased()
        let resolvedLink: InventoryItem?
        if let linkedItem, linkedItem.storeID == storeID {
            resolvedLink = linkedItem
        } else {
            resolvedLink = inventoryService.items.first { item in
                item.displayName.lowercased() == normalizedQuery || item.name.lowercased() == normalizedQuery
            } ?? inventoryService.items.first { item in
                item.displayName.lowercased().contains(normalizedQuery)
            }
        }

        let task = ManualRefillTask(
            name: trimmed,
            quantity: max(1, quantity),
            availableQuantity: resolvedLink?.quantity ?? 0,
            linkedItemID: resolvedLink?.id,
            storeID: storeID
        )
        manualTaskStorage[storeID, default: []].append(task)
        if storeID == inventoryService.selectedStoreID {
            manualTasks.append(task)
        }
    }

    func strikeManual(taskID: UUID) {
        guard let storeID = inventoryService.selectedStoreID else { return }
        guard let task = manualTasks.first(where: { $0.id == taskID }) else { return }
        if let linked = task.linkedItemID {
            Task { [inventoryService] in
                await inventoryService.incrementQuantity(itemID: linked, delta: -task.quantity)
            }
        }
        manualTasks.removeAll { $0.id == taskID }
        if var tasks = manualTaskStorage[storeID] {
            tasks.removeAll { $0.id == taskID }
            manualTaskStorage[storeID] = tasks
        }
    }

    func removeManualTasks(at offsets: IndexSet) {
        guard let storeID = inventoryService.selectedStoreID else { return }
        let removed = offsets.map { manualTasks[$0].id }
        manualTasks.remove(atOffsets: offsets)
        if var tasks = manualTaskStorage[storeID] {
            tasks.removeAll { removed.contains($0.id) }
            manualTaskStorage[storeID] = tasks
        }
    }

    func suggestions(for query: String, limit: Int = 6) -> [InventoryItem] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        let lowercasedTokens = trimmed.lowercased().split(separator: " ")
        guard !lowercasedTokens.isEmpty else { return [] }

        return inventoryService.items
            .filter { item in
                let haystack = "\(item.name.lowercased()) \(item.subName.lowercased()) \(item.type.lowercased())"
                return lowercasedTokens.allSatisfy { haystack.contains($0) }
            }
            .sorted { $0.name < $1.name }
            .prefix(limit)
            .map { $0 }
    }

    func analyzeShelfImage(_ data: Data) async {
        guard inventoryService.selectedStoreID != nil else {
            shelfScanError = "Select a store before scanning shelves."
            shelfSuggestions = []
            return
        }
        isScanningShelf = true
        shelfScanError = nil
        do {
            let inventorySnapshot = inventoryService.items.map(ShelfInventorySnapshot.init(item:))
            let candidates = try await shelfRecognizer.analyzeShelf(imageData: data, inventory: inventorySnapshot)
            let mapped = candidates.map { candidate -> ShelfSuggestion in
                let linkedItem = candidate.itemID.flatMap { id in
                    inventoryService.items.first(where: { $0.id == id })
                } ?? inventoryService.items.first { item in
                    item.displayName.caseInsensitiveCompare(candidate.name) == .orderedSame
                }
                let available = linkedItem?.quantity ?? candidate.availableQuantity
                let quantity = max(1, candidate.suggestedQuantity)
                return ShelfSuggestion(
                    itemID: linkedItem?.id ?? candidate.itemID,
                    displayName: linkedItem?.displayName ?? candidate.name,
                    suggestedQuantity: quantity,
                    availableQuantity: available,
                    confidence: candidate.confidence
                )
            }
            shelfSuggestions = mapped
            if mapped.isEmpty {
                shelfScanError = "Nothing to refill detected."
            }
        } catch {
            shelfScanError = "Shelf analysis failed. Please try again."
            shelfSuggestions = []
        }
        isScanningShelf = false
    }

    func applyShelfSuggestion(_ suggestion: ShelfSuggestion) {
        guard suggestion.suggestedQuantity > 0 else { return }
        let linkedItem = suggestion.itemID.flatMap { id in
            inventoryService.items.first(where: { $0.id == id })
        }
        addManualTask(name: suggestion.displayName, quantity: suggestion.suggestedQuantity, linkedItem: linkedItem)
        shelfSuggestions.removeAll { $0.id == suggestion.id }
    }

    func clearShelfScanResults() {
        shelfSuggestions = []
        shelfScanError = nil
    }

    private func updateState(with items: [InventoryItem]) {
        refillItems = items
            .filter { $0.isBelowMinimum }
            .sorted { lhs, rhs in
                lhs.name < rhs.name
            }

        let itemMap = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })

        if let storeID = inventoryService.selectedStoreID {
            var tasks = manualTaskStorage[storeID] ?? []
            for index in tasks.indices {
                if let linkedID = tasks[index].linkedItemID,
                   let linkedItem = itemMap[linkedID] {
                    tasks[index].availableQuantity = linkedItem.quantity
                } else {
                    tasks[index].availableQuantity = 0
                }
            }
            manualTaskStorage[storeID] = tasks
            manualTasks = tasks
        }

        var updatedSuggestions: [ShelfSuggestion] = []
        for suggestion in shelfSuggestions {
            if let itemID = suggestion.itemID, let item = itemMap[itemID] {
                if item.minimum <= item.quantity {
                    continue
                }
                var updated = suggestion
                updated.displayName = item.displayName
                updated.availableQuantity = item.quantity
                updated.suggestedQuantity = max(1, item.minimum - item.quantity)
                updatedSuggestions.append(updated)
            } else {
                updatedSuggestions.append(suggestion)
            }
        }
        shelfSuggestions = updatedSuggestions
    }
}

struct ShelfSuggestion: Identifiable, Equatable {
    let id: UUID
    let itemID: UUID?
    var displayName: String
    var suggestedQuantity: Int
    var availableQuantity: Int
    var confidence: Double

    init(id: UUID = UUID(), itemID: UUID?, displayName: String, suggestedQuantity: Int, availableQuantity: Int, confidence: Double) {
        self.id = id
        self.itemID = itemID
        self.displayName = displayName
        self.suggestedQuantity = suggestedQuantity
        self.availableQuantity = availableQuantity
        self.confidence = confidence
    }
}

struct ManualRefillTask: Identifiable, Equatable {
    let id: UUID
    var name: String
    var quantity: Int
    var availableQuantity: Int
    var linkedItemID: UUID?
    var storeID: UUID

    init(id: UUID = UUID(), name: String, quantity: Int, availableQuantity: Int, linkedItemID: UUID?, storeID: UUID) {
        self.id = id
        self.name = name
        self.quantity = quantity
        self.availableQuantity = availableQuantity
        self.linkedItemID = linkedItemID
        self.storeID = storeID
    }
}
