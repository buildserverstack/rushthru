import XCTest
@testable import rushthru

@MainActor
final class InventoryServiceTests: XCTestCase {
    private var activity: ActivityLogCoordinator!
    private var locations: LocationCoordinator!
    private var inventory: InventoryService!

    override func setUp() async throws {
        try await super.setUp()
        activity = ActivityLogCoordinator()
        locations = LocationCoordinator(activityLogger: activity)
        await locations.bootstrap()
        inventory = InventoryService(activityLogger: activity, locationCoordinator: locations)
        await inventory.bootstrap()
    }

    override func tearDown() {
        inventory = nil
        locations = nil
        activity = nil
        super.tearDown()
    }

    func testCreateRegistersTypeAndSize() async {
        let storeID = locations.selectedStoreID!
        let item = InventoryItem(
            name: "Trailhead Bourbon",
            subName: "Single Barrel",
            type: "Craft Whiskey",
            sizeML: 900,
            quantity: 6,
            minimum: 4,
            storeID: storeID,
            aisle: "Aisle 1",
            shelf: "Shelf 1",
            row: "Row 1",
            column: "Column 1"
        )
        await inventory.create(item: item)

        XCTAssertEqual(inventory.items.count, 1)
        let stored = inventory.items.first
        XCTAssertEqual(stored?.type.lowercased(), "craft whiskey")
        XCTAssertTrue(inventory.availableTypes.contains { ItemIdentity.normalizeType($0) == ItemIdentity.normalizeType("Craft Whiskey") })
        XCTAssertTrue(inventory.availableSizes.contains(900))
        XCTAssertTrue(inventory.customSizeOptions.contains(900))
    }

    func testIncrementQuantityDoesNotGoNegative() async {
        let item = await seededItem(quantity: 5)
        await inventory.incrementQuantity(itemID: item.id, delta: -10)
        let updated = inventory.item(id: item.id)
        XCTAssertEqual(updated?.quantity, 0)
    }

    func testExistingItemMatchingIdentity() async {
        let item = await seededItem(quantity: 2)
        let identity = item.normalizedIdentity
        let existing = inventory.existingItem(matching: identity)
        XCTAssertEqual(existing?.id, item.id)
    }

    func testRemoveCustomTypeFailsWhileInUse() async {
        let item = await seededItem(type: "Seasonal Spirits")
        XCTAssertFalse(inventory.removeCustomType("Seasonal Spirits").removed)
        await inventory.incrementQuantity(itemID: item.id, delta: -item.quantity)
        await inventory.update(item: InventoryItem(
            id: item.id,
            name: item.name,
            subName: item.subName,
            type: "Whiskey",
            sizeML: item.sizeML,
            quantity: 0,
            minimum: item.minimum,
            primaryLocationID: item.primaryLocationID,
            storeID: item.storeID,
            aisle: item.aisle,
            shelf: item.shelf,
            row: item.row,
            column: item.column
        ))
        let result = inventory.removeCustomType("Seasonal Spirits")
        XCTAssertTrue(result.removed)
    }

    func testCustomSizeRemovalRequiresUnusedSize() async {
        let item = await seededItem(size: 950)
        XCTAssertFalse(inventory.removeCustomSize(950).removed)

        await inventory.update(item: InventoryItem(
            id: item.id,
            name: item.name,
            subName: item.subName,
            type: item.type,
            sizeML: 750,
            quantity: item.quantity,
            minimum: item.minimum,
            primaryLocationID: item.primaryLocationID,
            storeID: item.storeID,
            aisle: item.aisle,
            shelf: item.shelf,
            row: item.row,
            column: item.column
        ))

        let result = inventory.removeCustomSize(950)
        XCTAssertTrue(result.removed)
        XCTAssertFalse(inventory.availableSizes.contains(950))
    }

    func testReplaceAllReassignsStoreAndClearsOldItems() async {
        _ = await seededItem(name: "Original", quantity: 1)
        let newItem = InventoryItem(
            name: "New Arrival",
            type: "Vodka",
            sizeML: 750,
            quantity: 3,
            minimum: 1,
            storeID: UUID()
        )
        await inventory.replaceAll(with: [newItem])

        XCTAssertEqual(inventory.items.count, 1)
        XCTAssertEqual(inventory.items.first?.name, "New Arrival")
        XCTAssertEqual(inventory.items.first?.storeID, locations.selectedStoreID)
    }

    @discardableResult
    private func seededItem(
        name: String = "Azure Agave",
        quantity: Int,
        type: String = "Tequila",
        size: Int = 750
    ) async -> InventoryItem {
        let storeID = locations.selectedStoreID!
        let item = InventoryItem(
            name: name,
            type: type,
            sizeML: size,
            quantity: quantity,
            minimum: 2,
            storeID: storeID
        )
        await inventory.create(item: item)
        return inventory.items.first { $0.id == item.id }!
    }
}
