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
    // Set when the last download attempt failed; tapping retry re-attempts.
    var downloadFailed: Bool = false
    var onRetry: (() -> Void)? = nil

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
            // Download progress / failure for remote models
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
            } else if downloadFailed {
                ZStack {
                    RoundedRectangle(cornerRadius: 20).fill(.black.opacity(0.45))
                    VStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.title3)
                            .foregroundStyle(.yellow)
                        Text("Download failed")
                            .font(.caption2)
                            .foregroundStyle(.white)
                        Button { onRetry?() } label: {
                            Label("Retry", systemImage: "arrow.clockwise")
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    }
                }
                .accessibilityLabel("\(name) download failed")
                .accessibilityHint("Double tap retry to try again")
            }
        }
        .overlay(alignment: .topLeading) {
            // Untextured models are blank canvases the user colors in the editor.
            if modelType?.hasBakedMaterials == false {
                Image(systemName: "paintbrush.fill")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(7)
                    .background(.ultraThinMaterial, in: Circle())
                    .padding(8)
                    .accessibilityLabel("Customizable — set color and material in the editor")
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
