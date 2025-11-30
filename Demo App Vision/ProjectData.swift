import Foundation
import simd

/// Represents a saved project with all its models and world anchor
struct ProjectData: Codable {
    let roomName: String
    let worldAnchorID: UUID?
    let dateCreated: Date
    var dateModified: Date
    var models: [SavedModel]

    struct SavedModel: Codable, Identifiable {
        let id: UUID
        let modelTypeName: String
        let position: Vector3
        let rotation: Quaternion
        let scale: Vector3
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
