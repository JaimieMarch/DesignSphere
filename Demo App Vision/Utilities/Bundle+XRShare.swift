import Foundation

private final class XRShareBundleMarker {}

extension Bundle {
    #if SWIFT_PACKAGE
    private static var xrShareBundleCandidates: [Bundle] {
        var buckets: [Bundle] = [Bundle(for: XRShareBundleMarker.self)]
        buckets.append(contentsOf: Bundle.allBundles)
        buckets.append(contentsOf: Bundle.allFrameworks)
        buckets.append(Bundle.main)
        return uniqueBundles(buckets)
    }
    #else
    private static var xrShareBundleCandidates: [Bundle] {
        uniqueBundles([Bundle.main] + Bundle.allBundles + Bundle.allFrameworks)
    }
    #endif

    public static var xrShareResources: Bundle {
        xrShareBundleCandidates.first ?? Bundle.main
    }

    public static var xrShareResourceBundles: [Bundle] {
        xrShareBundleCandidates
    }

    public static func xrShareLocateUSDZ(named name: String) -> URL? {
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
        return nil
    }

    public static func xrShareUSDZResources() -> [URL] {
        var unique: [String: URL] = [:]
        let searchDirectories = ["Resources/Models", "Models"]
        let fileManager = FileManager.default

        for bundle in xrShareBundleCandidates {
            for subdirectory in searchDirectories {
                guard let directoryURL = bundle.resourceURL?.appendingPathComponent(subdirectory) else { continue }
                guard let entries = try? fileManager.contentsOfDirectory(at: directoryURL, includingPropertiesForKeys: nil) else { continue }
                for url in entries where url.pathExtension.caseInsensitiveCompare("usdz") == .orderedSame {
                    unique[url.deletingPathExtension().lastPathComponent.lowercased()] = url
                }
            }

            if let fallback = bundle.urls(forResourcesWithExtension: "usdz", subdirectory: nil) {
                for url in fallback {
                    unique[url.deletingPathExtension().lastPathComponent.lowercased()] = url
                }
            }
        }

        return unique
            .sorted { $0.key < $1.key }
            .map { $0.value }
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
