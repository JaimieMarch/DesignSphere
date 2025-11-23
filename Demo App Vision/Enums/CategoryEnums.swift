// Define enums for model categories

enum Category: String, CaseIterable, Identifiable, Codable {
    case all = "All"
    case seating = "Seating"
    case tables = "Tables"
    case storage = "Storage"
    case lighting = "Lighting"
    case decor = "Decor"
    case beds = "Beds"
    case outdoor = "Outdoor"
    case rugs = "Rugs"
    // placeholder for future categories
    case other = "Other"
    
    var id: String { rawValue }
    
    var icon: String {
        switch self {
        case .all: return "square.grid.2x2"
        case .seating: return "chair.fill"
        case .tables: return "tablecells.fill"
        case .storage: return "cabinet.fill"
        case .lighting: return "lightbulb.fill"
        case .decor: return "leaf.fill"
        case .beds: return "bed.double.fill"
        case .outdoor: return "sun.max.fill"
        case .rugs: return "square.fill"
        case .other: return "questionmark.circle.fill"
        }
    }
}
