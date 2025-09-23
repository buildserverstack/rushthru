import XCTest
@testable import rushthru

@MainActor
final class CSVViewModelTests: XCTestCase {
    private var activity: ActivityLogViewModel!
    private var locations: LocationsViewModel!
    private var inventory: InventoryService!
    private var coordinator: CSVViewModel!

    override func setUp() async throws {
        try await super.setUp()
        activity = ActivityLogViewModel()
        locations = LocationsViewModel(activityLogger: activity)
        await locations.bootstrap()
        inventory = InventoryService(activityLogger: activity, locationCoordinator: locations)
        await inventory.bootstrap()
        coordinator = CSVViewModel(inventoryService: inventory, locationCoordinator: locations, activityLogger: activity)
    }

    override func tearDown() {
        coordinator = nil
        inventory = nil
        locations = nil
        activity = nil
        super.tearDown()
    }

    func testExportIncludesHeaderAndLogsActivity() async {
        let storeID = locations.selectedStoreID!
        await inventory.create(item: InventoryItem(name: "Azure Agave", type: "Tequila", sizeML: 750, quantity: 2, minimum: 0, storeID: storeID))
        let csv = coordinator.exportInventory()
        XCTAssertTrue(csv.contains("id,name,sub_name,type,size,quantity,aisle,shelf,row,column"))
        XCTAssertTrue(csv.contains("Azure Agave"))
        XCTAssertEqual(activity.entries.first?.action, .export)
    }

    func testValidateDetectsMissingColumns() {
        let issues = coordinator.validate(csv: "name,type\nSample,Whiskey")
        XCTAssertFalse(issues.isEmpty)
        XCTAssertEqual(coordinator.lastValidationIssues.count, issues.count)
    }

    func testReplaceInventoryParsesRows() async throws {
        let header = "id,name,sub_name,type,size,quantity,aisle,shelf,row,column"
        let row = "\(UUID().uuidString),Trailhead Bourbon,,Whiskey,750,5,Aisle 1,Shelf 1,Row 1,Column 1"
        let csv = "\(header)\n\(row)"
        try await coordinator.replaceInventory(with: csv)
        XCTAssertEqual(inventory.items.count, 1)
        XCTAssertEqual(inventory.items.first?.name, "Trailhead Bourbon")
        XCTAssertEqual(coordinator.lastImportSummary?.importedItems, 1)
        XCTAssertEqual(activity.entries.first?.action, .import)
    }

    func testReplaceInventoryThrowsOnValidationFailure() async {
        await XCTAssertThrowsErrorAsync(try await coordinator.replaceInventory(with: "name\nSample"))
        XCTAssertFalse(coordinator.lastValidationIssues.isEmpty)
    }
}

private func XCTAssertThrowsErrorAsync<T>(_ expression: @autoclosure () async throws -> T) async {
    do {
        _ = try await expression()
        XCTFail("Expected error to be thrown")
    } catch {
        // expected
    }
}
