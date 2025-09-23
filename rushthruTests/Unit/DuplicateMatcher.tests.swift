import XCTest
@testable import rushthru

final class DuplicateMatcherTests: XCTestCase {
    func testSimilarityIsPerfectForIdenticalIdentity() {
        let identity = ItemIdentity(name: "Azure Agave", type: "Tequila", sizeML: 750)
        XCTAssertEqual(DuplicateMatcher.similarity(between: identity, and: identity), 1.0, accuracy: 0.0001)
        XCTAssertTrue(DuplicateMatcher.shouldMerge(lhs: identity, rhs: identity))
    }

    func testSimilarityPenalizesDifferences() {
        let lhs = ItemIdentity(name: "Azure Agave", type: "Tequila", sizeML: 750)
        let rhs = ItemIdentity(name: "Azure Agave", type: "Whiskey", sizeML: 750)
        XCTAssertLessThan(DuplicateMatcher.similarity(between: lhs, and: rhs), 1.0)
        XCTAssertFalse(DuplicateMatcher.shouldMerge(lhs: lhs, rhs: rhs))
    }

    func testStringSimilarityHandlesInsertions() {
        let lhs = ItemIdentity(name: "Trailhead Bourbon", type: "Whiskey", sizeML: 750)
        let rhs = ItemIdentity(name: "Trailhead Bourbn", type: "Whiskey", sizeML: 750)
        XCTAssertGreaterThan(DuplicateMatcher.similarity(between: lhs, and: rhs), 0.9)
    }
}
