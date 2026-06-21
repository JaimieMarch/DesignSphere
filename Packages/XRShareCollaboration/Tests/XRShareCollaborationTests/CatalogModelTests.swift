import XCTest
@testable import XRShareCollaboration

@available(visionOS 26.0, *)
final class CatalogModelTests: XCTestCase {

    /// The pipeline writes these category strings into catalog.json; the app
    /// maps them back with ModelCategory(rawValue:). This guards that contract.
    func testManifestCategoryStringsRoundTrip() {
        let pipelineCategories = ["seating", "beds", "storage", "lighting",
                                  "decor", "media", "tables", "unknown"]
        for raw in pipelineCategories {
            XCTAssertNotNil(
                CollaborativeSessionController.ModelCategory(rawValue: raw),
                "ModelCategory is missing a case for manifest category '\(raw)'"
            )
        }
    }

    func testEveryCategoryHasANonEmptyLabel() {
        for category in CollaborativeSessionController.ModelCategory.allCases {
            XCTAssertFalse(category.label.isEmpty, "\(category) has no label")
        }
    }

    func testEverySourceHasANonEmptyLabel() {
        for source in CollaborativeSessionController.ModelSource.allCases {
            XCTAssertFalse(source.label.isEmpty, "\(source) has no label")
        }
    }

    func testUnknownCategoryFallsBackForUnmappedString() {
        XCTAssertNil(CollaborativeSessionController.ModelCategory(rawValue: "spaceship"))
    }
}
