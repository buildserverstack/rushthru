import XCTest
@testable import rushthru

@MainActor
final class BulkCountCoordinatorTests: XCTestCase {
    private var activity: ActivityLogCoordinator!
    private var locations: LocationCoordinator!
    private var inventory: InventoryService!
    private var coordinator: BulkCountCoordinator!

    override func setUp() async throws {
        try await super.setUp()
        activity = ActivityLogCoordinator()
        locations = LocationCoordinator(activityLogger: activity)
        await locations.bootstrap()
        inventory = InventoryService(activityLogger: activity, locationCoordinator: locations)
        await inventory.bootstrap()
        coordinator = BulkCountCoordinator(inventoryService: inventory)
    }

    override func tearDown() {
        coordinator = nil
        inventory = nil
        locations = nil
        activity = nil
        super.tearDown()
    }

    func testAddAdjustmentMergesQuantities() async {
        let item = await seedItem(quantity: 5)
        coordinator.addAdjustment(for: item, adjustment: 2)
        coordinator.addAdjustment(for: item, adjustment: -2)
        XCTAssertTrue(coordinator.adjustments.isEmpty)

        coordinator.addAdjustment(for: item, adjustment: -3)
        XCTAssertEqual(coordinator.adjustments.first?.adjustment, -3)
    }

    func testCommitAppliesAdjustmentsAndClears() async {
        let item = await seedItem(quantity: 5)
        coordinator.addAdjustment(for: item, adjustment: -2)
        await coordinator.commit()
        XCTAssertTrue(coordinator.adjustments.isEmpty)
        let updated = inventory.item(id: item.id)
        XCTAssertEqual(updated?.quantity, 3)
    }

    @discardableResult
    private func seedItem(quantity: Int) async -> InventoryItem {
        let storeID = locations.selectedStoreID!
        let item = InventoryItem(name: "Azure Agave", type: "Tequila", sizeML: 750, quantity: quantity, minimum: 0, storeID: storeID)
        await inventory.create(item: item)
        return inventory.item(id: item.id)!
    }
}
