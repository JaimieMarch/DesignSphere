// Defines possible placement positions for models

enum PlacementType {
    case floor
    case wall
    case ceiling
    case surface // account for stackable decor (think vase or pictureframe)
    case anywhere
}
