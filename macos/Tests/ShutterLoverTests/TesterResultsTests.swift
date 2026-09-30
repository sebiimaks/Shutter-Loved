import XCTest
import PDFKit
import MeasurementCore
@testable import ShutterLover

final class TesterResultsTests: XCTestCase {
    private func manualRecord(tester: OwnedTester, mode: BabyMeasurementMode = .automatic,
                              value: Double = 8, unit: ManualTimeUnit = .milliseconds) -> MeasurementRecord {
        MeasurementRecord(rawLine: "", packet: nil,
                          manual: ManualMeasurement(enteredValue: value, unit: unit, mode: mode),
                          tester: TesterSnapshot(tester: tester), direction: .unknown,
                          nominalDenominator: 125, isDemo: false)
    }

    private func usbRecord(tester: OwnedTester? = nil) throws -> MeasurementRecord {
        let packet = DemoPackets.sample(nominalDenominator: 125, index: 0)
        return MeasurementRecord(rawLine: String(decoding: try JSONEncoder().encode(packet), as: UTF8.self),
                                 packet: packet, tester: tester.map { TesterSnapshot(tester: $0) },
                                 direction: .unknown, nominalDenominator: 125, isDemo: false)
    }

    private func linkedSession(_ records: [MeasurementRecord]) -> CaptureSession {
        var camera = CameraProfile(name: "Synthetic camera")
        camera.catalogueID = UUID()
        camera.catalogueCameraID = UUID()
        camera.catalogueRevision = 1
        var session = CaptureSession(cameraName: camera.name, demo: false)
        session.cameraID = camera.id
        session.cameraSnapshot = CameraIdentitySnapshot(camera: camera)
        session.records = records
        return session
    }

    private func exportedTest(_ session: CaptureSession) throws -> [String: Any] {
        let data = try ShutterTesterExchange.exportResults(producerLibraryID: UUID(), session: session)
        try ShutterTesterExchange.validateResults(data)
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        return try XCTUnwrap((root["tests"] as? [[String: Any]])?.first)
    }

    func testManualMkIIExportHasOneDurationWithoutInventedSensorOrTravel() throws {
        var tester = OwnedTester(name: "Bench Baby", model: .babyShutterTesterMkII)
        tester.serialNumber = "BABY-QA-1"
        var record = manualRecord(tester: tester, value: 125, unit: .reciprocalSeconds)
        record.manual?.illumination = 72
        record.manual?.notes = "Synthetic display entry"
        let result = try exportedTest(linkedSession([record]))
        let quantities = try XCTUnwrap(result["measurements"] as? [[String: Any]])
        XCTAssertEqual(quantities.count, 1)
        XCTAssertEqual(quantities[0]["quantity"] as? String, "exposureDuration")
        XCTAssertEqual(try XCTUnwrap(quantities[0]["value"] as? Double), 0.008, accuracy: 1e-12)
        XCTAssertNil(quantities[0]["position"], "Manual transcription does not establish a physical sensor position.")
        XCTAssertEqual(quantities[0]["sampleIndex"] as? Int, 1)
        let metadata = try XCTUnwrap(result["tester"] as? [String: Any])
        XCTAssertEqual(metadata["model"] as? String, tester.model.displayName)
        XCTAssertEqual(metadata["manufacturer"] as? String, tester.model.manufacturer)
        XCTAssertEqual(metadata["serial"] as? String, tester.serialNumber)
        let notes = try XCTUnwrap(result["notes"] as? String)
        for expected in ["Manually transcribed effective exposure", "125.0 1/s", "automatic", "Illumination E0: 72.0", tester.id.uuidString.lowercased(), "Synthetic display entry"] {
            XCTAssertTrue(notes.contains(expected), "Missing provenance: \(expected)")
        }
        XCTAssertNil(record.result.bottomLeft.durationMS)
        XCTAssertNil(record.result.topRight.durationMS)
        XCTAssertNil(record.result.openingTravelMS)
    }

    func testManualMkIExportPreservesMeasuredExposureMeaning() throws {
        let tester = OwnedTester(name: "Original Baby", model: .babyShutterTesterMkI)
        let record = manualRecord(tester: tester, mode: .unspecified, value: 0.008, unit: .seconds)
        let result = try exportedTest(linkedSession([record]))
        let notes = try XCTUnwrap(result["notes"] as? String)
        XCTAssertTrue(notes.contains("Manually transcribed measured exposure"))
        XCTAssertTrue(notes.contains("0.008 s"))
        XCTAssertEqual((result["measurements"] as? [[String: Any]])?.count, 1)
    }

    func testMixedTesterExportUsesPerSampleAttributionWithoutClaimingOneModel() throws {
        let baby = OwnedTester(name: "Baby unit", model: .babyShutterTesterMkII)
        let lover = OwnedTester(name: "USB unit", model: .shutterLover)
        let session = linkedSession([manualRecord(tester: baby), try usbRecord(tester: lover)])
        let result = try exportedTest(session)
        let metadata = try XCTUnwrap(result["tester"] as? [String: Any])
        XCTAssertNil(metadata["model"])
        let notes = try XCTUnwrap(result["notes"] as? String)
        XCTAssertTrue(notes.contains(baby.id.uuidString.lowercased()))
        XCTAssertTrue(notes.contains(lover.id.uuidString.lowercased()))
        let measurements = try XCTUnwrap(result["measurements"] as? [[String: Any]])
        XCTAssertEqual(measurements.filter { $0["sampleIndex"] as? Int == 1 }.count, 1)
        XCTAssertEqual(measurements.filter { $0["sampleIndex"] as? Int == 2 }.count, 5)
    }

    func testLegacyExportDoesNotRewriteExistingEvidenceNotesOrTesterMetadata() throws {
        var record = try usbRecord()
        record.capturedAt = Date(timeIntervalSince1970: 1_800_000_000)
        var session = linkedSession([record])
        // Selecting a new tester for future readings must not relabel old evidence.
        session.tester = TesterSnapshot(tester: OwnedTester(name: "Newly selected unit", model: .babyShutterTesterMkII))
        let result = try exportedTest(session)
        let expected = "Shutter Lover calculation version 1. Exposure and calibrated outer-sensor curtain intervals are measured seconds. Curtain intervals span the 32 × 20 mm sensor rectangle; they are not full-frame travel estimates. Exported 1 complete included device readings; omitted 0 excluded, partial or invalid readings and 0 nonpositive/unavailable curtain quantities. Raw events, calibration, exclusions and complete provenance are retained in the Shutter Lover archive."
            + "\n\nSample 1: reading \(record.id.uuidString.lowercased()); direction unknown; captured 2027-01-15T08:00:00.000Z."
        XCTAssertEqual(result["notes"] as? String, expected)
        let metadata = try XCTUnwrap(result["tester"] as? [String: String])
        XCTAssertEqual(metadata, ["model": "Shutter Lover", "firmware": record.firmwareVersion])
        XCTAssertFalse(session.testerSummary.contains("Newly selected unit"))
    }

    func testGroupsSeparatePhysicalUnitsModesModelsAndMeasurementSource() throws {
        let first = OwnedTester(name: "Baby A", model: .babyShutterTesterMkII)
        let second = OwnedTester(name: "Baby B", model: .babyShutterTesterMkII)
        let original = OwnedTester(name: "Original Baby", model: .babyShutterTesterMkI)
        let readings = [manualRecord(tester: first), manualRecord(tester: first, value: 10),
                        manualRecord(tester: first, mode: .global), manualRecord(tester: second),
                        manualRecord(tester: original, mode: .unspecified), try usbRecord()]
        let groups = CameraResultGroup.groups(for: linkedSession(readings))
        XCTAssertEqual(groups.count, 5)
        let repeated = try XCTUnwrap(groups.first { $0.count == 2 })
        XCTAssertEqual(repeated.meanMS, 9, accuracy: 1e-12)
        XCTAssertEqual(try XCTUnwrap(repeated.sampleSD), sqrt(2), accuracy: 1e-12)
        XCTAssertEqual(Set(groups.map(\.id)).count, 5)
    }

    func testGroupingUsesStableOwnedIdentityAndRetainsPerReadingIllumination() throws {
        var tester = OwnedTester(name: "Old nickname", model: .babyShutterTesterMkII)
        var first = manualRecord(tester: tester)
        first.manual?.illumination = 70
        tester.name = "Updated nickname"
        var second = manualRecord(tester: tester)
        second.manual?.illumination = 72
        XCTAssertEqual(first.resultContextID, second.resultContextID)
        let groups = CameraResultGroup.groups(for: linkedSession([first, second]))
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups.first?.count, 2)
        XCTAssertEqual(first.tester?.name, "Old nickname")
        XCTAssertTrue(first.manualProvenanceDescription?.contains("70.0") == true)
    }

    @MainActor
    func testPDFShowsTesterManualProvenanceAndSeparatedSummaryRows() throws {
        var tester = OwnedTester(name: "Report Baby", model: .babyShutterTesterMkII)
        tester.serialNumber = "REPORT-UNIT-1"
        let automatic = manualRecord(tester: tester, value: 8)
        let global = manualRecord(tester: tester, mode: .global, value: 16)
        let session = linkedSession([automatic, global])
        let pdf = try CameraReport.pdf(camera: CameraProfile(name: "Synthetic camera"), image: nil, session: session)
        let document = try XCTUnwrap(PDFDocument(data: pdf))
        let text = (0..<document.pageCount).compactMap { document.page(at: $0)?.string }.joined(separator: "\n")
        for expected in ["Tester used:", "Report Baby", "REPORT-UNIT-1", tester.model.manufacturer,
                         "Manual readings", "Effective exposure", "Automatic mode", "Global mode",
                         "8.000 ms", "16.000 ms", "Original manual entries", automatic.id.uuidString.lowercased()] {
            XCTAssertTrue(text.contains(expected), "Report missing \(expected)")
        }
        XCTAssertFalse(text.contains("12.000 ms"), "Different manual modes cannot be averaged together.")
    }

    func testPortableArchiveCopyPreservesManualEvidenceAndImmutableTesterSnapshot() throws {
        var tester = OwnedTester(name: "Archive Baby", model: .babyShutterTesterMkII)
        tester.serialNumber = "ARCHIVE-UNIT-1"
        tester.calibrationDate = Date(timeIntervalSince1970: 1_800_000_000)
        tester.calibrationNotes = "Synthetic calibration note"
        var record = manualRecord(tester: tester, mode: .global, value: 125, unit: .reciprocalSeconds)
        record.manual?.illumination = 70
        record.manual?.seriesIllumination = 90
        record.manual?.notes = "Original display copied by operator"
        let camera = CameraProfile(name: "Archive camera")
        var session = CaptureSession(cameraName: camera.name, demo: false)
        session.cameraID = camera.id
        session.cameraSnapshot = CameraIdentitySnapshot(camera: camera)
        session.tester = record.tester
        session.records = [record]
        let archive = PortableCameraArchive(sourceLibraryID: UUID(), camera: camera, sessions: [session])
        let decoded = try PortableCameraArchive.decode(SessionStore.encoder().encode(archive))
        let (copy, tests) = decoded.localCopy()
        let copiedSession = try XCTUnwrap(tests.first)
        let copiedReading = try XCTUnwrap(copiedSession.records.first)
        XCTAssertNotEqual(copy.id, camera.id)
        XCTAssertNotEqual(copiedSession.id, session.id)
        XCTAssertNotEqual(copiedReading.id, record.id)
        XCTAssertEqual(copiedReading.manual, record.manual)
        XCTAssertEqual(copiedReading.tester, record.tester)
        XCTAssertEqual(copiedSession.tester, session.tester)
        XCTAssertEqual(copiedReading.capturedAt.timeIntervalSince1970, record.capturedAt.timeIntervalSince1970, accuracy: 0.001)
        XCTAssertEqual(copiedReading.result, record.result)
        XCTAssertNil(copiedReading.packet)
        XCTAssertTrue(copiedReading.rawLine.isEmpty)
        XCTAssertTrue(copiedReading.manualProvenanceDescription?.contains("Series maximum illumination E0: 90.0") == true)
        try SessionStore.validateLibrary(CameraLibraryArchive(cameras: [copy], sessions: tests))
    }
}
