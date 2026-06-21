import XCTest
import simd
@testable import DesignSphere

final class ProjectDataTests: XCTestCase {
    func testCurrentProjectRoundTripsAllPersistedFields() throws {
        let projectID = UUID()
        let anchorID = UUID()
        let created = Date(timeIntervalSince1970: 1_700_000_000)
        let modified = created.addingTimeInterval(60)
        let material = ProjectData.SavedMaterial(
            baseColorR: 0.1,
            baseColorG: 0.2,
            baseColorB: 0.3,
            baseColorA: 0.4,
            roughness: 0.5,
            metallic: 0.6,
            specular: 0.7,
            materialType: .wood
        )
        let savedModel = ProjectData.SavedModel(
            id: projectID,
            modelTypeName: "chair",
            position: .init(SIMD3<Float>(1, 2, 3)),
            rotation: .init(simd_quatf(angle: .pi / 3, axis: SIMD3<Float>(0, 1, 0))),
            scale: .init(SIMD3<Float>(0.5, 1.5, 2.5)),
            material: material,
            originalBounds: .init(SIMD3<Float>(4, 5, 6))
        )
        let original = ProjectData(
            roomName: "Living Room",
            worldAnchorID: anchorID,
            dateCreated: created,
            dateModified: modified,
            models: [savedModel]
        )

        let decoded = try JSONDecoder().decode(ProjectData.self, from: JSONEncoder().encode(original))
        XCTAssertEqual(decoded.schemaVersion, ProjectData.currentSchemaVersion)
        XCTAssertEqual(decoded.roomName, "Living Room")
        XCTAssertEqual(decoded.worldAnchorID, anchorID)
        XCTAssertEqual(decoded.dateCreated, created)
        XCTAssertEqual(decoded.dateModified, modified)
        XCTAssertEqual(decoded.models.count, 1)
        XCTAssertEqual(decoded.models[0].id, projectID)
        XCTAssertEqual(decoded.models[0].modelTypeName, "chair")
        XCTAssertEqual(decoded.models[0].position.simd3, SIMD3<Float>(1, 2, 3))
        XCTAssertEqual(decoded.models[0].scale.simd3, SIMD3<Float>(0.5, 1.5, 2.5))
        XCTAssertEqual(decoded.models[0].originalBounds?.simd3, SIMD3<Float>(4, 5, 6))
        XCTAssertEqual(decoded.models[0].material?.materialType, .wood)
        XCTAssertEqual(decoded.models[0].material?.roughness, 0.5)
    }

    func testLegacyProjectWithoutSchemaVersionDefaultsToVersionOne() throws {
        let json = """
        {
          "roomName": "Legacy",
          "dateCreated": 0,
          "dateModified": 10,
          "models": []
        }
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        let project = try decoder.decode(ProjectData.self, from: Data(json.utf8))
        XCTAssertEqual(project.schemaVersion, 1)
        XCTAssertEqual(project.roomName, "Legacy")
        XCTAssertNil(project.worldAnchorID)
        XCTAssertTrue(project.models.isEmpty)
    }

    func testVectorConversionPreservesComponents() {
        let source = SIMD3<Float>(-.infinity, 0.25, .greatestFiniteMagnitude)
        let converted = ProjectData.Vector3(source).simd3
        XCTAssertEqual(converted.x, source.x)
        XCTAssertEqual(converted.y, source.y)
        XCTAssertEqual(converted.z, source.z)
    }

    func testQuaternionConversionPreservesVector() {
        let source = simd_normalize(simd_quatf(ix: 0.1, iy: 0.2, iz: 0.3, r: 0.4))
        let converted = ProjectData.Quaternion(source).quatf
        XCTAssertEqual(converted.vector.x, source.vector.x, accuracy: 0.0001)
        XCTAssertEqual(converted.vector.y, source.vector.y, accuracy: 0.0001)
        XCTAssertEqual(converted.vector.z, source.vector.z, accuracy: 0.0001)
        XCTAssertEqual(converted.vector.w, source.vector.w, accuracy: 0.0001)
    }

    func testMaterialTypesRoundTripRawValues() throws {
        for type in [ProjectData.MaterialType.wood, .metal, .fabric, .leather, .custom] {
            let data = try JSONEncoder().encode(type)
            XCTAssertEqual(try JSONDecoder().decode(ProjectData.MaterialType.self, from: data), type)
        }
    }
}
