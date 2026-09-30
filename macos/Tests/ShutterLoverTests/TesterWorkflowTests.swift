import XCTest
import DeviceTransport
import MeasurementCore
@testable import ShutterLover

final class TesterWorkflowTests: XCTestCase {
    private let measuredAt = Date(timeIntervalSince1970: 1_700_000_000)

    private func manualSession(model: TesterModel = .babyShutterTesterMkII) -> CaptureSession {
        var session = CaptureSession(cameraName: "Manual camera", demo: false)
        session.tester = TesterSnapshot(model: model)
        return session
    }

    private func usbSession() throws -> CaptureSession {
        let packet = DemoPackets.sample(nominalDenominator: 125, index: 0)
        let record = MeasurementRecord(rawLine: String(decoding: try JSONEncoder().encode(packet), as: UTF8.self), packet: packet, direction: .horizontal, nominalDenominator: 125, isDemo: false)
        return CaptureSession(cameraName: "USB camera", demo: false, records: [record], tester: TesterSnapshot(model: .shutterLover))
    }

    @MainActor
    private func withModel(sessions: [CaptureSession], testers: [OwnedTester] = [], _ body: (AppModel, UserDefaults) throws -> Void) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("tester-workflow-\(UUID().uuidString)")
        let suite = "tester-workflow-preferences-\(UUID().uuidString)"
        let preferences = try XCTUnwrap(UserDefaults(suiteName: suite))
        let store = SessionStore(directory: directory)
        try store.saveLibrary(CameraLibraryArchive(sessions: sessions, ownedTesters: testers))
        let model = AppModel(store: store, startDiscovery: false, preferences: preferences)
        defer {
            model.shutDown()
            preferences.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: directory)
        }
        try body(model, preferences)
    }

    @MainActor
    private func add(_ model: AppModel, to session: CaptureSession, tester: TesterSnapshot? = nil,
                     measurement: ManualMeasurement = ManualMeasurement(enteredValue: 8), nominal: Double = 125) -> Bool {
        model.addManualReading(sessionID: session.id, measurement: measurement,
                               tester: tester ?? TesterSnapshot(model: .babyShutterTesterMkII),
                               nominalDenominator: nominal, capturedAt: measuredAt)
    }

    @MainActor
    func testManualAppendPersistsExactInputAndOwnedTesterAcrossReload() throws {
        let session = manualSession()
        let owned = OwnedTester(name: "My Baby", model: .babyShutterTesterMkII, serialNumber: "BABY-42", firmwareVersion: "2.1", calibrationNotes: "Checked with reference")
        let measurement = ManualMeasurement(enteredValue: 125, unit: .reciprocalSeconds, mode: .global, illumination: 23, seriesIllumination: 45, notes: "At f/8")
        try withModel(sessions: [session], testers: [owned]) { model, preferences in
            XCTAssertTrue(add(model, to: session, tester: TesterSnapshot(tester: owned), measurement: measurement))
            let original = try XCTUnwrap(model.currentRecords.first)
            XCTAssertEqual(model.selectedRecordID, original.id)
            XCTAssertEqual(original.manual, measurement)
            XCTAssertNil(original.packet)
            XCTAssertEqual(original.tester, TesterSnapshot(tester: owned))
            XCTAssertEqual(original.capturedAt, measuredAt)
            XCTAssertEqual(model.currentSession?.effectiveRevision, session.effectiveRevision + 1)
            XCTAssertEqual(original.result.center.durationMS, 8)
            XCTAssertNil(original.result.openingTravelMS)
            let saved = try model.store.loadLibrary()
            XCTAssertEqual(saved.sessions.first?.records.first?.id, original.id)
            XCTAssertEqual(saved.sessions.first?.records.first?.manual, measurement)
            XCTAssertEqual(saved.ownedTesters, [owned])
            let reloaded = AppModel(store: model.store, startDiscovery: false, preferences: preferences)
            defer { reloaded.shutDown() }
            XCTAssertEqual(reloaded.currentRecords.first?.id, original.id)
            XCTAssertEqual(reloaded.currentRecords.first?.tester, original.tester)
            XCTAssertEqual(reloaded.currentRecords.first?.manual, measurement)
            XCTAssertEqual(reloaded.currentSession?.effectiveRevision, model.currentSession?.effectiveRevision)
        }
    }

    @MainActor
    func testFailedManualWriteNeverPublishesUnsavedReadingOrSessionChanges() throws {
        let session = manualSession()
        try withModel(sessions: [session]) { model, _ in
            let before = try Data(contentsOf: model.store.cameraLibraryURL)
            let blocker = model.store.directory.appendingPathComponent("library.previous.json", isDirectory: true)
            try FileManager.default.createDirectory(at: blocker, withIntermediateDirectories: false)
            defer { try? FileManager.default.removeItem(at: blocker) }
            XCTAssertFalse(add(model, to: session, nominal: 250))
            XCTAssertNotNil(model.errorMessage)
            XCTAssertTrue(model.currentRecords.isEmpty)
            XCTAssertEqual(model.currentSession?.nominalDenominator, 125)
            XCTAssertEqual(model.currentSession?.effectiveRevision, session.effectiveRevision)
            XCTAssertNil(model.selectedRecordID)
            XCTAssertEqual(try Data(contentsOf: model.store.cameraLibraryURL), before)
        }
    }

    @MainActor
    func testInvalidManualInputsLeaveMemoryAndStoredBytesUnchanged() throws {
        let session = manualSession()
        try withModel(sessions: [session]) { model, _ in
            let before = try Data(contentsOf: model.store.cameraLibraryURL)
            for value in [-1.0, 0.0, Double.nan, Double.infinity] {
                XCTAssertFalse(add(model, to: session, measurement: ManualMeasurement(enteredValue: value)))
                XCTAssertTrue(model.currentRecords.isEmpty)
                XCTAssertEqual(try Data(contentsOf: model.store.cameraLibraryURL), before)
            }
            for nominal in [-1.0, 0.0, Double.nan, Double.infinity] {
                XCTAssertFalse(add(model, to: session, nominal: nominal))
                XCTAssertTrue(model.currentRecords.isEmpty)
                XCTAssertEqual(try Data(contentsOf: model.store.cameraLibraryURL), before)
            }
            XCTAssertFalse(add(model, to: session, measurement: ManualMeasurement(enteredValue: 8, mode: .global, illumination: 30, seriesIllumination: 20)))
            XCTAssertEqual(try Data(contentsOf: model.store.cameraLibraryURL), before)
            XCTAssertEqual(model.currentSession?.effectiveRevision, session.effectiveRevision)
        }
    }

    @MainActor
    func testCannotAppendManualReadingToDemoTrashActiveOrUSBTest() throws {
        let demo = CaptureSession(cameraName: "Demo", demo: true)
        var trash = manualSession()
        trash.trashedAt = measuredAt
        let active = manualSession()
        let usb = try usbSession()
        try withModel(sessions: [demo, trash, active, usb]) { model, _ in
            model.activeCaptureSessionID = active.id
            let before = try Data(contentsOf: model.store.cameraLibraryURL)
            for session in [demo, trash, active, usb] {
                XCTAssertFalse(add(model, to: session))
                XCTAssertEqual(model.sessions.first { $0.id == session.id }?.records.count, session.records.count)
                XCTAssertEqual(try Data(contentsOf: model.store.cameraLibraryURL), before)
            }
            XCTAssertEqual(model.activeCaptureSessionID, active.id)
        }
    }

    @MainActor
    func testMkIAllowsDisplayValueAndRejectsMkIIModeOrIllumination() throws {
        let session = manualSession(model: .babyShutterTesterMkI)
        let tester = TesterSnapshot(model: .babyShutterTesterMkI)
        try withModel(sessions: [session]) { model, _ in
            for measurement in [ManualMeasurement(enteredValue: 8, mode: .automatic), ManualMeasurement(enteredValue: 8, illumination: 20), ManualMeasurement(enteredValue: 8, mode: .global, seriesIllumination: 40)] {
                XCTAssertFalse(add(model, to: session, tester: tester, measurement: measurement))
                XCTAssertTrue(model.currentRecords.isEmpty)
            }
            XCTAssertTrue(add(model, to: session, tester: tester))
            XCTAssertEqual(model.currentRecords.first?.tester?.model, .babyShutterTesterMkI)
            XCTAssertEqual(model.currentRecords.first?.measurementLabel, "Measured exposure")
            XCTAssertNil(model.currentRecords.first?.manual?.illumination)
            XCTAssertNil(model.currentRecords.first?.manual?.seriesIllumination)
            XCTAssertFalse(add(model, to: session, tester: TesterSnapshot(model: .babyShutterTesterMkII)))
            XCTAssertEqual(model.currentRecords.count, 1)
        }
    }

    @MainActor
    func testInventoryEditsAndRemovalPreserveHistoricalSnapshots() throws {
        let session = manualSession()
        var owned = OwnedTester(name: "Original tester", model: .babyShutterTesterMkII, serialNumber: "Old serial", calibrationNotes: "Original calibration")
        let original = TesterSnapshot(tester: owned)
        try withModel(sessions: [session], testers: [owned]) { model, _ in
            XCTAssertTrue(add(model, to: session, tester: original))
            let first = try SessionStore.encoder().encode(XCTUnwrap(model.currentRecords.first))
            owned.name = "Renamed tester"
            owned.serialNumber = "Corrected serial"
            owned.calibrationNotes = "New calibration"
            XCTAssertTrue(model.saveOwnedTester(owned))
            XCTAssertEqual(try SessionStore.encoder().encode(XCTUnwrap(model.currentRecords.first)), first)
            // A stale sheet snapshot is refreshed from the current inventory on save.
            XCTAssertTrue(add(model, to: session, tester: original))
            XCTAssertEqual(model.currentRecords.last?.tester, TesterSnapshot(tester: owned))
            XCTAssertTrue(model.removeOwnedTester(owned.id))
            XCTAssertTrue(model.ownedTesters.isEmpty)
            XCTAssertEqual(try SessionStore.encoder().encode(XCTUnwrap(model.currentRecords.first)), first)
            let saved = try model.store.loadLibrary()
            XCTAssertTrue(saved.ownedTesters.isEmpty)
            XCTAssertEqual(saved.sessions.first?.records.first?.tester, original)
            XCTAssertEqual(saved.sessions.first?.records.last?.tester, TesterSnapshot(tester: owned))
        }
    }

    @MainActor
    func testRemovedOwnedTesterInStaleManualSheetCannotAppend() throws {
        let session = manualSession()
        let owned = OwnedTester(name: "Removed Baby", model: .babyShutterTesterMkII)
        let stale = TesterSnapshot(tester: owned)
        try withModel(sessions: [session], testers: [owned]) { model, _ in
            XCTAssertTrue(model.removeOwnedTester(owned.id))
            let before = try Data(contentsOf: model.store.cameraLibraryURL)
            XCTAssertFalse(add(model, to: session, tester: stale))
            XCTAssertTrue(model.currentRecords.isEmpty)
            XCTAssertEqual(try Data(contentsOf: model.store.cameraLibraryURL), before)
            XCTAssertNotNil(model.errorMessage)
        }
    }

    @MainActor
    func testDuplicateUSBBindingAndSavedModelChangeAreRejectedAtomically() throws {
        let binding = TesterUSBIdentity(vendorID: 0x2341, productID: 0x0043, serialNumber: "SAME-UNIT")
        let original = OwnedTester(name: "USB original", model: .shutterLover, usbBinding: binding)
        let duplicate = OwnedTester(name: "USB duplicate", model: .shutterLover, usbBinding: binding)
        try withModel(sessions: [manualSession()], testers: [original]) { model, _ in
            let before = try Data(contentsOf: model.store.cameraLibraryURL)
            XCTAssertFalse(model.saveOwnedTester(duplicate))
            XCTAssertEqual(model.ownedTesters, [original])
            XCTAssertEqual(try Data(contentsOf: model.store.cameraLibraryURL), before)
            var changed = original
            changed.model = .babyShutterTesterMkII
            changed.usbBinding = nil
            XCTAssertFalse(model.saveOwnedTester(changed))
            XCTAssertEqual(model.ownedTesters, [original])
            XCTAssertEqual(try Data(contentsOf: model.store.cameraLibraryURL), before)
        }
    }

    @MainActor
    func testConnectedTesterMatchingRequiresUniqueVendorProductAndSerialNeverPath() throws {
        let binding = TesterUSBIdentity(vendorID: 0x2341, productID: 0x0043, serialNumber: "USB-123")
        let owned = OwnedTester(name: "My USB tester", model: .shutterLover, usbBinding: binding)
        let known = SerialDevice(name: "Known", path: "/dev/cu.original", usbVendorID: binding.vendorID, usbProductID: binding.productID, usbSerialNumber: binding.serialNumber)
        let moved = SerialDevice(name: "Moved", path: "/dev/cu.changed", usbVendorID: binding.vendorID, usbProductID: binding.productID, usbSerialNumber: binding.serialNumber)
        try withModel(sessions: [manualSession()], testers: [owned]) { model, _ in
            model.devices = [known]
            XCTAssertEqual(model.matchedOwnedTester(for: known)?.id, owned.id)
            XCTAssertEqual(model.connectionTester(for: known).id, owned.id)
            model.devices = [moved]
            XCTAssertEqual(model.matchedOwnedTester(for: moved)?.id, owned.id)
            XCTAssertEqual(model.connectionTester(for: moved).devicePath, moved.path)
            XCTAssertEqual(model.connectionTester(for: moved).usbIdentity, binding)
            for stranger in [SerialDevice(name: "Reused path", path: known.path),
                             SerialDevice(name: "Different vendor", path: known.path, usbVendorID: 9, usbProductID: binding.productID, usbSerialNumber: binding.serialNumber),
                             SerialDevice(name: "Different product", path: known.path, usbVendorID: binding.vendorID, usbProductID: 9, usbSerialNumber: binding.serialNumber),
                             SerialDevice(name: "Different serial", path: known.path, usbVendorID: binding.vendorID, usbProductID: binding.productID, usbSerialNumber: "OTHER")] {
                model.devices = [stranger]
                XCTAssertNil(model.matchedOwnedTester(for: stranger))
                XCTAssertNil(model.connectionTester(for: stranger).id)
            }
            model.devices = [known, moved]
            XCTAssertNil(model.matchedOwnedTester(for: known))
            model.selectedPortPath = known.path
            XCTAssertNotNil(model.connectionIdentityProblem)
            model.devices = [known]
            var duplicate = owned
            duplicate.id = UUID()
            model.ownedTesters.append(duplicate)
            XCTAssertNil(model.matchedOwnedTester(for: known))
            model.ownedTesters = [owned]
        }
    }

    @MainActor
    func testExplicitMismatchedUSBIdentityIsBlocked() throws {
        let owned = OwnedTester(name: "Bound unit", model: .shutterLover, usbBinding: TesterUSBIdentity(vendorID: 1, productID: 2, serialNumber: "UNIT-A"))
        let stranger = SerialDevice(name: "Other unit", path: "/dev/cu.stranger", usbVendorID: 1, usbProductID: 2, usbSerialNumber: "UNIT-B")
        try withModel(sessions: [manualSession()], testers: [owned]) { model, _ in
            model.devices = [stranger]
            model.selectedPortPath = stranger.path
            model.selectedConnectionTesterID = owned.id
            XCTAssertNotNil(model.connectionIdentityProblem)
            model.connect()
            XCTAssertFalse(model.isConnecting)
            XCTAssertNil(model.activeCaptureSessionID)
            XCTAssertNotNil(model.errorMessage)
        }
    }

    @MainActor
    func testNewManualSessionDoesNotRetargetLiveCaptureAndRejectsItsUSBEvents() throws {
        let live = try usbSession()
        let packet = try XCTUnwrap(live.records.first?.packet)
        let raw = try XCTUnwrap(live.records.first?.rawLine)
        try withModel(sessions: [live]) { model, _ in
            model.activeCaptureSessionID = live.id
            model.isConnected = true
            let physical = TesterSnapshot(model: .shutterLover)
            model.connectionTesterSnapshot = physical
            model.newManualSession()
            let manual = try XCTUnwrap(model.currentSession)
            XCTAssertNotEqual(manual.id, live.id)
            XCTAssertEqual(manual.tester?.model, .babyShutterTesterMkII)
            XCTAssertEqual(model.activeCaptureSessionID, live.id)
            XCTAssertEqual(model.connectionTesterSnapshot, physical)
            model.append(packet: packet, raw: raw, simulated: false)
            XCTAssertEqual(model.sessions.first { $0.id == live.id }?.records.count, 2)
            XCTAssertTrue(model.currentRecords.isEmpty)
            // A stale destination cannot force USB evidence into a manual test.
            model.activeCaptureSessionID = manual.id
            model.append(packet: packet, raw: raw, simulated: false)
            XCTAssertTrue(model.currentRecords.isEmpty)
            model.activeCaptureSessionID = live.id
        }
    }

    @MainActor
    func testActiveTesterCannotBeEditedRemovedOrSwappedWhileRecording() throws {
        let live = try usbSession()
        let owned = OwnedTester(name: "Connected", model: .shutterLover)
        try withModel(sessions: [live], testers: [owned]) { model, _ in
            model.activeCaptureSessionID = live.id
            model.connectionTesterSnapshot = TesterSnapshot(tester: owned)
            var edited = owned
            edited.name = "Changed mid-capture"
            let before = try Data(contentsOf: model.store.cameraLibraryURL)
            XCTAssertFalse(model.saveOwnedTester(edited))
            XCTAssertFalse(model.removeOwnedTester(owned.id))
            XCTAssertFalse(model.setSessionTester(live.id, tester: TesterSnapshot(model: .babyShutterTesterMkII)))
            XCTAssertEqual(model.ownedTesters, [owned])
            XCTAssertEqual(try Data(contentsOf: model.store.cameraLibraryURL), before)
        }
    }
}
