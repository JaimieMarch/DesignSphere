import Foundation
import RealityKit
import SwiftUI
#if canImport(ARKit)
import ARKit
#endif

#if os(visionOS)
@MainActor
public final class FocusModeManager: ObservableObject {

    /// Configurable dimensions for the virtual focus room
    public struct FocusRoomDimensions: Equatable {
        public var width: Float
        public var depth: Float
        public var height: Float

        public init(width: Float, depth: Float, height: Float) {
            self.width = width
            self.depth = depth
            self.height = height
        }
    }

    @Published public private(set) var isFocusModeActive: Bool = false
    @Published public private(set) var focusRoomDimensions = FocusRoomDimensions(width: 7.0, depth: 7.0, height: 3.2)

    private weak var sharedAnchorEntity: AnchorEntity?
    private var focusModeElements: [Entity] = []
    private var focusRoomCenter: SIMD3<Float> = .zero
    private var focusRoomOrientation: simd_quatf = simd_quatf(angle: 0, axis: SIMD3<Float>(0, 1, 0))

    public init() {}

    public func setSharedAnchor(_ anchor: AnchorEntity) {
        self.sharedAnchorEntity = anchor
    }

    // MARK: - Public API

    /// Surrounds the user with a neutral virtual room that occludes the real world
    public func enterFocusMode() {
        guard !isFocusModeActive else { return }
        isFocusModeActive = true
        // Don't build geometry yet - wait for head anchor position in recenterFocusModeAnchor
        recenterFocusModeAnchor()
    }

    /// Restores passthrough viewing and removes the focus environment.
    public func exitFocusMode() {
        guard isFocusModeActive else { return }
        teardownFocusModeEnvironment()
        isFocusModeActive = false
    }

    /// Update the room dimensions (meters). Clamped to reasonable bounds for comfort.
    public func updateFocusRoomDimensions(width: Float, depth: Float, height: Float) {
        let clampedWidth = max(4.0, min(10.0, width))
        let clampedDepth = max(4.0, min(10.0, depth))
        let clampedHeight = max(2.5, min(5.0, height))
        let newDimensions = FocusRoomDimensions(width: clampedWidth, depth: clampedDepth, height: clampedHeight)

        guard newDimensions != focusRoomDimensions else { return }
        focusRoomDimensions = newDimensions

        if isFocusModeActive {
            // Rebuild geometry with new dimensions at current position
            buildFocusRoomGeometry()
        }
    }

    /// Manually recenter the focus mode room around the user's current position.
    public func recenterFocusMode() {
        guard isFocusModeActive else {
            print("Focus Mode must be active to recenter")
            return
        }
        recenterFocusModeAnchor()
    }

    // MARK: - Private Implementation

    private func recenterFocusModeAnchor() {
        guard let sharedAnchor = sharedAnchorEntity else {
            print("Warning: sharedAnchorEntity not set")
            return
        }

        let headAnchor = AnchorEntity(.head)
        headAnchor.anchoring.trackingMode = .once
        sharedAnchor.addChild(headAnchor)

        Task {
            var attempts = 0
            while attempts < 40 && !headAnchor.isAnchored {
                try? await Task.sleep(nanoseconds: 25_000_000)
                attempts += 1
            }

            await MainActor.run {
                if !headAnchor.isAnchored {
                    print("Warning: Head anchor failed to track after \(attempts) attempts")
                    headAnchor.removeFromParent()
                    return
                }

                // Get eye/head position in shared space
                let eyePosition = headAnchor.convert(position: SIMD3<Float>(0, 0, 0), to: sharedAnchor)

                // Place floor 1 meter below eye level
                // Room center = eye level - 1.0m + (room height / 2)
                let dims = focusRoomDimensions
                let floorOffset: Float = -1.0  // 1 meter below eye level
                let roomCenterY = eyePosition.y + floorOffset + (dims.height / 2.0)

                focusRoomCenter = SIMD3<Float>(eyePosition.x, roomCenterY, eyePosition.z)

                print("DEBUG: Eye position: \(eyePosition)")
                print("DEBUG: Floor will be at Y: \(eyePosition.y + floorOffset)")
                print("DEBUG: Room center: \(focusRoomCenter)")
                print("DEBUG: Ceiling will be at Y: \(eyePosition.y + floorOffset + dims.height)")

                // Align room orientation with user's forward direction (only yaw, no pitch/roll)
                let transform = headAnchor.transformMatrix(relativeTo: sharedAnchor)
                let forward = SIMD3<Float>(transform.columns.2.x, 0, transform.columns.2.z)
                let horizontalForward = simd_length_squared(forward) > 0.001 ? simd_normalize(forward) : SIMD3<Float>(0, 0, -1)
                let yawQuat = simd_quatf(from: SIMD3<Float>(0, 0, -1), to: horizontalForward)
                focusRoomOrientation = yawQuat

                headAnchor.removeFromParent()

                // Build geometry with calculated position
                buildFocusRoomGeometry()
            }
        }
    }

    private func buildFocusRoomGeometry() {
        guard let sharedAnchor = sharedAnchorEntity else { return }

        focusModeElements.forEach { $0.removeFromParent() }
        focusModeElements.removeAll()

        let dims = focusRoomDimensions
        let wallThickness: Float = 0.02
        let floorThickness: Float = 0.02
        let trimThickness: Float = 0.015
        let trimHeight: Float = 0.12

        func tint(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat) -> UnlitMaterial {
            var material = UnlitMaterial()
            material.color = .init(tint: UIColor(red: red, green: green, blue: blue, alpha: 1))
            return material
        }

        // Helper to convert local position to world position using stored center and orientation
        func worldPosition(for localPos: SIMD3<Float>) -> SIMD3<Float> {
            let rotated = focusRoomOrientation.act(localPos)
            let result = focusRoomCenter + rotated
            print("DEBUG: localPos \(localPos) -> rotated \(rotated) -> world \(result)")
            return result
        }

        func makeBox(size: SIMD3<Float>, color: UnlitMaterial, localPosition: SIMD3<Float>, enableCollision: Bool = false) -> ModelEntity {
            let entity = ModelEntity(mesh: .generateBox(size: size))
            entity.model?.materials = [color]

            // Calculate world position and orientation
            entity.position = worldPosition(for: localPosition)
            entity.orientation = focusRoomOrientation

            // Add collision for physical interaction blocking
            if enableCollision {
                entity.components.set(CollisionComponent(shapes: [.generateBox(size: size)]))
            }

            // Add input target to make surfaces feel solid
            entity.components.set(InputTargetComponent(allowedInputTypes: .indirect))

            return entity
        }

        // Floor
        let floorLocalPos = SIMD3<Float>(0, -dims.height * 0.5, 0)
        let floor = makeBox(
            size: SIMD3<Float>(dims.width, floorThickness, dims.depth),
            color: tint(0.81, 0.83, 0.88),
            localPosition: floorLocalPos,
            enableCollision: true
        )
        print("DEBUG: Floor local position: \(floorLocalPos)")
        print("DEBUG: Floor world position: \(floor.position)")
        print("DEBUG: Floor should be \(dims.height * 0.5)m below center at \(focusRoomCenter)")
        sharedAnchor.addChild(floor)
        focusModeElements.append(floor)

        // Ceiling
        let ceilingLocalPos = SIMD3<Float>(0, dims.height * 0.5, 0)
        let ceiling = makeBox(
            size: SIMD3<Float>(dims.width, floorThickness, dims.depth),
            color: tint(0.93, 0.94, 0.98),
            localPosition: ceilingLocalPos,
            enableCollision: true
        )
        print("DEBUG: Ceiling local position: \(ceilingLocalPos)")
        print("DEBUG: Ceiling world position: \(ceiling.position)")
        sharedAnchor.addChild(ceiling)
        focusModeElements.append(ceiling)

        // Walls with collision to block interaction
        let frontWall = makeBox(
            size: SIMD3<Float>(dims.width, dims.height, wallThickness),
            color: tint(0.92, 0.94, 0.98),
            localPosition: SIMD3<Float>(0, 0, dims.depth * 0.5),
            enableCollision: true
        )
        let backWall = makeBox(
            size: SIMD3<Float>(dims.width, dims.height, wallThickness),
            color: tint(0.9, 0.92, 0.96),
            localPosition: SIMD3<Float>(0, 0, -dims.depth * 0.5),
            enableCollision: true
        )
        let leftWall = makeBox(
            size: SIMD3<Float>(wallThickness, dims.height, dims.depth),
            color: tint(0.88, 0.9, 0.95),
            localPosition: SIMD3<Float>(-dims.width * 0.5, 0, 0),
            enableCollision: true
        )
        let rightWall = makeBox(
            size: SIMD3<Float>(wallThickness, dims.height, dims.depth),
            color: tint(0.88, 0.9, 0.95),
            localPosition: SIMD3<Float>(dims.width * 0.5, 0, 0),
            enableCollision: true
        )
        [frontWall, backWall, leftWall, rightWall].forEach {
            sharedAnchor.addChild($0)
            focusModeElements.append($0)
        }

        // Floor trim / baseboards
        let trimY = (-dims.height * 0.5) + trimHeight * 0.5
        let trimColor = tint(0.75, 0.77, 0.82)

        let frontTrim = makeBox(
            size: SIMD3<Float>(dims.width, trimHeight, trimThickness),
            color: trimColor,
            localPosition: SIMD3<Float>(0, trimY, dims.depth * 0.5 - trimThickness * 0.5)
        )
        let backTrim = makeBox(
            size: SIMD3<Float>(dims.width, trimHeight, trimThickness),
            color: trimColor,
            localPosition: SIMD3<Float>(0, trimY, -dims.depth * 0.5 + trimThickness * 0.5)
        )
        let leftTrim = makeBox(
            size: SIMD3<Float>(trimThickness, trimHeight, dims.depth),
            color: trimColor,
            localPosition: SIMD3<Float>(-dims.width * 0.5 + trimThickness * 0.5, trimY, 0)
        )
        let rightTrim = makeBox(
            size: SIMD3<Float>(trimThickness, trimHeight, dims.depth),
            color: trimColor,
            localPosition: SIMD3<Float>(dims.width * 0.5 - trimThickness * 0.5, trimY, 0)
        )
        [frontTrim, backTrim, leftTrim, rightTrim].forEach {
            sharedAnchor.addChild($0)
            focusModeElements.append($0)
        }

        // Corner columns for clearer edges
        let columnColor = tint(0.7, 0.72, 0.78)
        let columnSize = SIMD3<Float>(trimThickness, dims.height, trimThickness)
        let cornerOffsets = [
            SIMD3<Float>(-dims.width * 0.5 + trimThickness * 0.5, 0, -dims.depth * 0.5 + trimThickness * 0.5),
            SIMD3<Float>(dims.width * 0.5 - trimThickness * 0.5, 0, -dims.depth * 0.5 + trimThickness * 0.5),
            SIMD3<Float>(-dims.width * 0.5 + trimThickness * 0.5, 0, dims.depth * 0.5 - trimThickness * 0.5),
            SIMD3<Float>(dims.width * 0.5 - trimThickness * 0.5, 0, dims.depth * 0.5 - trimThickness * 0.5)
        ]
        for offset in cornerOffsets {
            let column = makeBox(size: columnSize, color: columnColor, localPosition: offset)
            sharedAnchor.addChild(column)
            focusModeElements.append(column)
        }

        // Dynamic lighting for depth and realism (visionOS 2.0+)
        if #available(visionOS 2.0, *) {
            let primaryLight = DirectionalLight()
            primaryLight.light.color = .white
            primaryLight.light.intensity = 40000
            primaryLight.shadow = DirectionalLightComponent.Shadow()
            primaryLight.position = focusRoomCenter
            primaryLight.orientation = focusRoomOrientation * simd_quatf(angle: -.pi / 3, axis: SIMD3<Float>(1, 0, 0))
            sharedAnchor.addChild(primaryLight)
            focusModeElements.append(primaryLight)

            let fillLight = PointLight()
            fillLight.light.intensity = 1500
            fillLight.light.color = .white
            fillLight.position = worldPosition(for: SIMD3<Float>(0, -0.3, -dims.depth * 0.3))
            sharedAnchor.addChild(fillLight)
            focusModeElements.append(fillLight)
        }
    }

    private func teardownFocusModeEnvironment() {
        focusModeElements.forEach { $0.removeFromParent() }
        focusModeElements.removeAll()
    }
}
#endif
