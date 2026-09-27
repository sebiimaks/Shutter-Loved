import Foundation
import MeasurementCore

struct SettingCorrection: Codable, Equatable {
    var changedAt: Date
    var previousValue: Double
    var newValue: Double
}

struct MeasurementRecord: Identifiable, Codable {
    var id = UUID()
    var capturedAt = Date()
    var rawLine: String
    var packet: MeasurementPacket
    var direction: CurtainDirection
    var nominalDenominator: Double
    var isDemo: Bool
    var isExcluded = false
    var settingCorrections: [SettingCorrection] = []
    var calculationVersion = 1
    var devicePath: String? = nil
    var sensorWidthMM = 32.0
    var sensorHeightMM = 20.0
    var frameWidthMM = 36.0
    var frameHeightMM = 24.0
    var derivedSnapshot: MeasurementResult?

    var result: MeasurementResult {
        derivedSnapshot ?? MeasurementResult.calculate(packet: packet, direction: direction, nominalDenominator: nominalDenominator)
    }
}

struct CaptureSession: Identifiable, Codable {
    var id = UUID()
    var createdAt = Date()
    var updatedAt = Date()
    var cameraName: String
    var notes = ""
    var direction: CurtainDirection = .unknown
    var nominalDenominator = 125.0
    var autoAdvance = false
    var demo: Bool
    var records: [MeasurementRecord] = []
    // Optional additions deliberately keep original schema-1 files decodable.
    var cameraID: UUID?
    var cameraSnapshot: CameraIdentitySnapshot?
    var cameraAssignedAt: Date?
    var title: String?
    var operatorName: String?
    var lightSource: String?
    var testConditions: String?
    var toleranceStops: Double?
    var plannedSpeeds: [Double]?
    var repeatsPerSpeed: Int?
    var revision: Int?
    var lastExportedRevision: Int?
    /// Local visibility only: moving a test to Trash never changes its evidence revision.
    var trashedAt: Date?

    var displayTitle: String {
        if let title, !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return title }
        let date = createdAt.formatted(date: .abbreviated, time: .shortened)
        return cameraName.isEmpty ? date : "\(cameraName) · \(date)"
    }

    var effectiveRevision: Int { revision ?? 1 }
    var isTrashed: Bool { trashedAt != nil }

    mutating func markUpdated() {
        let (next, overflow) = effectiveRevision.addingReportingOverflow(1)
        revision = overflow ? Int.max : next
        updatedAt = Date()
    }
}

struct SessionArchive: Codable {
    var schemaVersion = 1
    var sessions: [CaptureSession]
}

enum SessionStoreError: LocalizedError {
    case unsupportedVersion(Int), invalid(String), tooLarge
    var errorDescription: String? {
        switch self {
        case .unsupportedVersion(let version): return "This session file uses format \(version), which this app cannot read."
        case .invalid(let reason): return "The session file is invalid: \(reason)"
        case .tooLarge: return "This file is too large to import (maximum 64 MB)."
        }
    }
}

/// Versioned local snapshots keep the alpha's storage inspectable and portable.
/// A failed load is reported; it is never treated as an empty library to overwrite.
struct SessionStore {
    let directory: URL
    var libraryURL: URL { directory.appendingPathComponent("sessions.json") }
    var cameraLibraryURL: URL { directory.appendingPathComponent("library.json") }
    var migrationBackupURL: URL { directory.appendingPathComponent("sessions.pre-camera-library.json") }

    static func standard() -> SessionStore {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return SessionStore(directory: base.appendingPathComponent("ShutterLover", isDirectory: true))
    }

    static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(formatter.string(from: date))
        }
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }

    static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        let precise = ISO8601DateFormatter()
        precise.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let seconds = ISO8601DateFormatter()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let value = try container.decode(String.self)
            guard let date = precise.date(from: value) ?? seconds.date(from: value) else {
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "Expected an ISO 8601 timestamp")
            }
            return date
        }
        return decoder
    }

    static func decode(_ data: Data) throws -> [CaptureSession] {
        guard data.count <= 64 * 1024 * 1024 else { throw SessionStoreError.tooLarge }
        let archive = try decoder().decode(SessionArchive.self, from: data)
        guard archive.schemaVersion == 1 else { throw SessionStoreError.unsupportedVersion(archive.schemaVersion) }
        try validate(archive.sessions)
        return archive.sessions
    }

    static func validate(_ sessions: [CaptureSession]) throws {
        guard sessions.count <= 50_000 else { throw SessionStoreError.invalid("too many test sessions") }
        guard Set(sessions.map(\.id)).count == sessions.count else { throw SessionStoreError.invalid("duplicate session identifiers") }
        var ids = Set<UUID>()
        for session in sessions {
            guard validDate(session.createdAt), validDate(session.updatedAt) else { throw SessionStoreError.invalid("invalid session date") }
            if let trashedAt = session.trashedAt, !validDate(trashedAt) { throw SessionStoreError.invalid("invalid trash date") }
            try validateText([session.cameraName, session.notes, session.title ?? "", session.operatorName ?? "", session.lightSource ?? "", session.testConditions ?? ""])
            guard validSetting(session.nominalDenominator) else { throw SessionStoreError.invalid("invalid camera setting") }
            if let tolerance = session.toleranceStops, !tolerance.isFinite || tolerance < 0 || tolerance > 10 {
                throw SessionStoreError.invalid("exposure tolerance must be between 0 and 10 stops")
            }
            if let speeds = session.plannedSpeeds { try validateSpeeds(speeds) }
            if let repeats = session.repeatsPerSpeed, !(1...1000).contains(repeats) { throw SessionStoreError.invalid("invalid repeat count") }
            guard session.effectiveRevision > 0 else { throw SessionStoreError.invalid("invalid session revision") }
            if let exported = session.lastExportedRevision, exported < 1 || exported > session.effectiveRevision {
                throw SessionStoreError.invalid("invalid last exported revision")
            }
            if let snapshot = session.cameraSnapshot {
                try validateText([snapshot.name, snapshot.manufacturer, snapshot.model, snapshot.serial, snapshot.inventoryID])
                try validateCatalogueIdentity(snapshot.catalogueID, snapshot.catalogueCameraID, snapshot.catalogueRevision)
            }
            for record in session.records {
                guard ids.count < 100_000 else { throw SessionStoreError.invalid("too many readings") }
                guard ids.insert(record.id).inserted else { throw SessionStoreError.invalid("duplicate reading identifiers") }
                guard validDate(record.capturedAt), record.rawLine.utf8.count <= 1_048_576 else { throw SessionStoreError.invalid("invalid reading timestamp or packet size") }
                guard validSetting(record.nominalDenominator), record.isDemo == session.demo else {
                    throw SessionStoreError.invalid("invalid setting or mixed simulated and device data")
                }
                guard record.calculationVersion == 1 else { throw SessionStoreError.invalid("unsupported calculation version") }
                var previousCorrection: SettingCorrection?
                for correction in record.settingCorrections {
                    guard validDate(correction.changedAt), validSetting(correction.previousValue), validSetting(correction.newValue),
                          previousCorrection == nil || previousCorrection?.newValue == correction.previousValue else {
                        throw SessionStoreError.invalid("inconsistent setting correction history")
                    }
                    previousCorrection = correction
                }
                if let last = previousCorrection, last.newValue != record.nominalDenominator {
                    throw SessionStoreError.invalid("setting does not match the last correction")
                }
                guard record.sensorWidthMM == 32, record.sensorHeightMM == 20, record.frameWidthMM == 36, record.frameHeightMM == 24 else {
                    throw SessionStoreError.invalid("this version only calculates the documented 32 × 20 mm sensor and 36 × 24 mm frame geometry")
                }
                let packetData = try encoder().encode(record.packet)
                guard case .measurement = PacketParser.parse(packetData) else {
                    throw SessionStoreError.invalid("unsupported measurement packet")
                }
                guard case .measurement(let original) = PacketParser.parse(Data(record.rawLine.utf8)), original == record.packet else {
                    throw SessionStoreError.invalid("original packet and decoded measurement disagree")
                }
                if let snapshot = record.derivedSnapshot,
                   snapshot != MeasurementResult.calculate(packet: record.packet, direction: record.direction, nominalDenominator: record.nominalDenominator) {
                    throw SessionStoreError.invalid("stored calculation does not match its original packet and settings")
                }
            }
        }
    }

    static func validSetting(_ value: Double) -> Bool { value.isFinite && value >= 0.001 && value <= 1_000_000 }

    private static func validDate(_ value: Date) -> Bool { value.timeIntervalSince1970.isFinite }

    private static func validateText(_ values: [String]) throws {
        guard values.allSatisfy({ $0.utf8.count <= 1_048_576 }) else { throw SessionStoreError.invalid("a text field exceeds 1 MB") }
    }

    private static func validateSpeeds(_ speeds: [Double]) throws {
        guard speeds.count <= 128, speeds.allSatisfy(validSetting), Set(speeds).count == speeds.count else {
            throw SessionStoreError.invalid("planned speeds must be distinct valid camera settings (maximum 128)")
        }
    }

    private static func validateCatalogueIdentity(_ catalogueID: UUID?, _ cameraID: UUID?, _ revision: Int?) throws {
        if catalogueID == nil && cameraID == nil && revision == nil { return }
        guard catalogueID != nil, cameraID != nil, let revision, revision > 0 else {
            throw SessionStoreError.invalid("incomplete catalogue camera identity")
        }
    }

    static func decodeLibrary(_ data: Data) throws -> CameraLibraryArchive {
        guard data.count <= 64 * 1024 * 1024 else { throw SessionStoreError.tooLarge }
        let archive = try decoder().decode(CameraLibraryArchive.self, from: data)
        guard archive.schemaVersion == 2 else { throw SessionStoreError.unsupportedVersion(archive.schemaVersion) }
        try validateLibrary(archive)
        return archive
    }

    static func validateLibrary(_ archive: CameraLibraryArchive) throws {
        guard archive.schemaVersion == 2 else { throw SessionStoreError.unsupportedVersion(archive.schemaVersion) }
        guard archive.cameras.count <= 10_000 else { throw SessionStoreError.invalid("too many cameras") }
        try validate(archive.sessions)
        let cameraIDs = Set(archive.cameras.map(\.id))
        guard cameraIDs.count == archive.cameras.count else { throw SessionStoreError.invalid("duplicate camera identifiers") }
        let sessionsByID = Dictionary(uniqueKeysWithValues: archive.sessions.map { ($0.id, $0) })
        var catalogueIdentities = Set<String>()
        var serviceIDs = Set<UUID>()
        for camera in archive.cameras {
            guard validDate(camera.createdAt), validDate(camera.updatedAt) else { throw SessionStoreError.invalid("invalid camera date") }
            try validateText([camera.name, camera.manufacturer, camera.model, camera.serial, camera.inventoryID,
                              camera.nickname, camera.tags, camera.format, camera.frameSize, camera.shutterType,
                              camera.mount, camera.lens, camera.lensSerial, camera.productionYear, camera.condition,
                              camera.acquisitionDate, camera.acquisitionSource, camera.purchasePrice, camera.currency,
                              camera.storageLocation, camera.notes])
            try validateSpeeds(camera.plannedSpeeds)
            if let filename = camera.photoFilename {
                guard !filename.isEmpty, filename != ".", filename != "..", filename.utf8.count <= 255,
                      !filename.contains("/"), !filename.contains("\\"), !filename.contains(":"),
                      !filename.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else {
                    throw SessionStoreError.invalid("camera photo must use a single safe filename")
                }
            }
            try validateCatalogueIdentity(camera.catalogueID, camera.catalogueCameraID, camera.catalogueRevision)
            if let catalogueID = camera.catalogueID, let cameraID = camera.catalogueCameraID {
                guard catalogueIdentities.insert("\(catalogueID.uuidString)/\(cameraID.uuidString)").inserted else {
                    throw SessionStoreError.invalid("duplicate catalogue camera identity")
                }
            }
            guard camera.catalogueSnapshots.count <= 1000 else { throw SessionStoreError.invalid("too many catalogue snapshots") }
            var revisions = Set<Int>()
            for snapshot in camera.catalogueSnapshots {
                guard camera.catalogueID != nil, snapshot.revision > 0,
                      snapshot.revision <= (camera.catalogueRevision ?? 0), revisions.insert(snapshot.revision).inserted,
                      validDate(snapshot.importedAt), snapshot.profileJSON.count <= 1_048_576,
                      (try? JSONSerialization.jsonObject(with: snapshot.profileJSON)) is [String: Any] else {
                    throw SessionStoreError.invalid("invalid catalogue revision snapshot")
                }
                try validateText([snapshot.sourceApplication])
            }
            guard camera.serviceEvents.count <= 1000 else { throw SessionStoreError.invalid("too many service entries") }
            for service in camera.serviceEvents {
                guard serviceIDs.insert(service.id).inserted, validDate(service.date) else { throw SessionStoreError.invalid("invalid or duplicate service entry") }
                try validateText([service.title, service.provider, service.notes])
                for sessionID in [service.beforeSessionID, service.afterSessionID].compactMap({ $0 }) {
                    guard let session = sessionsByID[sessionID], session.cameraID == camera.id else {
                        throw SessionStoreError.invalid("service comparison refers to a missing test or another camera")
                    }
                }
            }
        }
        for session in archive.sessions {
            if let cameraID = session.cameraID, !cameraIDs.contains(cameraID) {
                throw SessionStoreError.invalid("a test refers to a camera that is missing from the library")
            }
            // Test identity is intentionally not compared with the current camera's
            // metadata: a later catalogue import must not rewrite a historical test.
        }
    }

    /// The first successful load of a schema-1 installation preserves its source
    /// and a byte-for-byte migration backup before committing the new library.
    /// Sessions remain unassigned until the user chooses a physical camera.
    func loadLibrary() throws -> CameraLibraryArchive {
        if FileManager.default.fileExists(atPath: cameraLibraryURL.path) {
            return try Self.decodeLibrary(Self.readLimited(cameraLibraryURL))
        }
        let sessions = try load()
        let archive = CameraLibraryArchive(sessions: sessions)
        try saveLibrary(archive)
        return archive
    }

    func saveLibrary(_ archive: CameraLibraryArchive) throws {
        try Self.validateLibrary(archive)
        let data = try Self.encoder().encode(archive)
        guard data.count <= 64 * 1024 * 1024 else { throw SessionStoreError.tooLarge }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if FileManager.default.fileExists(atPath: cameraLibraryURL.path) {
            let previous = try Self.readLimited(cameraLibraryURL)
            try previous.write(to: directory.appendingPathComponent("library.previous.json"), options: .atomic)
        } else if FileManager.default.fileExists(atPath: libraryURL.path),
                  !FileManager.default.fileExists(atPath: migrationBackupURL.path) {
            let original = try Self.readLimited(libraryURL)
            // A failed or interrupted migration can retry safely without changing
            // an existing backup, even if the legacy file is edited afterwards.
            try original.write(to: migrationBackupURL, options: .atomic)
        }
        try data.write(to: cameraLibraryURL, options: .atomic)
    }

    private static func readLimited(_ url: URL) throws -> Data {
        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size <= 64 * 1024 * 1024 else { throw SessionStoreError.tooLarge }
        let data = try Data(contentsOf: url)
        guard data.count <= 64 * 1024 * 1024 else { throw SessionStoreError.tooLarge }
        return data
    }

    func load() throws -> [CaptureSession] {
        guard FileManager.default.fileExists(atPath: libraryURL.path) else { return [] }
        return try Self.decode(Self.readLimited(libraryURL))
    }

    func save(_ sessions: [CaptureSession]) throws {
        try Self.validate(sessions)
        let data = try Self.encoder().encode(SessionArchive(sessions: sessions))
        guard data.count <= 64 * 1024 * 1024 else { throw SessionStoreError.tooLarge }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if FileManager.default.fileExists(atPath: libraryURL.path) {
            let previous = try Data(contentsOf: libraryURL)
            try previous.write(to: directory.appendingPathComponent("sessions.previous.json"), options: .atomic)
        }
        try data.write(to: libraryURL, options: .atomic)
    }
}

enum SessionExport {
    static let headers = ["Reading", "Reading ID", "Received", "Setting (1/s)", "Speed (1/s)", "Time (ms)", "Open (ms)", "Close (ms)", "Open ext", "Close ext", "Speed Bot. L.", "Time Bot. L.", "Speed Top R.", "Time Top R.", "Open 1/2", "Open 2/2", "Close 1/2", "Close 2/2", "Direction", "Quality", "Excluded", "Simulated", "Firmware", "Exposure error (stops)", "Device path", "Sensor width (mm)", "Sensor height (mm)", "Frame width (mm)", "Frame height (mm)"]

    static func table(_ records: [MeasurementRecord], separator: String = ",", readingNumbers: [UUID: Int] = [:]) -> String {
        let date = ISO8601DateFormatter()
        date.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        func number(_ value: Double?) -> String { value.map { String($0) } ?? "" }
        func escape(_ string: String) -> String {
            if separator == "\t" { return string.replacingOccurrences(of: "\t", with: " ").replacingOccurrences(of: "\n", with: " ") }
            return "\"" + string.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        var rows = [headers]
        for (index, record) in records.enumerated() {
            let r = record.result
            rows.append([String(readingNumbers[record.id] ?? index + 1), record.id.uuidString, date.string(from: record.capturedAt), String(record.nominalDenominator),
                         number(r.center.reciprocalSeconds), number(r.center.durationMS), number(r.openingTravelMS), number(r.closingTravelMS),
                         number(r.openingFullFrameMS), number(r.closingFullFrameMS), number(r.bottomLeft.reciprocalSeconds), number(r.bottomLeft.durationMS),
                         number(r.topRight.reciprocalSeconds), number(r.topRight.durationMS), number(r.openingFirstSegmentMS), number(r.openingSecondSegmentMS),
                         number(r.closingFirstSegmentMS), number(r.closingSecondSegmentMS), record.direction.rawValue, r.quality.rawValue,
                         String(record.isExcluded), String(record.isDemo), record.packet.firmware_version, number(r.exposureErrorStops),
                         record.devicePath ?? "", String(record.sensorWidthMM), String(record.sensorHeightMM), String(record.frameWidthMM), String(record.frameHeightMM)])
        }
        return rows.map { $0.map(escape).joined(separator: separator) }.joined(separator: "\n") + "\n"
    }
}
