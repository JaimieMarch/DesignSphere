// Just helps to prevent repeating this Apple centric glass effect across pages
// Reusable via:
// .glassbackground

import SwiftUI

extension View {
    func glassBackground(cornerRadius: CGFloat) -> some View {
        background(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(.thinMaterial)
        )
    }
}
