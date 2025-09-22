import Foundation
import Combine

@MainActor
final class RefillService: ObservableObject {
    @Published private(set) var refillItems: [InventoryItem] = []
    @Published private(set) var manualTasks: [ManualRefillTask] = []

    private var cancellables = Set<AnyCancellable>()
    private let inventoryService: InventoryService
    private var manualTaskStorage: [UUID: [ManualRefillTask]] = [:]

    init(inventoryService: InventoryService) {
        self.inventoryService = inventoryService
        inventoryService.$items
            .receive(on: DispatchQueue.main)
            .sink { [weak self] items in
                guard let self else { return }
                self.refillItems = items
                    .filter { $0.isBelowMinimum }
                    .sorted { lhs, rhs in
                        lhs.name < rhs.name
                    }
                if let storeID = self.inventoryService.selectedStoreID {
                    var tasks = self.manualTaskStorage[storeID] ?? []
                    for index in tasks.indices {
                        if let linkedID = tasks[index].linkedItemID {
                            if let linkedItem = items.first(where: { $0.id == linkedID }) {
                                tasks[index].availableQuantity = linkedItem.quantity
                            } else {
                                tasks[index].availableQuantity = 0
                            }
                        }
                    }
                    self.manualTaskStorage[storeID] = tasks
                    self.manualTasks = tasks
                }
            }
            .store(in: &cancellables)
        inventoryService.$selectedStoreID
            .receive(on: DispatchQueue.main)
            .sink { [weak self] storeID in
                guard let self else { return }
                self.manualTasks = storeID.flatMap { self.manualTaskStorage[$0] } ?? []
            }
            .store(in: &cancellables)
    }

    func bootstrap() async {}

    func strike(itemID: UUID, movedQuantity: Int) async {
        guard movedQuantity > 0 else { return }
        await inventoryService.incrementQuantity(itemID: itemID, delta: -movedQuantity)
    }

    func addManualTask(name: String, quantity: Int) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard let storeID = inventoryService.selectedStoreID else { return }
        let normalized = trimmed.lowercased()
        let linked = inventoryService.items.first { item in
            item.displayName.lowercased() == normalized || item.name.lowercased() == normalized
        } ?? inventoryService.items.first { item in
            item.displayName.lowercased().contains(normalized)
        }
        let task = ManualRefillTask(
            name: trimmed,
            quantity: max(1, quantity),
            availableQuantity: linked?.quantity ?? 0,
            linkedItemID: linked?.id,
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
