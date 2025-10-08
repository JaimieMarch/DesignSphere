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
struct UnifiedModelPreview: View {
    
    let modelType: ModelType
    let size: CGSize
    let showBackground: Bool
    
    // The thumbnail image to display for the model once loaded
    @State private var thumbnail: Image? = nil
    
    init(modelType: ModelType, size: CGSize = CGSize(width: 80, height: 80), showBackground: Bool = true) {
        self.modelType = modelType
        self.size = size
        self.showBackground = showBackground
    }
    
    var body: some View {
        ZStack {
            if showBackground {
                RoundedRectangle(cornerRadius: 8)
                    .fill(.ultraThinMaterial)
            }
            
            
            // If thumbnail is available, render it, otherwise show a small progress indicator
            if let thumbnail = thumbnail {
                thumbnail
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: size.width, height: size.height)
            } else {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: .secondary))
                    .scaleEffect(0.8)
    }
        }
        .frame(width: size.width, height: size.height)
        .onAppear {
            
            
            // First try to get from cache synchronously
            if let cachedThumbnail = ThumbnailCache.shared.getCachedThumbnailSync(for: modelType.rawValue) {
               
                thumbnail = cachedThumbnail
                
            } else {
                
                // If not cached, load asynchronously via ThumbnailCache
                Task {
                    
                    let loadedThumbnail = await ThumbnailCache.shared.getCachedThumbnail(for: modelType.rawValue, size: size)
                    await MainActor.run {
                        thumbnail = loadedThumbnail
                    }
            }
            }
}
    }
}


// MARK: - Model Preview View

/// Model Preview that creates a cached thumbnail for the given ModelType
struct ModelPreviewView: View {
    
    
    let modelType: ModelType
    let size: CGSize
    let showBackground: Bool
    let preferThumbnails: Bool
    
    init(modelType: ModelType, size: CGSize = CGSize(width: 80, height: 80), showBackground: Bool = true, preferThumbnails: Bool = true) {
        
        
        self.modelType = modelType
        self.size = size
        self.showBackground = showBackground
        self.preferThumbnails = preferThumbnails
    }
    
    var body: some View {
        
        UnifiedModelPreview(modelType: modelType, size: size, showBackground: showBackground)
        
}
}


