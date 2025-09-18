import Foundation
import Combine

@MainActor
final class RefillService: ObservableObject {
    @Published private(set) var refillItems: [InventoryItem] = []

    private var cancellables = Set<AnyCancellable>()
    private let inventoryService: InventoryService

    init(inventoryService: InventoryService) {
        self.inventoryService = inventoryService
        inventoryService.$items
            .receive(on: DispatchQueue.main)
            .sink { [weak self] items in
                self?.refillItems = items.filter { $0.isBelowMinimum }.sorted { lhs, rhs in
                    lhs.name < rhs.name
                }
            }
            .store(in: &cancellables)
    }

    func bootstrap() async {}

    func strike(itemID: UUID, movedQuantity: Int) async {
        await inventoryService.incrementQuantity(itemID: itemID, delta: -movedQuantity)
    }
}
