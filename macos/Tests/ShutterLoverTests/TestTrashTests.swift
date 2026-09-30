import XCTest
import MeasurementCore
@testable import ShutterLover

final class TestTrashTests: XCTestCase {
    @MainActor
    private func withModel(sessions: [CaptureSession], cameras: [CameraProfile] = [], _ body: (AppModel, UserDefaults) throws -> Void) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("test-trash-\(UUID().uuidString)")
        let suite = "test-trash-preferences-\(UUID().uuidString)"
        let preferences = try XCTUnwrap(UserDefaults(suiteName: suite))
        let store = SessionStore(directory: directory)
        try store.saveLibrary(CameraLibraryArchive(cameras: cameras, sessions: sessions))
        let model = AppModel(store: store, startDiscovery: false, preferences: preferences)
        defer {
            model.shutDown()
            preferences.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: directory)
        }
        try body(model, preferences)
    }

    private func testSession(demo: Bool = false) throws -> CaptureSession {
        let packet = DemoPackets.sample(nominalDenominator: 125, index: 0)
        var record = MeasurementRecord(rawLine: String(decoding: try JSONEncoder().encode(packet), as: UTF8.self), packet: packet, direction: .horizontal, nominalDenominator: 125, isDemo: demo)
        record.derivedSnapshot = record.result
        var session = CaptureSession(cameraName: demo ? "Demo camera" : "Test camera", demo: demo)
        session.records = [record]
        session.revision = 7
        session.lastExportedRevision = 7
        session.notes = "Original evidence must survive Trash."
        return session
    }

    private func evidence(_ session: CaptureSession) throws -> Data {
        var value = session
        value.trashedAt = nil
        return try SessionStore.encoder().encode(value)
    }

    @MainActor
    func testTrashAndRestorePersistSameEvidenceIdentityAndRevision() throws {
        let session = try testSession()
        try withModel(sessions: [session]) { model, _ in
            model.selectSession(session.id)
            let original = try evidence(XCTUnwrap(model.currentSession))
            XCTAssertTrue(model.canTrashSession(session.id))
            model.trashSession(session.id)
            XCTAssertNil(model.selectedSessionID)
            XCTAssertNil(model.selectedRecordID)
            XCTAssertTrue(model.showCameraLibrary)
            XCTAssertTrue(model.sidebarSessions.isEmpty)
            XCTAssertEqual(model.trashedSessions.map(\.id), [session.id])
            XCTAssertFalse(model.canTrashSession(session.id))
            var stored = try XCTUnwrap(model.store.loadLibrary().sessions.first)
            XCTAssertTrue(stored.isTrashed)
            XCTAssertEqual(try evidence(stored), original)

            model.restoreSession(session.id)
            stored = try XCTUnwrap(model.store.loadLibrary().sessions.first)
            XCTAssertFalse(stored.isTrashed)
            XCTAssertEqual(try evidence(stored), original)
            XCTAssertEqual(model.selectedSessionID, session.id)
            XCTAssertEqual(model.selectedRecordID, session.records[0].id)
            XCTAssertFalse(model.showCameraLibrary)
            XCTAssertTrue(model.trashedSessions.isEmpty)
            XCTAssertEqual(model.sidebarSessions.map(\.id), [session.id])
        }
    }

    @MainActor
    func testActiveDestinationCannotBeTrashedWhileConnectedOrReconnecting() throws {
        let session = try testSession()
        try withModel(sessions: [session]) { model, _ in
            model.activeCaptureSessionID = session.id
            for state in [(true, false), (false, true), (false, false)] {
                model.isConnected = state.0
                model.isConnecting = state.1
                XCTAssertFalse(model.canTrashSession(session.id))
                model.trashSession(session.id)
                XCTAssertFalse(try XCTUnwrap(model.sessions.first).isTrashed)
                XCTAssertEqual(model.activeCaptureSessionID, session.id)
                XCTAssertNotNil(model.errorMessage)
            }
            model.disconnect()
            XCTAssertTrue(model.canTrashSession(session.id))
        }
    }

    @MainActor
    func testTrashAndRestoreOfHistoricalTestNeverRetargetCapture() throws {
        let historical = try testSession()
        let live = try testSession()
        try withModel(sessions: [historical, live]) { model, _ in
            model.activeCaptureSessionID = live.id
            model.selectSession(historical.id)
            model.trashSession(historical.id)
            XCTAssertEqual(model.activeCaptureSessionID, live.id)
            model.restoreSession(historical.id)
            XCTAssertEqual(model.selectedSessionID, historical.id)
            XCTAssertEqual(model.activeCaptureSessionID, live.id)
        }
    }

    @MainActor
    func testOnlyTrashedTestsAtStartupDoNotCreateDemoOrSelectTrash() throws {
        var session = try testSession(demo: true)
        session.trashedAt = Date()
        try withModel(sessions: [session]) { model, _ in
            XCTAssertEqual(model.sessions.count, 1)
            XCTAssertNil(model.currentSession)
            XCTAssertNil(model.selectedSessionID)
            XCTAssertNil(model.selectedRecordID)
            XCTAssertTrue(model.showCameraLibrary)
            XCTAssertTrue(model.sidebarSessions.isEmpty)
            XCTAssertEqual(model.demoSessionCount, 0)
            XCTAssertEqual(model.trashedSessions.map(\.id), [session.id])
            model.selectSession(session.id)
            XCTAssertNil(model.selectedSessionID)
            XCTAssertEqual(try model.store.loadLibrary().sessions.count, 1)
        }
    }

    func testLegacySessionsDecodeWithoutTrashProperty() throws {
        let session = try testSession()
        let data = try SessionStore.encoder().encode(SessionArchive(sessions: [session]))
        XCTAssertFalse(String(decoding: data, as: UTF8.self).contains("trashedAt"))
        let decoded = try XCTUnwrap(SessionStore.decode(data).first)
        XCTAssertNil(decoded.trashedAt)
        XCTAssertFalse(decoded.isTrashed)
        XCTAssertEqual(decoded.id, session.id)
        XCTAssertEqual(decoded.records.first?.id, session.records.first?.id)
    }

    @MainActor
    func testFailedTrashOrRestoreDoesNotPublishUnsavedState() throws {
        let session = try testSession()
        try withModel(sessions: [session]) { model, _ in
            let blocker = model.store.directory.appendingPathComponent("library.previous.json", isDirectory: true)
            let before = try Data(contentsOf: model.store.cameraLibraryURL)
            try FileManager.default.createDirectory(at: blocker, withIntermediateDirectories: false)
            model.trashSession(session.id)
            XCTAssertNotNil(model.errorMessage)
            XCTAssertFalse(try XCTUnwrap(model.sessions.first).isTrashed)
            XCTAssertEqual(model.selectedSessionID, session.id)
            XCTAssertEqual(try Data(contentsOf: model.store.cameraLibraryURL), before)

            try FileManager.default.removeItem(at: blocker)
            model.errorMessage = nil
            model.trashSession(session.id)
            XCTAssertTrue(try XCTUnwrap(model.sessions.first).isTrashed)
            let trashed = try Data(contentsOf: model.store.cameraLibraryURL)
            try FileManager.default.removeItem(at: blocker)
            try FileManager.default.createDirectory(at: blocker, withIntermediateDirectories: false)
            model.restoreSession(session.id)
            XCTAssertNotNil(model.errorMessage)
            XCTAssertTrue(try XCTUnwrap(model.sessions.first).isTrashed)
            XCTAssertNil(model.selectedSessionID)
            XCTAssertEqual(try Data(contentsOf: model.store.cameraLibraryURL), trashed)
            try FileManager.default.removeItem(at: blocker)
        }
    }

    @MainActor
    func testUnreadableLibraryGuardBlocksTrashAndRestore() throws {
        let active = try testSession()
        var trashed = try testSession()
        trashed.trashedAt = Date()
        try withModel(sessions: [active, trashed]) { model, _ in
            let before = try Data(contentsOf: model.store.cameraLibraryURL)
            model.libraryReadFailed = true
            XCTAssertFalse(model.canTrashSession(active.id))
            model.trashSession(active.id)
            model.restoreSession(trashed.id)
            XCTAssertFalse(try XCTUnwrap(model.sessions.first { $0.id == active.id }).isTrashed)
            XCTAssertTrue(try XCTUnwrap(model.sessions.first { $0.id == trashed.id }).isTrashed)
            XCTAssertEqual(try Data(contentsOf: model.store.cameraLibraryURL), before)
            XCTAssertNotNil(model.errorMessage)
            model.libraryReadFailed = false
        }
    }

    @MainActor
    func testCameraArchiveRetainsTrashedTestsAndServiceLinks() throws {
        var camera = CameraProfile(name: "Camera with service history")
        var before = try testSession()
        before.cameraID = camera.id
        var after = try testSession()
        after.cameraID = camera.id
        var service = CameraServiceEvent(title: "Shutter service")
        service.beforeSessionID = before.id
        service.afterSessionID = after.id
        camera.serviceEvents = [service]
        try withModel(sessions: [before, after], cameras: [camera]) { model, _ in
            model.trashSession(before.id)
            XCTAssertEqual(model.cameraSessions(camera.id).map(\.id), [after.id])
            let archive = try model.cameraArchive(camera.id)
            let decoded = try PortableCameraArchive.decode(SessionStore.encoder().encode(archive))
            XCTAssertEqual(Set(decoded.sessions.map(\.id)), [before.id, after.id])
            XCTAssertTrue(try XCTUnwrap(decoded.sessions.first { $0.id == before.id }).isTrashed)
            XCTAssertEqual(decoded.camera.serviceEvents.first?.beforeSessionID, before.id)
            XCTAssertEqual(decoded.camera.serviceEvents.first?.afterSessionID, after.id)
            XCTAssertNoThrow(try SessionStore.validateLibrary(model.store.loadLibrary()))
            let (copiedCamera, copiedTests) = decoded.localCopy()
            XCTAssertNoThrow(try SessionStore.validateLibrary(CameraLibraryArchive(cameras: [copiedCamera], sessions: copiedTests)))
            XCTAssertEqual(copiedTests.filter(\.isTrashed).count, 1)
        }
    }

    @MainActor
    func testTrashedEvidenceCannotBeSelectedMutatedAssignedOrRecordedInto() throws {
        var session = try testSession()
        session.lastExportedRevision = nil
        let camera = CameraProfile(name: "Other camera")
        try withModel(sessions: [session], cameras: [camera]) { model, _ in
            model.trashSession(session.id)
            let trashed = try evidence(XCTUnwrap(model.sessions.first))
            model.selectSession(session.id)
            XCTAssertNil(model.selectedSessionID)
            // Stale view callbacks and serial events must also be harmless.
            model.selectedSessionID = session.id
            model.selectedRecordID = session.records[0].id
            model.activeCaptureSessionID = session.id
            model.nominalDenominator = 60
            model.toggleExcluded(session.records[0].id)
            model.updateSelectedSetting(60)
            model.deleteSelectedReading()
            var edit = session
            edit.notes = "Stale editor callback"
            model.updateTestDetails(edit)
            model.assignSession(session.id, to: camera.id)
            model.append(packet: try XCTUnwrap(session.records[0].packet), raw: session.records[0].rawLine, simulated: false)
            model.activeCaptureSessionID = nil
            model.isConnected = true
            model.recordIntoSelectedTest()
            XCTAssertNil(model.activeCaptureSessionID)
            XCTAssertNil(model.currentSession)
            XCTAssertEqual(try evidence(XCTUnwrap(model.sessions.first)), trashed)
            XCTAssertThrowsError(try ShutterTesterExchange.exportResults(producerLibraryID: model.libraryID, session: XCTUnwrap(model.sessions.first)))
            // Must return before presenting a file save panel.
            model.exportTesterResults(session.id)
            model.exportSession()
            model.exportCSV()
        }
    }

    @MainActor
    func testReadingUndoWaitsUntilTestRestored() throws {
        let session = try testSession()
        try withModel(sessions: [session]) { model, _ in
            model.selectSession(session.id)
            model.deleteSelectedReading()
            XCTAssertTrue(model.canUndoDelete)
            model.trashSession(session.id)
            XCTAssertFalse(model.canUndoDelete)
            model.undoDelete()
            XCTAssertTrue(try XCTUnwrap(model.sessions.first).records.isEmpty)
            model.restoreSession(session.id)
            XCTAssertTrue(model.canUndoDelete)
            model.undoDelete()
            XCTAssertEqual(model.currentRecords.map(\.id), session.records.map(\.id))
            XCTAssertFalse(model.canUndoDelete)
        }
    }

    @MainActor
    func testRestoringHiddenDemoRevealsItWithoutCreatingAnotherDemo() throws {
        let session = try testSession(demo: true)
        try withModel(sessions: [session]) { model, preferences in
            model.trashSession(session.id)
            model.setShowDemoSessions(false)
            model.restoreSession(session.id)
            XCTAssertTrue(model.showDemoSessions)
            XCTAssertTrue(preferences.bool(forKey: "showDemoSessions"))
            XCTAssertEqual(model.sessions.count, 1)
            XCTAssertEqual(model.demoSessionCount, 1)
            XCTAssertEqual(model.sidebarSessions.map(\.id), [session.id])
            XCTAssertEqual(model.selectedSessionID, session.id)
        }
    }
}
