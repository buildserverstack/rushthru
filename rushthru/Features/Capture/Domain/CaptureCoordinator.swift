import Foundation

@MainActor
final class CaptureCoordinator: ObservableObject {
    @Published private(set) var lastResult: OCRResult = .empty
    @Published var isProcessing: Bool = false

    private let inventoryService: InventoryService

    init(inventoryService: InventoryService) {
        self.inventoryService = inventoryService
    }

    func bootstrap() async {}

    func process(fields: NormalizedFields) async {
        if let exact = inventoryService.items.first(where: { $0.normalizedIdentity == fields.identity }) {
            await inventoryService.incrementQuantity(itemID: exact.id, delta: fields.initialQuantity)
            return
        }

        let candidates = inventoryService.items
            .map { ($0, DuplicateMatcher.similarity(between: $0.normalizedIdentity, and: fields.identity)) }
            .sorted { $0.1 > $1.1 }

        if let (candidate, score) = candidates.first, score >= 0.88 {
            await inventoryService.incrementQuantity(itemID: candidate.id, delta: fields.initialQuantity)
        } else {
            let newItem = InventoryItem(
                name: fields.name,
                subName: fields.subName,
                type: fields.type,
                sizeML: fields.sizeML,
                quantity: fields.initialQuantity,
                minimum: fields.minimum,
                primaryLocationID: nil
            )
            await inventoryService.create(item: newItem)
        }
    }
}

struct NormalizedFields {
    var name: String
    var subName: String
    var type: InventoryItem.ItemType
    var sizeML: Int
    var minimum: Int
    var initialQuantity: Int

    var identity: ItemIdentity {
        ItemIdentity(name: name, type: type, sizeML: sizeML)
    }
}
