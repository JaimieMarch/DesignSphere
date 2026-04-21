import ARKit
import RealityKit

enum SupportSurfacePolicy {
    static func driftLimit(for modelType: ModelType) -> Float {
        if modelType.classification == .ceiling {
            return 0.14
        }

        switch modelType.plane {
        case .vertical:
            return 0.18
        case .horizontal:
            switch modelType.classification {
            case .floor:
                return 0.35
            case .table, .seat:
                return 0.20
            default:
                return 0.28
            }
        case .any:
            return 0.25
        default:
            return 0.25
        }
    }

    static func normalAlignmentThreshold(for modelType: ModelType) -> Float {
        if modelType.classification == .ceiling {
            return 0.985
        }

        switch modelType.plane {
        case .vertical:
            return 0.98
        case .horizontal:
            return modelType.classification == .floor ? 0.95 : 0.97
        case .any:
            return 0.95
        default:
            return 0.95
        }
    }

    @available(visionOS 2.0, *)
    static func normalAlignmentThreshold(for classification: MeshAnchor.MeshClassification?) -> Float {
        switch classification {
        case .ceiling:
            return 0.985
        case .wall, .window, .door, .cabinet, .tv:
            return 0.98
        case .table, .seat, .bed:
            return 0.97
        case .floor:
            return 0.95
        case .none, .stairs, .homeAppliance, .plant, nil:
            return 0.95
        @unknown default:
            return 0.95
        }
    }
}
