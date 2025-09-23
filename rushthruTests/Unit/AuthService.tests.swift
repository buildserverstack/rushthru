import XCTest
@testable import rushthru

@MainActor
final class AuthServiceTests: XCTestCase {
    private var auth: AuthService!

    override func setUp() async throws {
        try await super.setUp()
        auth = AuthService()
    }

    override func tearDown() {
        auth = nil
        super.tearDown()
    }

    func testBootstrapUnlocksWhenPinMissing() async {
        await auth.bootstrap()
        XCTAssertFalse(auth.isLocked)
        XCTAssertEqual(auth.state, .unlocked)
    }

    func testVerifySetsAndValidatesPin() async throws {
        auth.setPIN("1234")
        XCTAssertThrowsError(try await auth.verify(pin: "0000"))
        XCTAssertEqual(auth.failedAttempts, 1)

        try await auth.verify(pin: "1234")
        XCTAssertFalse(auth.isLocked)
        XCTAssertNil(auth.cooldownUntil)
        XCTAssertEqual(auth.failedAttempts, 0)
    }

    func testCooldownTriggersAfterFiveFailures() async {
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

    func testShouldAutoLockEvaluatesInactivityInterval() {
        auth.autoLockMinutes = 1
        let recent = Date().addingTimeInterval(-30)
        XCTAssertFalse(auth.shouldAutoLock(lastInteraction: recent))

        let stale = Date().addingTimeInterval(-120)
        XCTAssertTrue(auth.shouldAutoLock(lastInteraction: stale))
    }
}
