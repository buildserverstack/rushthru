import XCTest
@testable import rushthru

@MainActor
final class LocationsViewModelTests: XCTestCase {
    private var activity: ActivityLogViewModel!
    private var coordinator: LocationsViewModel!

    override func setUp() async throws {
        try await super.setUp()
        activity = ActivityLogViewModel()
        coordinator = LocationsViewModel(activityLogger: activity)
    }

    override func tearDown() {
        coordinator = nil
        activity = nil
        super.tearDown()
    }

    func testBootstrapCreatesDefaultStore() async {
        XCTAssertTrue(coordinator.stores.isEmpty)
        await coordinator.bootstrap()
        XCTAssertFalse(coordinator.stores.isEmpty)
        XCTAssertNotNil(coordinator.selectedStoreID)
    }

    func testCreateStorePreventsDuplicates() async {
        await coordinator.bootstrap()
        let created = await coordinator.createStore(named: "Downtown")
        XCTAssertTrue(created)
        let duplicate = await coordinator.createStore(named: "downtown")
        XCTAssertFalse(duplicate)
        XCTAssertEqual(coordinator.stores.count, 2)
    }

    func testDeleteRemovesLocation() async {
        await coordinator.bootstrap()
        let newStore = LocationNode(parentID: nil, kind: .store, name: "Airport", path: "Airport")
        await coordinator.upsert(location: newStore)
        XCTAssertTrue(coordinator.stores.contains { $0.id == newStore.id })
        await coordinator.delete(locationID: newStore.id)
        XCTAssertFalse(coordinator.stores.contains { $0.id == newStore.id })
    }
}
