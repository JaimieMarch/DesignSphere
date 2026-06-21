import Foundation
import RealityKit
import SwiftUI
import UIKit

#if os(visionOS)
@available(visionOS 26.0, *)
@MainActor
public final class MeasurementManager: ObservableObject {
    public enum Unit: String, CaseIterable, Identifiable, Sendable {
        case inches
        case feet
        case centimeters
        case meters

        public var id: String { rawValue }

        public var displayName: String {
            switch self {
            case .inches:
                return "Inches"
            case .feet:
                return "Feet"
            case .centimeters:
                return "Centimeters"
            case .meters:
                return "Meters"
            }
        }

        func format(distanceMeters: Float) -> String {
            switch self {
            case .inches:
                return String(format: "%.1f in", distanceMeters * 39.3701)
            case .feet:
                return String(format: "%.2f ft", distanceMeters * 3.28084)
            case .centimeters:
                return String(format: "%.1f cm", distanceMeters * 100)
            case .meters:
                return String(format: "%.2f m", distanceMeters)
            }
        }

        func formatDimensions(_ extents: SIMD3<Float>) -> String {
            [
                format(distanceMeters: extents.x),
                format(distanceMeters: extents.y),
                format(distanceMeters: extents.z)
            ].joined(separator: " × ")
        }
    }

    public enum DistanceSelectionState: Equatable {
        case inactive
        case awaitingFirstObject
        case awaitingSecondObject(UUID)
    }

    @Published public private(set) var unit: Unit = .centimeters
    @Published public private(set) var showDimensions: Bool = false
    @Published public private(set) var statusText: String = "Ready"
    @Published public private(set) var selectionState: DistanceSelectionState = .inactive
    @Published public private(set) var hasVirtualRuler: Bool = false
    @Published public private(set) var hasActiveDistanceMeasurement: Bool = false

    private weak var sharedAnchorEntity: AnchorEntity?
    private weak var manipulationManager: ManipulationManager?

    private var dimensionOverlays: [UUID: DimensionOverlay] = [:]
    private var distanceOverlay: DistanceOverlay?
    private var rulerRoot: Entity?

    public init() {}

    public var isAwaitingSelection: Bool {
        switch selectionState {
        case .inactive:
            return false
        case .awaitingFirstObject, .awaitingSecondObject:
            return true
        }
    }

    public func setSharedAnchor(_ anchor: AnchorEntity) {
        sharedAnchorEntity = anchor
    }

    func setManipulationManager(_ manager: ManipulationManager?) {
        manipulationManager = manager
    }

    public func setUnit(_ unit: Unit) {
        guard self.unit != unit else { return }
        self.unit = unit
        statusText = "Measurement unit set to \(unit.displayName)"
    }

    public func setShowDimensions(_ showDimensions: Bool) {
        self.showDimensions = showDimensions
        if showDimensions {
            statusText = "Object dimensions visible"
        } else {
            clearDimensionOverlays()
            statusText = "Object dimensions hidden"
        }
    }

    public func startDistanceMeasurement() {
        clearDistanceMeasurement()
        selectionState = .awaitingFirstObject
        statusText = "Tap the first object to measure from."
    }

    public func cancelDistanceSelection() {
        guard isAwaitingSelection else { return }
        selectionState = .inactive
        statusText = "Distance measurement cancelled"
    }

    public func clearDistanceMeasurement() {
        distanceOverlay?.root.removeFromParent()
        distanceOverlay = nil
        hasActiveDistanceMeasurement = false
        selectionState = .inactive
    }

    public func spawnVirtualRuler(deviceTransform: simd_float4x4?) {
        clearVirtualRuler()

        guard let sharedAnchor = sharedAnchorEntity else {
            statusText = "Measurement tools need a live scene anchor."
            return
        }

        let root = Entity()
        root.name = "MeasurementRuler"

        let body = ModelEntity(
            mesh: .generateBox(size: SIMD3<Float>(1.0, 0.018, 0.035), cornerRadius: 0.006),
            materials: [rulerBodyMaterial()]
        )
        root.addChild(body)

        let leadingCap = ModelEntity(
            mesh: .generateBox(size: SIMD3<Float>(0.03, 0.03, 0.05), cornerRadius: 0.008),
            materials: [rulerAccentMaterial()]
        )
        leadingCap.position = SIMD3<Float>(-0.5, 0, 0)
        root.addChild(leadingCap)

        let trailingCap = ModelEntity(
            mesh: .generateBox(size: SIMD3<Float>(0.03, 0.03, 0.05), cornerRadius: 0.008),
            materials: [rulerAccentMaterial()]
        )
        trailingCap.position = SIMD3<Float>(0.5, 0, 0)
        root.addChild(trailingCap)

        for tickIndex in 0...10 {
            let tickHeight: Float = tickIndex.isMultiple(of: 5) ? 0.06 : 0.035
            let tick = ModelEntity(
                mesh: .generateBox(size: SIMD3<Float>(0.004, tickHeight, 0.008), cornerRadius: 0.001),
                materials: [rulerTickMaterial()]
            )
            tick.position = SIMD3<Float>(Float(tickIndex) * 0.1 - 0.5, tickHeight * 0.5, 0)
            root.addChild(tick)
        }

        let label = makeBillboardLabel(
            text: "1.00 m",
            fontSize: 0.05,
            textColor: UIColor(red: 0.10, green: 0.10, blue: 0.12, alpha: 1.0),
            backgroundColor: UIColor(red: 0.97, green: 0.91, blue: 0.78, alpha: 0.92)
        )
        label.position = SIMD3<Float>(0, 0.085, 0)
        root.addChild(label)

        if let deviceTransform {
            let viewerPosition = SIMD3<Float>(
                deviceTransform.columns.3.x,
                deviceTransform.columns.3.y,
                deviceTransform.columns.3.z
            )
            let localViewer = sharedAnchor.convert(position: viewerPosition, from: nil)
            root.position = SIMD3<Float>(localViewer.x, max(localViewer.y - 0.12, 0.9), localViewer.z - 0.9)
        } else {
            root.position = SIMD3<Float>(0, 1.15, -1.0)
        }

        root.components.set(InputTargetComponent(allowedInputTypes: .all))
        root.generateCollisionShapes(recursive: true)
        manipulationManager?.configureModelForManipulation(entity: root)

        sharedAnchor.addChild(root)
        rulerRoot = root
        hasVirtualRuler = true
        statusText = "Virtual ruler placed in the scene."
    }

    public func clearVirtualRuler() {
        rulerRoot?.removeFromParent()
        rulerRoot = nil
        hasVirtualRuler = false
    }

    public func handleSpatialTap(on entity: Entity, modelsByID: [UUID: Model]) -> Bool {
        switch selectionState {
        case .inactive:
            return false
        case .awaitingFirstObject:
            guard let firstID = tappedModelID(for: entity),
                  modelsByID[firstID] != nil else {
                statusText = "Tap a placed object to start measuring."
                return true
            }

            selectionState = .awaitingSecondObject(firstID)
            if let firstModel = modelsByID[firstID] {
                statusText = "First object: \(firstModel.modelType.displayName). Tap the second object."
            } else {
                statusText = "Tap the second object."
            }
            return true
        case .awaitingSecondObject(let firstID):
            guard let secondID = tappedModelID(for: entity),
                  let firstModel = modelsByID[firstID],
                  let secondModel = modelsByID[secondID] else {
                statusText = "Tap another placed object to finish measuring."
                return true
            }

            guard firstID != secondID else {
                statusText = "Choose a different second object."
                return true
            }

            distanceOverlay = DistanceOverlay(firstID: firstID, secondID: secondID, root: distanceOverlay?.root ?? Entity())
            hasActiveDistanceMeasurement = true
            selectionState = .inactive
            updateDistanceOverlay(firstModel: firstModel, secondModel: secondModel)
            statusText = "Measured \(firstModel.modelType.displayName) to \(secondModel.modelType.displayName)."
            return true
        }
    }

    public func syncScene(with models: [Model]) {
        if showDimensions {
            syncDimensionOverlays(with: models)
        } else if !dimensionOverlays.isEmpty {
            clearDimensionOverlays()
        }

        guard let distanceOverlay else { return }
        guard let firstModel = models.first(where: { $0.id == distanceOverlay.firstID }),
              let secondModel = models.first(where: { $0.id == distanceOverlay.secondID }) else {
            clearDistanceMeasurement()
            statusText = "Distance measurement cleared because one object is gone."
            return
        }

        updateDistanceOverlay(firstModel: firstModel, secondModel: secondModel)
    }

    public func reset() {
        clearDistanceMeasurement()
        clearVirtualRuler()
        clearDimensionOverlays()
        selectionState = .inactive
        statusText = "Ready"
    }
}

@available(visionOS 26.0, *)
private extension MeasurementManager {
    struct DimensionOverlay {
        let root: Entity
        var renderedText: String
    }

    struct DistanceOverlay {
        let firstID: UUID
        let secondID: UUID
        let root: Entity
    }

    struct AxisAlignedBounds {
        let center: SIMD3<Float>
        let extents: SIMD3<Float>

        var min: SIMD3<Float> { center - extents * 0.5 }
        var max: SIMD3<Float> { center + extents * 0.5 }
    }

    func tappedModelID(for entity: Entity) -> UUID? {
        guard let modelEntity = entityAncestorOrSelf(entity, with: InstanceIDComponent.self),
              let instanceIDString = modelEntity.components[InstanceIDComponent.self]?.id else {
            return nil
        }
        return UUID(uuidString: instanceIDString)
    }

    func syncDimensionOverlays(with models: [Model]) {
        guard let sharedAnchor = sharedAnchorEntity else { return }

        let activeIDs = Set(models.map(\.id))
        for (id, overlay) in dimensionOverlays where !activeIDs.contains(id) {
            overlay.root.removeFromParent()
            dimensionOverlays.removeValue(forKey: id)
        }

        for model in models {
            guard let entity = model.modelEntity,
                  entity.parent != nil else { continue }

            let bounds = entity.visualBounds(relativeTo: sharedAnchor)
            guard bounds.extents.x.isFinite,
                  bounds.extents.y.isFinite,
                  bounds.extents.z.isFinite,
                  bounds.extents.x > 0,
                  bounds.extents.y > 0,
                  bounds.extents.z > 0 else {
                continue
            }

            let labelText = unit.formatDimensions(bounds.extents)
            let overlayRoot: Entity

            if let existing = dimensionOverlays[model.id], existing.renderedText == labelText {
                overlayRoot = existing.root
            } else {
                dimensionOverlays[model.id]?.root.removeFromParent()
                overlayRoot = makeBillboardLabel(
                    text: labelText,
                    fontSize: 0.036,
                    textColor: UIColor(red: 0.14, green: 0.14, blue: 0.17, alpha: 1.0),
                    backgroundColor: UIColor(red: 0.97, green: 0.92, blue: 0.82, alpha: 0.92)
                )
                dimensionOverlays[model.id] = DimensionOverlay(root: overlayRoot, renderedText: labelText)
                sharedAnchor.addChild(overlayRoot)
            }

            let offset = max(bounds.extents.y * 0.6, 0.16)
            overlayRoot.position = SIMD3<Float>(bounds.center.x, bounds.max.y + offset, bounds.center.z)
            overlayRoot.isEnabled = true
        }
    }

    func clearDimensionOverlays() {
        for overlay in dimensionOverlays.values {
            overlay.root.removeFromParent()
        }
        dimensionOverlays.removeAll()
    }

    func updateDistanceOverlay(firstModel: Model, secondModel: Model) {
        guard let sharedAnchor = sharedAnchorEntity,
              let firstEntity = firstModel.modelEntity,
              let secondEntity = secondModel.modelEntity else {
            clearDistanceMeasurement()
            return
        }

        let firstBoundsBox = firstEntity.visualBounds(relativeTo: sharedAnchor)
        let secondBoundsBox = secondEntity.visualBounds(relativeTo: sharedAnchor)
        let firstBounds = AxisAlignedBounds(center: firstBoundsBox.center, extents: firstBoundsBox.extents)
        let secondBounds = AxisAlignedBounds(center: secondBoundsBox.center, extents: secondBoundsBox.extents)
        let segment = closestSegment(between: firstBounds, and: secondBounds)
        let distance = simd_distance(segment.start, segment.end)

        let root: Entity
        if let existing = distanceOverlay?.root {
            for child in existing.children {
                child.removeFromParent()
            }
            root = existing
        } else {
            root = Entity()
            sharedAnchor.addChild(root)
        }

        let midpoint = (segment.start + segment.end) * 0.5
        root.position = midpoint

        let lineVector = segment.end - segment.start
        let lineLength = max(simd_length(lineVector), 0.001)
        let normalizedDirection = simd_length_squared(lineVector) > 0.00001
            ? simd_normalize(lineVector)
            : SIMD3<Float>(1, 0, 0)
        root.orientation = simd_quatf(from: SIMD3<Float>(1, 0, 0), to: normalizedDirection)

        let line = ModelEntity(
            mesh: .generateBox(size: SIMD3<Float>(1, 0.009, 0.009), cornerRadius: 0.003),
            materials: [distanceLineMaterial()]
        )
        line.scale = SIMD3<Float>(lineLength, 1, 1)
        root.addChild(line)

        let startCap = ModelEntity(
            mesh: .generateSphere(radius: 0.014),
            materials: [distanceCapMaterial()]
        )
        startCap.position = SIMD3<Float>(-lineLength * 0.5, 0, 0)
        root.addChild(startCap)

        let endCap = ModelEntity(
            mesh: .generateSphere(radius: 0.014),
            materials: [distanceCapMaterial()]
        )
        endCap.position = SIMD3<Float>(lineLength * 0.5, 0, 0)
        root.addChild(endCap)

        let label = makeBillboardLabel(
            text: unit.format(distanceMeters: distance),
            fontSize: 0.045,
            textColor: UIColor(red: 0.14, green: 0.14, blue: 0.17, alpha: 1.0),
            backgroundColor: UIColor(red: 0.98, green: 0.92, blue: 0.81, alpha: 0.95)
        )
        label.position = SIMD3<Float>(0, 0.085, 0)
        root.addChild(label)

        distanceOverlay = DistanceOverlay(firstID: firstModel.id, secondID: secondModel.id, root: root)
        hasActiveDistanceMeasurement = true
    }

    func closestSegment(
        between firstBounds: AxisAlignedBounds,
        and secondBounds: AxisAlignedBounds
    ) -> (start: SIMD3<Float>, end: SIMD3<Float>) {
        var start = SIMD3<Float>.zero
        var end = SIMD3<Float>.zero

        for axisIndex in 0..<3 {
            let firstMin = firstBounds.min[axisIndex]
            let firstMax = firstBounds.max[axisIndex]
            let secondMin = secondBounds.min[axisIndex]
            let secondMax = secondBounds.max[axisIndex]

            if firstMax < secondMin {
                start[axisIndex] = firstMax
                end[axisIndex] = secondMin
            } else if secondMax < firstMin {
                start[axisIndex] = firstMin
                end[axisIndex] = secondMax
            } else {
                let overlapMin = max(firstMin, secondMin)
                let overlapMax = min(firstMax, secondMax)
                let overlapCenter = (overlapMin + overlapMax) * 0.5
                start[axisIndex] = overlapCenter
                end[axisIndex] = overlapCenter
            }
        }

        return (start, end)
    }

    func makeBillboardLabel(
        text: String,
        fontSize: CGFloat,
        textColor: UIColor,
        backgroundColor: UIColor
    ) -> Entity {
        let root = Entity()

        if #available(visionOS 2.0, *) {
            var billboard = BillboardComponent()
            billboard.blendFactor = 1.0
            root.components.set(billboard)
        }

        let textMesh = MeshResource.generateText(
            text,
            extrusionDepth: 0.001,
            font: .systemFont(ofSize: fontSize, weight: .semibold),
            containerFrame: .zero,
            alignment: .center,
            lineBreakMode: .byClipping
        )

        let textEntity = ModelEntity(
            mesh: textMesh,
            materials: [textMaterial(textColor)]
        )
        let textBounds = textEntity.visualBounds(relativeTo: nil)
        textEntity.position = SIMD3<Float>(
            -textBounds.center.x,
            -textBounds.center.y,
            0.005
        )

        let plateWidth = max(textBounds.extents.x + 0.035, 0.16)
        let plateHeight = max(textBounds.extents.y + 0.026, 0.06)
        let plate = ModelEntity(
            mesh: .generateBox(size: SIMD3<Float>(plateWidth, plateHeight, 0.008), cornerRadius: 0.02),
            materials: [backgroundMaterial(backgroundColor)]
        )

        root.addChild(plate)
        root.addChild(textEntity)
        return root
    }

    func rulerBodyMaterial() -> SimpleMaterial {
        SimpleMaterial(color: UIColor(red: 0.95, green: 0.90, blue: 0.78, alpha: 0.98), isMetallic: false)
    }

    func rulerAccentMaterial() -> SimpleMaterial {
        SimpleMaterial(color: UIColor(red: 0.90, green: 0.66, blue: 0.28, alpha: 1.0), isMetallic: true)
    }

    func rulerTickMaterial() -> SimpleMaterial {
        SimpleMaterial(color: UIColor(red: 0.24, green: 0.24, blue: 0.27, alpha: 1.0), isMetallic: false)
    }

    func distanceLineMaterial() -> SimpleMaterial {
        SimpleMaterial(color: UIColor(red: 0.94, green: 0.83, blue: 0.60, alpha: 0.98), isMetallic: false)
    }

    func distanceCapMaterial() -> SimpleMaterial {
        SimpleMaterial(color: UIColor(red: 0.98, green: 0.93, blue: 0.82, alpha: 1.0), isMetallic: true)
    }

    func textMaterial(_ color: UIColor) -> UnlitMaterial {
        var material = UnlitMaterial()
        material.color = .init(tint: color)
        return material
    }

    func backgroundMaterial(_ color: UIColor) -> SimpleMaterial {
        SimpleMaterial(color: color, isMetallic: false)
    }

    func entityAncestorOrSelf<T: Component>(_ entity: Entity, with componentType: T.Type) -> Entity? {
        var current: Entity? = entity
        while let candidate = current {
            if candidate.components[componentType] != nil {
                return candidate
            }
            current = candidate.parent
        }
        return nil
    }
}
#endif
