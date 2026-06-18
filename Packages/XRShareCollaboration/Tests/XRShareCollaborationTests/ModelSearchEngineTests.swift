import XCTest
@testable import XRShareCollaboration

/// A lightweight stand-in for a catalog model, since ModelDescriptor's init is
/// not accessible outside its defining module.
private struct MockModel: ModelSearchable {
    let searchName: String
    let searchCategoryKey: String
}

final class ModelSearchEngineTests: XCTestCase {
    private let engine = ModelSearchEngine()

    /// Mirrors the shipped 9-model catalog (name + ModelCategory.rawValue).
    private let catalog: [MockModel] = [
        MockModel(searchName: "65 In TV", searchCategoryKey: "media"),
        MockModel(searchName: "Chair", searchCategoryKey: "seating"),
        MockModel(searchName: "Chandelier", searchCategoryKey: "lighting"),
        MockModel(searchName: "Closet", searchCategoryKey: "storage"),
        MockModel(searchName: "Coffee Table", searchCategoryKey: "tables"),
        MockModel(searchName: "Couch", searchCategoryKey: "seating"),
        MockModel(searchName: "Dinner Table", searchCategoryKey: "tables"),
        MockModel(searchName: "Stool", searchCategoryKey: "seating"),
        MockModel(searchName: "Vase", searchCategoryKey: "decor")
    ]

    private func results(_ query: String) -> [String] {
        engine.search(query, in: catalog).map(\.searchName)
    }

    // MARK: - Intent recall

    func testSynonymRecallsWholeSeatingCategory() {
        // The core ask: a seating term surfaces every seating item, not just
        // items whose name contains the query.
        let expected = Set(["Chair", "Couch", "Stool"])
        XCTAssertEqual(Set(results("sofa")), expected)
        XCTAssertEqual(Set(results("couch")), expected)
        XCTAssertEqual(Set(results("recliner")), expected)
        XCTAssertEqual(Set(results("seating")), expected)
        XCTAssertEqual(Set(results("chair")), expected)
    }

    func testCategoryIntentWords() {
        XCTAssertEqual(Set(results("table")), ["Coffee Table", "Dinner Table"])
        XCTAssertEqual(results("lighting"), ["Chandelier"])
        XCTAssertEqual(results("light"), ["Chandelier"])
        XCTAssertEqual(results("storage"), ["Closet"])
        XCTAssertEqual(results("decor"), ["Vase"])
        XCTAssertEqual(results("tv"), ["65 In TV"])
    }

    // MARK: - Ranking

    func testFullQueryCoverageRanksFirst() {
        // "coffee table" should rank the Coffee Table above the Dinner Table.
        XCTAssertEqual(results("coffee table"), ["Coffee Table", "Dinner Table"])
    }

    func testExactNameOutranksCategoryPeers() {
        // "stool" matches all seating, but the Stool itself should rank first.
        XCTAssertEqual(results("stool").first, "Stool")
    }

    // MARK: - Partial input

    func testPrefixTypingMatches() {
        XCTAssertEqual(Set(results("tabl")), ["Coffee Table", "Dinner Table"])
    }

    // MARK: - Precision (no false positives)

    func testUnrelatedQueriesReturnNothing() {
        XCTAssertTrue(results("banana").isEmpty)
        XCTAssertTrue(results("wood").isEmpty)
    }

    func testShortTokenDoesNotLeakAcrossCategories() {
        // Regression: the "in" in "65 In TV" must not match "seat-IN-g" or
        // "din-IN-g" as a substring.
        XCTAssertFalse(results("seating").contains("65 In TV"))
        XCTAssertFalse(results("dining").contains("65 In TV"))
    }

    // MARK: - Degenerate input

    func testEmptyQueryReturnsInputUnchanged() {
        XCTAssertEqual(results(""), catalog.map(\.searchName))
        XCTAssertEqual(results("   "), catalog.map(\.searchName))
    }
}
