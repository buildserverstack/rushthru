import XCTest
@testable import rushthru

@MainActor
final class SearchCoordinatorTests: XCTestCase {
    private var activity: ActivityLogCoordinator!
    private var locations: LocationCoordinator!
    private var inventory: InventoryService!
    private var defaults: UserDefaults!
    private var coordinator: SearchCoordinator!
    private var suiteName: String!

    override func setUp() async throws {
        try await super.setUp()
        activity = ActivityLogCoordinator()
        locations = LocationCoordinator(activityLogger: activity)
        await locations.bootstrap()
        inventory = InventoryService(activityLogger: activity, locationCoordinator: locations)
        await inventory.bootstrap()
        suiteName = "SearchCoordinatorTests.\(UUID().uuidString)"
        if let suiteDefaults = UserDefaults(suiteName: suiteName) {
            defaults = suiteDefaults
            defaults.removePersistentDomain(forName: suiteName)
        } else {
            defaults = .standard
        }
        coordinator = SearchCoordinator(inventoryService: inventory, defaults: defaults)
    }

    override func tearDown() {
        if let suiteName, defaults !== UserDefaults.standard {
            defaults?.removePersistentDomain(forName: suiteName)
        }
        coordinator = nil
        defaults = nil
        inventory = nil
        locations = nil
        activity = nil
        super.tearDown()
    }

    func testPerformSearchFiltersByQueryTypeAndSize() async {
        let storeID = locations.selectedStoreID!
        await inventory.create(item: InventoryItem(name: "Trailhead Bourbon", type: "Whiskey", sizeML: 750, quantity: 5, minimum: 1, storeID: storeID))
        await inventory.create(item: InventoryItem(name: "Azure Agave", type: "Tequila", sizeML: 1000, quantity: 3, minimum: 1, storeID: storeID))

        coordinator.query = "trail"
        coordinator.selectedType = "Whiskey"
        coordinator.selectedSize = 750
        XCTAssertEqual(coordinator.results.count, 1)
        XCTAssertEqual(coordinator.results.first?.name, "Trailhead Bourbon")

        coordinator.query = "agave"
        coordinator.selectedType = nil
        coordinator.selectedSize = nil
        XCTAssertEqual(coordinator.results.count, 1)
        XCTAssertEqual(coordinator.results.first?.name, "Azure Agave")
    }

    func testHistoryPersistsAndCapsAtTenEntries() {
        for index in 0..<12 {
            let query = "Query \(index)"
            coordinator.addToHistory(query)
        }
        XCTAssertEqual(coordinator.history.count, 10)
        XCTAssertEqual(coordinator.history.first?.query, "Query 11")

        coordinator.clearHistory()
        XCTAssertTrue(coordinator.history.isEmpty)
    }
}
