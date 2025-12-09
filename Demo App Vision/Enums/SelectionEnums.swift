// Represents the interaction state of a model through the UI
// Used to control visuals such as outlines or selection indicators:
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
