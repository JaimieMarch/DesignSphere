import Foundation

private final class XRShareBundleMarker {}

public extension Bundle {
    #if SWIFT_PACKAGE
    private static var xrShareBundleCandidates: [Bundle] {
        var buckets: [Bundle] = [Bundle(for: XRShareBundleMarker.self)]
        buckets.append(contentsOf: Bundle.allBundles)
        buckets.append(contentsOf: Bundle.allFrameworks)
        buckets.append(Bundle.main)
        return uniqueBundles(buckets).filter { bundle in
            !bundle.bundlePath.contains("/System/Library")
        }
    }
    #else
    private static var xrShareBundleCandidates: [Bundle] {
        uniqueBundles([Bundle.main] + Bundle.allBundles + Bundle.allFrameworks).filter { bundle in
            !bundle.bundlePath.contains("/System/Library")
        }
    }
    #endif

    static var xrShareResources: Bundle {
        xrShareBundleCandidates.first ?? Bundle.main
    }

    static var xrShareResourceBundles: [Bundle] {
        xrShareBundleCandidates
    }

    static func xrShareLocateUSDZ(named name: String) -> URL? {
        // Search bundled resources first to prevent imported files from shadowing core catalog assets.
        let searchDirectories = ["Resources/Models", "Models"]
        for bundle in xrShareBundleCandidates {
            for subdirectory in searchDirectories {
                if let url = bundle.url(forResource: name, withExtension: "usdz", subdirectory: subdirectory) {
                    return url
                }
            }
            if let url = bundle.url(forResource: name, withExtension: "usdz") {
                return url
            }
        }

        // Then check Documents/Imports for user-imported models.
        let fileManager = FileManager.default
        if let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first {
            let importsURL = documentsURL.appendingPathComponent("Imports").appendingPathComponent("\(name).usdz")
            if fileManager.fileExists(atPath: importsURL.path) {
                return importsURL
            }
        }
        return nil
    }

    static func xrShareUSDZResources() -> [URL] {
        var unique: [String: URL] = [:]
        let searchDirectories = ["Resources/Models", "Models"]
        let fileManager = FileManager.default

        for bundle in xrShareBundleCandidates {
            for subdirectory in searchDirectories {
                guard let directoryURL = bundle.resourceURL?.appendingPathComponent(subdirectory) else { continue }
                guard let entries = try? fileManager.contentsOfDirectory(at: directoryURL, includingPropertiesForKeys: nil) else { continue }
                for url in entries where url.pathExtension.caseInsensitiveCompare("usdz") == .orderedSame {
                    let key = url.deletingPathExtension().lastPathComponent.lowercased()
                    if unique[key] == nil {
                        unique[key] = url
                    }
                }
            }

            if let fallback = bundle.urls(forResourcesWithExtension: "usdz", subdirectory: nil) {
                for url in fallback {
                    let key = url.deletingPathExtension().lastPathComponent.lowercased()
                    if unique[key] == nil {
                        unique[key] = url
                    }
                }
            }
        }

        // Also search Documents/Imports directory for user-imported models
        if let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first {
            let importsURL = documentsURL.appendingPathComponent("Imports")
            if let entries = try? fileManager.contentsOfDirectory(at: importsURL, includingPropertiesForKeys: nil) {
                for url in entries where url.pathExtension.caseInsensitiveCompare("usdz") == .orderedSame {
                    let key = url.deletingPathExtension().lastPathComponent.lowercased()
                    if unique[key] == nil {
                        unique[key] = url
                    }
                }
            }
        }

        return unique
            .sorted { $0.key < $1.key }
            .map { $0.value }
    }

    static func xrShareBuiltinUSDZNames() -> Set<String> {
        var names: Set<String> = []
        let searchDirectories = ["Resources/Models", "Models"]
        let fileManager = FileManager.default

        for bundle in xrShareBundleCandidates {
            for subdirectory in searchDirectories {
                guard let directoryURL = bundle.resourceURL?.appendingPathComponent(subdirectory) else { continue }
                guard let entries = try? fileManager.contentsOfDirectory(at: directoryURL, includingPropertiesForKeys: nil) else { continue }
                for url in entries where url.pathExtension.caseInsensitiveCompare("usdz") == .orderedSame {
                    names.insert(url.deletingPathExtension().lastPathComponent.lowercased())
                }
            }
            if let fallback = bundle.urls(forResourcesWithExtension: "usdz", subdirectory: nil) {
                for url in fallback {
                    names.insert(url.deletingPathExtension().lastPathComponent.lowercased())
                }
            }
        }

        return names
    }

    private static func uniqueBundles(_ bundles: [Bundle]) -> [Bundle] {
        var seen: Set<String> = []
        var result: [Bundle] = []
        for bundle in bundles {
            let path = bundle.bundlePath
            guard !path.isEmpty else { continue }
            if seen.insert(path).inserted {
                result.append(bundle)
            }
        }
        return result
    }
}
