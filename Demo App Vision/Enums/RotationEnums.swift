// Define enums for model rotation axis
// This is rotation ABOUT that axis

enum RotationAxis: String, Codable {
    case yOnly      // VERTICAL ONLY
    case all        // Full 3D rotation
    case none       // Fixed orientation (picture frame doesn't need to rotate at all)
    case xOnly      // pitch
    case zOnly      // roll
    
    var description: String {
        switch self {
        case .yOnly: return "Vertical Rotation"
        case .all: return "Free Rotation"
        case .none: return "No Rotation"
        case .xOnly: return "Horizontal Rotation"
        case .zOnly: return "Side Rotation"
        }
    }
}
