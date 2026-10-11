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
    /// Failures that retrying cannot fix in this session (the hosted file does
    /// not match its manifest checksum). A subset of `failedIDs`; the catalog
    /// uses it to stop offering a Retry that would only fail again.
    @Published public private(set) var permanentlyFailedIDs: Set<String> = []
    /// When the store will next allow a download after a transient failure.
    /// Before this moment a Retry is refused by the backoff, so the catalog
    /// shows a countdown instead of a button that silently fails again.
    @Published public private(set) var retryDates: [String: Date] = [:]

    private init() {}

    /// 0...1 progress for a model id, or nil if it isn't downloading.
    public func fraction(for id: String) -> Double? {
        fractions[id.lowercased()]
    }

    /// True if the model's last download attempt failed (until retried).
    public func isFailed(_ id: String) -> Bool {
        failedIDs.contains(id.lowercased())
    }

    /// True if the model's last failure cannot be fixed by retrying.
    public func isPermanentlyFailed(_ id: String) -> Bool {
        permanentlyFailedIDs.contains(id.lowercased())
    }

    /// The moment another download attempt will be allowed, if a transient
    /// failure is still inside its backoff window.
    public func retryDate(for id: String) -> Date? {
        retryDates[id.lowercased()]
    }

    public func clearFailure(_ id: String) {
        let key = id.lowercased()
        failedIDs.remove(key)
        permanentlyFailedIDs.remove(key)
        retryDates.removeValue(forKey: key)
    }

    func begin(_ id: String) {
        let key = id.lowercased()
        failedIDs.remove(key)
        permanentlyFailedIDs.remove(key)
        retryDates.removeValue(forKey: key)
        fractions[key] = 0
    }

    func setRetryDate(_ id: String, _ date: Date?) {
        let key = id.lowercased()
        if let date {
            retryDates[key] = date
        } else {
            retryDates.removeValue(forKey: key)
        }
    }
    func update(_ id: String, _ fraction: Double) { fractions[id.lowercased()] = min(max(fraction, 0), 1) }
    func finish(_ id: String) { fractions.removeValue(forKey: id.lowercased()) }
    func fail(_ id: String, permanent: Bool = false) {
        let key = id.lowercased()
        fractions.removeValue(forKey: key)
        failedIDs.insert(key)
        // A plain failure never downgrades a permanent one: the model manager
        // re-raises after the store has already classified the same failure,
        // and only a fresh attempt (`begin`) or `clearFailure` should lift it.
        if permanent {
            permanentlyFailedIDs.insert(key)
        }
    }
}
