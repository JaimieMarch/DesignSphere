import Foundation
import simd

/// Persists and restores world-anchor transforms for project saves.
final class WorldAnchorProvider {
    static let shared = WorldAnchorProvider()

    private let fileURL: URL
    private var storedAnchors: [UUID: StoredAnchor] = [:]
    private let fileManager: FileManager

    private struct StoredAnchor: Codable {
        let id: UUID
        let matrix: [Float]

        var transform: simd_float4x4 {
            simd_float4x4(matrixArray: matrix)
        }
    }

    private init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
        let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        self.fileURL = documentsURL.appendingPathComponent("DesignSphereAnchors.json")
        loadFromDisk()
    }

    func saveAnchor(id: UUID, transform: simd_float4x4) {
        if storedAnchors[id] != nil {
            print("WorldAnchorProvider: Updating existing anchor \(id)")
        } else {
            print("WorldAnchorProvider: Creating new anchor \(id)")
        }
        storedAnchors[id] = StoredAnchor(id: id, matrix: transform.toArray())
        persist()
    }

    func transform(for id: UUID) -> simd_float4x4? {
        storedAnchors[id]?.transform
    }

    func hasAnchor(id: UUID) -> Bool {
        storedAnchors[id] != nil
    }

    func removeAnchor(id: UUID) {
        guard storedAnchors.removeValue(forKey: id) != nil else { return }
        persist()
    }

    func removeAllAnchors(deleteFile: Bool = false) {
        storedAnchors.removeAll()
        if deleteFile {
            try? fileManager.removeItem(at: fileURL)
        } else {
            persist()
        }
    }

    private func loadFromDisk() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        do {
            let decoder = JSONDecoder()
            let decoded = try decoder.decode([UUID: StoredAnchor].self, from: data)
            storedAnchors = decoded
        } catch {
            print("WorldAnchorProvider: Failed to load anchors – \(error)")
            storedAnchors = [:]
        }
    }

    private func persist() {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            let data = try encoder.encode(storedAnchors)
            try data.write(to: fileURL, options: .atomic)
            try fileManager.setAttributes(
                [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
                ofItemAtPath: fileURL.path
            )
        } catch {
            print("WorldAnchorProvider: Failed to persist anchors – \(error)")
        }
    }
}

private extension simd_float4x4 {
    func toArray() -> [Float] {
        [
            columns.0.x, columns.0.y, columns.0.z, columns.0.w,
            columns.1.x, columns.1.y, columns.1.z, columns.1.w,
            columns.2.x, columns.2.y, columns.2.z, columns.2.w,
            columns.3.x, columns.3.y, columns.3.z, columns.3.w
        ]
    }

    init(matrixArray: [Float]) {
        if matrixArray.count == 16 {
            self.init(columns: (
                SIMD4<Float>(matrixArray[0], matrixArray[1], matrixArray[2], matrixArray[3]),
                SIMD4<Float>(matrixArray[4], matrixArray[5], matrixArray[6], matrixArray[7]),
                SIMD4<Float>(matrixArray[8], matrixArray[9], matrixArray[10], matrixArray[11]),
                SIMD4<Float>(matrixArray[12], matrixArray[13], matrixArray[14], matrixArray[15])
            ))
        } else {
            self = matrix_identity_float4x4
        }
    }
}
