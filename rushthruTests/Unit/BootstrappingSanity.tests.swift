import XCTest
@testable import rushthru

final class BootstrappingSanityTests: XCTestCase {
    func testDefaultFlagsEnableAllFeatures() {
        let flags = FeatureFlags()
        for flag in FeatureFlag.allCases {
            XCTAssertTrue(flags.isEnabled(flag))
        }
    }

    func testBootStateTransitions() {
        var flags = FeatureFlags()
        XCTAssertEqual(flags.bootState, .coldStart)
        flags.bootState = .running
        XCTAssertEqual(flags.bootState, .running)
        flags.bootState = .degraded(reason: "Database unavailable")
        XCTAssertTrue(flags.bootState.isDegraded)
    }
}
