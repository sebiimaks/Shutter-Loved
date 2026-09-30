import XCTest
import PDFKit
import MeasurementCore
@testable import ShutterLover

final class CalibrationResultsTests: XCTestCase {
    private func tester(distanceMM: Double? = 325.5) -> OwnedTester {
        var tester = OwnedTester(name: "Calibration evidence tester", model: .shutterLover)
        tester.serialNumber = "SYNTHETIC-CALIBRATION-1"
        tester.calibratedOptimalDistanceMM = distanceMM
        return tester
    }

    private func reading(_ tester: OwnedTester) throws -> MeasurementRecord {
        let packet = DemoPackets.sample(nominalDenominator: 125, index: 0)
        return MeasurementRecord(rawLine: String(decoding: try JSONEncoder().encode(packet), as: UTF8.self),
                                 packet: packet, tester: TesterSnapshot(tester: tester),
                                 direction: .unknown, nominalDenominator: 125, isDemo: false)
    }

    private func camera() -> CameraProfile {
        var camera = CameraProfile(name: "Calibration evidence camera")
        camera.catalogueID = UUID()
        camera.catalogueCameraID = UUID()
        camera.catalogueRevision = 1
        return camera
    }

    private func session(_ records: [MeasurementRecord], camera: CameraProfile) -> CaptureSession {
        var session = CaptureSession(cameraName: camera.name, demo: false)
        session.cameraID = camera.id
        session.cameraSnapshot = CameraIdentitySnapshot(camera: camera)
        session.tester = records.last?.tester
        session.records = records
        return session
    }

    func testDistanceSnapshotKeepsOriginalCalibrationAcrossProfileEditsAndArchives() throws {
        var owned = tester()
        let original = try reading(owned)
        owned.calibratedOptimalDistanceMM = 450
        let later = try reading(owned)
        XCTAssertEqual(original.tester?.calibratedOptimalDistanceMM, 325.5)
        XCTAssertEqual(later.tester?.calibratedOptimalDistanceMM, 450)
        XCTAssertEqual(original.result, later.result, "Calibration recommendations do not change measured timing.")

        let camera = camera()
        let session = session([original, later], camera: camera)
        let fullSessionData = try SessionStore.encoder().encode(SessionArchive(sessions: [session]))
        let sessions = try SessionStore.decode(fullSessionData)
        XCTAssertEqual(sessions.first?.records.map { $0.tester?.calibratedOptimalDistanceMM }, [325.5, 450])
        let fullCameraData = try SessionStore.encoder().encode(PortableCameraArchive(sourceLibraryID: UUID(), camera: camera, sessions: [session]))
        let archived = try PortableCameraArchive.decode(fullCameraData)
        let (_, copies) = archived.localCopy()
        XCTAssertEqual(copies.first?.records.map { $0.tester?.calibratedOptimalDistanceMM }, [325.5, 450])
        XCTAssertEqual(copies.first?.records.first?.tester, original.tester)
        XCTAssertEqual(copies.first?.records.last?.tester, later.tester)
    }

    func testRecordedCalibrationDistancesRemainSeparateIncludingUnknown() throws {
        var owned = tester()
        let first = try reading(owned)
        owned.name = "New nickname"
        let sameCalibration = try reading(owned)
        owned.calibratedOptimalDistanceMM = 450
        let recalibrated = try reading(owned)
        owned.calibratedOptimalDistanceMM = nil
        let unknown = try reading(owned)
        XCTAssertEqual(first.resultContextID, sameCalibration.resultContextID)
        XCTAssertNotEqual(first.resultContextID, recalibrated.resultContextID)
        XCTAssertNotEqual(first.resultContextID, unknown.resultContextID)
        let groups = CameraResultGroup.groups(for: session([first, sameCalibration, recalibrated, unknown], camera: camera()))
        XCTAssertEqual(groups.count, 3)
        XCTAssertEqual(groups.first { $0.count == 2 }?.records.count, 2)
        XCTAssertTrue(first.resultContextDescription.contains("Calibrated optimal distance: 325.5 mm"))
        XCTAssertTrue(first.testerProvenanceDescription.contains("actual placement not recorded"))
        XCTAssertFalse(unknown.testerProvenanceDescription.contains("Calibrated optimal distance"))
    }

    func testArmariumV1CarriesCalibrationInNotesWithoutNewFieldsOrMeasurements() throws {
        let owned = tester()
        let record = try reading(owned)
        let session = session([record], camera: camera())
        let data = try ShutterTesterExchange.exportResults(producerLibraryID: UUID(), session: session)
        try ShutterTesterExchange.validateResults(data)
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(root["version"] as? Int, 1)
        let test = try XCTUnwrap((root["tests"] as? [[String: Any]])?.first)
        let notes = try XCTUnwrap(test["notes"] as? String)
        XCTAssertTrue(notes.contains("Calibrated optimal distance: 325.5 mm"))
        XCTAssertTrue(notes.contains("recommended LED-to-sensor distance; actual placement not recorded"))
        let metadata = try XCTUnwrap(test["tester"] as? [String: Any])
        XCTAssertEqual(Set(metadata.keys), Set(["model", "manufacturer", "serial", "firmware"]))
        XCTAssertNil(test["calibratedOptimalDistanceMM"])
        XCTAssertNil(test["conditions"], "A calibration recommendation is not an observed setup condition.")
        let measurements = try XCTUnwrap(test["measurements"] as? [[String: Any]])
        XCTAssertEqual(measurements.count, 5)
        XCTAssertTrue(measurements.allSatisfy { $0["unit"] as? String == "s" })
        XCTAssertTrue(measurements.allSatisfy { Set($0.keys).isSubset(of: ["quantity", "value", "unit", "nominalValue", "position", "sampleIndex"]) })
    }

    func testTableExportKeepsDistanceColumnAlignedAndUnknownDistanceBlank() throws {
        let recorded = try reading(tester())
        let unknown = try reading(tester(distanceMM: nil))
        let rows = SessionExport.table([recorded, unknown], separator: "\t")
            .split(separator: "\n").map { $0.split(separator: "\t", omittingEmptySubsequences: false).map(String.init) }
        XCTAssertEqual(rows.count, 3)
        XCTAssertEqual(rows[0], SessionExport.headers)
        XCTAssertTrue(rows.allSatisfy { $0.count == SessionExport.headers.count })
        let distanceColumn = try XCTUnwrap(rows[0].firstIndex(of: "Calibrated optimal distance (mm)"))
        XCTAssertEqual(distanceColumn, SessionExport.headers.count - 1)
        XCTAssertEqual(rows[1][distanceColumn], "325.5")
        XCTAssertEqual(rows[2][distanceColumn], "", "Unknown distance must remain blank, never zero.")
        let timeColumn = try XCTUnwrap(rows[0].firstIndex(of: "Time (ms)"))
        XCTAssertEqual(Double(rows[1][timeColumn]), recorded.result.center.durationMS)
        XCTAssertEqual(rows[1][timeColumn], rows[2][timeColumn], "Calibration metadata must not change measured timing.")
    }

    @MainActor
    func testPDFIdentifiesRecommendedDistanceWithoutClaimingActualPlacement() throws {
        let camera = camera()
        let session = try session([reading(tester())], camera: camera)
        let document = try XCTUnwrap(PDFDocument(data: CameraReport.pdf(camera: camera, image: nil, session: session)))
        let text = (0..<document.pageCount).compactMap { document.page(at: $0)?.string }
            .joined(separator: " ").components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.joined(separator: " ")
        XCTAssertTrue(text.contains("Calibrated optimal distance: 325.5 mm"))
        XCTAssertTrue(text.contains("actual placement not recorded"))
        XCTAssertTrue(text.contains("recorded calibration distances separate"))
    }
}
