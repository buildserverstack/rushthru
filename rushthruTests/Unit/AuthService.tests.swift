import XCTest
@testable import rushthru

@MainActor
final class AuthServiceTests: XCTestCase {
    private var database: DatabaseManager!
    private var auth: AuthService!

    override func setUp() async throws {
        try await super.setUp()
        database = DatabaseManager()
        database.resetForTesting()
        auth = AuthService(database: database)
    }

    override func tearDown() {
        auth = nil
        database = nil
        super.tearDown()
    }

    func testBootstrapUnlocksWhenPinMissing() async {
        await auth.bootstrap()
        XCTAssertFalse(auth.isLocked)
        XCTAssertEqual(auth.state, .unlocked)
        XCTAssertFalse(auth.hasPIN)
    }

    func testVerifySetsAndValidatesPin() async throws {
        await auth.bootstrap()
        auth.setPIN("1234")
        XCTAssertTrue(auth.hasPIN)
        XCTAssertTrue(auth.isLocked)
        XCTAssertThrowsError(try await auth.verify(pin: "0000"))
        XCTAssertEqual(auth.failedAttempts, 1)

        try await auth.verify(pin: "1234")
        XCTAssertFalse(auth.isLocked)
        XCTAssertNil(auth.cooldownUntil)
        XCTAssertEqual(auth.failedAttempts, 0)
    }

    func testCooldownTriggersAfterFiveFailures() async {
        await auth.bootstrap()
        auth.setPIN("2468")
        for _ in 0..<5 {
            XCTAssertThrowsError(try await auth.verify(pin: "1357"))
        }
        XCTAssertNotNil(auth.cooldownUntil)
        do {
            _ = try await auth.verify(pin: "2468")
            XCTFail("Expected cooldown error")
        } catch let error as AuthService.AuthError {
            if case .cooldownActive = error {
                // expected
            } else {
                XCTFail("Unexpected error: \(error)")
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testShouldAutoLockEvaluatesInactivityInterval() async {
        await auth.bootstrap()
        auth.setPIN("1111")
        auth.autoLockMinutes = 1
        let recent = Date().addingTimeInterval(-30)
        XCTAssertFalse(auth.shouldAutoLock(lastInteraction: recent))

        let stale = Date().addingTimeInterval(-120)
        XCTAssertTrue(auth.shouldAutoLock(lastInteraction: stale))
    }

    func testClearPinRemovesLock() async {
        await auth.bootstrap()
        auth.setPIN("1357")
        auth.clearPIN()
        XCTAssertFalse(auth.hasPIN)
        XCTAssertFalse(auth.isLocked)
        XCTAssertEqual(auth.failedAttempts, 0)
        XCTAssertNil(auth.cooldownUntil)
    }

    func testBootstrapRestoresStoredPinAndLocks() async {
        await auth.bootstrap()
        auth.setPIN("9876")
        XCTAssertTrue(auth.isLocked)
        try? await auth.verify(pin: "9876")
        XCTAssertFalse(auth.isLocked)

        let freshAuth = AuthService(database: database)
        await freshAuth.bootstrap()
        XCTAssertTrue(freshAuth.hasPIN)
        XCTAssertTrue(freshAuth.isLocked)
        XCTAssertEqual(freshAuth.failedAttempts, 0)
    }
}
