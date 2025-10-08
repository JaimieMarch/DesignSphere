//
// SharePlayMessages.Swift
// XR Share
//
// The data that is exchanged between participants in a SharePlay session using GroupSessionMessenger
//


import Foundation
import simd


extension simd_quatf: Codable {
    public func encode(to encoder: Encoder) throws {
        var container = encoder.unkeyedContainer()
        try container.encode(imag.x)
        try container.encode(imag.y)
        try container.encode(imag.z)
        try container.encode(real)
    }
    
    
    public init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        let ix = try container.decode(Float.self)
        let iy = try container.decode(Float.self)
        let iz = try container.decode(Float.self)
        let r = try container.decode(Float.self)
        self.init(vector: SIMD4<Float>(ix, iy, iz, r))
    }
}

/// Universal transform for cross-platform coordinate system translation
struct UniversalTransform: Codable {
    let position: SIMD3<Float>
    let rotation: simd_quatf
    let scale: SIMD3<Float>
    let referenceAnchorID: UUID
    

    enum CodingKeys: CodingKey {
        case position
        case rotation
        case scale
        case referenceAnchorID
    }

    init(position: SIMD3<Float>, rotation: simd_quatf, scale: SIMD3<Float>, referenceAnchorID: UUID) {
        self.position = position
        self.rotation = rotation
        self.scale = scale
        self.referenceAnchorID = referenceAnchorID
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        position = try container.decode(SIMD3<Float>.self, forKey: .position)
        
        // Decode rotation as a 4-element float array
        let rotArray = try container.decode([Float].self, forKey: .rotation)
        if rotArray.count == 4 {
            rotation = simd_quatf(ix: rotArray[0], iy: rotArray[1], iz: rotArray[2], r: rotArray[3])
        } else {
            rotation = simd_quatf(angle: 0, axis: SIMD3<Float>(0, 1, 0))
        }
        scale = try container.decode(SIMD3<Float>.self, forKey: .scale)
        referenceAnchorID = try container.decode(UUID.self, forKey: .referenceAnchorID)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(position, forKey: .position)
        
        // Encode rotation as [ix, iy, iz, r]
        let rotArray = [rotation.imag.x, rotation.imag.y, rotation.imag.z, rotation.real]
        try container.encode(rotArray, forKey: .rotation)
        try container.encode(scale, forKey: .scale)
        try container.encode(referenceAnchorID, forKey: .referenceAnchorID)
    }
}

/// Message sent when a user adds a new model
struct AddModelMessage: Codable {
    let modelType: ModelType
    let instanceID: UUID
    let initialTransform: UniversalTransform
}


/// Message sent when a model is removed
struct RemoveModelMessage: Codable {
    let instanceID: UUID
}

/// Message sent when a model's transform is updated  (user rotates, drags, moves model)
struct ModelTransformMessage: Codable {
    let instanceID: UUID
    let newTransform: UniversalTransform
}

/// Message sent when ownership of a model changes
struct OwnershipChangeMessage: Codable {
    let entityID: UUID
    let newOwner: UUID
}

/// Message sent when a model is selected
struct SelectModelMessage: Codable {
    let entityID: UUID
    let participantID: UUID
}

/// Message sent to synchronize all models when a new participant joins
struct SyncAllModelsMessage: Codable {
    struct ModelState: Codable {
        let modelType: ModelType
        let instanceID: UUID
        let transform: UniversalTransform
        let ownerID: UUID?
    }
    let models: [ModelState]
    let referenceAnchorID: UUID
}

/// Message sent to request full state sync
struct RequestSyncMessage: Codable {
    let participantID: UUID
}


/// Message sent to share anchor information for spatial alignment
struct AnchorMessage: Codable {
    enum AnchorType: String, Codable {
        case worldAnchor   // visionOS: WorldAnchor
        case worldMap      // iOS: ARWorldMap
    }

    let anchorID: UUID
    let anchorType: AnchorType
    let anchorData: Data?
}

/// Versioned handshake for cross-app compatibility and capability discovery
struct ProtocolHandshakeMessage: Codable {
    let protocolVersion: Int
  
    
    let appName: String
    let platform: String
    
    // Sender identity so receivers can map capabilities to participants
    let senderID: UUID
    
    // Feature flags
    let supportsModelSync: Bool
    let supportsARWorldMap: Bool
    let supportsUnreliableTransforms: Bool
}
