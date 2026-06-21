import RealityKit
import XCTest
import simd
@testable import XRShareCollaboration

@MainActor
final class SceneHistoryTests: XCTestCase {
    func testAddCanBeUndoneAndRedone() throws {
        let history = SceneHistoryManager()
        let snapshot = makeSnapshot()
        history.recordAdd(snapshot)
        XCTAssertTrue(history.canUndo)
        XCTAssertFalse(history.canRedo)

        let entry = try XCTUnwrap(history.prepareUndo())
        XCTAssertTrue(history.isApplyingHistory)
        XCTAssertEqual(entry.focusInstanceID, snapshot.instanceID)
        history.finishUndo(entry)
        XCTAssertFalse(history.canUndo)
        XCTAssertTrue(history.canRedo)

        let redo = try XCTUnwrap(history.prepareRedo())
        history.finishRedo(redo)
        XCTAssertTrue(history.canUndo)
        XCTAssertFalse(history.canRedo)
        XCTAssertFalse(history.isApplyingHistory)
    }

    func testCancelledUndoAndRedoReturnEntriesToOriginalStacks() throws {
        let history = SceneHistoryManager()
        history.recordRemove(makeSnapshot())

        let undo = try XCTUnwrap(history.prepareUndo())
        history.cancelUndo(undo)
        XCTAssertTrue(history.canUndo)
        XCTAssertFalse(history.canRedo)

        let secondUndo = try XCTUnwrap(history.prepareUndo())
        history.finishUndo(secondUndo)
        let redo = try XCTUnwrap(history.prepareRedo())
        history.cancelRedo(redo)
        XCTAssertFalse(history.canUndo)
        XCTAssertTrue(history.canRedo)
    }

    func testClearResetsStacksTransactionsAndApplyingState() throws {
        let history = SceneHistoryManager()
        let snapshot = makeSnapshot()
        history.recordAdd(snapshot)
        _ = try XCTUnwrap(history.prepareUndo())
        history.beginTransactionIfNeeded(with: snapshot)
        history.clear()
        XCTAssertFalse(history.canUndo)
        XCTAssertFalse(history.canRedo)
        XCTAssertFalse(history.isApplyingHistory)
        XCTAssertNil(history.prepareUndo())
        XCTAssertNil(history.prepareRedo())
    }

    func testSuppressionIsNestedAndPreventsRecording() {
        let history = SceneHistoryManager()
        history.beginRecordingSuppression()
        history.beginRecordingSuppression()
        XCTAssertTrue(history.isRecordingSuspended)
        history.recordAdd(makeSnapshot())
        history.endRecordingSuppression()
        XCTAssertTrue(history.isRecordingSuspended)
        history.endRecordingSuppression()
        XCTAssertFalse(history.isRecordingSuspended)
        history.endRecordingSuppression()
        XCTAssertFalse(history.isRecordingSuspended)
        XCTAssertFalse(history.canUndo)
    }

    func testInsignificantTransactionIsNotRecorded() {
        let history = SceneHistoryManager()
        let before = makeSnapshot()
        let after = makeSnapshot(
            id: before.instanceID,
            position: SIMD3<Float>(0.0005, 0, 0),
            scale: SIMD3<Float>(1.0005, 1, 1)
        )
        history.beginTransactionIfNeeded(with: before)
        history.commitTransaction(for: before.instanceID, after: after, forceRecord: false)
        XCTAssertFalse(history.canUndo)
    }

    func testPositionScaleAndRotationDeltasAreRecorded() {
        let changes: [(ModelSnapshot) -> ModelSnapshot] = [
            { before in self.makeSnapshot(id: before.instanceID, position: SIMD3<Float>(0.002, 0, 0)) },
            { before in self.makeSnapshot(id: before.instanceID, scale: SIMD3<Float>(1.002, 1, 1)) },
            { before in self.makeSnapshot(id: before.instanceID, rotation: simd_quatf(angle: 0.1, axis: SIMD3<Float>(0, 1, 0))) }
        ]

        for change in changes {
            let history = SceneHistoryManager()
            let before = makeSnapshot()
            history.beginTransactionIfNeeded(with: before)
            history.commitTransaction(for: before.instanceID, after: change(before), forceRecord: false)
            XCTAssertTrue(history.canUndo)
        }
    }

    func testForceRecordCapturesUnchangedTransaction() {
        let history = SceneHistoryManager()
        let snapshot = makeSnapshot()
        history.beginTransactionIfNeeded(with: snapshot)
        history.commitTransaction(for: snapshot.instanceID, after: snapshot, forceRecord: true)
        XCTAssertTrue(history.canUndo)
    }

    func testDiscardedAndMissingTransactionsDoNotRecord() {
        let history = SceneHistoryManager()
        let snapshot = makeSnapshot()
        history.beginTransactionIfNeeded(with: snapshot)
        history.discardTransaction(for: snapshot.instanceID)
        history.commitTransaction(for: snapshot.instanceID, after: snapshot, forceRecord: true)
        XCTAssertFalse(history.canUndo)
    }

    func testNewEntryClearsRedoHistory() throws {
        let history = SceneHistoryManager()
        history.recordAdd(makeSnapshot())
        let entry = try XCTUnwrap(history.prepareUndo())
        history.finishUndo(entry)
        XCTAssertTrue(history.canRedo)
        history.recordAdd(makeSnapshot())
        XCTAssertFalse(history.canRedo)
    }

    private func makeSnapshot(
        id: UUID = UUID(),
        position: SIMD3<Float> = .zero,
        rotation: simd_quatf = simd_quatf(angle: 0, axis: SIMD3<Float>(0, 1, 0)),
        scale: SIMD3<Float> = .one
    ) -> ModelSnapshot {
        ModelSnapshot(
            instanceID: id,
            modelType: ModelType(rawValue: "chair", classification: .floor),
            position: position,
            rotation: rotation,
            scale: scale,
            materials: [],
            materialType: nil,
            originalBounds: nil,
            snapState: nil
        )
    }
}
