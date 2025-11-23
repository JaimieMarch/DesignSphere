// Create a furniture struct to attach to furniture

import Foundation

struct Model: Identifiable {
    let id = UUID()
    let name: String
    let modelname: String
    let thumbnail: String
    let placementType: PlacementType
    
    let isSelected: Bool
    let needsPhysics: Bool
    let canStack: Bool
}
