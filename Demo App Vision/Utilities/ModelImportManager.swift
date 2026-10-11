import Foundation
import RealityKit
import XRShareCollaboration

@MainActor
enum ModelImportManager {
    static let maximumFileBytes = 150 * 1_024 * 1_024

    enum ImportError: LocalizedError {
        case invalidFile, invalidName, duplicateName, tooLarge

        var errorDescription: String? {
            switch self {
            case .invalidFile: return "Choose a valid USDZ file containing a 3D model."
            case .invalidName: return "Rename the file using a shorter model name and try again."
            case .duplicateName: return "A model with that name already exists in the catalog. Rename the file and try again."
            case .tooLarge: return "Model is too large. The maximum import size is 150 MB."
            }
        }
    }

    static func importModel(from source: URL, existingNames: Set<String>, directory: URL? = nil) async throws -> String {
        guard source.isFileURL, source.pathExtension.lowercased() == "usdz" else { throw ImportError.invalidFile }
        let scoped = source.startAccessingSecurityScopedResource()
        defer { if scoped { source.stopAccessingSecurityScopedResource() } }
        try validateSize(at: source)

        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_-"))
        let name = String(source.deletingPathExtension().lastPathComponent.unicodeScalars.map {
            allowed.contains($0) ? Character($0) : "_"
        }).replacingOccurrences(of: "__", with: "_")
            .trimmingCharacters(in: CharacterSet(charactersIn: "_-"))
        guard !name.isEmpty, name.utf8.count <= 180 else { throw ImportError.invalidName }

        let files = FileManager.default
        let imports = directory ?? files.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Imports", isDirectory: true)
        try files.createDirectory(at: imports, withIntermediateDirectories: true)
        let localNames = try files.contentsOfDirectory(at: imports, includingPropertiesForKeys: nil)
            .map { $0.deletingPathExtension().lastPathComponent.lowercased() }
        let reserved = Set(existingNames.map { $0.lowercased() })
            .union(localNames).union(Bundle.xrShareBuiltinUSDZNames())
        guard !reserved.contains(name.lowercased()) else { throw ImportError.duplicateName }

        let staged = files.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".usdz")
        defer { try? files.removeItem(at: staged) }
        try files.copyItem(at: source, to: staged)
        try validateSize(at: staged)
        do {
            let entity = try await ModelEntity(contentsOf: staged)
            let extents = entity.visualBounds(relativeTo: entity).extents
            guard [extents.x, extents.y, extents.z].allSatisfy(\.isFinite),
                  max(extents.x, max(extents.y, extents.z)) > 0 else { throw ImportError.invalidFile }
        } catch { throw ImportError.invalidFile }

        // Loading yields the main actor; a second import may have claimed this
        // name while we validated. Check again before committing the file.
        let destination = imports.appendingPathComponent(name + ".usdz")
        guard !files.fileExists(atPath: destination.path) else { throw ImportError.duplicateName }
        try files.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: staged.path)
        try files.moveItem(at: staged, to: destination)
        return name
    }

    private static func validateSize(at url: URL) throws {
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        guard values.isRegularFile == true, let size = values.fileSize, size > 0 else { throw ImportError.invalidFile }
        guard size <= maximumFileBytes else { throw ImportError.tooLarge }
    }
}
