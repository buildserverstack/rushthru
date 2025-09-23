import XCTest
@testable import rushthru

@MainActor
final class RefillViewModelTests: XCTestCase {
    private var activity: ActivityLogViewModel!
    private var locations: LocationsViewModel!
    private var inventory: InventoryService!
    private var shelfRecognizer: ShelfRecognizerStub!
    private var refill: RefillViewModel!

    override func setUp() async throws {
        try await super.setUp()
        activity = ActivityLogViewModel()
        locations = LocationsViewModel(activityLogger: activity)
        await locations.bootstrap()
        inventory = InventoryService(activityLogger: activity, locationCoordinator: locations)
        await inventory.bootstrap()
        shelfRecognizer = ShelfRecognizerStub()
        refill = RefillViewModel(inventoryService: inventory, shelfRecognizer: shelfRecognizer)
    }

    override func tearDown() {
        refill = nil
        shelfRecognizer = nil
        inventory = nil
        locations = nil
        activity = nil
        super.tearDown()
    }

    func testAddManualTaskLinksExistingItem() async {
        let item = await seedItem(name: "Azure Agave", quantity: 2)
        refill.addManualTask(name: "Azure Agave", quantity: 1)
        XCTAssertEqual(refill.manualTasks.count, 1)
        XCTAssertEqual(refill.manualTasks.first?.linkedItemID, item.id)
        XCTAssertEqual(refill.manualTasks.first?.availableQuantity, item.quantity)
    }

    func testStrikeReducesInventoryQuantity() async {
        let item = await seedItem(quantity: 5)
        await refill.strike(itemID: item.id, movedQuantity: 3)
        await Task.yield()
        let updated = inventory.item(id: item.id)
        XCTAssertEqual(updated?.quantity, 2)
    }

    func testSuggestionsFilterByTokens() async {
        _ = await seedItem(name: "Trailhead Bourbon", quantity: 1)
        _ = await seedItem(name: "Azure Agave", quantity: 1)
        let results = refill.suggestions(for: "trail bourbon")
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.name, "Trailhead Bourbon")
    }

    func testAnalyzeShelfPromotesDeficitToSuggestion() async {
        let item = await seedItem(name: "Trailhead Bourbon", quantity: 1, minimum: 4)
        await shelfRecognizer.setResult(.success([
            ShelfRecognitionCandidate(itemID: item.id, name: item.displayName, availableQuantity: item.quantity, suggestedQuantity: 1, confidence: 0.9)
        ]))
        await refill.analyzeShelfImage(Data())
        XCTAssertEqual(refill.shelfSuggestions.count, 1)
        XCTAssertEqual(refill.shelfSuggestions.first?.suggestedQuantity, 3)
        XCTAssertFalse(refill.shelfSuggestions.first?.isCapacityBased ?? true)
    }

    func testAnalyzeShelfFailureSurfacesError() async {
        await shelfRecognizer.setResult(.failure(TestError.shelfFailure))
        await refill.analyzeShelfImage(Data())
        XCTAssertTrue(refill.shelfSuggestions.isEmpty)
        XCTAssertEqual(refill.shelfScanError, "Shelf analysis failed. Please try again.")
    }

    func testApplyShelfSuggestionAddsManualTask() async {
        let item = await seedItem(name: "Azure Agave", quantity: 0, minimum: 4)
        let suggestion = ShelfSuggestion(itemID: item.id, displayName: item.displayName, suggestedQuantity: 4, availableQuantity: 0, confidence: 0.8)
        refill.applyShelfSuggestion(suggestion)
        XCTAssertTrue(refill.shelfSuggestions.isEmpty)
        XCTAssertEqual(refill.manualTasks.count, 1)
        XCTAssertEqual(refill.manualTasks.first?.linkedItemID, item.id)
    }

    @discardableResult
    private func seedItem(name: String = "Azure Agave", quantity: Int, minimum: Int = 0) async -> InventoryItem {
        let storeID = locations.selectedStoreID!
        let item = InventoryItem(name: name, type: "Tequila", sizeML: 750, quantity: quantity, minimum: minimum, storeID: storeID)
        await inventory.create(item: item)
        return inventory.item(id: item.id)!
    }

    private enum TestError: Error { case shelfFailure }
}

actor ShelfRecognizerStub: ShelfRecognizing {
    private var result: Result<[ShelfRecognitionCandidate], Error>

    init(result: Result<[ShelfRecognitionCandidate], Error> = .success([])) {
        self.result = result
    }

    func setResult(_ result: Result<[ShelfRecognitionCandidate], Error>) {
        self.result = result
    }

    func analyzeShelf(imageData: Data, inventory: [ShelfInventorySnapshot]) async throws -> [ShelfRecognitionCandidate] {
        switch result {
        case .success(let candidates):
            return candidates
        case .failure(let error):
            throw error
        }
    }
}
