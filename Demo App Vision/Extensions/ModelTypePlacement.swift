import XRShareCollaboration

extension ModelType {
    var preferredSurface: PlacementSurface {
        switch rawValue.lowercased() {
        case "chair", "stool", "sofa", "couch", "coffee_table", "closet", "dinner_table":
            return .floor
        case "vase":
            return .surface
        case "65_in_tv":
            return .wall
        case "chandelier":
            return .ceiling
        default:
            return .free
        }
    }
}
