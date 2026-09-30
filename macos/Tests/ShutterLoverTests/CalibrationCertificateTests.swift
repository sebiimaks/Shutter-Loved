import XCTest
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import MeasurementCore
@testable import ShutterLover

final class CalibrationCertificateTests: XCTestCase {
    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("calibration-certificate-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func pdf(password: String? = nil) throws -> Data {
        let bytes = NSMutableData()
        let consumer = try XCTUnwrap(CGDataConsumer(data: bytes))
        var page = CGRect(x: 0, y: 0, width: 300, height: 200)
        let options: CFDictionary? = password.map {
            [kCGPDFContextUserPassword: $0, kCGPDFContextOwnerPassword: "test-owner-password"] as CFDictionary
        }
        let context = try XCTUnwrap(CGContext(consumer: consumer, mediaBox: &page, options))
        context.beginPDFPage(nil)
        context.setFillColor(CGColor(gray: 0.2, alpha: 1))
        context.fill(CGRect(x: 10, y: 10, width: 40, height: 40))
        context.endPDFPage()
        context.closePDF()
        return bytes as Data
    }

    private func imageData(type: UTType) throws -> Data {
        let context = try XCTUnwrap(CGContext(data: nil, width: 32, height: 24, bitsPerComponent: 8, bytesPerRow: 0,
                                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(red: 0.2, green: 0.4, blue: 0.8, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 32, height: 24))
        let image = try XCTUnwrap(context.makeImage())
        let bytes = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(bytes, type.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return bytes as Data
    }

    func testPDFAttachmentCopiesExactBytesAndSurvivesOriginalRemovalAndLibraryReload() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let original = directory.appendingPathComponent("Calibration.PDF")
        let bytes = try pdf()
        try bytes.write(to: original)
        let certificate = try CalibrationCertificate.read(from: original)
        XCTAssertEqual(certificate.data, bytes)
        XCTAssertEqual(certificate.filename, "Calibration.PDF")
        XCTAssertEqual(certificate.contentType, .pdf)
        try FileManager.default.removeItem(at: original)

        let tester = OwnedTester(name: "Calibrated unit", model: .shutterLover,
                                 calibratedOptimalDistanceMM: 12.5, calibrationCertificate: certificate)
        let store = SessionStore(directory: directory.appendingPathComponent("library"))
        try store.saveLibrary(CameraLibraryArchive(ownedTesters: [tester]))
        let restored = try XCTUnwrap(store.loadLibrary().ownedTesters.first)
        let restoredCertificate = try XCTUnwrap(restored.calibrationCertificate)
        XCTAssertEqual(restoredCertificate.id, certificate.id)
        XCTAssertEqual(restoredCertificate.filename, certificate.filename)
        XCTAssertEqual(restoredCertificate.importedAt.timeIntervalSince1970,
                       certificate.importedAt.timeIntervalSince1970, accuracy: 0.001)
        XCTAssertEqual(restored.calibrationCertificate?.data, bytes)
        XCTAssertEqual(restored.calibratedOptimalDistanceMM, 12.5)
        XCTAssertNoThrow(try restored.calibrationCertificate?.validate())
    }

    func testSupportedImagesImportWithActualTypeAndOriginalBytes() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        for (type, suffix) in [(UTType.png, "png"), (.jpeg, "jpeg"), (.tiff, "tiff"), (.heic, "heic")] {
            let bytes = try imageData(type: type)
            let url = directory.appendingPathComponent("certificate.\(suffix)")
            try bytes.write(to: url)
            let certificate = try CalibrationCertificate.read(from: url)
            XCTAssertEqual(certificate.contentType, type)
            XCTAssertEqual(certificate.data, bytes)
            XCTAssertNoThrow(try certificate.validate())
        }
    }

    func testValidationRejectsUnsupportedMalformedMismatchedEmptyAndUnsafeAttachments() throws {
        let bytes = try pdf()
        for filename in ["", ".", "..", "../certificate.pdf", "folder/certificate.pdf", "folder\\certificate.pdf", "a:certificate.pdf", "bad\nname.pdf", String(repeating: "a", count: 256) + ".pdf"] {
            XCTAssertThrowsError(try CalibrationCertificate(filename: filename, data: bytes).validate(), filename)
        }
        for certificate in [CalibrationCertificate(filename: "certificate.txt", data: bytes),
                            CalibrationCertificate(filename: "certificate.png", data: bytes),
                            CalibrationCertificate(filename: "certificate.pdf", data: try imageData(type: .png)),
                            CalibrationCertificate(filename: "certificate.pdf", data: Data()),
                            CalibrationCertificate(filename: "certificate.pdf", data: Data("%PDF-1.7\nnot a PDF document".utf8)),
                            CalibrationCertificate(filename: "certificate.png", data: Data([0x89, 0x50, 0x4e, 0x47])),
                            CalibrationCertificate(filename: "certificate.pdf", data: Data(repeating: 0, count: CalibrationCertificate.maximumBytes + 1))] {
            XCTAssertThrowsError(try certificate.validate(), certificate.filename)
        }
        var certificate = CalibrationCertificate(filename: "certificate.pdf", data: bytes)
        certificate.importedAt = Date(timeIntervalSince1970: .infinity)
        XCTAssertThrowsError(try certificate.validate())
    }

    func testPasswordLockedPDFIsRejected() throws {
        XCTAssertThrowsError(try CalibrationCertificate(filename: "locked.pdf", data: pdf(password: "secret")).validate())
    }

    func testImportRejectsDirectoriesAndOversizedFilesBeforeReadingContents() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        XCTAssertThrowsError(try CalibrationCertificate.read(from: directory))
        let oversized = directory.appendingPathComponent("large.pdf")
        XCTAssertTrue(FileManager.default.createFile(atPath: oversized.path, contents: nil))
        let handle = try FileHandle(forWritingTo: oversized)
        try handle.truncate(atOffset: UInt64(CalibrationCertificate.maximumBytes + 1))
        try handle.close()
        XCTAssertThrowsError(try CalibrationCertificate.read(from: oversized)) { error in
            guard case CalibrationCertificateError.tooLarge = error else { return XCTFail("Unexpected error: \(error)") }
        }
    }

    func testDistanceValidationAndModelRestrictionsApplyToInventoryAndSnapshots() throws {
        var tester = OwnedTester(name: "Shutter Lover", model: .shutterLover)
        XCTAssertNoThrow(try SessionStore.validateOwnedTesters([tester]))
        for distance in [0.001, 25, 10_000] {
            tester.calibratedOptimalDistanceMM = distance
            XCTAssertNoThrow(try SessionStore.validateOwnedTesters([tester]))
            XCTAssertNoThrow(try SessionStore.validateTesterSnapshot(TesterSnapshot(tester: tester)))
        }
        for distance in [0, -1, 10_000.001, .infinity, -.infinity, .nan] {
            tester.calibratedOptimalDistanceMM = distance
            XCTAssertThrowsError(try SessionStore.validateOwnedTesters([tester]))
            XCTAssertThrowsError(try SessionStore.validateTesterSnapshot(TesterSnapshot(tester: tester)))
        }
        for model in [TesterModel.babyShutterTesterMkI, .babyShutterTesterMkII] {
            tester.model = model
            tester.calibratedOptimalDistanceMM = 25
            XCTAssertThrowsError(try SessionStore.validateOwnedTesters([tester]))
            XCTAssertThrowsError(try SessionStore.validateTesterSnapshot(TesterSnapshot(tester: tester)))
            tester.calibratedOptimalDistanceMM = nil
            tester.calibrationCertificate = CalibrationCertificate(filename: "certificate.pdf", data: try pdf())
            XCTAssertThrowsError(try SessionStore.validateOwnedTesters([tester]))
            tester.calibrationCertificate = nil
            XCTAssertNoThrow(try SessionStore.validateOwnedTesters([tester]))
        }
    }

    func testHistoricalSnapshotKeepsDistanceAfterInventoryChangesAndExportsNoCertificate() throws {
        var tester = OwnedTester(name: "Calibrated unit", model: .shutterLover,
                                 calibratedOptimalDistanceMM: 24.5,
                                 calibrationCertificate: CalibrationCertificate(filename: "certificate.pdf", data: try pdf()))
        let snapshot = TesterSnapshot(tester: tester)
        let packet = DemoPackets.sample(nominalDenominator: 125, index: 0)
        let record = MeasurementRecord(rawLine: String(decoding: try JSONEncoder().encode(packet), as: UTF8.self),
                                       packet: packet, tester: snapshot, direction: .horizontal,
                                       nominalDenominator: 125, isDemo: false)
        let session = CaptureSession(cameraName: "Camera", demo: false, records: [record], tester: snapshot)
        tester.calibratedOptimalDistanceMM = 31
        tester.calibrationCertificate = nil
        let restored = try SessionStore.decodeLibrary(SessionStore.encoder().encode(CameraLibraryArchive(sessions: [session], ownedTesters: [tester])))
        XCTAssertEqual(restored.ownedTesters[0].calibratedOptimalDistanceMM, 31)
        XCTAssertEqual(restored.sessions[0].records[0].tester?.calibratedOptimalDistanceMM, 24.5)
        XCTAssertEqual(restored.sessions[0].records[0].tester, snapshot)
        let portable = try SessionStore.encoder().encode(SessionArchive(sessions: [session]))
        let json = String(decoding: portable, as: UTF8.self)
        XCTAssertTrue(json.contains("calibratedOptimalDistanceMM"))
        XCTAssertFalse(json.contains("calibrationCertificate"))
        XCTAssertFalse(json.contains("certificate.pdf"))
        XCTAssertEqual(try SessionStore.decode(portable)[0].records[0].tester?.calibratedOptimalDistanceMM, 24.5)
    }

    func testLegacyTesterAndSnapshotWithoutNewFieldsDecodeUnchanged() throws {
        let tester = OwnedTester(name: "Legacy unit", model: .shutterLover)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: SessionStore.encoder().encode(tester)) as? [String: Any])
        object.removeValue(forKey: "calibratedOptimalDistanceMM")
        object.removeValue(forKey: "calibrationCertificate")
        let restored = try SessionStore.decoder().decode(OwnedTester.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertEqual(restored, tester)
        XCTAssertNil(restored.calibrationCertificate)
        XCTAssertNil(restored.calibratedOptimalDistanceMM)

        let snapshot = TesterSnapshot(tester: tester)
        var historical = try XCTUnwrap(JSONSerialization.jsonObject(with: SessionStore.encoder().encode(snapshot)) as? [String: Any])
        historical.removeValue(forKey: "calibratedOptimalDistanceMM")
        XCTAssertEqual(try SessionStore.decoder().decode(TesterSnapshot.self, from: JSONSerialization.data(withJSONObject: historical)), snapshot)
    }
}
