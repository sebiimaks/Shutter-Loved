import AppKit
import Foundation
import ImageIO
import MeasurementCore
import UniformTypeIdentifiers

@MainActor
extension AppModel {
    func cameraSessions(_ cameraID: UUID) -> [CaptureSession] {
        sessions.filter { $0.cameraID == cameraID && !$0.isTrashed }.sorted { $0.createdAt > $1.createdAt }
    }

    func selectCamera(_ id: UUID) {
        selectedCameraID = id
        showCameraLibrary = true
        showGuide = false
    }

    func newCamera() { editingCamera = CameraProfile(name: "") }

    func saveCamera(_ camera: CameraProfile) {
        var updated = camera
        updated.name = updated.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !updated.name.isEmpty else { errorMessage = "Give this camera a name."; return }
        updated.updatedAt = Date()
        var candidate = cameras
        if let index = candidate.firstIndex(where: { $0.id == updated.id }) { candidate[index] = updated }
        else { candidate.insert(updated, at: 0) }
        do {
            try commitLibrary(cameras: candidate, sessions: sessions)
            selectCamera(updated.id)
        } catch { errorMessage = "Camera could not be saved: \(error.localizedDescription)" }
    }

    func newCameraTest(_ cameraID: UUID, title: String = "Shutter test") {
        guard let camera = cameras.first(where: { $0.id == cameraID }) else { return }
        var session = CaptureSession(cameraName: camera.name, demo: false)
        session.tester = connectionTesterSnapshot
        session.cameraID = camera.id
        session.cameraSnapshot = CameraIdentitySnapshot(camera: camera)
        session.direction = camera.defaultDirection
        session.title = title
        session.toleranceStops = 1.0 / 3.0
        session.plannedSpeeds = camera.plannedSpeeds
        session.repeatsPerSpeed = 3
        session.revision = 1
        do {
            try commitLibrary(cameras: cameras, sessions: [session] + sessions)
            selectSession(session.id)
            selectedCameraID = cameraID
            if isConnected || isConnecting || activeCaptureSessionID != nil { activeCaptureSessionID = session.id }
        } catch { errorMessage = "Test could not be created: \(error.localizedDescription)" }
    }

    func openCameraTest(_ id: UUID) { selectSession(id) }

    func returnToCapture() {
        if let id = activeCaptureSessionID { selectSession(id) }
    }

    func recordIntoSelectedTest() {
        guard let session = currentSession, !session.demo else { return }
        guard canRecordUSB(in: session) else { errorMessage = "Baby tester tests use manual entry. Start a Shutter Lover test for USB capture."; return }
        guard isConnected || isConnecting || activeCaptureSessionID != nil else { return }
        if activeCaptureSessionID == session.id { return }
        if let tester = connectionTesterSnapshot, !setSessionTester(session.id, tester: tester) { return }
        activeCaptureSessionID = session.id
    }

    func assignSession(_ sessionID: UUID, to cameraID: UUID) {
        guard let camera = cameras.first(where: { $0.id == cameraID }),
              let index = sessions.firstIndex(where: { $0.id == sessionID && !$0.isTrashed }) else { return }
        guard !sessions[index].demo else { errorMessage = "Demo readings stay separate from physical camera records."; return }
        guard sessions[index].cameraID == nil else { errorMessage = "This test already belongs to a camera. Create a new test for another body."; return }
        guard sessions[index].lastExportedRevision == nil else { errorMessage = "An exported test cannot be reassigned to another camera identity."; return }
        var candidate = sessions
        candidate[index].cameraID = camera.id
        candidate[index].cameraSnapshot = CameraIdentitySnapshot(camera: camera)
        candidate[index].cameraAssignedAt = Date()
        // Preserve the name and setup recorded when these measurements arrived.
        candidate[index].markUpdated()
        do {
            try commitLibrary(cameras: cameras, sessions: candidate)
            selectCamera(camera.id)
        } catch { errorMessage = "Test could not be assigned: \(error.localizedDescription)" }
    }

    func updateTestDetails(_ edited: CaptureSession) {
        guard let index = sessions.firstIndex(where: { $0.id == edited.id && !$0.isTrashed }) else { return }
        var candidate = sessions
        // Copy only editable metadata; a sheet opened before a reading arrived must not overwrite it.
        candidate[index].title = edited.title
        candidate[index].operatorName = edited.operatorName
        candidate[index].lightSource = edited.lightSource
        candidate[index].testConditions = edited.testConditions
        candidate[index].toleranceStops = edited.toleranceStops
        candidate[index].plannedSpeeds = edited.plannedSpeeds
        candidate[index].repeatsPerSpeed = edited.repeatsPerSpeed
        candidate[index].notes = edited.notes
        candidate[index].markUpdated()
        do {
            try commitLibrary(cameras: cameras, sessions: candidate)
            if selectedSessionID == edited.id { syncSelectedSetup() }
        }
        catch { errorMessage = "Test details could not be saved: \(error.localizedDescription)" }
    }

    func chooseCameraPhoto(_ cameraID: UUID) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.message = "Choose the camera’s photograph. It will be copied into your local library and shown in a 3:2 frame."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        importCameraPhoto(url, cameraID: cameraID)
    }

    func importCameraPhoto(_ url: URL, cameraID: UUID) {
        guard let index = cameras.firstIndex(where: { $0.id == cameraID }) else { return }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do {
            guard url.isFileURL else { throw SessionStoreError.invalid("Choose a local image file.") }
            let properties = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
            guard properties.isRegularFile == true, (properties.fileSize ?? Int.max) <= 25 * 1024 * 1024 else {
                throw SessionStoreError.invalid("Choose an image file smaller than 25 MB.")
            }
            let original = try Data(contentsOf: url)
            guard let source = CGImageSourceCreateWithData(original as CFData, nil),
                  CGImageSourceGetCount(source) > 0,
                  let info = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
                  let width = info[kCGImagePropertyPixelWidth] as? Int, let height = info[kCGImagePropertyPixelHeight] as? Int,
                  width > 0, height > 0, width <= 40_000, height <= 40_000,
                  width * height <= 160_000_000 else { throw SessionStoreError.invalid("This image is unreadable or too large to decode safely.") }
            let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: 2400, kCGImageSourceCreateThumbnailWithTransform: true]
            guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary),
                  let preview = NSBitmapImageRep(cgImage: image).representation(using: .jpeg, properties: [.compressionFactor: 0.9]) else {
                throw SessionStoreError.invalid("This image could not be converted for display.")
            }
            let directory = store.directory.appendingPathComponent("photos", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let name = UUID().uuidString + ".jpg"
            // Preserve the user's original as well as the bounded display image.
            try original.write(to: directory.appendingPathComponent(name + ".original"), options: .atomic)
            try preview.write(to: directory.appendingPathComponent(name), options: .atomic)
            var candidate = cameras
            candidate[index].photoFilename = name
            candidate[index].updatedAt = Date()
            try commitLibrary(cameras: candidate, sessions: sessions)
        } catch { errorMessage = "Photo could not be imported: \(error.localizedDescription)" }
    }

    func cameraImage(_ camera: CameraProfile) -> NSImage? {
        guard let name = camera.photoFilename, URL(fileURLWithPath: name).lastPathComponent == name else { return nil }
        let url = store.directory.appendingPathComponent("photos").appendingPathComponent(name)
        return NSImage(contentsOf: url)
    }

    func importCameraCatalogue() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.message = "Select the camera catalogue exported by Armarium Lucis → Shutter Tester. Changes will be reviewed first."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? Int.max
            guard size <= 8 * 1024 * 1024 else { throw SessionStoreError.invalid("Shutter Tester JSON files must be no larger than 8 MB.") }
            catalogueReview = try ShutterTesterExchange.reviewCatalogue(Data(contentsOf: url), cameras: cameras)
            showCatalogueReview = true
        } catch { errorMessage = "Camera import failed: \(error.localizedDescription)" }
    }

    func applyCameraCatalogue() {
        guard let review = catalogueReview else { return }
        do {
            let candidate = try ShutterTesterExchange.applyCatalogue(review, cameras: cameras)
            try commitLibrary(cameras: candidate, sessions: sessions)
            showCatalogueReview = false
            catalogueReview = nil
            if let camera = candidate.first(where: { $0.catalogueID == review.catalogueID }) { selectCamera(camera.id) }
        } catch { errorMessage = "Camera import was not applied: \(error.localizedDescription)" }
    }

    func exportTesterResults(_ sessionID: UUID) {
        guard let session = sessions.first(where: { $0.id == sessionID && !$0.isTrashed }) else { return }
        do {
            let data = try ShutterTesterExchange.exportResults(producerLibraryID: libraryID, session: session)
            if save(data: data, filename: "\(safeFilename(session.cameraName))-test-results.json", type: .json),
               let index = sessions.firstIndex(where: { $0.id == sessionID }) {
                // Export state is bookkeeping, not a change to the evidence revision.
                sessions[index].lastExportedRevision = session.effectiveRevision
                saveNow()
            }
        } catch { errorMessage = "Results could not be exported for Armarium Lucis: \(error.localizedDescription)" }
    }
}
