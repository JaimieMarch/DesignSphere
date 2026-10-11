import Foundation
import simd

/// Represents a saved project with all its models and world anchor
struct ProjectData: Codable {
    /// Current schema version - increment when making breaking changes to the data structure
    static let currentSchemaVersion = 1
    static let filesDidChangeNotification = Notification.Name("ProjectData.filesDidChange")

    /// Schema version of this project file (for migration support)
    let schemaVersion: Int

    var roomName: String
    let worldAnchorID: UUID?
    let dateCreated: Date
    var dateModified: Date
    var models: [SavedModel]

    /// Shared by normal loading and backup restoration, before touching the scene.
    func validate() throws {
        guard (1...Self.currentSchemaVersion).contains(schemaVersion),
              Self.isValidName(roomName),
              models.count <= 10_000,
              Set(models.map(\.id)).count == models.count,
              dateCreated.timeIntervalSinceReferenceDate.isFinite,
              dateModified.timeIntervalSinceReferenceDate.isFinite,
              models.allSatisfy({ model in
                  Self.isValidName(model.modelTypeName)
                      && [model.position.x, model.position.y, model.position.z].allSatisfy(\.isFinite)
                      && [model.rotation.x, model.rotation.y, model.rotation.z, model.rotation.w].allSatisfy(\.isFinite)
                      && abs(simd_length(model.rotation.quatf.vector) - 1) < 0.01
                      && [model.scale.x, model.scale.y, model.scale.z].allSatisfy { $0.isFinite && $0 > 0 }
                      && (model.originalBounds.map {
                          [$0.x, $0.y, $0.z].allSatisfy { $0.isFinite && $0 > 0 }
                      } ?? true)
                      && (model.material.map {
                          [$0.baseColorR, $0.baseColorG, $0.baseColorB, $0.baseColorA]
                              .allSatisfy { $0.isFinite && (0...1).contains($0) }
                              && [$0.roughness, $0.metallic, $0.specular].allSatisfy {
                                  $0.map { $0.isFinite && (0...1).contains($0) } ?? true
                              }
                      } ?? true)
              }) else { throw ProjectError.invalidData }
    }

    static func isValidName(_ name: String) -> Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && name.utf8.count <= 255
            && !name.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains)
    }

    /// Leave space for import suffixes and the extension within filesystem limits.
    static func fileStem(for roomName: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: " _-"))
        let filtered = roomName.unicodeScalars.map { allowed.contains($0) ? Character($0) : "-" }
        var result = String(filtered).replacingOccurrences(of: "--", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        while result.utf8.count > 180 { result.removeLast() }
        return result.isEmpty ? "Project" : result
    }

    /// Standard initializer with current schema version
    init(roomName: String, worldAnchorID: UUID?, dateCreated: Date, dateModified: Date, models: [SavedModel]) {
        self.schemaVersion = Self.currentSchemaVersion
        self.roomName = roomName
        self.worldAnchorID = worldAnchorID
        self.dateCreated = dateCreated
        self.dateModified = dateModified
        self.models = models
    }

    /// Custom decoder to handle legacy projects without schemaVersion
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        // Handle missing schemaVersion for backwards compatibility with existing projects
        self.schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1

        self.roomName = try container.decode(String.self, forKey: .roomName)
        self.worldAnchorID = try container.decodeIfPresent(UUID.self, forKey: .worldAnchorID)
        self.dateCreated = try container.decode(Date.self, forKey: .dateCreated)
        self.dateModified = try container.decode(Date.self, forKey: .dateModified)
        self.models = try container.decode([SavedModel].self, forKey: .models)

        // Future: Add migration logic here when schemaVersion changes
        // if schemaVersion < 2 { ... migrate data ... }
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, roomName, worldAnchorID, dateCreated, dateModified, models
    }

    struct SavedModel: Codable, Identifiable {
        let id: UUID
        let modelTypeName: String
        let position: Vector3
        let rotation: Quaternion
        let scale: Vector3
        let material: SavedMaterial?
        let originalBounds: Vector3?  // Stores original unscaled dimensions for accurate editing
    }

    /// Material type for explicit tracking
    enum MaterialType: String, Codable {
        case wood
        case metal
        case fabric
        case leather
        case custom  // For color-only or user-modified materials
    }

    /// Represents saved material properties
    struct SavedMaterial: Codable {
        let baseColorR: Float
        let baseColorG: Float
        let baseColorB: Float
        let baseColorA: Float
        let roughness: Float?
        let metallic: Float?
        let specular: Float?
        let materialType: MaterialType?  // Explicit material type instead of inferring
    }

    /// Helper struct for encoding SIMD3<Float>
    struct Vector3: Codable {
        let x: Float
        let y: Float
        let z: Float

        init(_ simd: SIMD3<Float>) {
            self.x = simd.x
            self.y = simd.y
            self.z = simd.z
        }

        var simd3: SIMD3<Float> {
            SIMD3<Float>(x, y, z)
        }
    }

    /// Helper struct for encoding simd_quatf
    struct Quaternion: Codable {
        let x: Float
        let y: Float
        let z: Float
        let w: Float

        init(_ quat: simd_quatf) {
            self.x = quat.imag.x
            self.y = quat.imag.y
            self.z = quat.imag.z
            self.w = quat.real
        }

        var quatf: simd_quatf {
            simd_quatf(ix: x, iy: y, iz: z, r: w)
        }
    }
}
