import AppKit
import PDFKit
import XCTest
import MeasurementCore
@testable import ShutterLover

final class CameraMediaTests: XCTestCase {
    @MainActor
    private func withModel(_ body: (AppModel) throws -> Void) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("camera-media-tests-\(UUID().uuidString)")
        let model = AppModel(store: SessionStore(directory: directory), startDiscovery: false)
        defer {
            model.shutDown()
            try? FileManager.default.removeItem(at: directory)
        }
        try body(model)
    }

    /// Draw a synthetic 3:2 subject with no downloaded assets or personal files.
    @MainActor
    private func syntheticPhoto() throws -> Data {
        let bitmap = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 300, pixelsHigh: 200,
                                                  bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                                  isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        let graphics = try XCTUnwrap(NSGraphicsContext(bitmapImageRep: bitmap))
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = graphics
        NSColor(calibratedRed: 0.9, green: 0.88, blue: 0.82, alpha: 1).setFill()
        NSBezierPath(rect: NSRect(x: 0, y: 0, width: 300, height: 200)).fill()
        NSColor.darkGray.setFill()
        NSBezierPath(roundedRect: NSRect(x: 45, y: 45, width: 210, height: 110), xRadius: 8, yRadius: 8).fill()
        NSColor.lightGray.setFill()
        NSBezierPath(rect: NSRect(x: 65, y: 145, width: 50, height: 20)).fill()
        NSBezierPath(rect: NSRect(x: 195, y: 145, width: 35, height: 20)).fill()
        NSColor.black.setFill()
        NSBezierPath(ovalIn: NSRect(x: 102, y: 52, width: 96, height: 96)).fill()
        NSColor(calibratedRed: 0.18, green: 0.35, blue: 0.46, alpha: 1).setFill()
        NSBezierPath(ovalIn: NSRect(x: 116, y: 66, width: 68, height: 68)).fill()
        NSGraphicsContext.restoreGraphicsState()
        return try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
    }

    @MainActor
    private func installPhoto(_ model: AppModel) throws -> (CameraProfile, Data, Data) {
        var camera = CameraProfile(name: "SYNTHETIC QA CAMERA")
        camera.manufacturer = "Synthetic"
        camera.model = "QA fixture"
        camera.serial = "QA-0001"
        camera.inventoryID = "TEST-ONLY"
        camera.format = "35 mm"
        camera.shutterType = "Focal plane"
        camera.defaultDirection = .horizontal
        camera.photoFit = true
        model.saveCamera(camera)
        let original = try syntheticPhoto()
        let input = model.store.directory.appendingPathComponent("synthetic-input.png")
        try original.write(to: input, options: .atomic)
        model.importCameraPhoto(input, cameraID: camera.id)
        camera = try XCTUnwrap(model.cameras.first { $0.id == camera.id })
        let filename = try XCTUnwrap(camera.photoFilename)
        let preview = try Data(contentsOf: model.store.directory.appendingPathComponent("photos").appendingPathComponent(filename))
        return (camera, original, preview)
    }

    @MainActor
    func testPhotoImportPreservesOriginalAndCreatesBoundedPortableDisplayImage() throws {
        try withModel { model in
            let (camera, original, preview) = try installPhoto(model)
            let name = try XCTUnwrap(camera.photoFilename)
            XCTAssertEqual(name, URL(fileURLWithPath: name).lastPathComponent)
            XCTAssertFalse(name.contains("/"))
            XCTAssertFalse(name.contains("\\"))
            XCTAssertTrue(name.hasSuffix(".jpg"))
            let directory = model.store.directory.appendingPathComponent("photos")
            XCTAssertEqual(try Data(contentsOf: directory.appendingPathComponent(name + ".original")), original)
            let image = try XCTUnwrap(NSBitmapImageRep(data: preview))
            XCTAssertGreaterThan(image.pixelsWide, 0)
            XCTAssertGreaterThan(image.pixelsHigh, 0)
            XCTAssertLessThanOrEqual(image.pixelsWide, 2400)
            XCTAssertLessThanOrEqual(image.pixelsHigh, 2400)
            XCTAssertEqual(Double(image.pixelsWide) / Double(image.pixelsHigh), 1.5, accuracy: 0.001)
            XCTAssertNotEqual(preview, original, "The portable JPEG is separate from the byte-preserved PNG original.")
            XCTAssertNotNil(model.cameraImage(camera))
            XCTAssertEqual(try model.store.loadLibrary().cameras.first?.photoFilename, name)
            XCTAssertEqual(model.saveStatus, "Saved locally")
            XCTAssertNil(model.errorMessage)
        }
    }

    @MainActor
    func testPortableArchiveRoundTripsPhotoAndRejectsMissingOrMalformedDisplayData() throws {
        try withModel { model in
            let (camera, original, preview) = try installPhoto(model)
            let archive = PortableCameraArchive(sourceLibraryID: model.libraryID, camera: camera, sessions: [], photo: preview, originalPhoto: original)
            let decoded = try PortableCameraArchive.decode(SessionStore.encoder().encode(archive))
            XCTAssertEqual(decoded.photo, preview)
            XCTAssertEqual(decoded.originalPhoto, original)
            XCTAssertEqual(decoded.camera.photoFilename, camera.photoFilename)
            XCTAssertTrue(decoded.camera.photoFit)
            let bitmap = try XCTUnwrap(decoded.photo.flatMap(NSBitmapImageRep.init(data:)))
            XCTAssertEqual(Double(bitmap.pixelsWide) / Double(bitmap.pixelsHigh), 1.5, accuracy: 0.001)
            var malformed = archive
            malformed.photo = nil
            XCTAssertThrowsError(try PortableCameraArchive.decode(SessionStore.encoder().encode(malformed)))
            malformed.photo = Data("This is not an image".utf8)
            XCTAssertThrowsError(try PortableCameraArchive.decode(SessionStore.encoder().encode(malformed)))
            malformed.photo = preview
            malformed.camera.photoFilename = nil
            XCTAssertThrowsError(try PortableCameraArchive.decode(SessionStore.encoder().encode(malformed)))
        }
    }

    @MainActor
    func testReportDistinguishesLaterAssignedIdentityFromOriginalRecordedName() throws {
        try withModel { model in
            let camera = CameraProfile(name: "Catalogue camera selected later")
            model.saveCamera(camera)
            model.newSession(demo: false)
            model.cameraName = "Original name written at the bench"
            model.activeCaptureSessionID = model.selectedSessionID
            let packet = DemoPackets.sample(nominalDenominator: 125, index: 0)
            model.append(packet: packet, raw: String(decoding: try JSONEncoder().encode(packet), as: UTF8.self), simulated: false)
            let sessionID = try XCTUnwrap(model.selectedSessionID)
            model.assignSession(sessionID, to: camera.id)
            let session = try XCTUnwrap(model.sessions.first { $0.id == sessionID })
            let assignedAt = try XCTUnwrap(session.cameraAssignedAt)
            let data = try CameraReport.pdf(camera: camera, image: nil, session: session)
            let document = try XCTUnwrap(PDFDocument(data: data))
            let text = (0..<document.pageCount).compactMap { document.page(at: $0)?.string }.joined(separator: "\n")
            XCTAssertTrue(text.contains("Original recorded camera name: Original name written at the bench"))
            XCTAssertTrue(text.contains("Assigned camera identity: Catalogue camera selected later"))
            XCTAssertTrue(text.contains("Assigned after capture: \(assignedAt.formatted(date: .long, time: .shortened))"))
            XCTAssertFalse(text.contains("Camera at test time:"), "A later assignment cannot establish which camera identity was known during capture.")
        }
    }

    @MainActor
    func testPhotoReportContainsEvidenceLabelsAndPaginatesAllLongNotes() throws {
        try withModel { model in
            let (camera, _, _) = try installPhoto(model)
            model.newCameraTest(camera.id, title: "Synthetic shutter report")
            model.activeCaptureSessionID = model.selectedSessionID
            for index in 0..<4 {
                let packet = DemoPackets.sample(nominalDenominator: 125, index: index, partial: index == 2)
                model.append(packet: packet, raw: String(decoding: try JSONEncoder().encode(packet), as: UTF8.self), simulated: false)
            }
            model.toggleExcluded(try XCTUnwrap(model.currentRecords.last?.id))
            var session = try XCTUnwrap(model.currentSession)
            session.operatorName = "QA Operator"
            session.lightSource = "Synthetic LED"
            session.testConditions = "Controlled synthetic input, no physical camera tested"
            let sentinel = "QA-END-OF-LONG-NOTES-72941"
            session.notes = "SYNTHETIC QA DATA. These generated readings are not evidence of camera performance.\n\n"
                + (1...120).map { "QA note \($0): Preserve the entire note across page boundaries, with legible text, stable margins and no clipped continuation lines." }.joined(separator: "\n")
                + "\n\n" + sentinel
            let data = try CameraReport.pdf(camera: camera, image: model.cameraImage(camera), session: session)
            let document = try XCTUnwrap(PDFDocument(data: data))
            XCTAssertGreaterThanOrEqual(document.pageCount, 2)
            let pages = (0..<document.pageCount).compactMap { document.page(at: $0)?.string }
            XCTAssertEqual(pages.count, document.pageCount)
            let text = pages.joined(separator: "\n")
            for label in [camera.name, "Shutter timing report", "Make / model:", "Serial: QA-0001", "Collection ID: TEST-ONLY",
                          "Synthetic shutter report", "Camera at test time:", "QA Operator", "Synthetic LED",
                          "Chosen timing tolerance:", "Center exposure by setting", "Count", "2 included complete readings",
                          "1 excluded", "1 partial or invalid", "Planned settings:", "Test notes", "QA note 1:", "QA note 120:", sentinel] {
                XCTAssertTrue(text.contains(label), "PDF is missing: \(label)")
            }
            XCTAssertTrue(pages.last?.contains(sentinel) == true, "The final note must survive the final page break.")
            for (index, page) in pages.enumerated() {
                XCTAssertTrue(page.contains("Page \(index + 1)"), "Every page needs its numbered footer.")
            }
            // Explicit artifact generation for isolated UI/report QA. Normal runs
            // remain self-contained in their temporary directory.
            if let base = ProcessInfo.processInfo.environment["SHUTTER_LOVER_QA_REPORT_BASE"] {
                try data.write(to: URL(fileURLWithPath: base + ".pdf"), options: .atomic)
                let firstPage = try XCTUnwrap(document.page(at: 0))
                let thumbnail = firstPage.thumbnail(of: NSSize(width: 1190, height: 1684), for: .mediaBox)
                let tiff = try XCTUnwrap(thumbnail.tiffRepresentation)
                let bitmap = try XCTUnwrap(NSBitmapImageRep(data: tiff))
                let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
                try png.write(to: URL(fileURLWithPath: base + ".png"), options: .atomic)
            }
        }
    }
}
