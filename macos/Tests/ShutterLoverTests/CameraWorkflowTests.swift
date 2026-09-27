import XCTest
import MeasurementCore
@testable import ShutterLover

final class CameraWorkflowTests: XCTestCase {
    @MainActor
    private func withModel(_ body: (AppModel) throws -> Void) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("camera-workflow-tests-\(UUID().uuidString)")
        let model = AppModel(store: SessionStore(directory: directory), startDiscovery: false)
        defer {
            model.shutDown()
            try? FileManager.default.removeItem(at: directory)
        }
        try body(model)
    }

    @MainActor
    private func receive(_ model: AppModel, nominal: Double = 125, partial: Bool = false, index: Int = 0) throws {
        let packet = DemoPackets.sample(nominalDenominator: nominal, index: index, partial: partial)
        let raw = String(decoding: try JSONEncoder().encode(packet), as: UTF8.self)
        model.append(packet: packet, raw: raw, simulated: false)
    }

    private func linkedCamera(name: String = "Nikon F2") -> CameraProfile {
        var camera = CameraProfile(name: name)
        camera.manufacturer = "Nikon"
        camera.model = "F2"
        camera.serial = "7340001"
        camera.inventoryID = "SL-001"
        camera.defaultDirection = .horizontal
        camera.plannedSpeeds = [30, 60, 125, 250]
        camera.catalogueID = UUID()
        camera.catalogueCameraID = UUID()
        camera.catalogueRevision = 3
        camera.catalogueSnapshots = [CatalogueSnapshot(revision: 3, profileJSON: Data("{}".utf8), importedAt: Date(), sourceApplication: "Armarium Lucis")]
        return camera
    }

    @MainActor
    func testNewCameraAndTestPersistSetupAndCapturedIdentity() throws {
        try withModel { model in
            model.newCamera()
            var camera = try XCTUnwrap(model.editingCamera)
            camera.name = "  Canon VIL  "
            camera.serial = "123456"
            camera.defaultDirection = .horizontal
            camera.plannedSpeeds = [60, 125, 250]
            model.saveCamera(camera)
            XCTAssertEqual(model.selectedCamera?.name, "Canon VIL")
            XCTAssertTrue(model.showCameraLibrary)
            model.newCameraTest(camera.id, title: "Before service")
            let test = try XCTUnwrap(model.currentSession)
            XCTAssertFalse(test.demo)
            XCTAssertEqual(test.cameraID, camera.id)
            XCTAssertEqual(test.cameraSnapshot?.serial, "123456")
            XCTAssertEqual(test.cameraSnapshot?.name, "Canon VIL")
            XCTAssertEqual(test.direction, .horizontal)
            XCTAssertEqual(test.plannedSpeeds, [60, 125, 250])
            XCTAssertEqual(test.repeatsPerSpeed, 3)
            XCTAssertEqual(test.toleranceStops, 1.0 / 3.0)
            XCTAssertEqual(test.displayTitle, "Before service")
            XCTAssertNil(model.activeCaptureSessionID, "A disconnected new test must not pretend the device is recording.")
            camera.serial = "Corrected catalogue serial"
            model.saveCamera(camera)
            XCTAssertEqual(model.sessions.first(where: { $0.id == test.id })?.cameraSnapshot?.serial, "123456")
            let saved = try model.store.loadLibrary()
            XCTAssertEqual(saved.cameras.count, 1)
            XCTAssertEqual(saved.sessions.first(where: { $0.id == test.id })?.cameraSnapshot?.serial, "123456")
            XCTAssertEqual(saved.libraryID, model.libraryID)
        }
    }

    @MainActor
    func testBrowsingOtherCamerasHistoricalTestsAndDemoNeverRetargetsLiveReadings() throws {
        try withModel { model in
            let camera = linkedCamera()
            let other = CameraProfile(name: "Different camera")
            model.saveCamera(camera)
            model.saveCamera(other)
            model.newCameraTest(camera.id, title: "Historical test")
            let historyID = try XCTUnwrap(model.selectedSessionID)
            model.activeCaptureSessionID = historyID
            try receive(model)
            model.newCameraTest(camera.id, title: "Live test")
            let liveID = try XCTUnwrap(model.selectedSessionID)
            XCTAssertEqual(model.activeCaptureSessionID, liveID)
            model.direction = .horizontal
            model.nominalDenominator = 125

            model.selectCamera(other.id)
            try receive(model, index: 1)
            XCTAssertEqual(model.activeCaptureSessionID, liveID)
            XCTAssertEqual(model.selectedCameraID, other.id)
            model.openCameraTest(historyID)
            let selectedHistoricalReading = model.selectedRecordID
            model.nominalDenominator = 500
            model.direction = .vertical
            try receive(model, index: 2)
            XCTAssertEqual(model.selectedRecordID, selectedHistoricalReading)
            XCTAssertEqual(model.currentRecords.count, 1)

            let demoID = try XCTUnwrap(model.sessions.first(where: \.demo)?.id)
            model.selectSession(demoID)
            model.addDemoReading()
            let selectedDemoReading = model.selectedRecordID
            try receive(model, index: 3)
            XCTAssertEqual(model.currentRecords.count, 1)
            XCTAssertEqual(model.selectedRecordID, selectedDemoReading)
            XCTAssertTrue(model.currentRecords[0].isDemo)
            XCTAssertEqual(model.activeCaptureSessionID, liveID)

            let live = try XCTUnwrap(model.sessions.first { $0.id == liveID })
            XCTAssertEqual(live.records.count, 3)
            XCTAssertTrue(live.records.allSatisfy { !$0.isDemo && $0.direction == .horizontal && $0.nominalDenominator == 125 })
            XCTAssertEqual(model.sessions.first(where: { $0.id == historyID })?.records.count, 1)
            model.returnToCapture()
            XCTAssertEqual(model.selectedSessionID, liveID)
            XCTAssertFalse(model.showCameraLibrary)
            XCTAssertEqual(model.nominalDenominator, 125)
            XCTAssertEqual(model.direction, .horizontal)
            XCTAssertNil(model.errorMessage)
        }
    }

    @MainActor
    func testAutoAdvanceUsesLiveDestinationSettingsWhileViewingAnotherTest() throws {
        try withModel { model in
            let camera = linkedCamera()
            model.saveCamera(camera)
            model.newCameraTest(camera.id, title: "Historical test")
            let historyID = try XCTUnwrap(model.selectedSessionID)
            model.nominalDenominator = 500
            model.direction = .vertical
            model.newCameraTest(camera.id, title: "Live test")
            let liveID = try XCTUnwrap(model.selectedSessionID)
            model.activeCaptureSessionID = liveID
            model.nominalDenominator = 125
            model.direction = .horizontal
            model.autoAdvance = true
            model.selectSession(historyID)

            try receive(model, nominal: 125)
            var live = try XCTUnwrap(model.activeCaptureSession)
            XCTAssertEqual(live.records.last?.nominalDenominator, 125)
            XCTAssertEqual(live.records.last?.direction, .horizontal)
            XCTAssertEqual(live.nominalDenominator, 250)
            XCTAssertEqual(model.nominalDenominator, 500)
            XCTAssertEqual(model.direction, .vertical)
            XCTAssertFalse(model.autoAdvance)
            try receive(model, nominal: 250, partial: true)
            live = try XCTUnwrap(model.activeCaptureSession)
            XCTAssertEqual(live.records.last?.result.quality, .partial)
            XCTAssertEqual(live.nominalDenominator, 250)
            try receive(model, nominal: 250, index: 2)
            live = try XCTUnwrap(model.activeCaptureSession)
            XCTAssertEqual(live.nominalDenominator, 500)
            XCTAssertEqual(live.records.map(\.nominalDenominator), [125, 250, 250])
            XCTAssertTrue(model.currentRecords.isEmpty)
            XCTAssertEqual(try model.store.loadLibrary().sessions.first(where: { $0.id == liveID })?.nominalDenominator, 500)
        }
    }

    @MainActor
    func testAssigningLegacyTestKeepsRawEvidenceAndItsRecordedSetup() throws {
        try withModel { model in
            model.newSession(demo: false)
            let legacyID = try XCTUnwrap(model.selectedSessionID)
            model.activeCaptureSessionID = legacyID
            model.cameraName = "Name originally recorded at the bench"
            model.nominalDenominator = 60
            model.direction = .vertical
            model.sessionNotes = "Original test notes"
            try receive(model, nominal: 60)
            let before = try XCTUnwrap(model.currentSession)
            // Explicit opt-in only: an isolated QA app can exercise the same import
            // and assignment path. This never writes synthetic evidence by default.
            if let path = ProcessInfo.processInfo.environment["SHUTTER_LOVER_QA_FIXTURE_PATH"] {
                var fixture = before
                fixture.cameraName = "Synthetic QA camera — not a physical test"
                fixture.notes = "SYNTHETIC QA DATA. Generated from DemoPackets solely to exercise the real-data import/assignment UI in an isolated QA app. Not evidence of camera performance."
                try SessionStore.encoder().encode(SessionArchive(sessions: [fixture])).write(to: URL(fileURLWithPath: path), options: .atomic)
            }
            let camera = linkedCamera()
            model.saveCamera(camera)
            model.assignSession(legacyID, to: camera.id)
            let after = try XCTUnwrap(model.sessions.first { $0.id == legacyID })
            XCTAssertEqual(after.id, before.id)
            XCTAssertEqual(after.cameraName, before.cameraName)
            XCTAssertEqual(after.notes, before.notes)
            XCTAssertEqual(after.direction, before.direction)
            XCTAssertEqual(after.nominalDenominator, before.nominalDenominator)
            XCTAssertEqual(after.records[0].rawLine, before.records[0].rawLine)
            XCTAssertEqual(after.records[0].packet, before.records[0].packet)
            XCTAssertEqual(after.records[0].derivedSnapshot, before.records[0].derivedSnapshot)
            XCTAssertEqual(after.records[0].capturedAt, before.records[0].capturedAt)
            XCTAssertEqual(after.records[0].direction, .vertical)
            XCTAssertEqual(after.records[0].nominalDenominator, 60)
            XCTAssertEqual(after.cameraID, camera.id)
            XCTAssertEqual(after.cameraSnapshot?.catalogueCameraID, camera.catalogueCameraID)
            XCTAssertEqual(after.effectiveRevision, before.effectiveRevision + 1)
            let data = try ShutterTesterExchange.exportResults(producerLibraryID: model.libraryID, session: after)
            XCTAssertNoThrow(try ShutterTesterExchange.validateResults(data))
            let other = linkedCamera(name: "Second camera")
            model.saveCamera(other)
            model.assignSession(legacyID, to: other.id)
            XCTAssertEqual(model.sessions.first(where: { $0.id == legacyID })?.cameraID, camera.id)
            XCTAssertNotNil(model.errorMessage)
        }
    }

    @MainActor
    func testMetadataSheetPreservesReadingsCapturedAndCorrectedSinceItOpened() throws {
        try withModel { model in
            let camera = linkedCamera()
            model.saveCamera(camera)
            model.newCameraTest(camera.id)
            model.activeCaptureSessionID = model.selectedSessionID
            model.sessionNotes = "Old notes"
            try receive(model)
            var edited = try XCTUnwrap(model.currentSession)
            edited.title = "After adjustment"
            edited.notes = "New metadata-sheet notes"
            edited.operatorName = "Technician"
            edited.lightSource = "LED panel"
            edited.testConditions = "20 °C"
            edited.toleranceStops = 0.25
            edited.repeatsPerSpeed = 5
            edited.plannedSpeeds = [60, 125, 250]
            try receive(model, index: 1)
            model.updateSelectedSetting(60)
            let freshReading = try XCTUnwrap(model.selectedRecord)
            let revisionBeforeSave = try XCTUnwrap(model.currentSession).effectiveRevision
            model.updateTestDetails(edited)
            let saved = try XCTUnwrap(model.currentSession)
            XCTAssertEqual(saved.records.count, 2)
            XCTAssertEqual(saved.records.last?.id, freshReading.id)
            XCTAssertEqual(saved.records.last?.rawLine, freshReading.rawLine)
            XCTAssertEqual(saved.records.last?.nominalDenominator, 60)
            XCTAssertEqual(saved.records.last?.settingCorrections, freshReading.settingCorrections)
            XCTAssertEqual(saved.records.last?.derivedSnapshot, freshReading.derivedSnapshot)
            XCTAssertEqual(saved.title, "After adjustment")
            XCTAssertEqual(saved.operatorName, "Technician")
            XCTAssertEqual(saved.notes, "New metadata-sheet notes")
            XCTAssertEqual(saved.repeatsPerSpeed, 5)
            XCTAssertEqual(saved.effectiveRevision, revisionBeforeSave + 1)
            // Subsequent edits in the live setup must not restore stale published notes.
            model.nominalDenominator = 250
            XCTAssertEqual(model.currentSession?.notes, "New metadata-sheet notes")
            model.saveNow()
            XCTAssertEqual(try model.store.loadLibrary().sessions.first(where: { $0.id == saved.id })?.records.count, 2)
        }
    }

    @MainActor
    func testPortableCopyPreservesEvidenceButGetsNewLocalIdentitiesAndNoCatalogueLink() throws {
        try withModel { model in
            let camera = linkedCamera()
            model.saveCamera(camera)
            model.newCameraTest(camera.id, title: "Before service")
            model.activeCaptureSessionID = model.selectedSessionID
            try receive(model)
            model.updateSelectedSetting(60)
            model.toggleExcluded(try XCTUnwrap(model.selectedRecordID))
            var originalSession = try XCTUnwrap(model.currentSession)
            originalSession.lastExportedRevision = originalSession.effectiveRevision
            var sourceCamera = camera
            var service = CameraServiceEvent(title: "Shutter service")
            service.beforeSessionID = originalSession.id
            service.afterSessionID = originalSession.id
            sourceCamera.serviceEvents = [service]
            sourceCamera.notes = "Keep these local notes"
            // Catalogue edits made after capture must not rewrite copied history.
            sourceCamera.name = "Nikon F2 revised catalogue name"
            sourceCamera.serial = "Corrected serial after capture"
            sourceCamera.inventoryID = "Revised collection number"
            let archive = PortableCameraArchive(sourceLibraryID: model.libraryID, camera: sourceCamera, sessions: [originalSession])
            let decoded = try PortableCameraArchive.decode(SessionStore.encoder().encode(archive))
            let (copy, copiedSessions) = decoded.localCopy()
            let copiedTest = try XCTUnwrap(copiedSessions.first)
            XCTAssertNotEqual(copy.id, camera.id)
            XCTAssertEqual(copy.name, "Nikon F2 revised catalogue name (copy)")
            XCTAssertEqual(copy.notes, sourceCamera.notes)
            XCTAssertEqual(copy.serial, sourceCamera.serial)
            XCTAssertNil(copy.catalogueID)
            XCTAssertNil(copy.catalogueCameraID)
            XCTAssertNil(copy.catalogueRevision)
            XCTAssertTrue(copy.catalogueSnapshots.isEmpty)
            XCTAssertNotEqual(copy.serviceEvents[0].id, service.id)
            XCTAssertEqual(copy.serviceEvents[0].beforeSessionID, copiedTest.id)
            XCTAssertEqual(copy.serviceEvents[0].afterSessionID, copiedTest.id)
            XCTAssertNotEqual(copiedTest.id, originalSession.id)
            XCTAssertEqual(copiedTest.cameraID, copy.id)
            XCTAssertNil(copiedTest.cameraSnapshot?.catalogueID)
            XCTAssertNil(copiedTest.cameraSnapshot?.catalogueCameraID)
            XCTAssertNil(copiedTest.cameraSnapshot?.catalogueRevision)
            XCTAssertEqual(copiedTest.cameraSnapshot?.name, originalSession.cameraSnapshot?.name)
            XCTAssertEqual(copiedTest.cameraSnapshot?.manufacturer, originalSession.cameraSnapshot?.manufacturer)
            XCTAssertEqual(copiedTest.cameraSnapshot?.model, originalSession.cameraSnapshot?.model)
            XCTAssertEqual(copiedTest.cameraSnapshot?.serial, originalSession.cameraSnapshot?.serial)
            XCTAssertEqual(copiedTest.cameraSnapshot?.inventoryID, originalSession.cameraSnapshot?.inventoryID)
            XCTAssertEqual(copiedTest.effectiveRevision, 1)
            XCTAssertNil(copiedTest.lastExportedRevision)
            let reading = try XCTUnwrap(copiedTest.records.first)
            XCTAssertNotEqual(reading.id, originalSession.records[0].id)
            XCTAssertEqual(reading.rawLine, originalSession.records[0].rawLine)
            XCTAssertEqual(reading.packet, originalSession.records[0].packet)
            XCTAssertEqual(reading.derivedSnapshot, originalSession.records[0].derivedSnapshot)
            XCTAssertEqual(reading.direction, originalSession.records[0].direction)
            XCTAssertEqual(reading.nominalDenominator, originalSession.records[0].nominalDenominator)
            XCTAssertEqual(reading.capturedAt.timeIntervalSince1970, originalSession.records[0].capturedAt.timeIntervalSince1970, accuracy: 0.001)
            XCTAssertEqual(reading.settingCorrections.last?.newValue, 60)
            XCTAssertTrue(reading.isExcluded)
            XCTAssertEqual(decoded.camera.catalogueCameraID, camera.catalogueCameraID)
            XCTAssertEqual(decoded.sessions[0].id, originalSession.id)
            XCTAssertNoThrow(try SessionStore.validateLibrary(CameraLibraryArchive(cameras: [copy], sessions: copiedSessions)))
            XCTAssertThrowsError(try ShutterTesterExchange.exportResults(producerLibraryID: model.libraryID, session: copiedTest))
        }
    }

    @MainActor
    func testEvidenceEditsEachAdvanceRevisionAndUndoRestoresFrozenReading() throws {
        try withModel { model in
            let camera = linkedCamera()
            model.saveCamera(camera)
            model.newCameraTest(camera.id)
            model.activeCaptureSessionID = model.selectedSessionID
            let initialRevision = try XCTUnwrap(model.currentSession).effectiveRevision
            try receive(model)
            let original = try XCTUnwrap(model.selectedRecord)
            var revision = try XCTUnwrap(model.currentSession).effectiveRevision
            XCTAssertEqual(revision, initialRevision + 1)
            model.toggleExcluded(original.id)
            XCTAssertEqual(model.currentSession?.effectiveRevision, revision + 1)
            revision += 1
            model.updateSelectedSetting(60)
            XCTAssertEqual(model.currentSession?.effectiveRevision, revision + 1)
            revision += 1
            let corrected = try XCTUnwrap(model.selectedRecord)
            XCTAssertNotEqual(corrected.derivedSnapshot, original.derivedSnapshot)
            XCTAssertEqual(corrected.rawLine, original.rawLine)
            model.deleteSelectedReading()
            XCTAssertEqual(model.currentSession?.effectiveRevision, revision + 1)
            XCTAssertTrue(model.currentRecords.isEmpty)
            XCTAssertTrue(model.canUndoDelete)
            revision += 1
            model.undoDelete()
            XCTAssertEqual(model.currentSession?.effectiveRevision, revision + 1)
            XCTAssertEqual(model.selectedRecord?.id, original.id)
            XCTAssertEqual(model.selectedRecord?.rawLine, original.rawLine)
            XCTAssertEqual(model.selectedRecord?.derivedSnapshot, corrected.derivedSnapshot)
            XCTAssertEqual(model.selectedRecord?.settingCorrections, corrected.settingCorrections)
            XCTAssertTrue(try XCTUnwrap(model.selectedRecord).isExcluded)
            XCTAssertFalse(model.canUndoDelete)
            let saved = try model.store.loadLibrary().sessions.first(where: { $0.id == model.selectedSessionID })
            XCTAssertEqual(saved?.effectiveRevision, revision + 1)
            XCTAssertEqual(saved?.records.first?.derivedSnapshot, corrected.derivedSnapshot)
        }
    }
}
