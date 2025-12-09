// Define style categories for models throughout the UI
// Currently unused - may be useful in the future

enum Style: String, CaseIterable, Identifiable, Codable {
    case modern = "Modern"
    case classic = "Classic"
    case industrial = "Industrial"
    case scandinavian = "Scandinavian"
    case minimalist = "Minimalist"
    case rustic = "Rustic"
    case contemporary = "Contemporary"
    case traditional = "Traditional"
    case midCentury = "Mid-Century"
    
    var id: String { rawValue }
}
