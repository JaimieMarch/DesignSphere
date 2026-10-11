//
//  CatalogDownloads.swift
//  XRShareCollaboration
//
//  The user-facing view of what the catalog has downloaded: how much space it
//  takes and a way to give that space back. Everything here is cache data, so
//  clearing it loses nothing; models and thumbnails download again on use.
//

import Foundation

public enum CatalogDownloads {
    /// Bytes used by downloaded models and thumbnails.
    public static func diskUsage() async -> Int64 {
        let models = await ModelFileStore.shared.downloadedBytes()
        let thumbnails = totalBytes(in: ThumbnailCache.remoteThumbnailDirectory, withExtension: "png")
        return models + thumbnails
    }

    /// Deletes downloaded models and thumbnails. Models still downloading are
    /// left alone, and thumbnails already on screen stay in memory.
    /// Returns the number of files removed.
    @discardableResult
    public static func removeAll() async -> Int {
        let models = await ModelFileStore.shared.removeAllDownloads()
        return models + removeFiles(in: ThumbnailCache.remoteThumbnailDirectory, withExtension: "png")
    }

    static func totalBytes(in directory: URL, withExtension ext: String) -> Int64 {
        let files = (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.fileSizeKey]
        )) ?? []
        return files
            .filter { $0.pathExtension == ext }
            .reduce(Int64(0)) { total, file in
                total + Int64((try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
            }
    }

    static func removeFiles(in directory: URL, withExtension ext: String) -> Int {
        let fm = FileManager.default
        let files = (try? fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        return files
            .filter { $0.pathExtension == ext }
            .filter { (try? fm.removeItem(at: $0)) != nil }
            .count
    }
}
