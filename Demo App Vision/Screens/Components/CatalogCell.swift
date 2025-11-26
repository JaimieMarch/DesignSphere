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

    var body: some View {
        VStack(spacing: 8) {
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
        .overlay(alignment: .topTrailing) {
            Button(action: onFavoriteToggle) {
                Image(systemName: isFavorite ? "star.fill" : "star")
                    .foregroundStyle(isFavorite ? .yellow : .secondary)
                    .font(.system(size: 16))
            }
            .buttonStyle(.plain)
            .padding(8)
        }
    }
}
