// Defines each cell inside the catalog home view
// Each model is shown in the catalog based on these definitions

import SwiftUI
import XRShareCollaboration

struct CatalogCell: View {
    // the name and favorite state
    let name: String
    let isFavorite: Bool
    let onFavoriteToggle: () -> Void
    let modelType: ModelType?

    // Optional remove mode
    var showRemove: Bool = false
    var onRemove: (() -> Void)? = nil

    @State private var isHovered = false

    var body: some View {
        VStack(spacing: 8) {
            ZStack(alignment: .topTrailing) {
                // Display thumbnail using QLThumbnailGenerator cached preview
                if let modelType = modelType {
                    ModelPreviewView(
                        modelType: modelType,
                        size: CGSize(width: 160, height: 130),
                        showBackground: false
                    )
                    .frame(height: 130)
                } else {
                    // Fallback to placeholder if model type not found
                    Image(systemName: "cube.fill")
                        .font(.system(size: 64))
                        .foregroundStyle(.secondary)
                        .frame(height: 130)
                }

                // Remove button appears on hover (only in remove mode)
                if showRemove && isHovered, let onRemove = onRemove {
                    Button(action: onRemove) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 24))
                            .foregroundStyle(.white, .red)
                    }
                    .buttonStyle(.plain)
                    .padding(8)
                    .transition(.scale.combined(with: .opacity))
                }
            }

            // name under
            Text(name)
                .font(.footnote.weight(.medium))
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .frame(height: 32)
        }
        .padding(12)
        .frame(maxWidth: .infinity)
        .frame(height: 200)
        .glassBackground(cornerRadius: 20)
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(showRemove && isHovered ? Color.blue.opacity(0.5) : Color.clear, lineWidth: 2)
        )
        .overlay(alignment: .topTrailing) {
            // Favorite toggle (only when not in remove mode)
            if !showRemove {
                Button(action: onFavoriteToggle) {
                    Image(systemName: isFavorite ? "star.fill" : "star")
                        .foregroundStyle(isFavorite ? .yellow : .secondary)
                        .font(.system(size: 16))
                }
                .buttonStyle(.plain)
                .padding(8)
            }
        }
        .onHover { hovering in
            if showRemove {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isHovered = hovering
                }
            }
        }
    }
}
