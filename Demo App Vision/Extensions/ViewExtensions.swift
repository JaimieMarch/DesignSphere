// Reusable modifier for applying a consistent glass-style background
// Reusable via:
// .glassbackground
// Helps keep the app's visuals consistent

import SwiftUI

extension View {
    func glassBackground(cornerRadius: CGFloat) -> some View {
        background(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(.thinMaterial)
        )
    }
}
