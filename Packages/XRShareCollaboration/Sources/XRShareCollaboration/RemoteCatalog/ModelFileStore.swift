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
        let task = Task<URL, Error> {
            try await Self.download(remoteURL, to: destination, expectedSHA: expectedSHA)
        }
        inFlight[key] = task
        defer { inFlight[key] = nil }
        return try await task.value
    }

    private func touch(_ url: URL) {
        try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: url.path)
    }

    private static func download(_ url: URL, to destination: URL, expectedSHA: String?) async throws -> URL {
        let (tempURL, response) = try await URLSession.shared.download(from: url)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw StoreError.downloadFailed
        }
        if let expectedSHA, !expectedSHA.isEmpty {
            let data = try Data(contentsOf: tempURL)
            let actual = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
            guard actual == expectedSHA.lowercased() else { throw StoreError.checksumMismatch }
        }
        try? FileManager.default.removeItem(at: destination)
        try FileManager.default.moveItem(at: tempURL, to: destination)
        return destination
    }
}
