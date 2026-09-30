import AppKit
import Foundation
import UniformTypeIdentifiers
import ImageIO

/// A full-fidelity local backup/copy format, distinct from the deliberately limited tester interchange.
struct PortableCameraArchive: Codable {
    var format = "com.shutterlover.camera-archive"
    var version = 2
    var sourceLibraryID: UUID
    var exportedAt = Date()
    var camera: CameraProfile
    var sessions: [CaptureSession]
    var photo: Data?
    var originalPhoto: Data?

    static func decode(_ data: Data) throws -> Self {
        guard data.count <= 64 * 1024 * 1024 else { throw SessionStoreError.tooLarge }
        let result = try SessionStore.decoder().decode(Self.self, from: data)
        guard result.format == "com.shutterlover.camera-archive", (1...2).contains(result.version) else {
            throw SessionStoreError.invalid("Unsupported camera archive format or version.")
        }
        try SessionStore.validateLibrary(CameraLibraryArchive(libraryID: result.sourceLibraryID, cameras: [result.camera], sessions: result.sessions))
        guard result.sessions.allSatisfy({ $0.cameraID == result.camera.id && !$0.demo }),
              (result.photo?.count ?? 0) <= 15 * 1024 * 1024,
              (result.originalPhoto?.count ?? 0) <= 25 * 1024 * 1024,
              (result.photo != nil) == (result.camera.photoFilename != nil) else {
            throw SessionStoreError.invalid("The archive has invalid camera membership or photograph data.")
        }
        if let photo = result.photo {
            guard let source = CGImageSourceCreateWithData(photo as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
                  let info = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
                  let width = info[kCGImagePropertyPixelWidth] as? Int,
                  let height = info[kCGImagePropertyPixelHeight] as? Int,
                  width > 0, height > 0, width <= 2400, height <= 2400,
                  CGImageSourceCreateImageAtIndex(source, 0, nil) != nil else {
                throw SessionStoreError.invalid("The archive display photograph is invalid.")
            }
        }
        return result
    }

    /// Import as a copy is explicit. It cannot impersonate the original catalogue/test producer.
    func localCopy() -> (CameraProfile, [CaptureSession]) {
        var copy = camera
        copy.id = UUID()
        copy.name += " (copy)"
        copy.catalogueID = nil
        copy.catalogueCameraID = nil
        copy.catalogueRevision = nil
        copy.catalogueSnapshots = []
        copy.createdAt = Date()
        copy.updatedAt = Date()
        let sessionIDs = Dictionary(uniqueKeysWithValues: sessions.map { ($0.id, UUID()) })
        for index in copy.serviceEvents.indices {
            copy.serviceEvents[index].id = UUID()
            copy.serviceEvents[index].beforeSessionID = copy.serviceEvents[index].beforeSessionID.flatMap { sessionIDs[$0] }
            copy.serviceEvents[index].afterSessionID = copy.serviceEvents[index].afterSessionID.flatMap { sessionIDs[$0] }
        }
        let copiedSessions = sessions.map { original -> CaptureSession in
            var session = original
            session.id = sessionIDs[original.id]!
            session.cameraID = copy.id
            // Copying an archive changes local identity, not what was known at
            // test time. Current camera metadata may have changed since capture.
            session.cameraSnapshot?.catalogueID = nil
            session.cameraSnapshot?.catalogueCameraID = nil
            session.cameraSnapshot?.catalogueRevision = nil
            session.revision = 1
            session.lastExportedRevision = nil
            for index in session.records.indices { session.records[index].id = UUID() }
            return session
        }
        return (copy, copiedSessions)
    }
}

@MainActor
extension AppModel {
    func cameraArchive(_ cameraID: UUID) throws -> PortableCameraArchive {
        guard let camera = cameras.first(where: { $0.id == cameraID }) else {
            throw SessionStoreError.invalid("the camera is missing from the library")
        }
        // A full archive includes Trash so no evidence or service comparison link is lost.
        let allTests = sessions.filter { $0.cameraID == cameraID }.sorted { $0.createdAt > $1.createdAt }
        var archive = PortableCameraArchive(sourceLibraryID: libraryID, camera: camera, sessions: allTests)
        if let filename = camera.photoFilename {
            let directory = store.directory.appendingPathComponent("photos")
            archive.photo = try Data(contentsOf: directory.appendingPathComponent(filename))
            let original = directory.appendingPathComponent(filename + ".original")
            if FileManager.default.fileExists(atPath: original.path) { archive.originalPhoto = try Data(contentsOf: original) }
        }
        return archive
    }

    func exportCameraArchive(_ cameraID: UUID) {
        guard let camera = cameras.first(where: { $0.id == cameraID }) else { return }
        do {
            let archive = try cameraArchive(cameraID)
            let data = try SessionStore.encoder().encode(archive)
            _ = try PortableCameraArchive.decode(data)
            save(data: data, filename: "\(safeFilename(camera.name)).shuttercamera", type: .shutterCameraArchive)
        } catch { errorMessage = "Camera archive could not be exported: \(error.localizedDescription)" }
    }

    func importCameraArchive() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.shutterCameraArchive, .json]
        panel.message = "Import a full Shutter Loved camera archive as a separate copy. Armarium camera catalogues use the other import command."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? Int.max
            guard size <= 64 * 1024 * 1024 else { throw SessionStoreError.tooLarge }
            let data = try Data(contentsOf: url)
            let archive = try PortableCameraArchive.decode(data)
            let alert = NSAlert()
            alert.messageText = "Import \(archive.camera.name) as a separate copy?"
            alert.informativeText = "This creates a new camera and \(archive.sessions.count) copied tests. Original packets and timestamps are retained. The copy will have new IDs and no Armarium catalogue link. The original archive is retained locally for provenance."
            alert.addButton(withTitle: "Import as a Copy")
            alert.addButton(withTitle: "Cancel")
            guard alert.runModal() == .alertFirstButtonReturn else { return }
            var (camera, imported) = archive.localCopy()
            if let photo = archive.photo {
                let directory = store.directory.appendingPathComponent("photos")
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                let filename = UUID().uuidString + ".jpg"
                try photo.write(to: directory.appendingPathComponent(filename), options: .atomic)
                if let original = archive.originalPhoto { try original.write(to: directory.appendingPathComponent(filename + ".original"), options: .atomic) }
                camera.photoFilename = filename
            }
            let originals = store.directory.appendingPathComponent("imported-archives")
            try FileManager.default.createDirectory(at: originals, withIntermediateDirectories: true)
            try data.write(to: originals.appendingPathComponent(camera.id.uuidString + ".shuttercamera"), options: .atomic)
            try commitLibrary(cameras: [camera] + cameras, sessions: imported + sessions)
            selectCamera(camera.id)
        } catch { errorMessage = "Camera archive was not imported: \(error.localizedDescription)" }
    }
}

extension UTType {
    static let shutterCameraArchive = UTType(exportedAs: "com.shutterlover.camera-archive", conformingTo: .json)
}
