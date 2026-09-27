import XCTest
import MeasurementCore
@testable import ShutterLover

final class SessionStoreTests: XCTestCase {
    private func sampleSession() -> CaptureSession {
        var session = CaptureSession(cameraName: "Test camera", demo: true)
        let packet = DemoPackets.sample(nominalDenominator: 125, index: 0)
        session.direction = .horizontal
        session.records = [MeasurementRecord(rawLine: String(decoding: try! JSONEncoder().encode(packet), as: UTF8.self), packet: packet, direction: .horizontal, nominalDenominator: 125, isDemo: true)]
        return session
    }

    func testRoundTripPreservesPacketSetupAndCorrections() throws {
        var session = sampleSession()
        session.records[0].settingCorrections = [.init(changedAt: Date(), previousValue: 60, newValue: 125)]
        session.records[0].isExcluded = true
        let data = try SessionStore.encoder().encode(SessionArchive(sessions: [session]))
        let result = try XCTUnwrap(SessionStore.decode(data).first)
        XCTAssertEqual(result.id, session.id)
        XCTAssertEqual(result.records[0].packet, session.records[0].packet)
        XCTAssertEqual(result.records[0].rawLine, session.records[0].rawLine)
        XCTAssertEqual(result.records[0].direction, .horizontal)
        XCTAssertEqual(result.records[0].settingCorrections[0].previousValue, 60)
        XCTAssertTrue(result.records[0].isExcluded)
        XCTAssertEqual(result.records[0].capturedAt.timeIntervalSince1970, session.records[0].capturedAt.timeIntervalSince1970, accuracy: 0.001)
    }

    func testUnsupportedVersionAndDuplicateIDsAreRejected() throws {
        let session = sampleSession()
        let unsupported = try SessionStore.encoder().encode(SessionArchive(schemaVersion: 7, sessions: [session]))
        XCTAssertThrowsError(try SessionStore.decode(unsupported))
        XCTAssertThrowsError(try SessionStore.validate([session, session]))
        var duplicate = session
        duplicate.records.append(duplicate.records[0])
        XCTAssertThrowsError(try SessionStore.validate([duplicate]))
    }

    func testMixedSimulatedAndRealRecordsRejected() {
        var session = sampleSession()
        session.demo = false
        XCTAssertThrowsError(try SessionStore.validate([session]))
    }

    func testConflictingRawPacketAndGeometryAreRejected() {
        var session = sampleSession()
        session.records[0].rawLine = "{}"
        XCTAssertThrowsError(try SessionStore.validate([session]))
        session = sampleSession()
        session.records[0].settingCorrections = [.init(changedAt: Date(), previousValue: 60, newValue: 250)]
        XCTAssertThrowsError(try SessionStore.validate([session]))
        session = sampleSession()
        session.records[0].frameWidthMM = 60
        XCTAssertThrowsError(try SessionStore.validate([session]))
    }

    @MainActor
    func testTemporaryInvalidSettingDoesNotLoseReadingOrOtherEdits() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let model = AppModel(store: SessionStore(directory: root), startDiscovery: false)
        model.nominalDenominator = 125
        model.nominalDenominator = 0
        model.cameraName = "Kept name"
        model.direction = .horizontal
        model.addDemoReading()
        XCTAssertEqual(model.currentRecords.count, 1)
        XCTAssertEqual(model.currentRecords[0].nominalDenominator, 125)
        XCTAssertEqual(model.currentRecords[0].direction, .horizontal)
        XCTAssertEqual(model.currentSession?.cameraName, "Kept name")
        model.shutDown()
    }

    func testAtomicLibraryRetainsPreviousSnapshotAndReportsCorruption() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = SessionStore(directory: root)
        var session = sampleSession()
        try store.save([session])
        session.cameraName = "Updated"
        try store.save([session])
        XCTAssertEqual(try store.load().first?.cameraName, "Updated")
        let previous = try Data(contentsOf: root.appendingPathComponent("sessions.previous.json"))
        XCTAssertEqual(try SessionStore.decode(previous).first?.cameraName, "Test camera")
        try Data("bad data".utf8).write(to: store.libraryURL)
        XCTAssertThrowsError(try store.load())
        XCTAssertEqual(try String(contentsOf: store.libraryURL, encoding: .utf8), "bad data")
    }

    func testExportIncludesEveryOriginalMetricAndMissingIsNotZero() {
        var session = sampleSession()
        session.records[0].packet = DemoPackets.sample(nominalDenominator: 125, index: 0, partial: true)
        let output = SessionExport.table(session.records, separator: "\t")
        let rows = output.split(separator: "\n").map { $0.split(separator: "\t", omittingEmptySubsequences: false) }
        XCTAssertEqual(rows[0].count, SessionExport.headers.count)
        XCTAssertEqual(rows[1].count, SessionExport.headers.count)
        XCTAssertTrue(rows[1].contains(""))
        XCTAssertTrue(output.contains("Open 1/2"))
        XCTAssertTrue(output.contains("Close 2/2"))
        XCTAssertTrue(output.contains("Simulated"))
        let selected = SessionExport.table(session.records, separator: "\t", readingNumbers: [session.records[0].id: 8])
        XCTAssertTrue(selected.contains("\n8\t\(session.records[0].id.uuidString)\t"))
    }

    @MainActor
    func testSetupChangesDoNotReinterpretPreviousReadingsAndDeleteCanUndo() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let model = AppModel(store: SessionStore(directory: root), startDiscovery: false)
        model.direction = .horizontal
        model.nominalDenominator = 125
        model.addDemoReading()
        let first = try XCTUnwrap(model.selectedRecord)
        model.direction = .vertical
        model.nominalDenominator = 250
        XCTAssertEqual(model.currentRecords[0].direction, .horizontal)
        XCTAssertEqual(model.currentRecords[0].nominalDenominator, 125)
        model.deleteSelectedReading()
        XCTAssertTrue(model.currentRecords.isEmpty)
        model.undoDelete()
        XCTAssertEqual(model.currentRecords[0].id, first.id)
        model.updateSelectedSetting(60)
        XCTAssertEqual(model.currentRecords[0].packet, first.packet)
        XCTAssertEqual(model.currentRecords[0].settingCorrections.count, 1)
        model.shutDown()
    }

    @MainActor
    func testPartialReadingDoesNotAdvanceSequenceAndDemoRemainsSeparate() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let model = AppModel(store: SessionStore(directory: root), startDiscovery: false)
        model.nominalDenominator = 125
        model.autoAdvance = true
        model.addDemoReading(partial: true)
        XCTAssertEqual(model.nominalDenominator, 125)
        model.addDemoReading()
        XCTAssertEqual(model.nominalDenominator, 250)
        model.setDemoMode(false)
        XCTAssertEqual(model.sessions.count, 2)
        XCTAssertTrue(model.currentRecords.isEmpty)
        XCTAssertFalse(model.isDemoMode)
        model.addDemoReading()
        XCTAssertTrue(model.currentRecords.isEmpty)
        model.shutDown()
    }

    @MainActor
    func testCorruptLibraryIsNeverOverwrittenOnStartupOrQuit() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let store = SessionStore(directory: root)
        try Data("broken".utf8).write(to: store.libraryURL)
        let model = AppModel(store: store, startDiscovery: false)
        model.addDemoReading()
        model.shutDown()
        XCTAssertEqual(try String(contentsOf: store.libraryURL, encoding: .utf8), "broken")
        XCTAssertTrue(model.saveStatus.hasPrefix("Not saved"))
    }
}
