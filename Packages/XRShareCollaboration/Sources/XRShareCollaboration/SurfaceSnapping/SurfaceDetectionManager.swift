//
// SurfaceDetectionManager.swift
// XRShareCollaboration
//
// Manages ARKit plane detection and tracking
//

import Foundation
import ARKit
import Combine

@MainActor
public class SurfaceDetectionManager: ObservableObject {
    @Published public private(set) var detectedPlanes: [UUID: DetectedPlane] = [:]
    @Published public private(set) var isDetecting = false

    private var planeDetectionProvider: PlaneDetectionProvider?
    private var detectionTask: Task<Void, Never>?

    public init() {}

    /// Start detecting planes with ARKit session
    public func startDetection(session: ARKitSession) async throws {
        guard !isDetecting else {
            print("Plane detection already running")
            return
        }

        // Create plane detection provider for both horizontal and vertical surfaces
        let provider = PlaneDetectionProvider(alignments: [.horizontal, .vertical])
        planeDetectionProvider = provider

        // Run the provider with the ARKit session
        try await session.run([provider])

        isDetecting = true
        print("Started plane detection")

        // Start monitoring plane updates
        startMonitoringPlanes()
    }

    /// Stop plane detection
    nonisolated public func stopDetection() {
        Task { @MainActor in
            detectionTask?.cancel()
            detectionTask = nil
            planeDetectionProvider = nil
            isDetecting = false
            detectedPlanes.removeAll()
            print("Stopped plane detection")
        }
    }

    /// Monitor plane updates from ARKit
    private func startMonitoringPlanes() {
        guard let provider = planeDetectionProvider else { return }

        detectionTask = Task { @MainActor in
            for await update in provider.anchorUpdates {
                handlePlaneUpdate(update)
            }
        }
    }

    /// Handle plane anchor updates
    private func handlePlaneUpdate(_ update: AnchorUpdate<PlaneAnchor>) {
        switch update.event {
        case .added:
            let plane = DetectedPlane(from: update.anchor)
            detectedPlanes[plane.id] = plane
            print("Plane added: \(plane.id), classification: \(plane.classification), alignment: \(plane.alignment)")

        case .updated:
            let plane = DetectedPlane(from: update.anchor)
            detectedPlanes[plane.id] = plane

        case .removed:
            detectedPlanes.removeValue(forKey: update.anchor.id)
            print("Plane removed: \(update.anchor.id)")
        }
    }

    /// Get all horizontal planes
    public func getHorizontalPlanes() -> [DetectedPlane] {
        return Array(detectedPlanes.values).filter { $0.alignment == .horizontal }
    }

    /// Get all vertical planes (walls)
    public func getVerticalPlanes() -> [DetectedPlane] {
        return Array(detectedPlanes.values).filter { $0.alignment == .vertical }
    }

    /// Get planes of a specific classification
    public func getPlanes(classification: PlaneAnchor.Classification) -> [DetectedPlane] {
        return Array(detectedPlanes.values).filter { $0.classification == classification }
    }

    /// Get plane by ID
    public func getPlane(id: UUID) -> DetectedPlane? {
        return detectedPlanes[id]
    }

    deinit {
        stopDetection()
    }
}
