// Defines each cell inside the catalog home view
// Each cell displays a model preview, its name, and a toggleable favorite button

import SwiftUI
import XRShareCollaboration

struct CatalogCell: View {
    // Model metadata
    let name: String
    let isFavorite: Bool
    let onFavoriteToggle: () -> Void
    let modelType: ModelType?

    // Optional remove mode
    var showRemove: Bool = false
    var onRemove: (() -> Void)? = nil

    // Download progress (0...1) for remote models; nil when not downloading.
    var downloadFraction: Double? = nil

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
                    .font(.largeTitle)
                    .imageScale(.large)
                    .foregroundStyle(.secondary)
                    .frame(height: 130)
            }
            // Display model name beneath the thumbnail
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
        .overlay {
            // Download progress for remote models
            if let downloadFraction {
                ZStack {
                    RoundedRectangle(cornerRadius: 20).fill(.black.opacity(0.4))
                    VStack(spacing: 6) {
                        ProgressView(value: downloadFraction)
                            .progressViewStyle(.linear)
                            .tint(.white)
                            .frame(width: 90)
                        Text("\(Int(downloadFraction * 100))%")
                            .font(.caption2)
                            .foregroundStyle(.white)
                    }
                }
                .accessibilityLabel("Downloading \(name), \(Int(downloadFraction * 100)) percent")
            }
        }
        .overlay(alignment: .topTrailing) {
            // Show remove button in remove mode, favorite star otherwise
            if showRemove, let onRemove = onRemove {
                Button(action: onRemove) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.white, .red)
                }
                .buttonStyle(.plain)
                .padding(8)
                .accessibilityLabel("Remove \(name)")
                .accessibilityHint("Removes this model from your imports")
            } else {
                Button(action: onFavoriteToggle) {
                    Image(systemName: isFavorite ? "star.fill" : "star")
                        .foregroundStyle(isFavorite ? .yellow : .secondary)
                        .font(.subheadline)
                }
                .buttonStyle(.plain)
                .padding(8)
                .accessibilityLabel(isFavorite ? "Remove from favorites" : "Add to favorites")
                .accessibilityHint(isFavorite ? "Removes \(name) from your favorites" : "Adds \(name) to your favorites")
            }
        }
    }
}
