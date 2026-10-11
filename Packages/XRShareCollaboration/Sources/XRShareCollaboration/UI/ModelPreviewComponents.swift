//
//  ModelPreviewComponents.swift
//  XR Share
//
//  Cache backed model preview components used in order to show a preview/thumbail of the models

import SwiftUI
import QuickLookThumbnailing
import Foundation

#if os(iOS)
import UIKit
#endif

// MARK: - Model Preview

/// Cache backed model preview for a single ModelType
public struct UnifiedModelPreview: View {

    let modelType: ModelType
    let size: CGSize
    let showBackground: Bool

    // The thumbnail image to display for the model once loaded
    @State private var thumbnail: Image? = nil
    // Set once a load has run to completion (successfully or not). Without it a
    // model whose thumbnail can't be resolved renders a spinner forever, which
    // reads as a permanently stuck tile.
    @State private var didAttemptLoad = false

    public init(modelType: ModelType, size: CGSize = CGSize(width: 80, height: 80), showBackground: Bool = true) {
        self.modelType = modelType
        self.size = size
        self.showBackground = showBackground
    }

    public var body: some View {
        ZStack {
            if showBackground {
                RoundedRectangle(cornerRadius: 8)
                    .fill(.ultraThinMaterial)
            }
            
            
            // Thumbnail when we have one; a spinner only while a load is still
            // in flight; a neutral glyph once loading finished with nothing.
            if let thumbnail = thumbnail {
                thumbnail
                    .resizable().scaledToFit()
                    .frame(width: size.width, height: size.height)
            } else if didAttemptLoad {
                Image(systemName: "cube")
                    .font(.largeTitle)
                    .imageScale(.large)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            } else {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: .secondary))
                    .scaleEffect(0.8)
    }
        }
        .frame(width: size.width, height: size.height)
        // `.task` rather than `.onAppear`: it is cancelled when the cell leaves
        // the grid, which is what makes the debounce below able to stop a
        // download from ever starting.
        .task(id: modelType.id) {
            // Already in memory — no work, no request.
            if let cachedThumbnail = ThumbnailCache.shared.getCachedThumbnailSync(for: modelType.rawValue) {
                thumbnail = cachedThumbnail
                didAttemptLoad = true
                return
            }

            // Scrolling the 182-model catalog mounts cells far faster than
            // anyone reads them. Waiting briefly before fetching means a cell
            // flicked past never costs a request at all, because SwiftUI
            // cancels this task when the cell scrolls away.
            do {
                try await Task.sleep(nanoseconds: 200_000_000)
            } catch {
                return
            }

            // Remote models fetch their pre-rendered thumbnail; bundled models
            // use the packaged PNG.
            let loadedThumbnail = await ThumbnailCache.shared.loadThumbnail(for: modelType)
            guard !Task.isCancelled else { return }
            thumbnail = loadedThumbnail
            didAttemptLoad = true
        }
    }
}


// MARK: - Model Preview View

/// Model Preview that creates a cached thumbnail for the given ModelType
public struct ModelPreviewView: View {


    let modelType: ModelType
    let size: CGSize
    let showBackground: Bool
    let preferThumbnails: Bool

    public init(modelType: ModelType, size: CGSize = CGSize(width: 80, height: 80), showBackground: Bool = true, preferThumbnails: Bool = true) {


        self.modelType = modelType
        self.size = size
        self.showBackground = showBackground
        self.preferThumbnails = preferThumbnails
    }

    public var body: some View {
        
        UnifiedModelPreview(modelType: modelType, size: size, showBackground: showBackground)
        
}
}


