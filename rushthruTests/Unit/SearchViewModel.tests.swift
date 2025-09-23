import XCTest
@testable import rushthru

@MainActor
final class SearchViewModelTests: XCTestCase {
    private var activity: ActivityLogViewModel!
    private var locations: LocationsViewModel!
    private var inventory: InventoryService!
    private var defaults: UserDefaults!
    private var coordinator: SearchViewModel!
    private var suiteName: String!

    override func setUp() async throws {
        try await super.setUp()
        activity = ActivityLogViewModel()
        locations = LocationsViewModel(activityLogger: activity)
        await locations.bootstrap()
        inventory = InventoryService(activityLogger: activity, locationCoordinator: locations)
        await inventory.bootstrap()
        suiteName = "SearchViewModelTests.\(UUID().uuidString)"
        if let suiteDefaults = UserDefaults(suiteName: suiteName) {
            defaults = suiteDefaults
            defaults.removePersistentDomain(forName: suiteName)
        } else {
            defaults = .standard
        }
        coordinator = SearchViewModel(inventoryService: inventory, defaults: defaults)
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
