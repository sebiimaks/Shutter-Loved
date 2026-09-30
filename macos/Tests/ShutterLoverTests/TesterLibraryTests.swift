import XCTest
import MeasurementCore
@testable import ShutterLover

final class TesterLibraryTests: XCTestCase {
    private func temporaryStore() -> SessionStore {
        SessionStore(directory: FileManager.default.temporaryDirectory.appendingPathComponent("tester-library-tests-\(UUID().uuidString)"))
    }

    private func hardwareSession() throws -> CaptureSession {
        let packet = DemoPackets.sample(nominalDenominator: 125, index: 0)
        let record = MeasurementRecord(rawLine: String(decoding: try JSONEncoder().encode(packet), as: UTF8.self), packet: packet, direction: .horizontal, nominalDenominator: 125, isDemo: false)
        return CaptureSession(cameraName: "Legacy camera", demo: false, records: [record])
    }

    func testSchemaTwoMigrationBacksUpExactBytesAndPreservesHistoricalReadings() throws {
        let store = temporaryStore()
        defer { try? FileManager.default.removeItem(at: store.directory) }
        try FileManager.default.createDirectory(at: store.directory, withIntermediateDirectories: true)
        let session = try hardwareSession()
        let archive = CameraLibraryArchive(schemaVersion: 2, sessions: [session])
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: SessionStore.encoder().encode(archive)) as? [String: Any])
        object.removeValue(forKey: "ownedTesters")
        let original = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
        try original.write(to: store.cameraLibraryURL)
        let migrated = try store.loadLibrary()
        XCTAssertEqual(migrated.schemaVersion, 3)
        XCTAssertEqual(migrated.libraryID, archive.libraryID)
        XCTAssertEqual(migrated.sessions[0].id, session.id)
        XCTAssertEqual(migrated.sessions[0].records[0].id, session.records[0].id)
        XCTAssertEqual(migrated.sessions[0].records[0].rawLine, session.records[0].rawLine)
        XCTAssertNil(migrated.sessions[0].records[0].tester)
        XCTAssertEqual(migrated.sessions[0].records[0].testerDescription, "Shutter Lover (individual tester not recorded)")
        XCTAssertTrue(migrated.ownedTesters.isEmpty)
        XCTAssertEqual(try Data(contentsOf: store.testerMigrationBackupURL), original)
        XCTAssertEqual(try store.loadLibrary().libraryID, archive.libraryID)
        XCTAssertEqual(try Data(contentsOf: store.testerMigrationBackupURL), original)
    }

    func testSchemaOneSessionStillDecodesAndNewExportUsesSchemaTwo() throws {
        let source = try hardwareSession()
        let data = try SessionStore.encoder().encode(SessionArchive(schemaVersion: 1, sessions: [source]))
        let result = try XCTUnwrap(SessionStore.decode(data).first)
        XCTAssertEqual(result.records[0].packet, source.records[0].packet)
        XCTAssertNil(result.records[0].manual)
        XCTAssertNil(result.records[0].tester)
        XCTAssertEqual(SessionArchive(sessions: [result]).schemaVersion, 2)
    }

    func testUnknownAndDamagedLibrariesCannotBeMigratedOrOverwritten() throws {
        let store = temporaryStore()
        defer { try? FileManager.default.removeItem(at: store.directory) }
        try FileManager.default.createDirectory(at: store.directory, withIntermediateDirectories: true)
        let unsupported = try SessionStore.encoder().encode(CameraLibraryArchive(schemaVersion: 99))
        for bytes in [unsupported, Data("corrupt library".utf8)] {
            try bytes.write(to: store.cameraLibraryURL)
            XCTAssertThrowsError(try store.loadLibrary())
            XCTAssertThrowsError(try store.saveLibrary(CameraLibraryArchive()))
            XCTAssertEqual(try Data(contentsOf: store.cameraLibraryURL), bytes)
            XCTAssertFalse(FileManager.default.fileExists(atPath: store.testerMigrationBackupURL.path))
        }
    }

    func testModelCatalogueRejectsArbitraryImportedModels() throws {
        XCTAssertEqual(Set(TesterModel.allCases), [.shutterLover, .babyShutterTesterMkI, .babyShutterTesterMkII])
        let tester = OwnedTester(name: "My tester", model: .babyShutterTesterMkII)
        let original = try SessionStore.encoder().encode(CameraLibraryArchive(ownedTesters: [tester]))
        let altered = String(decoding: original, as: UTF8.self).replacingOccurrences(of: "babyShutterTesterMkII", with: "Unapproved Generic Tester")
        XCTAssertThrowsError(try SessionStore.decodeLibrary(Data(altered.utf8)))
    }

    func testTesterSnapshotSurvivesInventoryEditsAndRoundTripsIndependently() throws {
        var tester = OwnedTester(name: "Bench Baby", model: .babyShutterTesterMkII, serialNumber: "A123", firmwareVersion: "1.2", notes: "Inventory note", calibrationDate: Date(timeIntervalSince1970: 1_700_000_000), calibrationNotes: "Reference checked")
        let snapshot = TesterSnapshot(tester: tester)
        let record = MeasurementRecord(rawLine: "", manual: ManualMeasurement(enteredValue: 8), tester: snapshot, direction: .unknown, nominalDenominator: 125, isDemo: false)
        let session = CaptureSession(cameraName: "Camera", demo: false, records: [record], tester: snapshot)
        tester.name = "New name"
        tester.serialNumber = "Corrected inventory serial"
        tester.calibrationNotes = "Later calibration"
        let saved = try SessionStore.decodeLibrary(SessionStore.encoder().encode(CameraLibraryArchive(sessions: [session], ownedTesters: [tester])))
        XCTAssertEqual(saved.ownedTesters[0], tester)
        XCTAssertEqual(saved.sessions[0].records[0].tester, snapshot)
        XCTAssertEqual(saved.sessions[0].records[0].tester?.serialNumber, "A123")
        XCTAssertEqual(saved.sessions[0].records[0].tester?.calibrationNotes, "Reference checked")
    }

    func testRejectsDuplicateInventoryIdentitiesAndAllowsBabyUSBAssociation() throws {
        let binding = TesterUSBIdentity(vendorID: 0x2341, productID: 0x0043, serialNumber: "ABC:/123")
        XCTAssertEqual(binding.stableIdentityKey, "usb:2341:0043:" + Data("ABC:/123".utf8).base64EncodedString())
        var first = OwnedTester(name: "Bench USB", model: .shutterLover, usbBinding: binding)
        var second = first
        XCTAssertThrowsError(try SessionStore.validateOwnedTesters([first, second]))
        second.id = UUID()
        XCTAssertThrowsError(try SessionStore.validateOwnedTesters([first, second]))
        second.usbBinding?.serialNumber = " \nABC:/123\n "
        XCTAssertThrowsError(try SessionStore.validateOwnedTesters([first, second]))
        second.usbBinding = nil
        XCTAssertNoThrow(try SessionStore.validateOwnedTesters([first, second]))
        first.model = .babyShutterTesterMkII
        XCTAssertNoThrow(try SessionStore.validateOwnedTesters([first]))
        XCTAssertFalse(first.model.supportsUSBRecording)
        for binding in [TesterUSBIdentity(vendorID: -1, productID: 1, serialNumber: "a"), TesterUSBIdentity(vendorID: 1, productID: 65_536, serialNumber: "a"), TesterUSBIdentity(vendorID: 1, productID: 1, serialNumber: "  ")] {
            XCTAssertThrowsError(try SessionStore.validateUSBIdentity(binding))
        }
    }

    func testUSBReadingCannotClaimBabyHardwareAndManualHistoryNeedsNoCurrentInventoryEntry() throws {
        var session = try hardwareSession()
        session.records[0].tester = TesterSnapshot(model: .babyShutterTesterMkII)
        XCTAssertThrowsError(try SessionStore.validate([session]))
        let snapshot = TesterSnapshot(tester: OwnedTester(name: "Historical tester", model: .babyShutterTesterMkI))
        let record = MeasurementRecord(rawLine: "", manual: ManualMeasurement(enteredValue: 8), tester: snapshot, direction: .unknown, nominalDenominator: 125, isDemo: false)
        session.records = [record]
        XCTAssertNoThrow(try SessionStore.validateLibrary(CameraLibraryArchive(sessions: [session])))
    }
}
