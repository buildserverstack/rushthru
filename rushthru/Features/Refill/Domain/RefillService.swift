import Foundation
import Combine

@MainActor
final class RefillService: ObservableObject {
    @Published private(set) var refillItems: [InventoryItem] = []
    @Published private(set) var manualTasks: [ManualRefillTask] = []

    private var cancellables = Set<AnyCancellable>()
    private let inventoryService: InventoryService

    init(inventoryService: InventoryService) {
        self.inventoryService = inventoryService
        inventoryService.$items
            .receive(on: DispatchQueue.main)
            .sink { [weak self] items in
                self?.refillItems = items
                    .filter { $0.isBelowMinimum }
                    .sorted { lhs, rhs in
                        lhs.name < rhs.name
                    }
            }
            .store(in: &cancellables)
    }

    func bootstrap() async {}

    func strike(itemID: UUID, movedQuantity: Int) async {
        await inventoryService.incrementQuantity(itemID: itemID, delta: movedQuantity)
    }

    func addManualTask(name: String, quantity: Int) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        manualTasks.append(ManualRefillTask(name: trimmed, quantity: max(1, quantity)))
    }

    func strikeManual(taskID: UUID) {
        manualTasks.removeAll { $0.id == taskID }
    }

    func removeManualTasks(at offsets: IndexSet) {
        manualTasks.remove(atOffsets: offsets)
    }

    func suggestions(for query: String, limit: Int = 6) -> [InventoryItem] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        let lowercasedTokens = trimmed.lowercased().split(separator: " ")
        guard !lowercasedTokens.isEmpty else { return [] }

        return inventoryService.items
            .filter { item in
                let haystack = "\(item.name.lowercased()) \(item.subName.lowercased()) \(item.type.rawValue)"
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

    init(id: UUID = UUID(), name: String, quantity: Int) {
        self.id = id
        self.name = name
        self.quantity = quantity
    }
}
