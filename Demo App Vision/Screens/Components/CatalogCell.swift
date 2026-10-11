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
    // Set when retrying cannot help (the hosted file is damaged), so the cell
    // explains that instead of offering a Retry that would fail again.
    var downloadUnavailable: Bool = false
    // After a transient failure the download is held back until this moment;
    // until then a Retry would be refused, so the cell counts down instead.
    var retryDate: Date? = nil
    var onRetry: (() -> Void)? = nil

    /// "Retry in 2 min" while a backoff is running, `nil` once a retry is allowed.
    static func retryWaitText(until retryDate: Date?, now: Date) -> String? {
        guard let retryDate else { return nil }
        let remaining = retryDate.timeIntervalSince(now)
        guard remaining > 0 else { return nil }
        if remaining < 60 {
            return "Retry in \(max(Int(remaining.rounded(.up)), 1)) s"
        }
        return "Retry in \(Int((remaining / 60).rounded(.up))) min"
    }

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
                    .accessibilityHidden(true)
            }
            // Display model name and the first-use network cost before a tap
            // starts downloading a remote model.
            VStack(spacing: 2) {
                Text(name)
                    .font(.footnote.weight(.medium))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)

                if !showRemove, let size = modelType?.remoteDownloadSizeLabel {
                    Label("\(size) download on first use", systemImage: "arrow.down.circle")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .accessibilityLabel("Downloads \(size) the first time this model is used")
                }
            }
            .frame(minHeight: 46)
        }
        .padding(12)
        .frame(maxWidth: .infinity)
        .frame(minHeight: 214)
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
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Downloading \(name), \(Int(downloadFraction * 100)) percent")
            } else if downloadFailed {
                ZStack {
                    RoundedRectangle(cornerRadius: 20).fill(.black.opacity(0.45))
                    VStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.title3)
                            .foregroundStyle(.yellow)
                        if downloadUnavailable {
                            Text("Unavailable right now")
                                .font(.caption2)
                                .foregroundStyle(.white)
                            Text("This model's file is damaged. It will return once the catalog is fixed.")
                                .font(.caption2)
                                .foregroundStyle(.white.opacity(0.85))
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 10)
                        } else {
                            Text("Download failed")
                                .font(.caption2)
                                .foregroundStyle(.white)
                            TimelineView(.periodic(from: .now, by: 5)) { context in
                                let waiting = Self.retryWaitText(until: retryDate, now: context.date)
                                VStack(spacing: 6) {
                                    if let waiting {
                                        Text(waiting)
                                            .font(.caption2)
                                            .foregroundStyle(.white.opacity(0.85))
                                    }
                                    Button { onRetry?() } label: {
                                        Label("Retry", systemImage: "arrow.clockwise")
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .controlSize(.small)
                                    .disabled(waiting != nil)
                                }
                            }
                        }
                    }
                }
                .accessibilityElement(children: downloadUnavailable ? .combine : .contain)
                .accessibilityLabel(downloadUnavailable
                    ? "\(name) is unavailable right now because its file is damaged"
                    : "\(name) download failed")
                .accessibilityHint(downloadUnavailable ? "" : "Double tap retry to try again")
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
