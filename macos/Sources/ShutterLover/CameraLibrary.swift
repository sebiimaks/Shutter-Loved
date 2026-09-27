import Foundation
import MeasurementCore

/// A local record represents one physical camera. Catalogue IDs are a separate
/// namespace, so matching names or serial numbers never merge camera records.
struct CameraProfile: Identifiable, Codable, Equatable {
    var id = UUID()
    var createdAt = Date()
    var updatedAt = Date()
    var name: String
    var manufacturer = ""
    var model = ""
    var serial = ""
    var inventoryID = ""
    var nickname = ""
    var tags = ""
    var format = ""
    var frameSize = ""
    var shutterType = ""
    var mount = ""
    var lens = ""
    var lensSerial = ""
    var productionYear = ""
    var condition = ""
    var acquisitionDate = ""
    var acquisitionSource = ""
    var purchasePrice = ""
    var currency = ""
    var storageLocation = ""
    var notes = ""
    var defaultDirection: CurtainDirection = .unknown
    var plannedSpeeds: [Double] = [30, 60, 125, 250, 500, 1000]
    var photoFilename: String?
    var photoFit = false
    var archived = false
    var serviceEvents: [CameraServiceEvent] = []
    var catalogueID: UUID?
    var catalogueCameraID: UUID?
    var catalogueRevision: Int?
    var catalogueSnapshots: [CatalogueSnapshot] = []
}

struct CatalogueSnapshot: Codable, Equatable {
    var revision: Int
    var profileJSON: Data
    var importedAt: Date
    var sourceApplication: String
}

struct CameraServiceEvent: Identifiable, Codable, Equatable {
    var id = UUID()
    var date = Date()
    var title: String
    var provider = ""
    var notes = ""
    var beforeSessionID: UUID?
    var afterSessionID: UUID?
}

/// Identity at the time of testing stays intact when a camera's current details
/// are edited or a newer catalogue revision is imported.
struct CameraIdentitySnapshot: Codable, Equatable {
    var name: String
    var manufacturer: String
    var model: String
    var serial: String
    var inventoryID: String
    var catalogueID: UUID?
    var catalogueCameraID: UUID?
    var catalogueRevision: Int?

    init(camera: CameraProfile) {
        name = camera.name
        manufacturer = camera.manufacturer
        model = camera.model
        serial = camera.serial
        inventoryID = camera.inventoryID
        catalogueID = camera.catalogueID
        catalogueCameraID = camera.catalogueCameraID
        catalogueRevision = camera.catalogueRevision
    }
}

struct CameraLibraryArchive: Codable {
    var schemaVersion = 2
    var libraryID = UUID()
    var cameras: [CameraProfile] = []
    var sessions: [CaptureSession] = []
}
