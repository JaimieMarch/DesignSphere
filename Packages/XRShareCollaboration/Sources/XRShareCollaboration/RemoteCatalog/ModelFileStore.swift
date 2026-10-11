//
//  ModelFileStore.swift
//  XRShareCollaboration
//
//  Resolves a (remote) ModelType to a local usdz file URL: returns the cached
//  copy if present, otherwise downloads it, verifies its sha256, and stores it
//  under Caches/. Concurrent requests for the same model are coalesced.
//

import Foundation
import CryptoKit

public actor ModelFileStore {
    public static let shared = ModelFileStore()

    public enum StoreError: Error, Equatable {
        case notRemote
        case downloadFailed
        case checksumMismatch
        /// The download was deliberately not attempted: this model failed
        /// recently and is still inside its backoff window (or failed its
        /// integrity check, which no amount of retrying can fix).
        case retrySuppressed
    }

    /// Default on-disk budget for downloaded models. `Caches/` is OS-purgeable
    /// on visionOS, so every byte held here is a byte that may have to be
    /// fetched again after a purge; keep the exposure modest.
    static let defaultCacheBudgetBytes = 500_000_000

    /// First retry waits this long after a transient failure, doubling per
    /// consecutive failure up to `maximumBackoff`.
    private static let baseBackoff: TimeInterval = 60
    private static let maximumBackoff: TimeInterval = 3600

    /// A download attempt that failed, so repeats can be suppressed.
    private struct FailureRecord {
        var attempts: Int
        var lastFailure: Date
        /// The bytes at that URL cannot satisfy the manifest checksum, so
        /// re-downloading them is guaranteed waste.
        var isIntegrityFailure: Bool
    }

    private var inFlight: [String: Task<URL, Error>] = [:]
    /// Keyed by cache key, not model id: for a checksummed model the key *is*
    /// the expected sha256, so a corrected manifest entry gets a new key and is
    /// not suppressed by the old entry's failure.
    private var failures: [String: FailureRecord] = [:]

    /// Soft cap on the on-disk model cache; least-recently-used usdz files are
    /// evicted past this. `Caches/` is also OS-purgeable, so this is best-effort.
    private let cacheBudgetBytes: Int
    private let cacheDirectoryOverride: URL?
    private let sessionConfiguration: URLSessionConfiguration
    private let now: @Sendable () -> Date

    init(
        cacheDirectory: URL? = nil,
        cacheBudgetBytes: Int = ModelFileStore.defaultCacheBudgetBytes,
        sessionConfiguration: URLSessionConfiguration = .default,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.cacheDirectoryOverride = cacheDirectory
        self.cacheBudgetBytes = cacheBudgetBytes
        self.sessionConfiguration = sessionConfiguration
        self.now = now
    }

    private var cacheDirectory: URL {
        if let cacheDirectoryOverride {
            try? FileManager.default.createDirectory(at: cacheDirectoryOverride, withIntermediateDirectories: true)
            return cacheDirectoryOverride
        }
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("RemoteModels", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func cacheKey(for modelType: ModelType) -> String {
        if let sha = modelType.remoteSHA256, !sha.isEmpty { return sha.lowercased() }
        let seed = modelType.remoteURL?.absoluteString ?? modelType.rawValue
        return SHA256.hash(data: Data(seed.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    private func cachePath(for modelType: ModelType) -> URL {
        cacheDirectory.appendingPathComponent(cacheKey(for: modelType) + ".usdz")
    }

    /// True if the model's usdz is already downloaded.
    public func isCached(_ modelType: ModelType) -> Bool {
        guard modelType.isRemote else { return false }
        return FileManager.default.fileExists(atPath: cachePath(for: modelType).path)
    }

    /// Returns a local usdz URL, downloading and caching it on first use.
    public func localURL(for modelType: ModelType) async throws -> URL {
        guard let remoteURL = modelType.remoteURL else { throw StoreError.notRemote }
        let key = cacheKey(for: modelType)
        let destination = cachePath(for: modelType)

        if FileManager.default.fileExists(atPath: destination.path) {
            touch(destination)
            failures[key] = nil
            return destination
        }

        if let existing = inFlight[key] {
            return try await existing.value
        }

        // Without this the same doomed download repeats on every tap: a stale
        // manifest checksum re-fetches the whole usdz forever, and a flaky
        // network re-fetches it as fast as the user can tap.
        if isSuppressed(key) {
            await RemoteDownloadProgress.shared.fail(
                modelType.id,
                permanent: failures[key]?.isIntegrityFailure == true
            )
            await RemoteDownloadProgress.shared.setRetryDate(modelType.id, nextAttemptDate(for: key))
            throw StoreError.retrySuppressed
        }

        let expectedSHA = modelType.remoteSHA256
        let id = modelType.id
        let configuration = sessionConfiguration
        let task = Task<URL, Error> {
            try await Self.download(
                remoteURL,
                to: destination,
                expectedSHA: expectedSHA,
                id: id,
                sessionConfiguration: configuration
            )
        }
        inFlight[key] = task
        defer { inFlight[key] = nil }
        do {
            let url = try await task.value
            failures[key] = nil
            enforceBudget(keeping: url)
            return url
        } catch {
            recordFailure(key, error: error)
            await RemoteDownloadProgress.shared.setRetryDate(id, nextAttemptDate(for: key))
            throw error
        }
    }

    // MARK: - Failure memo

    /// True while another attempt for this key would be wasted.
    private func isSuppressed(_ key: String) -> Bool {
        guard let record = failures[key] else { return false }
        // A checksum mismatch is a property of the bytes, not of the moment;
        // the same request can only produce the same mismatch. Suppress it for
        // the life of the process — a fixed manifest changes the sha, and so
        // the key, which lifts the suppression on its own.
        if record.isIntegrityFailure { return true }
        return now().timeIntervalSince(record.lastFailure) < Self.backoff(forAttempt: record.attempts)
    }

    private func recordFailure(_ key: String, error: Error) {
        let attempts = (failures[key]?.attempts ?? 0) + 1
        failures[key] = FailureRecord(
            attempts: attempts,
            lastFailure: now(),
            isIntegrityFailure: (error as? StoreError) == .checksumMismatch
        )
    }

    /// When a transient failure's backoff ends; `nil` for no failure or for an
    /// integrity failure, which no amount of waiting fixes.
    private func nextAttemptDate(for key: String) -> Date? {
        guard let record = failures[key], !record.isIntegrityFailure else { return nil }
        return record.lastFailure.addingTimeInterval(Self.backoff(forAttempt: record.attempts))
    }

    /// 60s, 2m, 4m, ... capped at an hour.
    static func backoff(forAttempt attempt: Int) -> TimeInterval {
        let doublings = Double(max(attempt, 1) - 1)
        return min(baseBackoff * pow(2, doublings), maximumBackoff)
    }

    /// Seconds until another attempt for this model would be made, `nil` if one
    /// would be made now, and `.infinity` for a failure that retrying can't fix.
    func retryDelay(for modelType: ModelType) -> TimeInterval? {
        guard let record = failures[cacheKey(for: modelType)] else { return nil }
        if record.isIntegrityFailure { return .infinity }
        let remaining = Self.backoff(forAttempt: record.attempts)
            - now().timeIntervalSince(record.lastFailure)
        return remaining > 0 ? remaining : nil
    }

    /// Evict least-recently-used usdz files when the cache exceeds its budget.
    private func enforceBudget(keeping: URL) {
        let fm = FileManager.default
        let keys: [URLResourceKey] = [.fileSizeKey, .contentModificationDateKey]
        guard let files = try? fm.contentsOfDirectory(
            at: cacheDirectory, includingPropertiesForKeys: keys
        ) else { return }

        var entries: [(url: URL, size: Int, date: Date)] = []
        var total = 0
        for file in files where file.pathExtension == "usdz" {
            let values = try? file.resourceValues(forKeys: Set(keys))
            let size = values?.fileSize ?? 0
            entries.append((file, size, values?.contentModificationDate ?? .distantPast))
            total += size
        }

        guard total > cacheBudgetBytes else { return }
        for entry in entries.sorted(by: { $0.date < $1.date }) {
            if total <= cacheBudgetBytes { break }
            if entry.url == keeping { continue }
            // Only count space that was actually reclaimed, so a file that
            // refuses to delete doesn't stop the loop short of the budget.
            guard (try? fm.removeItem(at: entry.url)) != nil else { continue }
            total -= entry.size
        }
    }

    private func touch(_ url: URL) {
        try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: url.path)
    }

    private static func download(
        _ url: URL,
        to destination: URL,
        expectedSHA: String?,
        id: String,
        sessionConfiguration: URLSessionConfiguration
    ) async throws -> URL {
        await RemoteDownloadProgress.shared.begin(id)
        let downloader = ProgressiveDownloader(configuration: sessionConfiguration) { fraction in
            Task { @MainActor in Self.reportProgress(id, fraction) }
        }
        do {
            let tempURL = try await downloader.download(url)
            defer { try? FileManager.default.removeItem(at: tempURL) }

            if let expectedSHA, !expectedSHA.isEmpty {
                let data = try Data(contentsOf: tempURL)
                let actual = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
                guard actual == expectedSHA.lowercased() else { throw StoreError.checksumMismatch }
            }
            try? FileManager.default.removeItem(at: destination)
            try FileManager.default.moveItem(at: tempURL, to: destination)
            await RemoteDownloadProgress.shared.finish(id)
            return destination
        } catch {
            await RemoteDownloadProgress.shared.fail(
                id,
                permanent: (error as? StoreError) == .checksumMismatch
            )
            throw error
        }
    }

    /// Publishes progress only while the model is still in flight.
    ///
    /// Progress callbacks hop to the main actor on their own `Task`, separately
    /// from `finish`/`fail`, so a trailing update can otherwise land after the
    /// download has completed and strand the tile under a permanent 100%
    /// overlay. No entry means nothing is downloading, so there is nothing to
    /// report.
    @MainActor
    static func reportProgress(_ id: String, _ fraction: Double) {
        guard RemoteDownloadProgress.shared.fraction(for: id) != nil else { return }
        RemoteDownloadProgress.shared.update(id, fraction)
    }
}

/// URLSession download wrapped to report progress and a stable temp-file URL.
private final class ProgressiveDownloader: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private var continuation: CheckedContinuation<URL, Error>?
    private let onProgress: @Sendable (Double) -> Void
    private var lastReported: Double = -1
    private let configuration: URLSessionConfiguration
    private lazy var session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)

    init(
        configuration: URLSessionConfiguration,
        onProgress: @escaping @Sendable (Double) -> Void
    ) {
        self.configuration = configuration
        self.onProgress = onProgress
        super.init()
    }

    func download(_ url: URL) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            session.downloadTask(with: url).resume()
        }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64, totalBytesWritten: Int64,
                    totalBytesExpectedToWrite: Int64) {
        guard totalBytesExpectedToWrite > 0 else { return }
        let fraction = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
        if fraction - lastReported >= 0.02 || fraction >= 1.0 {
            lastReported = fraction
            onProgress(min(fraction, 1.0))
        }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didFinishDownloadingTo location: URL) {
        defer { session.finishTasksAndInvalidate() }
        if let http = downloadTask.response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            continuation?.resume(throwing: ModelFileStore.StoreError.downloadFailed)
            continuation = nil
            return
        }
        // `location` is removed once this method returns, so move it now.
        let stable = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".usdz")
        do {
            try FileManager.default.moveItem(at: location, to: stable)
            continuation?.resume(returning: stable)
        } catch {
            continuation?.resume(throwing: error)
        }
        continuation = nil
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let error, continuation != nil else { return }
        continuation?.resume(throwing: error)
        continuation = nil
        session.finishTasksAndInvalidate()
    }
}
