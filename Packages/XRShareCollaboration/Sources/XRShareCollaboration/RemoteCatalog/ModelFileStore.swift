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

    public enum StoreError: Error { case notRemote, downloadFailed, checksumMismatch }

    private var inFlight: [String: Task<URL, Error>] = [:]

    /// Soft cap on the on-disk model cache; least-recently-used usdz files are
    /// evicted past this. `Caches/` is also OS-purgeable, so this is best-effort.
    private let cacheBudgetBytes = 1_500_000_000  // ~1.5 GB

    private init() {}

    private var cacheDirectory: URL {
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
            return destination
        }

        if let existing = inFlight[key] {
            return try await existing.value
        }

        let expectedSHA = modelType.remoteSHA256
        let id = modelType.id
        let task = Task<URL, Error> {
            try await Self.download(remoteURL, to: destination, expectedSHA: expectedSHA, id: id)
        }
        inFlight[key] = task
        defer { inFlight[key] = nil }
        let url = try await task.value
        enforceBudget(keeping: url)
        return url
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
            try? fm.removeItem(at: entry.url)
            total -= entry.size
        }
    }

    private func touch(_ url: URL) {
        try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: url.path)
    }

    private static func download(_ url: URL, to destination: URL, expectedSHA: String?, id: String) async throws -> URL {
        await RemoteDownloadProgress.shared.begin(id)
        let downloader = ProgressiveDownloader { fraction in
            Task { @MainActor in RemoteDownloadProgress.shared.update(id, fraction) }
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
            await RemoteDownloadProgress.shared.finish(id)
            throw error
        }
    }
}

/// URLSession download wrapped to report progress and a stable temp-file URL.
private final class ProgressiveDownloader: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private var continuation: CheckedContinuation<URL, Error>?
    private let onProgress: @Sendable (Double) -> Void
    private var lastReported: Double = -1
    private lazy var session = URLSession(configuration: .default, delegate: self, delegateQueue: nil)

    init(onProgress: @escaping @Sendable (Double) -> Void) {
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
