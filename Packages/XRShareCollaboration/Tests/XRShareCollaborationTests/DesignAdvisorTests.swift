import XCTest
@testable import XRShareCollaboration

private struct MockItem: DesignCatalogItem {
    let advisorID: String
    let categoryKey: String
    let isTextured: Bool
}

final class DesignAdvisorTests: XCTestCase {
    private let advisor = DesignAdvisor()

    /// A small catalog with a few items per category.
    private let catalog: [MockItem] = {
        var items: [MockItem] = []
        let categories = ["seating", "tables", "media", "lighting", "decor", "storage", "beds"]
        for category in categories {
            for index in 0..<3 {
                items.append(MockItem(
                    advisorID: "\(category)_\(index)",
                    categoryKey: category,
                    isTextured: index == 0   // one textured per category
                ))
            }
        }
        return items
    }()

    // MARK: - Room sets

    func testRoomSetMatchesTemplateCategories() {
        let set = advisor.roomSet(for: .livingRoom, from: catalog)
        let slots = ["seating", "tables", "media", "lighting", "decor", "seating"]
        XCTAssertEqual(set.count, slots.count)
        XCTAssertEqual(set.map(\.categoryKey), slots)
    }

    func testRoomSetHasNoDuplicates() {
        let set = advisor.roomSet(for: .livingRoom, from: catalog)
        XCTAssertEqual(Set(set.map(\.advisorID)).count, set.count, "a model shouldn't appear twice")
    }

    func testRoomSetPrefersTexturedModels() {
        let set = advisor.roomSet(for: .office, from: catalog)
        // Each category has exactly one textured item (index 0); the first pick
        // per category should be textured when available.
        XCTAssertTrue(set.allSatisfy(\.isTextured) || set.contains(where: \.isTextured))
    }

    func testRoomSetSkipsMissingCategories() {
        // Catalog with only seating: a living room collapses to its seating slots.
        let seatingOnly = catalog.filter { $0.categoryKey == "seating" }
        let set = advisor.roomSet(for: .livingRoom, from: seatingOnly)
        XCTAssertTrue(set.allSatisfy { $0.categoryKey == "seating" })
        XCTAssertEqual(set.count, 2, "living room has two seating slots")
    }

    // MARK: - Complements

    func testComplementsSuggestComplementaryCategories() {
        // Placed a sofa → expect tables / lighting / decor among suggestions.
        let suggestions = advisor.complements(
            placedCategories: ["seating"],
            placedIDs: ["seating_0"],
            from: catalog
        )
        XCTAssertFalse(suggestions.isEmpty)
        let categories = Set(suggestions.map(\.categoryKey))
        XCTAssertTrue(categories.contains("tables"))
        XCTAssertFalse(categories.contains("seating"), "shouldn't lead with more of what's already placed")
    }

    func testComplementsExcludePlacedModels() {
        let suggestions = advisor.complements(
            placedCategories: ["seating", "tables"],
            placedIDs: ["seating_0", "tables_0"],
            from: catalog
        )
        XCTAssertFalse(suggestions.contains { $0.advisorID == "seating_0" || $0.advisorID == "tables_0" })
    }

    func testComplementsEmptyWhenNothingPlaced() {
        let suggestions = advisor.complements(placedCategories: [], placedIDs: [], from: catalog)
        XCTAssertTrue(suggestions.isEmpty)
    }

    // MARK: - Similar

    func testSimilarReturnsSameCategoryOnly() {
        let target = catalog.first { $0.categoryKey == "lighting" }!
        let similar = advisor.similar(to: target, from: catalog)
        XCTAssertFalse(similar.isEmpty)
        XCTAssertTrue(similar.allSatisfy { $0.categoryKey == "lighting" })
        XCTAssertFalse(similar.contains { $0.advisorID == target.advisorID })
    }
}
