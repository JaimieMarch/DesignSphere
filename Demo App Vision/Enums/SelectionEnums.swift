// Defines selection state for each model
// Helps define the current state of a model
// - Selected, locked, hovered

import SwiftUI

enum SelectionState {
    case none
    case selected
    case highlighted
    case locked
    
    var outlineColor: Color? {
        switch self {
        case .none: return nil
        case .selected: return .blue
        case .highlighted: return .yellow
        case .locked: return .red
        }
    }
}
