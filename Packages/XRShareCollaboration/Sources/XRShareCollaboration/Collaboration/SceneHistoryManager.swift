import Foundation
import RealityKit
import simd

struct ModelSnapshot {
    let instanceID: UUID
    let modelType: ModelType
    let position: SIMD3<Float>
    let rotation: simd_quatf
    let scale: SIMD3<Float>
    let materials: [any Material]
    let materialType: String?
    let originalBounds: SIMD3<Float>?
    let snapState: SnapStateComponent?
}

enum SceneHistoryEntry {
    case add(ModelSnapshot)
    case remove(ModelSnapshot)
    case update(before: ModelSnapshot, after: ModelSnapshot)

    var focusInstanceID: UUID {
        switch self {
        case .add(let snapshot), .remove(let snapshot):
            return snapshot.instanceID
        case .update(_, let after):
            return after.instanceID
        }
    }
}

@MainActor
final class SceneHistoryManager: ObservableObject {
    @Published private(set) var canUndo = false
    @Published private(set) var canRedo = false

    private var undoStack: [SceneHistoryEntry] = []
    private var redoStack: [SceneHistoryEntry] = []
    private var activeTransactions: [UUID: ModelSnapshot] = [:]
    private var recordingSuppressionDepth = 0

    private(set) var isApplyingHistory = false
    var isRecordingSuspended: Bool {
        recordingSuppressionDepth > 0
    }

    func clear() {
        undoStack.removeAll()
        redoStack.removeAll()
        activeTransactions.removeAll()
        isApplyingHistory = false
        publishAvailability()
    }

    func beginRecordingSuppression() {
        recordingSuppressionDepth += 1
    }

    func endRecordingSuppression() {
        guard recordingSuppressionDepth > 0 else { return }
        recordingSuppressionDepth -= 1
    }

    func beginTransactionIfNeeded(with snapshot: ModelSnapshot) {
        guard !isApplyingHistory, !isRecordingSuspended else { return }
        guard activeTransactions[snapshot.instanceID] == nil else { return }
        activeTransactions[snapshot.instanceID] = snapshot
    }

    func discardTransaction(for instanceID: UUID) {
        activeTransactions.removeValue(forKey: instanceID)
    }

    func commitTransaction(
        for instanceID: UUID,
        after snapshot: ModelSnapshot,
        forceRecord: Bool
    ) {
        guard !isApplyingHistory, !isRecordingSuspended else { return }
        guard let before = activeTransactions.removeValue(forKey: instanceID) else { return }

        if !forceRecord, !hasMeaningfulTransformDelta(from: before, to: snapshot) {
            return
        }

        push(.update(before: before, after: snapshot))
    }

    func recordAdd(_ snapshot: ModelSnapshot) {
        guard !isApplyingHistory, !isRecordingSuspended else { return }
        activeTransactions.removeValue(forKey: snapshot.instanceID)
        push(.add(snapshot))
    }

    func recordRemove(_ snapshot: ModelSnapshot) {
        guard !isApplyingHistory, !isRecordingSuspended else { return }
        activeTransactions.removeValue(forKey: snapshot.instanceID)
        push(.remove(snapshot))
    }

    func prepareUndo() -> SceneHistoryEntry? {
        guard let entry = undoStack.popLast() else { return nil }
        isApplyingHistory = true
        publishAvailability()
        return entry
    }

    func finishUndo(_ entry: SceneHistoryEntry) {
        redoStack.append(entry)
        isApplyingHistory = false
        publishAvailability()
    }

    func cancelUndo(_ entry: SceneHistoryEntry) {
        undoStack.append(entry)
        isApplyingHistory = false
        publishAvailability()
    }

    func prepareRedo() -> SceneHistoryEntry? {
        guard let entry = redoStack.popLast() else { return nil }
        isApplyingHistory = true
        publishAvailability()
        return entry
    }

    func finishRedo(_ entry: SceneHistoryEntry) {
        undoStack.append(entry)
        isApplyingHistory = false
        publishAvailability()
    }

    func cancelRedo(_ entry: SceneHistoryEntry) {
        redoStack.append(entry)
        isApplyingHistory = false
        publishAvailability()
    }

    private func push(_ entry: SceneHistoryEntry) {
        undoStack.append(entry)
        redoStack.removeAll()
        publishAvailability()
    }

    private func publishAvailability() {
        canUndo = !undoStack.isEmpty
        canRedo = !redoStack.isEmpty
    }

    private func hasMeaningfulTransformDelta(
        from before: ModelSnapshot,
        to after: ModelSnapshot
    ) -> Bool {
        if simd_distance(before.position, after.position) > 0.001 {
            return true
        }

        if simd_length(before.scale - after.scale) > 0.001 {
            return true
        }

        let rotationDelta = abs(simd_dot(before.rotation.vector, after.rotation.vector))
        if rotationDelta < 0.9995 {
            return true
        }

        return false
    }
}
