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
    }

    public struct Asset: Codable, Sendable {
        public let url: String
        public let bytes: Int?
        public let sha256: String?
    }

    public struct Placement: Codable, Sendable {
        public let classification: String   // floor | wall | ceiling | table | any
        public let plane: String            // horizontal | vertical | any
        public let canStack: Bool
        public let needsPhysics: Bool
        public let preserveRealWorldScale: Bool
    }
}
