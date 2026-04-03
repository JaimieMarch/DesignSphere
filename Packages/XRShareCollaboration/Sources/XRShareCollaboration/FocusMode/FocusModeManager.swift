import Foundation
import RealityKit
import SwiftUI
#if canImport(ARKit)
import ARKit
#endif

#if os(visionOS)
@MainActor
public final class FocusModeManager: ObservableObject {

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

    public enum FocusModeTheme: String, CaseIterable, Identifiable, Sendable {
        case calmStudio
        case warmAtelier
        case brightLoft
        case nightGallery

        public var id: String { rawValue }

        public var displayName: String {
            switch self {
            case .calmStudio:
                return "Calm Studio"
            case .warmAtelier:
                return "Warm Atelier"
            case .brightLoft:
                return "Bright Loft"
            case .nightGallery:
                return "Night Gallery"
            }
        }

        public var subtitle: String {
            switch self {
            case .calmStudio:
                return "Soft neutrals with a balanced, low-distraction light."
            case .warmAtelier:
                return "Warm materials and amber accents for a cozy shell."
            case .brightLoft:
                return "Airy, high-key tones with a cleaner modern edge."
            case .nightGallery:
                return "Cinematic contrast with sculpted highlights."
            }
        }

        public var symbolName: String {
            switch self {
            case .calmStudio:
                return "sun.and.horizon"
            case .warmAtelier:
                return "flame"
            case .brightLoft:
                return "sparkles"
            case .nightGallery:
                return "moon.stars"
            }
        }

        public var swatch: Color {
            switch self {
            case .calmStudio:
                return Color(red: 0.78, green: 0.79, blue: 0.81)
            case .warmAtelier:
                return Color(red: 0.84, green: 0.67, blue: 0.53)
            case .brightLoft:
                return Color(red: 0.82, green: 0.86, blue: 0.90)
            case .nightGallery:
                return Color(red: 0.28, green: 0.31, blue: 0.39)
            }
        }

        fileprivate var palette: FocusModePalette {
            switch self {
            case .calmStudio:
                return FocusModePalette(
                    floorPrimary: UIColor(red: 0.84, green: 0.85, blue: 0.88, alpha: 1.0),
                    floorSecondary: UIColor(red: 0.92, green: 0.93, blue: 0.95, alpha: 1.0),
                    wallPrimary: UIColor(red: 0.92, green: 0.94, blue: 0.97, alpha: 1.0),
                    wallSecondary: UIColor(red: 0.86, green: 0.88, blue: 0.92, alpha: 1.0),
                    wallAccent: UIColor(red: 0.72, green: 0.74, blue: 0.79, alpha: 1.0),
                    trim: UIColor(red: 0.70, green: 0.72, blue: 0.77, alpha: 1.0),
                    glow: UIColor(red: 0.94, green: 0.95, blue: 0.98, alpha: 1.0),
                    keyLight: UIColor(red: 0.98, green: 0.98, blue: 1.0, alpha: 1.0),
                    fillLight: UIColor(red: 0.85, green: 0.89, blue: 0.96, alpha: 1.0),
                    accentLight: UIColor(red: 0.96, green: 0.92, blue: 0.82, alpha: 1.0),
                    keyIntensity: 42_000,
                    fillIntensity: 4_000,
                    accentIntensity: 1_200
                )
            case .warmAtelier:
                return FocusModePalette(
                    floorPrimary: UIColor(red: 0.84, green: 0.76, blue: 0.67, alpha: 1.0),
                    floorSecondary: UIColor(red: 0.94, green: 0.89, blue: 0.83, alpha: 1.0),
                    wallPrimary: UIColor(red: 0.97, green: 0.92, blue: 0.85, alpha: 1.0),
                    wallSecondary: UIColor(red: 0.90, green: 0.83, blue: 0.75, alpha: 1.0),
                    wallAccent: UIColor(red: 0.78, green: 0.67, blue: 0.57, alpha: 1.0),
                    trim: UIColor(red: 0.69, green: 0.58, blue: 0.48, alpha: 1.0),
                    glow: UIColor(red: 0.99, green: 0.92, blue: 0.76, alpha: 1.0),
                    keyLight: UIColor(red: 1.0, green: 0.97, blue: 0.89, alpha: 1.0),
                    fillLight: UIColor(red: 0.98, green: 0.84, blue: 0.69, alpha: 1.0),
                    accentLight: UIColor(red: 0.97, green: 0.71, blue: 0.46, alpha: 1.0),
                    keyIntensity: 38_000,
                    fillIntensity: 3_500,
                    accentIntensity: 1_600
                )
            case .brightLoft:
                return FocusModePalette(
                    floorPrimary: UIColor(red: 0.86, green: 0.88, blue: 0.90, alpha: 1.0),
                    floorSecondary: UIColor(red: 0.95, green: 0.97, blue: 0.98, alpha: 1.0),
                    wallPrimary: UIColor(red: 0.95, green: 0.96, blue: 0.98, alpha: 1.0),
                    wallSecondary: UIColor(red: 0.87, green: 0.90, blue: 0.93, alpha: 1.0),
                    wallAccent: UIColor(red: 0.68, green: 0.79, blue: 0.84, alpha: 1.0),
                    trim: UIColor(red: 0.63, green: 0.67, blue: 0.70, alpha: 1.0),
                    glow: UIColor(red: 0.96, green: 0.99, blue: 1.0, alpha: 1.0),
                    keyLight: UIColor(red: 0.98, green: 0.99, blue: 1.0, alpha: 1.0),
                    fillLight: UIColor(red: 0.82, green: 0.90, blue: 0.95, alpha: 1.0),
                    accentLight: UIColor(red: 0.72, green: 0.89, blue: 0.88, alpha: 1.0),
                    keyIntensity: 45_000,
                    fillIntensity: 4_600,
                    accentIntensity: 1_400
                )
            case .nightGallery:
                return FocusModePalette(
                    floorPrimary: UIColor(red: 0.18, green: 0.20, blue: 0.24, alpha: 1.0),
                    floorSecondary: UIColor(red: 0.24, green: 0.26, blue: 0.30, alpha: 1.0),
                    wallPrimary: UIColor(red: 0.16, green: 0.18, blue: 0.22, alpha: 1.0),
                    wallSecondary: UIColor(red: 0.22, green: 0.24, blue: 0.29, alpha: 1.0),
                    wallAccent: UIColor(red: 0.33, green: 0.35, blue: 0.41, alpha: 1.0),
                    trim: UIColor(red: 0.45, green: 0.46, blue: 0.51, alpha: 1.0),
                    glow: UIColor(red: 0.88, green: 0.90, blue: 0.95, alpha: 1.0),
                    keyLight: UIColor(red: 0.96, green: 0.96, blue: 1.0, alpha: 1.0),
                    fillLight: UIColor(red: 0.58, green: 0.65, blue: 0.78, alpha: 1.0),
                    accentLight: UIColor(red: 0.98, green: 0.72, blue: 0.38, alpha: 1.0),
                    keyIntensity: 31_000,
                    fillIntensity: 2_600,
                    accentIntensity: 2_200
                )
            }
        }
    }

    fileprivate struct FocusModePalette {
        let floorPrimary: UIColor
        let floorSecondary: UIColor
        let wallPrimary: UIColor
        let wallSecondary: UIColor
        let wallAccent: UIColor
        let trim: UIColor
        let glow: UIColor
        let keyLight: UIColor
        let fillLight: UIColor
        let accentLight: UIColor
        let keyIntensity: Float
        let fillIntensity: Float
        let accentIntensity: Float
    }

    @Published public private(set) var isFocusModeActive: Bool = false
    @Published public private(set) var isRecentering: Bool = false
    @Published public private(set) var focusRoomDimensions = FocusRoomDimensions(width: 7.0, depth: 7.0, height: 3.2)
    @Published public private(set) var activeTheme: FocusModeTheme = .calmStudio
    @Published public private(set) var statusText: String = "Ready"
    @Published public private(set) var lastRecenteredAt: Date?

    private weak var sharedAnchorEntity: AnchorEntity?
    private var focusModeRoot: Entity?
    private var focusRoomCenter: SIMD3<Float> = .zero
    private var focusRoomOrientation: simd_quatf = simd_quatf(angle: 0, axis: SIMD3<Float>(0, 1, 0))
    private var recenterRevision: Int = 0
    private let debugLogging = false

    public init() {}

    public func setSharedAnchor(_ anchor: AnchorEntity) {
        sharedAnchorEntity = anchor
    }

    public func setFocusTheme(_ theme: FocusModeTheme) {
        guard theme != activeTheme else { return }
        activeTheme = theme
        statusText = "Applied \(theme.displayName)"
        if isFocusModeActive {
            rebuildFocusModeEnvironment()
        }
    }

    public func enterFocusMode() {
        guard !isFocusModeActive else {
            recenterFocusMode()
            return
        }

        guard sharedAnchorEntity != nil else {
            statusText = "Focus mode needs a live shared anchor"
            return
        }

        isFocusModeActive = true
        statusText = "Positioning focus room..."
        recenterFocusModeAnchor()
    }

    public func exitFocusMode() {
        guard isFocusModeActive || isRecentering || focusModeRoot != nil else { return }
        recenterRevision += 1
        teardownFocusModeEnvironment()
        isRecentering = false
        isFocusModeActive = false
        statusText = "Passthrough restored"
    }

    public func updateFocusRoomDimensions(width: Float, depth: Float, height: Float) {
        let clampedWidth = max(4.0, min(10.0, width))
        let clampedDepth = max(4.0, min(10.0, depth))
        let clampedHeight = max(2.5, min(5.0, height))
        let newDimensions = FocusRoomDimensions(width: clampedWidth, depth: clampedDepth, height: clampedHeight)

        guard newDimensions != focusRoomDimensions else { return }
        focusRoomDimensions = newDimensions

        if isFocusModeActive {
            statusText = "Rebuilding room layout..."
            rebuildFocusModeEnvironment()
            statusText = "Room updated"
        } else {
            statusText = "Room size updated"
        }
    }

    public func recenterFocusMode() {
        guard isFocusModeActive else {
            statusText = "Enter focus mode first"
            return
        }

        statusText = "Recentering..."
        recenterFocusModeAnchor()
    }

    // MARK: - Private Implementation

    private func nextRevision() -> Int {
        recenterRevision += 1
        return recenterRevision
    }

    private func recenterFocusModeAnchor() {
        guard let sharedAnchor = sharedAnchorEntity else {
            statusText = "Shared anchor unavailable"
            return
        }

        let revision = nextRevision()
        isRecentering = true

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
                guard self.recenterRevision == revision else {
                    headAnchor.removeFromParent()
                    return
                }

                let needsInitialBuild = self.focusModeRoot == nil

                guard headAnchor.isAnchored else {
                    headAnchor.removeFromParent()
                    self.isRecentering = false
                    self.statusText = needsInitialBuild ? "Unable to place focus room" : "Unable to recenter right now"
                    if needsInitialBuild {
                        self.isFocusModeActive = false
                        self.teardownFocusModeEnvironment()
                    }
                    return
                }

                let eyePosition = headAnchor.convert(position: SIMD3<Float>(0, 0, 0), to: sharedAnchor)
                let dims = self.focusRoomDimensions
                let floorOffset: Float = -0.5
                let roomCenterY = eyePosition.y + floorOffset + (dims.height / 2.0)

                self.focusRoomCenter = SIMD3<Float>(eyePosition.x, roomCenterY, eyePosition.z)

                let transform = headAnchor.transformMatrix(relativeTo: sharedAnchor)
                let forward = SIMD3<Float>(transform.columns.2.x, 0, transform.columns.2.z)
                let horizontalForward = simd_length_squared(forward) > 0.001 ? simd_normalize(forward) : SIMD3<Float>(0, 0, -1)
                self.focusRoomOrientation = simd_quatf(from: SIMD3<Float>(0, 0, -1), to: horizontalForward)

                headAnchor.removeFromParent()
                self.rebuildFocusModeEnvironment()
                self.lastRecenteredAt = Date()
                self.isRecentering = false
                self.statusText = needsInitialBuild ? "Focus room ready" : "Focus room aligned"
            }
        }
    }

    private func rebuildFocusModeEnvironment() {
        guard let sharedAnchor = sharedAnchorEntity else { return }

        focusModeRoot?.removeFromParent()

        let root = Entity()
        root.name = "FocusModeRoot"
        root.transform = Transform(
            scale: .one,
            rotation: focusRoomOrientation,
            translation: focusRoomCenter
        )
        sharedAnchor.addChild(root)
        focusModeRoot = root

        let palette = activeTheme.palette
        let dims = focusRoomDimensions
        buildShell(in: root, dims: dims, palette: palette)
        buildLighting(in: root, dims: dims, palette: palette)
    }

    private func buildShell(in root: Entity, dims: FocusRoomDimensions, palette: FocusModePalette) {
        let width = dims.width
        let depth = dims.depth
        let height = dims.height

        let floorThickness: Float = 0.045
        let wallThickness: Float = 0.055
        let trimThickness: Float = 0.018
        let trimHeight: Float = 0.13
        let coveHeight: Float = 0.10

        func surfaceMaterial(_ color: UIColor, roughness: Float, metallic: Float = 0.0) -> PhysicallyBasedMaterial {
            var material = PhysicallyBasedMaterial()
            material.baseColor = .init(tint: color)
            material.roughness = .init(floatLiteral: roughness)
            material.metallic = .init(floatLiteral: metallic)
            return material
        }

        func glowMaterial(_ color: UIColor) -> UnlitMaterial {
            var material = UnlitMaterial()
            material.color = .init(tint: color)
            return material
        }

        func makeBox(
            size: SIMD3<Float>,
            localPosition: SIMD3<Float>,
            material: PhysicallyBasedMaterial,
            collision: Bool = false,
            name: String
        ) -> ModelEntity {
            let entity = ModelEntity(mesh: .generateBox(size: size), materials: [material])
            entity.name = name
            entity.position = localPosition
            if collision {
                entity.components.set(CollisionComponent(shapes: [.generateBox(size: size)]))
            }
            return entity
        }

        func makeBox(
            size: SIMD3<Float>,
            localPosition: SIMD3<Float>,
            material: UnlitMaterial,
            collision: Bool = false,
            name: String
        ) -> ModelEntity {
            let entity = ModelEntity(mesh: .generateBox(size: size), materials: [material])
            entity.name = name
            entity.position = localPosition
            if collision {
                entity.components.set(CollisionComponent(shapes: [.generateBox(size: size)]))
            }
            return entity
        }

        // Base shell.
        let floor = makeBox(
            size: SIMD3<Float>(width + 0.3, floorThickness, depth + 0.3),
            localPosition: SIMD3<Float>(0, -height * 0.5 + floorThickness * 0.5, 0),
            material: surfaceMaterial(palette.floorPrimary, roughness: 0.92),
            collision: true,
            name: "FocusFloor"
        )
        root.addChild(floor)

        let floorInset = makeBox(
            size: SIMD3<Float>(width * 0.92, 0.018, depth * 0.92),
            localPosition: SIMD3<Float>(0, -height * 0.5 + 0.04, 0),
            material: surfaceMaterial(palette.floorSecondary, roughness: 0.88),
            name: "FocusFloorInset"
        )
        root.addChild(floorInset)

        let ceiling = makeBox(
            size: SIMD3<Float>(width + 0.24, floorThickness, depth + 0.24),
            localPosition: SIMD3<Float>(0, height * 0.5 - floorThickness * 0.5, 0),
            material: surfaceMaterial(palette.wallPrimary, roughness: 0.95),
            collision: true,
            name: "FocusCeiling"
        )
        root.addChild(ceiling)

        // Main walls.
        let wallSpecs: [(name: String, size: SIMD3<Float>, position: SIMD3<Float>, collision: Bool, color: UIColor, roughness: Float)] = [
            ("FocusFrontWall", SIMD3<Float>(width, height, wallThickness), SIMD3<Float>(0, 0, depth * 0.5 - wallThickness * 0.5), true, palette.wallPrimary, 0.94),
            ("FocusBackWall", SIMD3<Float>(width, height, wallThickness), SIMD3<Float>(0, 0, -depth * 0.5 + wallThickness * 0.5), true, palette.wallSecondary, 0.96),
            ("FocusLeftWall", SIMD3<Float>(wallThickness, height, depth), SIMD3<Float>(-width * 0.5 + wallThickness * 0.5, 0, 0), true, palette.wallSecondary, 0.95),
            ("FocusRightWall", SIMD3<Float>(wallThickness, height, depth), SIMD3<Float>(width * 0.5 - wallThickness * 0.5, 0, 0), true, palette.wallSecondary, 0.95)
        ]

        for spec in wallSpecs {
            let wall = makeBox(
                size: spec.size,
                localPosition: spec.position,
                material: surfaceMaterial(spec.color, roughness: spec.roughness),
                collision: spec.collision,
                name: spec.name
            )
            root.addChild(wall)
        }

        // Layered inner shell to avoid a flat cuboid look.
        let innerInset: Float = 0.055
        let innerWallThickness: Float = 0.018
        let wallLayers: [(String, SIMD3<Float>, SIMD3<Float>, UIColor, Float)] = [
            ("FocusFrontCove", SIMD3<Float>(width * 0.96, height * 0.96, innerWallThickness), SIMD3<Float>(0, 0.0, depth * 0.5 - innerInset), palette.wallAccent, 0.82),
            ("FocusBackCove", SIMD3<Float>(width * 0.96, height * 0.96, innerWallThickness), SIMD3<Float>(0, 0.0, -depth * 0.5 + innerInset), palette.wallAccent, 0.82),
            ("FocusLeftCove", SIMD3<Float>(innerWallThickness, height * 0.96, depth * 0.96), SIMD3<Float>(-width * 0.5 + innerInset, 0.0, 0), palette.wallAccent, 0.82),
            ("FocusRightCove", SIMD3<Float>(innerWallThickness, height * 0.96, depth * 0.96), SIMD3<Float>(width * 0.5 - innerInset, 0.0, 0), palette.wallAccent, 0.82)
        ]

        for layer in wallLayers {
            let panel = makeBox(
                size: layer.1,
                localPosition: layer.2,
                material: surfaceMaterial(layer.3, roughness: layer.4),
                name: layer.0
            )
            root.addChild(panel)
        }

        // Architectural trim and a ceiling band to make the room feel designed.
        let trimColor = palette.trim
        let trimY = -height * 0.5 + trimHeight * 0.5
        let ceilingBandY = height * 0.5 - coveHeight * 0.5

        let baseFront = makeBox(
            size: SIMD3<Float>(width * 0.98, trimHeight, trimThickness),
            localPosition: SIMD3<Float>(0, trimY, depth * 0.5 - trimThickness * 0.75),
            material: surfaceMaterial(trimColor, roughness: 0.76),
            name: "FocusBaseFront"
        )
        let baseBack = makeBox(
            size: SIMD3<Float>(width * 0.98, trimHeight, trimThickness),
            localPosition: SIMD3<Float>(0, trimY, -depth * 0.5 + trimThickness * 0.75),
            material: surfaceMaterial(trimColor, roughness: 0.76),
            name: "FocusBaseBack"
        )
        let baseLeft = makeBox(
            size: SIMD3<Float>(trimThickness, trimHeight, depth * 0.98),
            localPosition: SIMD3<Float>(-width * 0.5 + trimThickness * 0.75, trimY, 0),
            material: surfaceMaterial(trimColor, roughness: 0.76),
            name: "FocusBaseLeft"
        )
        let baseRight = makeBox(
            size: SIMD3<Float>(trimThickness, trimHeight, depth * 0.98),
            localPosition: SIMD3<Float>(width * 0.5 - trimThickness * 0.75, trimY, 0),
            material: surfaceMaterial(trimColor, roughness: 0.76),
            name: "FocusBaseRight"
        )
        [baseFront, baseBack, baseLeft, baseRight].forEach { root.addChild($0) }

        let ceilingFront = makeBox(
            size: SIMD3<Float>(width * 0.96, coveHeight, trimThickness),
            localPosition: SIMD3<Float>(0, ceilingBandY, depth * 0.5 - trimThickness * 0.6),
            material: glowMaterial(palette.glow),
            name: "FocusCeilingFrontGlow"
        )
        let ceilingBack = makeBox(
            size: SIMD3<Float>(width * 0.96, coveHeight, trimThickness),
            localPosition: SIMD3<Float>(0, ceilingBandY, -depth * 0.5 + trimThickness * 0.6),
            material: glowMaterial(palette.glow),
            name: "FocusCeilingBackGlow"
        )
        let ceilingLeft = makeBox(
            size: SIMD3<Float>(trimThickness, coveHeight, depth * 0.96),
            localPosition: SIMD3<Float>(-width * 0.5 + trimThickness * 0.6, ceilingBandY, 0),
            material: glowMaterial(palette.glow),
            name: "FocusCeilingLeftGlow"
        )
        let ceilingRight = makeBox(
            size: SIMD3<Float>(trimThickness, coveHeight, depth * 0.96),
            localPosition: SIMD3<Float>(width * 0.5 - trimThickness * 0.6, ceilingBandY, 0),
            material: glowMaterial(palette.glow),
            name: "FocusCeilingRightGlow"
        )
        [ceilingFront, ceilingBack, ceilingLeft, ceilingRight].forEach { root.addChild($0) }

        // Corner posts and a subtle central landing pad add depth without clutter.
        let postSize = SIMD3<Float>(trimThickness * 1.15, height * 0.96, trimThickness * 1.15)
        let postOffsets = [
            SIMD3<Float>(-width * 0.5 + trimThickness, 0, -depth * 0.5 + trimThickness),
            SIMD3<Float>(width * 0.5 - trimThickness, 0, -depth * 0.5 + trimThickness),
            SIMD3<Float>(-width * 0.5 + trimThickness, 0, depth * 0.5 - trimThickness),
            SIMD3<Float>(width * 0.5 - trimThickness, 0, depth * 0.5 - trimThickness)
        ]
        for (index, offset) in postOffsets.enumerated() {
            let post = makeBox(
                size: postSize,
                localPosition: offset,
                material: surfaceMaterial(palette.wallAccent, roughness: 0.84),
                name: "FocusCornerPost\(index)"
            )
            root.addChild(post)
        }

        let landingPad = makeBox(
            size: SIMD3<Float>(width * 0.54, 0.012, depth * 0.54),
            localPosition: SIMD3<Float>(0, -height * 0.5 + 0.062, 0),
            material: surfaceMaterial(palette.accentLight, roughness: 0.98),
            name: "FocusLandingPad"
        )
        root.addChild(landingPad)

        // Small vertical light rails give the room a designed focal edge.
        let railSize = SIMD3<Float>(0.028, height * 0.42, 0.028)
        let railOffsets = [
            SIMD3<Float>(-width * 0.5 + 0.07, -height * 0.04, -depth * 0.5 + 0.07),
            SIMD3<Float>(width * 0.5 - 0.07, -height * 0.04, -depth * 0.5 + 0.07),
            SIMD3<Float>(-width * 0.5 + 0.07, -height * 0.04, depth * 0.5 - 0.07),
            SIMD3<Float>(width * 0.5 - 0.07, -height * 0.04, depth * 0.5 - 0.07)
        ]
        for (index, offset) in railOffsets.enumerated() {
            let rail = makeBox(
                size: railSize,
                localPosition: offset,
                material: glowMaterial(palette.accentLight),
                name: "FocusLightRail\(index)"
            )
            root.addChild(rail)
        }
    }

    private func buildLighting(in root: Entity, dims: FocusRoomDimensions, palette: FocusModePalette) {
        guard #available(visionOS 2.0, *) else { return }

        let keyLight = DirectionalLight()
        keyLight.name = "FocusKeyLight"
        keyLight.light.color = palette.keyLight
        keyLight.light.intensity = palette.keyIntensity
        keyLight.shadow = DirectionalLightComponent.Shadow()
        keyLight.position = SIMD3<Float>(0, dims.height * 0.18, -dims.depth * 0.05)
        keyLight.orientation = simd_quatf(angle: -.pi / 3.2, axis: SIMD3<Float>(1, 0, 0))
        root.addChild(keyLight)

        let fillLight = PointLight()
        fillLight.name = "FocusFillLight"
        fillLight.light.color = palette.fillLight
        fillLight.light.intensity = palette.fillIntensity
        fillLight.position = SIMD3<Float>(0, dims.height * 0.12, -dims.depth * 0.22)
        root.addChild(fillLight)

        let accentLight = PointLight()
        accentLight.name = "FocusAccentLight"
        accentLight.light.color = palette.accentLight
        accentLight.light.intensity = palette.accentIntensity
        accentLight.position = SIMD3<Float>(0, dims.height * 0.42, 0)
        root.addChild(accentLight)
    }

    private func teardownFocusModeEnvironment() {
        focusModeRoot?.removeFromParent()
        focusModeRoot = nil
    }

    private func debugLog(_ message: String) {
        guard debugLogging else { return }
        #if DEBUG
        print("FocusMode DEBUG: \(message)")
        #endif
    }
}
#endif
