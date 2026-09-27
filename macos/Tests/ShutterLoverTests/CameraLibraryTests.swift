import XCTest
import MeasurementCore
@testable import ShutterLover

final class CameraLibraryTests: XCTestCase {
    private func sampleSession(camera: CameraProfile? = nil) throws -> CaptureSession {
        let packet = DemoPackets.sample(nominalDenominator: 125, index: 0)
        var record = MeasurementRecord(rawLine: String(decoding: try JSONEncoder().encode(packet), as: UTF8.self),
                                       packet: packet, direction: .horizontal, nominalDenominator: 125, isDemo: false)
        record.derivedSnapshot = record.result
        var session = CaptureSession(cameraName: camera?.name ?? "Legacy camera", demo: false, records: [record])
        session.cameraID = camera?.id
        session.cameraSnapshot = camera.map(CameraIdentitySnapshot.init(camera:))
        return session
    }

    private func temporaryStore() -> SessionStore {
        SessionStore(directory: FileManager.default.temporaryDirectory.appendingPathComponent("camera-library-tests-\(UUID().uuidString)"))
    }

    func testLegacyMigrationPreservesSourceBytesAndLeavesSessionsUnassigned() throws {
        let store = temporaryStore()
        defer { try? FileManager.default.removeItem(at: store.directory) }
        let session = try sampleSession()
        try store.save([session])
        let original = try Data(contentsOf: store.libraryURL)
        let library = try store.loadLibrary()
        XCTAssertEqual(library.schemaVersion, 2)
        XCTAssertTrue(library.cameras.isEmpty)
        XCTAssertNil(library.sessions[0].cameraID)
        XCTAssertEqual(library.sessions[0].id, session.id)
        XCTAssertEqual(library.sessions[0].records[0].rawLine, session.records[0].rawLine)
        XCTAssertEqual(library.sessions[0].records[0].id, session.records[0].id)
        XCTAssertEqual(try Data(contentsOf: store.libraryURL), original)
        XCTAssertEqual(try Data(contentsOf: store.migrationBackupURL), original)
        XCTAssertEqual(try store.loadLibrary().libraryID, library.libraryID)
    }

    func testNewLibraryPersistsItsNamespaceBeforeAnyCameraExists() throws {
        let store = temporaryStore()
        defer { try? FileManager.default.removeItem(at: store.directory) }
        let first = try store.loadLibrary()
        XCTAssertTrue(first.cameras.isEmpty)
        XCTAssertEqual(first.libraryID, try store.loadLibrary().libraryID)
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.libraryURL.path))
    }

    func testLegacyFileWithoutAnyNewOptionalFieldsDecodes() throws {
        let session = try sampleSession()
        let data = try SessionStore.encoder().encode(SessionArchive(sessions: [session]))
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        var sessions = try XCTUnwrap(object["sessions"] as? [[String: Any]])
        for field in ["cameraID", "cameraSnapshot", "title", "operatorName", "lightSource", "testConditions", "toleranceStops", "plannedSpeeds", "repeatsPerSpeed", "revision", "lastExportedRevision"] {
            sessions[0].removeValue(forKey: field)
        }
        var records = try XCTUnwrap(sessions[0]["records"] as? [[String: Any]])
        records[0].removeValue(forKey: "derivedSnapshot")
        sessions[0]["records"] = records
        object["sessions"] = sessions
        let decoded = try XCTUnwrap(SessionStore.decode(JSONSerialization.data(withJSONObject: object)).first)
        XCTAssertNil(decoded.records[0].derivedSnapshot)
        XCTAssertEqual(decoded.records[0].result, session.records[0].result)
        XCTAssertEqual(decoded.effectiveRevision, 1)
    }

    func testFullProfileAndHistoricalIdentityRoundTripIndependently() throws {
        var camera = CameraProfile(name: "Nikon F2")
        camera.serial = "12345"
        camera.manufacturer = "Nikon"
        camera.photoFilename = "camera-portrait.jpg"
        camera.photoFit = true
        camera.catalogueID = UUID()
        camera.catalogueCameraID = UUID()
        camera.catalogueRevision = 1
        camera.catalogueSnapshots = [CatalogueSnapshot(revision: 1, profileJSON: Data("{\"name\":\"Nikon F2\"}".utf8), importedAt: Date(), sourceApplication: "Armarium Lucis")]
        var session = try sampleSession(camera: camera)
        session.title = "Before service"
        session.plannedSpeeds = [60, 125, 250]
        session.repeatsPerSpeed = 3
        session.toleranceStops = 0.3
        session.operatorName = "Operator"
        session.lightSource = "LED panel"
        session.testConditions = "Tripod, room temperature"
        session.markUpdated()
        var service = CameraServiceEvent(title: "Shutter adjustment")
        service.beforeSessionID = session.id
        camera.serviceEvents = [service]
        camera.name = "Updated local name"
        camera.serial = "Corrected serial"
        camera.catalogueRevision = 2
        camera.catalogueSnapshots.append(CatalogueSnapshot(revision: 2, profileJSON: Data("{}".utf8), importedAt: Date(), sourceApplication: "Armarium Lucis"))
        let archive = CameraLibraryArchive(cameras: [camera], sessions: [session])
        let decoded = try SessionStore.decodeLibrary(SessionStore.encoder().encode(archive))
        XCTAssertEqual(decoded.libraryID, archive.libraryID)
        XCTAssertEqual(decoded.cameras[0].name, "Updated local name")
        XCTAssertEqual(decoded.cameras[0].catalogueSnapshots.map(\.revision), [1, 2])
        XCTAssertEqual(decoded.cameras[0].serviceEvents[0].beforeSessionID, session.id)
        XCTAssertEqual(decoded.sessions[0].cameraSnapshot?.name, "Nikon F2")
        XCTAssertEqual(decoded.sessions[0].cameraSnapshot?.serial, "12345")
        XCTAssertEqual(decoded.sessions[0].cameraSnapshot?.catalogueRevision, 1)
        XCTAssertEqual(decoded.sessions[0].records[0].derivedSnapshot, session.records[0].result)
        XCTAssertEqual(decoded.sessions[0].effectiveRevision, 2)
        XCTAssertEqual(decoded.sessions[0].displayTitle, "Before service")
    }

    func testCorruptLegacyOrNewLibraryIsNeverReplacedByMigration() throws {
        let store = temporaryStore()
        defer { try? FileManager.default.removeItem(at: store.directory) }
        try FileManager.default.createDirectory(at: store.directory, withIntermediateDirectories: true)
        let bad = Data("corrupt source".utf8)
        try bad.write(to: store.libraryURL)
        XCTAssertThrowsError(try store.loadLibrary())
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.cameraLibraryURL.path))
        XCTAssertEqual(try Data(contentsOf: store.libraryURL), bad)
        try store.save([sampleSession()])
        _ = try store.loadLibrary()
        try bad.write(to: store.cameraLibraryURL)
        XCTAssertThrowsError(try store.loadLibrary())
        XCTAssertEqual(try Data(contentsOf: store.cameraLibraryURL), bad)
    }

    func testAtomicUpdatesRetainPreviousLibraryAndMigrationBackup() throws {
        let store = temporaryStore()
        defer { try? FileManager.default.removeItem(at: store.directory) }
        try store.save([sampleSession()])
        var archive = try store.loadLibrary()
        let backup = try Data(contentsOf: store.migrationBackupURL)
        let original = try Data(contentsOf: store.cameraLibraryURL)
        archive.cameras = [CameraProfile(name: "New camera")]
        try store.saveLibrary(archive)
        XCTAssertEqual(try Data(contentsOf: store.directory.appendingPathComponent("library.previous.json")), original)
        XCTAssertEqual(try Data(contentsOf: store.migrationBackupURL), backup)
        XCTAssertEqual(try store.loadLibrary().cameras.first?.name, "New camera")
    }

    func testSnapshotCannotDisagreeWithRecordedSettings() throws {
        var session = try sampleSession()
        session.records[0].nominalDenominator = 250
        XCTAssertThrowsError(try SessionStore.validate([session]))
        session.records[0].derivedSnapshot = MeasurementResult.calculate(packet: session.records[0].packet, direction: .horizontal, nominalDenominator: 250)
        XCTAssertNoThrow(try SessionStore.validate([session]))
    }

    func testRejectsDuplicateOrMissingLocalAndExternalIdentities() throws {
        var camera = CameraProfile(name: "Camera")
        let session = try sampleSession(camera: camera)
        XCTAssertThrowsError(try SessionStore.validateLibrary(CameraLibraryArchive(sessions: [session])))
        XCTAssertThrowsError(try SessionStore.validateLibrary(CameraLibraryArchive(cameras: [camera, camera])))
        camera.catalogueID = UUID()
        XCTAssertThrowsError(try SessionStore.validateLibrary(CameraLibraryArchive(cameras: [camera])))
        camera.catalogueCameraID = UUID()
        camera.catalogueRevision = 1
        var duplicate = camera
        duplicate.id = UUID()
        XCTAssertThrowsError(try SessionStore.validateLibrary(CameraLibraryArchive(cameras: [camera, duplicate])))
        duplicate.catalogueID = UUID()
        XCTAssertNoThrow(try SessionStore.validateLibrary(CameraLibraryArchive(cameras: [camera, duplicate])))
    }

    func testRejectsMediaTraversalAndCrossCameraServiceLinks() throws {
        var camera = CameraProfile(name: "Camera")
        for filename in ["../photo.jpg", "/tmp/photo.jpg", "dir/photo.jpg", "dir\\photo.jpg", ".", "..", "", "photo\n.jpg"] {
            camera.photoFilename = filename
            XCTAssertThrowsError(try SessionStore.validateLibrary(CameraLibraryArchive(cameras: [camera])), filename)
        }
        camera.photoFilename = "portrait.jpg"
        XCTAssertNoThrow(try SessionStore.validateLibrary(CameraLibraryArchive(cameras: [camera])))
        let other = CameraProfile(name: "Other physical camera")
        let session = try sampleSession(camera: other)
        var service = CameraServiceEvent(title: "Service")
        service.afterSessionID = session.id
        camera.serviceEvents = [service]
        XCTAssertThrowsError(try SessionStore.validateLibrary(CameraLibraryArchive(cameras: [camera, other], sessions: [session])))
    }

    func testRejectsUnsupportedSchemaAndInvalidTestParameters() throws {
        XCTAssertThrowsError(try SessionStore.decodeLibrary(SessionStore.encoder().encode(CameraLibraryArchive(schemaVersion: 99))))
        var session = try sampleSession()
        session.plannedSpeeds = [125, 125]
        XCTAssertThrowsError(try SessionStore.validate([session]))
        session.plannedSpeeds = [125]
        session.toleranceStops = -.infinity
        XCTAssertThrowsError(try SessionStore.validate([session]))
        session.toleranceStops = 0.3
        session.repeatsPerSpeed = 0
        XCTAssertThrowsError(try SessionStore.validate([session]))
        session.repeatsPerSpeed = 3
        session.lastExportedRevision = 2
        XCTAssertThrowsError(try SessionStore.validate([session]))
        session.markUpdated()
        XCTAssertNoThrow(try SessionStore.validate([session]))
    }
}
