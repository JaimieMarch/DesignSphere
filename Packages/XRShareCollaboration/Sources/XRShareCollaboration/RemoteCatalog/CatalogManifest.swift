//
//  CatalogManifest.swift
//  XRShareCollaboration
//
//  Codable mirror of the `catalog.json` served from object storage (R2).
//  Must stay in sync with Tools/catalog-pipeline/build_catalog.py.
//

import Foundation

public struct CatalogManifest: Codable, Sendable {
    public let version: Int
    public let generatedAt: String?
    public let models: [Entry]

    public struct Entry: Codable, Sendable {
        public let id: String
        public let displayName: String
        public let category: String
        /// False for geometry-only (untextured) models; the app applies a
        /// neutral grey instead of the missing-material placeholder. Defaults
        /// to true when absent (older manifests).
        public let textured: Bool?
        public let file: Asset
        public let thumbnail: Asset?
        public let placement: Placement

        var isValid: Bool {
            !id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && id.utf8.count <= 255
                && !id.contains("/") && !id.contains("\\")
                && !id.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains)
                && !displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && file.isValid(extensions: ["usdz"])
                && (thumbnail?.isValid(extensions: ["png", "jpg", "jpeg"]) ?? true)
        }
    }

    public struct Asset: Codable, Sendable {
        public let url: String
        public let bytes: Int?
        public let sha256: String?

        func isValid(extensions: Set<String>) -> Bool {
            guard let decodedPath = url.removingPercentEncoding,
                  !decodedPath.isEmpty, !decodedPath.hasPrefix("/"),
                  !decodedPath.contains("\\"), !decodedPath.contains(":"),
                  !decodedPath.contains("?"), !decodedPath.contains("#"),
                  !decodedPath.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains),
                  decodedPath.split(separator: "/", omittingEmptySubsequences: false)
                    .allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }),
                  extensions.contains((decodedPath as NSString).pathExtension.lowercased()),
                  bytes.map({ $0 > 0 }) ?? true,
                  sha256.map(Self.isValidSHA256) ?? true else { return false }
            return true
        }

        static func isValidSHA256(_ value: String) -> Bool {
            value.utf8.count == 64 && value.utf8.allSatisfy {
                (48...57).contains($0) || (65...70).contains($0) || (97...102).contains($0)
            }
        }
    }

    public struct Placement: Codable, Sendable {
        public let classification: String   // floor | wall | ceiling | table | any
        public let plane: String            // horizontal | vertical | any
        public let canStack: Bool
        public let needsPhysics: Bool
        public let preserveRealWorldScale: Bool
    }

    enum CodingKeys: String, CodingKey {
        case version, generatedAt, models
    }

    public init(version: Int, generatedAt: String?, models: [Entry]) {
        self.version = version
        self.generatedAt = generatedAt
        self.models = models
    }

    /// `version` is decoded strictly — a document without it isn't a catalog.
    /// `models` is decoded leniently: a single malformed entry (a new field the
    /// pipeline added, a row missing `canStack`) drops just that row instead of
    /// throwing away all 182. A whole-document failure would leave every user
    /// without a disk cache on "Catalog unavailable", and each Retry tap costs
    /// another full manifest fetch.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decode(Int.self, forKey: .version)
        guard version == 1 else {
            throw DecodingError.dataCorruptedError(forKey: .version, in: container, debugDescription: "Unsupported catalog version")
        }
        generatedAt = try container.decodeIfPresent(String.self, forKey: .generatedAt)
        let rows = try container.decodeIfPresent([FailableDecodable<Entry>].self, forKey: .models) ?? []
        var identifiers = Set<String>()
        models = rows.compactMap(\.value).filter {
            $0.isValid && identifiers.insert($0.id.lowercased()).inserted
        }
    }
}

/// Decodes `T` when the element is well-formed, and yields `nil` rather than
/// throwing when it isn't, so one bad element cannot fail a whole array.
struct FailableDecodable<T: Decodable>: Decodable {
    let value: T?

    init(from decoder: any Decoder) throws {
        value = try? T(from: decoder)
    }
}
