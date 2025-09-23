import XCTest
@testable import rushthru

@MainActor
final class ActivityLogCoordinatorTests: XCTestCase {
    private var coordinator: ActivityLogCoordinator!

    override func setUp() async throws {
        try await super.setUp()
        coordinator = ActivityLogCoordinator()
    }

    override func tearDown() {
        coordinator = nil
        super.tearDown()
    }

    func testLogInsertsEntryAtTop() {
        coordinator.log(action: .create, entity: .item, entityID: UUID(), before: nil, after: nil)
        coordinator.log(action: .edit, entity: .item, entityID: UUID(), before: nil, after: nil)

        XCTAssertEqual(coordinator.entries.count, 2)
        if coordinator.entries.count == 2 {
            XCTAssertEqual(coordinator.entries[0].action, .edit)
            XCTAssertEqual(coordinator.entries[1].action, .create)
        }
    }

    func testCompactRemovesEntriesBeforeCutoff() {
        coordinator.log(action: .create, entity: .item, entityID: UUID(), before: nil, after: nil)
        coordinator.log(action: .edit, entity: .item, entityID: UUID(), before: nil, after: nil)

        XCTAssertEqual(coordinator.entries.count, 2)
        coordinator.compact(olderThan: Date().addingTimeInterval(1))
        XCTAssertTrue(coordinator.entries.isEmpty)
    }
}
