//
// SnapBehavior.swift
// XRShareCollaboration
//
// Manages snap state and behavior for individual entities
//

import Foundation

/// Snap state for a placed model
public struct SnapBehavior {
    public enum SnapState {
        case free           // Not near any surface
        case nearSurface    // Within snap zone, showing preview
        case snapped        // Locked to surface
    }

    public var currentState: SnapState = .free
    public var snappedSurfaceID: UUID? = nil
    public var surfaceType: SurfaceClassification = .floor

    /// Distance threshold for snapping
    public let snapDistance: Float = 0.25  // 25cm snap zone

    /// Strength of magnetic snap effect (0-1)
    public let snapStrength: Float = 0.85

    /// Minimum distance improvement needed to switch surfaces (prevents flickering)
    public let surfaceSwitchThreshold: Float = 0.08

    public init() {}

    /// Reset snap state
    public mutating func reset() {
        currentState = .free
        snappedSurfaceID = nil
    }

    /// Update to snapped state
    public mutating func snapTo(surfaceID: UUID, type: SurfaceClassification) {
        currentState = .snapped
        snappedSurfaceID = surfaceID
        surfaceType = type
    }

    /// Check if currently snapped to a specific surface
    public func isSnappedTo(_ surfaceID: UUID) -> Bool {
        return currentState == .snapped && snappedSurfaceID == surfaceID
    }
}
