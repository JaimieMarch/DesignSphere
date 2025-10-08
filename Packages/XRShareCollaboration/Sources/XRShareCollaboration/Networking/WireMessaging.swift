import Foundation

/// Stable message discriminator for visionOS
enum WireKind: String, Codable {
    case addModel
    case removeModel
    case modelTransform
    case selectModel
    case ownershipChange
    case syncAllModels
    case requestSync
    case anchor
    case protocolHandshake
  
}

struct WireEnvelope: Codable {
    let t: WireKind
    let message: Data
}

enum WireCodec {
    static func encode<M: Codable>(_ payload: M, kind: WireKind) throws -> Data {
        let payloadData = try jsonEncoder.encode(payload)
        let envelope = WireEnvelope(t: kind, message: payloadData)
        return try jsonEncoder.encode(envelope)
    }

    static func decodeEnvelope(_ data: Data) throws -> WireEnvelope {
        try jsonDecoder.decode(WireEnvelope.self, from: data)
    }

    // Shared encoder/decoder to ensure consistent strategies 
    private static let jsonEncoder: JSONEncoder = {
        let enc = JSONEncoder()
        
        // Keep default strategies
        return enc
    }()

    private static let jsonDecoder: JSONDecoder = {
        let dec = JSONDecoder()
        
        // Keep default strategies
        return dec
    }()
}




