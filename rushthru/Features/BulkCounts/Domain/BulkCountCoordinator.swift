import Foundation

@MainActor
final class BulkCountCoordinator: ObservableObject {
    struct PendingAdjustment: Identifiable {
        var id: UUID { item.id }
        var item: InventoryItem
        var adjustment: Int
    }

    @Published private(set) var adjustments: [PendingAdjustment] = []

    private let inventoryService: InventoryService

    init(inventoryService: InventoryService) {
        self.inventoryService = inventoryService
    }

    func addAdjustment(for item: InventoryItem, adjustment: Int) {
        if let index = adjustments.firstIndex(where: { $0.item.id == item.id }) {
            var pending = adjustments[index]
            pending.adjustment += adjustment
            if pending.adjustment == 0 {
                adjustments.remove(at: index)
            } else {
                adjustments[index] = pending
            }
        } else {
            adjustments.append(PendingAdjustment(item: item, adjustment: adjustment))
        }
    }

    func commit() async {
        for pending in adjustments {
            let target = max(0, pending.item.quantity + pending.adjustment)
            await inventoryService.adjustQuantity(itemID: pending.item.id, to: target)
        }
        adjustments.removeAll()
    }

    func reset() {
        adjustments.removeAll()
    }
}
