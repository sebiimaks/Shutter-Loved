import XCTest
import MeasurementCore
@testable import ShutterLover

final class SidebarInteractionTests: XCTestCase {
    @MainActor
    private func withModel(_ body: (AppModel, UserDefaults) throws -> Void) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("sidebar-tests-\(UUID().uuidString)")
        let suite = "sidebar-tests-\(UUID().uuidString)"
        let preferences = try XCTUnwrap(UserDefaults(suiteName: suite))
        let model = AppModel(store: SessionStore(directory: directory), startDiscovery: false, preferences: preferences)
        defer {
            model.shutDown()
            preferences.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: directory)
        }
        try body(model, preferences)
    }

    @MainActor
    func testContextDeletionTargetsRequestedReadingAndUndoPreservesEvidence() throws {
        try withModel { model, _ in
            model.addDemoReading()
            model.addDemoReading()
            model.addDemoReading()
            let before = model.currentRecords
            let testID = try XCTUnwrap(model.selectedSessionID)
            let revision = try XCTUnwrap(model.currentSession).effectiveRevision
            model.selectedRecordID = before[2].id
            model.deleteReading(before[0].id)
            XCTAssertEqual(model.currentRecords.map(\.id), [before[1].id, before[2].id])
            XCTAssertEqual(model.selectedRecordID, before[2].id)
            XCTAssertEqual(model.currentSession?.effectiveRevision, revision + 1)
            XCTAssertEqual(try model.store.loadLibrary().sessions.first(where: { $0.id == testID })?.records.count, 2)
            model.undoDelete()
            XCTAssertEqual(model.currentRecords.map(\.id), before.map(\.id))
            XCTAssertEqual(model.currentRecords.map(\.rawLine), before.map(\.rawLine))
            XCTAssertEqual(model.selectedRecordID, before[0].id)
            XCTAssertFalse(model.canUndoDelete)
            XCTAssertEqual(model.currentSession?.effectiveRevision, revision + 2)
        }
    }

    @MainActor
    func testDeleteSelectionMovesToNeighbourAndLastReadingCanBeUndone() throws {
        try withModel { model, _ in
            model.addDemoReading()
            model.addDemoReading()
            model.addDemoReading()
            let ids = model.currentRecords.map(\.id)
            model.selectedRecordID = ids[1]
            model.deleteSelectedReading()
            XCTAssertEqual(model.selectedRecordID, ids[2])
            model.deleteReading(ids[2])
            XCTAssertEqual(model.selectedRecordID, ids[0])
            model.deleteSelectedReading()
            XCTAssertNil(model.selectedRecordID)
            XCTAssertTrue(model.currentRecords.isEmpty)
            model.undoDelete()
            XCTAssertEqual(model.currentRecords.map(\.id), [ids[0]])
            XCTAssertEqual(model.selectedRecordID, ids[0])
        }
    }

    @MainActor
    func testHidingDemosPersistsWithoutChangingEvidenceOrLiveCaptureDestination() throws {
        try withModel { model, preferences in
            let demoID = try XCTUnwrap(model.selectedSessionID)
            model.addDemoReading()
            model.newSession(demo: false)
            let realID = try XCTUnwrap(model.selectedSessionID)
            model.activeCaptureSessionID = realID
            model.selectSession(demoID)
            let before = try Data(contentsOf: model.store.cameraLibraryURL)
            model.setShowDemoSessions(false)
            XCTAssertEqual(model.sidebarSessions.map(\.id), [realID])
            XCTAssertTrue(model.showCameraLibrary)
            XCTAssertEqual(model.activeCaptureSessionID, realID)
            XCTAssertEqual(try Data(contentsOf: model.store.cameraLibraryURL), before)
            let packet = DemoPackets.sample(nominalDenominator: 125, index: 0)
            model.append(packet: packet, raw: String(decoding: try JSONEncoder().encode(packet), as: UTF8.self), simulated: false)
            XCTAssertEqual(model.sessions.first(where: { $0.id == realID })?.records.count, 1)
            XCTAssertEqual(model.sessions.first(where: { $0.id == demoID })?.records.count, 1)
            let reopened = AppModel(store: model.store, startDiscovery: false, preferences: preferences)
            XCTAssertFalse(reopened.showDemoSessions)
            XCTAssertEqual(reopened.sidebarSessions.map(\.id), [realID])
            reopened.shutDown()
            model.newSession(demo: true)
            XCTAssertTrue(model.showDemoSessions)
            XCTAssertTrue(model.sidebarSessions.contains(where: { $0.id == model.selectedSessionID }))
            XCTAssertEqual(model.activeCaptureSessionID, realID)
        }
    }
}
