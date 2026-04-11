#if SWIFT_PACKAGE
//
//  ModelType.swift
//  XR Anatomy
//
//  Model type definitions and categorization system for 3D models
//


import Foundation
import RealityKit




/// Represents a specific type of 3D model type with metadata and loading capabilities
public struct ModelType: Hashable, Identifiable, Sendable {
    public let rawValue: String

    // Instead of a random UUID, use the rawValue as the basis for the ID
    public var id: String { rawValue.lowercased() }

    // Convert rawValue to a more humanreadable format
    public var displayName: String {
        let words = rawValue.replacingOccurrences(of: "([a-z])([A-Z0-9])", with: "$1 $2", options: .regularExpression)
        return words.capitalized
    }

    public var classification: AnchoringComponent.Target.Classification = .any
    public var plane: AnchoringComponent.Target.Alignment = .any
    public var canStack: Bool = false
    public var needsPhysics: Bool = false

    public init(rawValue: String,
                    classification: AnchoringComponent.Target.Classification = .any,
                    plane: AnchoringComponent.Target.Alignment = .horizontal,
                    needsPhysics: Bool = false,
                canStack: Bool = false) {
            self.rawValue = rawValue
            self.classification = classification
            self.plane = plane
            self.needsPhysics = needsPhysics
        }

    /// Models that are already at real-world scale and shouldn't be normalized
    /// Set to true for models created in Reality Composer Pro with proper measurements
    /// Use the same defintion logic as the above to achieve this
    public var preserveRealWorldScale: Bool {
        switch rawValue.lowercased() {
        // Reality Composer Pro models made to scale (measured in inches/meters)
            // There is likely a better way to do this instead of using switch statements
            // problem for another day.
        case "chair", "stool", "sofa", "couch", "coffee_table", "closet", "dinner_table":
            return true
        case "vase", "65_in_tv":
            return true
        case "chandelier":
            return false
        default:
            return false
            // In the case we have other models, we still might need to normalize the size
            // I have no control over models downloaded/scanned
            // Editing models becomes highly important in this case
        }
    }


// MARK: - Model loading
    
    /// Creates a ModelEntity instance for this model type
    func createModelEntity() -> ModelEntity? {
        if let modelURL = Bundle.xrShareLocateUSDZ(named: rawValue) {
            return try? ModelEntity.loadModel(contentsOf: modelURL)
        }

        let filename = rawValue + ".usdz"
        for bundle in Bundle.xrShareResourceBundles {
            if let entity = try? ModelEntity.loadModel(named: filename, in: bundle) {
                return entity
            }
                }

        return nil
    }
    
    /// Discovers all available model types by scanning bundle resouces
    public static func allCases() -> [ModelType] {

            // 1. Scan bundle for USDZ files
            var canonicalNames: [String: String] = [:]

            for url in Bundle.xrShareUSDZResources() {
                let name = url.deletingPathExtension().lastPathComponent
                canonicalNames[name.lowercased()] = name
            }

            guard !canonicalNames.isEmpty else {
                return [ModelType(rawValue: "placeholder")]
            }


            let metadata: [String: (AnchoringComponent.Target.Classification, AnchoringComponent.Target.Alignment, Bool, Bool)] = [
                "65_in_tv": (.wall, .vertical, false, false),
                "chair": (.floor, .horizontal, true, false),
                "chandelier": (.ceiling, .horizontal, false, false),
                "closet": (.floor, .horizontal, false, false),
                "coffee_table": (.floor, .horizontal, true, false),
                "couch": (.floor, .horizontal, true, false),
                "dinner_table": (.floor, .horizontal, true, false),
                "stool": (.floor, .horizontal, true, false),
                "vase": (.table, .horizontal, false, false)
            ]


            let sortedKeys = canonicalNames.keys.sorted()

            let models = sortedKeys.compactMap { key -> ModelType? in
                guard let originalName = canonicalNames[key] else { return nil }

                if let m = metadata[key] {
                    return ModelType(
                        rawValue: originalName,
                        classification: m.0,
                        plane: m.1,
                        needsPhysics: m.2,
                        canStack: m.3
                    )
                }

                let inferred = inferredMetadata(for: key)
                return ModelType(
                    rawValue: originalName,
                    classification: inferred.0,
                    plane: inferred.1,
                    needsPhysics: inferred.2,
                    canStack: inferred.3
                )
            }

            return models
        }
    
    public static func ==(lhs: ModelType, rhs: ModelType) -> Bool {
        lhs.rawValue.lowercased() == rhs.rawValue.lowercased()
    }
    
    public func hash(into hasher: inout Hasher) {
        hasher.combine(rawValue.lowercased())
    }

    private static func inferredMetadata(
        for key: String
    ) -> (AnchoringComponent.Target.Classification, AnchoringComponent.Target.Alignment, Bool, Bool) {
        let words = Set(key.split(whereSeparator: { $0 == "_" || $0 == "-" }).map(String.init))

        if words.contains("tv") || words.contains("poster") || words.contains("painting") || words.contains("mirror") || words.contains("art") {
            return (.wall, .vertical, false, false)
        }

        if words.contains("chandelier") || words.contains("ceiling") || words.contains("pendant") {
            return (.ceiling, .horizontal, false, false)
        }

        if words.contains("lamp") || words.contains("vase") || words.contains("plant") {
            return (.table, .horizontal, false, false)
        }

        if words.contains("chair") || words.contains("stool") || words.contains("sofa") || words.contains("couch")
            || words.contains("table") || words.contains("desk") || words.contains("closet") || words.contains("dresser")
            || words.contains("cabinet") || words.contains("bed") || words.contains("shelf") {
            return (.floor, .horizontal, true, false)
        }

        // Imported or unknown assets should behave conservatively and prefer the floor.
        return (.floor, .horizontal, false, false)
    }
}
#endif

