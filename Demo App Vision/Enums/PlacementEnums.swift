// Defines possible placement positions for models

import Foundation

enum PlacementSurface {
    case floor // gravity-bound items
    case wall // wall mounted items
    case ceiling // for lighting/fans, other upper-mounted items
    case surface // account for stackable decor (think vase or pictureframe) 
    case free // default behavior
}
