//
//  RemoteDownloadProgress.swift
//  XRShareCollaboration
//
//  Observable, main-actor download progress keyed by model id (ModelType.id),
//  so the catalog UI can show a per-model progress indicator while a remote
//  usdz downloads. A model is "downloading" exactly while it has an entry here.
//

import Foundation
import Combine

@MainActor
public final class RemoteDownloadProgress: ObservableObject {
    public static let shared = RemoteDownloadProgress()

    @Published public private(set) var fractions: [String: Double] = [:]
    @Published public private(set) var failedIDs: Set<String> = []

    private init() {}

    /// 0...1 progress for a model id, or nil if it isn't downloading.
    public func fraction(for id: String) -> Double? {
        fractions[id.lowercased()]
    }

    /// True if the model's last download attempt failed (until retried).
    public func isFailed(_ id: String) -> Bool {
        failedIDs.contains(id.lowercased())
    }

    public func clearFailure(_ id: String) {
        failedIDs.remove(id.lowercased())
    }

    func begin(_ id: String) {
        let key = id.lowercased()
        failedIDs.remove(key)
        fractions[key] = 0
    }
    func update(_ id: String, _ fraction: Double) { fractions[id.lowercased()] = min(max(fraction, 0), 1) }
    func finish(_ id: String) { fractions.removeValue(forKey: id.lowercased()) }
    func fail(_ id: String) {
        let key = id.lowercased()
        fractions.removeValue(forKey: key)
        failedIDs.insert(key)
    }
}
