import Foundation
import MeasurementCore

/// Independent implementation of the public Shutter Tester JSON v1 document contract.
/// This layer is pure: review and apply return values; the caller persists one transaction.
enum ShutterTesterExchange {
    static let format = "org.armarium-lucis.shutter-tester"
    static let maximumFileBytes = 8 * 1024 * 1024

    static func reviewCatalogue(_ data: Data, cameras: [CameraProfile]) throws -> CatalogueImportReview {
        let catalogue = try parseCatalogue(data)
        // Duplicate external identities are corruption, never a reason to choose one arbitrarily.
        let matching = cameras.filter { $0.catalogueID == catalogue.id }
        let mapped = matching.compactMap(\.catalogueCameraID)
        guard Set(mapped).count == mapped.count else { throw ExchangeError.invalid("The camera database contains duplicate catalogue identities.") }
        let rows = catalogue.profiles.map { profile -> CatalogueImportRow in
            let existing = matching.first { $0.catalogueCameraID == profile.id }
            var disposition: CatalogueImportDisposition = .newCamera
            var detail = "Create a separate camera record with this catalogue identity."
            if let existing {
                if let previous = existing.catalogueSnapshots.first(where: { $0.revision == profile.revision }) {
                    if previous.profileJSON == profile.canonical {
                        disposition = .alreadyImported
                        detail = "This exact profile revision is already saved."
                    } else {
                        disposition = .conflict
                        detail = "The same catalogue camera and revision contain different profile data. Export a corrected, newer revision."
                    }
                } else if profile.revision < (existing.catalogueRevision ?? 0) {
                    disposition = .olderRevision
                    detail = "A newer profile is already saved. This older revision will be skipped."
                } else if profile.revision == existing.catalogueRevision {
                    disposition = .conflict
                    detail = "The current revision has no matching saved source snapshot. This batch cannot be applied safely."
                } else {
                    disposition = .newRevision
                    detail = "Update catalogue identity and specifications; keep local photos, notes, service history and test evidence."
                }
            }
            return CatalogueImportRow(externalCameraID: profile.id, localCameraID: existing?.id,
                                      cameraName: profile.name, revision: profile.revision,
                                      disposition: disposition, detail: detail)
        }
        let relevantIDs = Set(catalogue.profiles.map(\.id))
        let fingerprint = try SessionStore.encoder().encode(matching.filter { camera in camera.catalogueCameraID.map { relevantIDs.contains($0) } ?? false }.sorted { $0.id.uuidString < $1.id.uuidString })
        return CatalogueImportReview(originalData: data, catalogueID: catalogue.id, sourceApplication: catalogue.application,
                                     rows: rows, stateFingerprint: fingerprint)
    }

    static func applyCatalogue(_ review: CatalogueImportReview, cameras: [CameraProfile], importedAt: Date = Date()) throws -> [CameraProfile] {
        let refreshed = try reviewCatalogue(review.originalData, cameras: cameras)
        guard refreshed.rows == review.rows, refreshed.stateFingerprint == review.stateFingerprint else {
            throw ExchangeError.invalid("The camera database changed after this review. Review the catalogue again before applying it.")
        }
        guard refreshed.canApply else { throw ExchangeError.invalid("Resolve every catalogue conflict before importing this batch.") }
        let catalogue = try parseCatalogue(review.originalData)
        var candidate = cameras
        for (profile, row) in zip(catalogue.profiles, refreshed.rows) {
            guard row.disposition == .newCamera || row.disposition == .newRevision else { continue }
            var camera = row.localCameraID.flatMap { id in candidate.first { $0.id == id } } ?? CameraProfile(name: profile.name)
            camera.name = profile.name
            camera.manufacturer = try profile.node.text("manufacturer")
            camera.model = try profile.node.text("model")
            camera.inventoryID = try profile.node.text("inventoryID")
            camera.mount = try profile.node.text("mount")
            camera.serial = try profile.node.optionalText("serial") ?? ""
            let specifications = try profile.node.object("camera")
            let shutter = try profile.node.object("shutter")
            camera.format = try specifications.text("format")
            camera.shutterType = try shutter.text("architecture")
            // Descriptions are not a device configuration language. Only exact supported values map.
            camera.defaultDirection = CurtainDirection(rawValue: try shutter.text("travelDirection").lowercased()) ?? .unknown
            camera.catalogueID = catalogue.id
            camera.catalogueCameraID = profile.id
            camera.catalogueRevision = profile.revision
            camera.updatedAt = importedAt
            camera.catalogueSnapshots.append(CatalogueSnapshot(revision: profile.revision, profileJSON: profile.canonical,
                                                               importedAt: importedAt, sourceApplication: catalogue.application))
            if let index = candidate.firstIndex(where: { $0.id == camera.id }) { candidate[index] = camera }
            else { camera.createdAt = importedAt; candidate.append(camera) }
        }
        return candidate
    }

    /// Export one stable test revision. No raw packets, images, acquisitions or service notes leave here.
    static func exportResults(producerLibraryID: UUID, session: CaptureSession, createdAt: Date = Date()) throws -> Data {
        guard !session.isTrashed else { throw ExchangeError.invalid("Restore this test from Trash before exporting its results.") }
        guard !session.demo, !session.records.contains(where: \.isDemo) else {
            throw ExchangeError.invalid("Simulated measurements cannot be exported as camera evidence. Use the full Shutter Loved archive to keep demonstrations.")
        }
        guard let identity = session.cameraSnapshot, let catalogueID = identity.catalogueID,
              let externalID = identity.catalogueCameraID else {
            throw ExchangeError.invalid("This test has no Armarium catalogue identity. Import its camera from Armarium, then start a new test or explicitly assign this unlinked test to that camera.")
        }
        try SessionStore.validate([session])
        var measurements: [[String: Any]] = []
        var sampleNotes: [String] = []
        var exported = 0
        var omittedTravel = 0
        for (index, record) in session.records.enumerated() {
            let result = record.result
            guard !record.isExcluded, result.quality == .complete else { continue }
            guard index < 10_000 else { throw ExchangeError.invalid("A reading's original sample index exceeds the format's 10,000 limit. Export a smaller test run.") }
            let sample = index + 1
            let nominal = 1 / record.nominalDenominator
            func add(_ milliseconds: Double?, quantity: String, position: String, nominalValue: Double? = nil) throws {
                guard let milliseconds, milliseconds.isFinite, milliseconds > 0 else {
                    if quantity == "curtainTravelDuration" { omittedTravel += 1; return }
                    throw ExchangeError.invalid("A complete reading has no positive finite exposure duration.")
                }
                let seconds = milliseconds / 1_000
                guard seconds > 0, seconds <= 1e12 else { throw ExchangeError.invalid("A measured duration exceeds the exchange format's supported range.") }
                var measurement: [String: Any] = ["quantity": quantity, "value": seconds, "unit": "s", "position": position, "sampleIndex": sample]
                if let nominalValue { measurement["nominalValue"] = nominalValue }
                measurements.append(measurement)
            }
            try add(result.center.durationMS, quantity: "exposureDuration", position: "centre", nominalValue: nominal)
            try add(result.bottomLeft.durationMS, quantity: "exposureDuration", position: "bottom-left", nominalValue: nominal)
            try add(result.topRight.durationMS, quantity: "exposureDuration", position: "top-right", nominalValue: nominal)
            try add(result.openingTravelMS, quantity: "curtainTravelDuration", position: "opening curtain: bottom-left to top-right sensor interval")
            try add(result.closingTravelMS, quantity: "curtainTravelDuration", position: "closing curtain: bottom-left to top-right sensor interval")
            sampleNotes.append("Sample \(sample): reading \(record.id.uuidString.lowercased()); direction \(record.direction.rawValue); captured \(timestamp(record.capturedAt)).")
            exported += 1
        }
        guard !measurements.isEmpty else { throw ExchangeError.invalid("There are no included, complete device readings to export. Partial, invalid, excluded and simulated readings remain available in the full archive.") }
        guard measurements.count <= 512 else {
            throw ExchangeError.invalid("This test produces \(measurements.count) quantities; Shutter Tester JSON v1 permits 512 per run. No readings were truncated. Export the full archive, or create smaller test runs for Armarium.")
        }
        let omitted = session.records.count - exported
        // Keep generated evidence text stable across the app rename: changing
        // notes at the same test revision would conflict with previous imports.
        let explanation = "Shutter Lover calculation version 1. Exposure and calibrated outer-sensor curtain intervals are measured seconds. Curtain intervals span the 32 × 20 mm sensor rectangle; they are not full-frame travel estimates. Exported \(exported) complete included device readings; omitted \(omitted) excluded, partial or invalid readings and \(omittedTravel) nonpositive/unavailable curtain quantities. Raw events, calibration, exclusions and complete provenance are retained in the Shutter Lover archive."
        let association = session.cameraAssignedAt.map { "Camera association explicitly assigned on \(timestamp($0)) after capture; originally recorded camera name: \(session.cameraName)." } ?? ""
        let notes = ([session.notes, association, explanation] + sampleNotes).filter { !$0.isEmpty }.joined(separator: "\n\n")
        guard notes.utf8.count <= 16_384 else { throw ExchangeError.invalid("The notes and reading identity provenance exceed the format's 16 KiB limit. Shorten the test notes or use the full archive.") }
        let explicitTitle = session.title?.trimmingCharacters(in: .whitespacesAndNewlines)
        let exportTitle = explicitTitle.flatMap { $0.isEmpty ? nil : $0 } ?? "Shutter test · \(timestamp(session.createdAt))"
        var test: [String: Any] = ["id": session.id.uuidString.lowercased(), "cameraID": externalID.uuidString.lowercased(),
                                   "revision": session.effectiveRevision, "title": exportTitle,
                                   "performedAt": timestamp(session.createdAt), "testType": "shutterTiming", "measurements": measurements, "notes": notes]
        let firmware = Set(session.records.filter { !$0.isExcluded && $0.result.quality == .complete }.map { $0.packet.firmware_version })
        var tester: [String: Any] = ["model": "Shutter Lover"]
        if firmware.count == 1 { tester["firmware"] = firmware.first! }
        test["tester"] = tester
        var conditions: [String: Any] = [:]
        if let source = session.lightSource, !source.isEmpty { conditions["lightSource"] = source }
        if let notes = session.testConditions, !notes.isEmpty { conditions["notes"] = notes }
        if !conditions.isEmpty { test["conditions"] = conditions }
        let envelope: [String: Any] = ["format": format, "version": 1, "kind": "testResults", "createdAt": timestamp(createdAt),
                                       "source": ["libraryID": producerLibraryID.uuidString.lowercased(), "application": "Shutter Loved", "version": "0.2.3"],
                                       "requiredCapabilities": ["shutter-timing-v1"], "cameraCatalogueID": catalogueID.uuidString.lowercased(), "tests": [test]]
        let data = try JSONSerialization.data(withJSONObject: envelope, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        try validateResults(data)
        return data
    }

    /// Useful for independent fixture verification; does not import or reinterpret external results.
    static func validateResults(_ data: Data) throws {
        let root = try parseEnvelope(data, kind: "testResults", fields: ["cameraCatalogueID", "tests"])
        _ = try root.uuid("cameraCatalogueID")
        let tests = try root.array("tests", minimum: 1, maximum: 1_000)
        var testIDs = Set<UUID>()
        for entry in tests {
            let test = try entry.checkedObject(required: ["id", "cameraID", "revision", "title", "performedAt", "testType", "measurements"], optional: ["tester", "conditions", "notes"])
            guard testIDs.insert(try test.uuid("id")).inserted else { throw ExchangeError.invalid("A results file contains the same test UUID more than once.") }
            _ = try test.uuid("cameraID"); _ = try test.integer("revision", range: 1...2_147_483_647)
            _ = try test.text("title", maximum: 512, nonblank: true); try validateTimestamp(test.text("performedAt"))
            guard try test.text("testType") == "shutterTiming" else { throw ExchangeError.invalid("Unsupported test type; version 1 accepts shutterTiming.") }
            for entry in try test.array("measurements", minimum: 1, maximum: 512) {
                let measurement = try entry.checkedObject(required: ["quantity", "value", "unit"], optional: ["nominalValue", "position", "sampleIndex"])
                let quantity = try measurement.text("quantity")
                guard ["exposureDuration", "curtainTravelDuration", "flashDelay"].contains(quantity) else { throw ExchangeError.invalid("Unsupported measurement quantity \(quantity).") }
                guard try measurement.text("unit") == "s" else { throw ExchangeError.invalid("Measurements must declare seconds with unit s.") }
                for key in ["value", "nominalValue"] where measurement[key] != nil {
                    let value = try measurement.number(key)
                    guard abs(value) <= 1e12, quantity == "flashDelay" || value > 0 else { throw ExchangeError.invalid("The \(quantity) value must be positive (except signed flash delay), finite and within 10¹² seconds.") }
                }
                _ = try measurement.optionalText("position", maximum: 128)
                if measurement["sampleIndex"] != nil { _ = try measurement.integer("sampleIndex", range: 1...10_000) }
            }
            if let value = test["tester"] {
                let tester = try value.checkedObject(required: [], optional: ["manufacturer", "model", "serial", "firmware"])
                for key in tester.keys { _ = try tester.text(key, maximum: 512) }
            }
            if let value = test["conditions"] {
                let conditions = try value.checkedObject(required: [], optional: ["lightSource", "temperatureCelsius", "notes"])
                _ = try conditions.optionalText("lightSource", maximum: 512)
                _ = try conditions.optionalText("notes", maximum: 16_384)
                if conditions["temperatureCelsius"] != nil {
                    guard (-273.15...1_000).contains(try conditions.number("temperatureCelsius")) else { throw ExchangeError.invalid("Temperature is outside the supported range.") }
                }
            }
            _ = try test.optionalText("notes", maximum: 16_384)
        }
    }

    private struct Catalogue { let id: UUID; let application: String; let profiles: [Profile] }
    private struct Profile { let id: UUID; let revision: Int; let name: String; let node: [String: ExchangeJSON]; let canonical: Data }

    private static func parseCatalogue(_ data: Data) throws -> Catalogue {
        let root = try parseEnvelope(data, kind: "cameraCatalog", fields: ["cameras"])
        let source = try root.object("source")
        var ids = Set<UUID>()
        let profiles = try root.array("cameras", minimum: 1, maximum: 1_000).map { value -> Profile in
            var profile = try value.checkedObject(required: ["id", "revision", "name", "manufacturer", "model", "inventoryID", "mount", "camera", "shutter"], optional: ["serial"])
            let id = try profile.uuid("id")
            guard ids.insert(id).inserted else { throw ExchangeError.invalid("The catalogue contains duplicate camera UUIDs.") }
            let revision = try profile.integer("revision", range: 1...2_147_483_647)
            let name = try profile.text("name", maximum: 512, nonblank: true)
            for key in ["manufacturer", "model", "inventoryID", "mount"] { _ = try profile.text(key) }
            _ = try profile.optionalText("serial")
            for (key, fields) in [("camera", ["type", "captureMedium", "format"]),
                                  ("shutter", ["architecture", "location", "timingControl", "construction", "material", "maker", "model", "travelDirection", "speedRange", "modes", "powerRequirements", "batteryFallback", "flashSync"])] {
                let child = try profile[key]!.checkedObject(required: Set(fields), optional: [])
                for field in fields { _ = try child.text(field) }
            }
            profile["id"] = .string(id.uuidString.lowercased())
            let canonical = try JSONSerialization.data(withJSONObject: ExchangeJSON.object(profile).foundation, options: [.sortedKeys, .withoutEscapingSlashes])
            return Profile(id: id, revision: revision, name: name, node: profile, canonical: canonical)
        }
        return Catalogue(id: try source.uuid("libraryID"), application: try source.text("application"), profiles: profiles)
    }

    private static func parseEnvelope(_ data: Data, kind: String, fields: Set<String>) throws -> [String: ExchangeJSON] {
        var parser = try ExchangeJSONParser(data: data)
        let root = try parser.parse().checkedObject(required: Set(["format", "version", "kind", "createdAt", "source"]).union(fields), optional: ["requiredCapabilities"])
        guard try root.text("format") == format else { throw ExchangeError.invalid("This is not a Shutter Tester JSON document.") }
        guard try root.integer("version", range: 1...1) == 1 else { throw ExchangeError.invalid("Unsupported Shutter Tester JSON version.") }
        guard try root.text("kind") == kind else { throw ExchangeError.invalid("Expected a \(kind) document.") }
        try validateTimestamp(root.text("createdAt"))
        let source = try root["source"]!.checkedObject(required: ["libraryID", "application"], optional: ["version"])
        _ = try source.uuid("libraryID"); _ = try source.text("application", maximum: 256, nonblank: true)
        _ = try source.optionalText("version", maximum: 128)
        if root["requiredCapabilities"] != nil {
            var capabilities = Set<String>()
            for value in try root.array("requiredCapabilities", minimum: 0, maximum: 32) {
                guard case .string(let name) = value, name == "shutter-timing-v1", capabilities.insert(name).inserted else {
                    throw ExchangeError.invalid("Unknown or repeated required capability; supported: shutter-timing-v1.")
                }
            }
        }
        return root
    }

    private static func timestamp(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }

    private static func validateTimestamp(_ string: String) throws {
        let pattern = #"^([0-9]{4})-([0-9]{2})-([0-9]{2})T([0-9]{2}):([0-9]{2}):([0-9]{2})(?:\.[0-9]{1,9})?(Z|[+-]([0-9]{2}):([0-9]{2}))$"#
        let regex = try NSRegularExpression(pattern: pattern)
        let range = NSRange(string.startIndex..., in: string)
        guard let match = regex.firstMatch(in: string, range: range), match.range.length == range.length else { throw ExchangeError.invalid("Dates must be RFC 3339 timestamps with an explicit timezone.") }
        func component(_ index: Int) -> Int {
            guard let range = Range(match.range(at: index), in: string) else { return 0 }
            return Int(string[range]) ?? -1
        }
        let values = (1...6).map(component)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let parts = DateComponents(year: values[0], month: values[1], day: values[2], hour: values[3], minute: values[4], second: values[5])
        guard values[0] >= 1, (1...12).contains(values[1]), (1...31).contains(values[2]),
              (0...23).contains(values[3]), (0...59).contains(values[4]), (0...59).contains(values[5]),
              (0...23).contains(component(8)), (0...59).contains(component(9)),
              let date = calendar.date(from: parts), calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date) == parts else {
            throw ExchangeError.invalid("A timestamp has an invalid calendar date, time or timezone.")
        }
    }
}

struct CatalogueImportReview: Identifiable {
    let id = UUID()
    let originalData: Data
    let catalogueID: UUID
    let sourceApplication: String
    let rows: [CatalogueImportRow]
    fileprivate let stateFingerprint: Data
    var hasChanges: Bool { rows.contains { $0.disposition == .newCamera || $0.disposition == .newRevision } }
    var canApply: Bool { !rows.contains { $0.disposition == .conflict } }
}

struct CatalogueImportRow: Identifiable, Equatable {
    var id: UUID { externalCameraID }
    let externalCameraID: UUID
    let localCameraID: UUID?
    let cameraName: String
    let revision: Int
    let disposition: CatalogueImportDisposition
    let detail: String
}

enum CatalogueImportDisposition: String, Equatable {
    case newCamera = "New camera", newRevision = "New revision", alreadyImported = "Already imported", olderRevision = "Older revision", conflict = "Conflict"
    var title: String { rawValue }
}

enum ExchangeError: LocalizedError {
    case invalid(String)
    var errorDescription: String? { if case .invalid(let message) = self { return message }; return nil }
}

private indirect enum ExchangeJSON {
    case object([String: ExchangeJSON]), array([ExchangeJSON]), string(String), number(Double, integral: Bool), boolean(Bool)
    var foundation: Any {
        switch self {
        case .object(let value): return value.mapValues(\.foundation)
        case .array(let value): return value.map(\.foundation)
        case .string(let value): return value
        case .number(let value, _): return value
        case .boolean(let value): return value
        }
    }
    func checkedObject(required: Set<String>, optional: Set<String>) throws -> [String: ExchangeJSON] {
        guard case .object(let object) = self else { throw ExchangeError.invalid("Expected a JSON object.") }
        let fields = Set(object.keys)
        guard required.isSubset(of: fields) else { throw ExchangeError.invalid("Missing required fields: \(required.subtracting(fields).sorted().joined(separator: ", ")).") }
        guard fields.isSubset(of: required.union(optional)) else { throw ExchangeError.invalid("Unsupported fields: \(fields.subtracting(required.union(optional)).sorted().joined(separator: ", ")).") }
        return object
    }
}

private extension Dictionary where Key == String, Value == ExchangeJSON {
    func text(_ key: String, maximum: Int = 65_536, nonblank: Bool = false) throws -> String {
        guard case .string(let value) = self[key], value.utf8.count <= maximum,
              !nonblank || !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ExchangeError.invalid("\(key) must be \(nonblank ? "nonblank " : "")text of at most \(maximum) UTF-8 bytes.")
        }
        return value
    }
    func optionalText(_ key: String, maximum: Int = 65_536) throws -> String? {
        self[key] == nil ? nil : try text(key, maximum: maximum)
    }
    func number(_ key: String) throws -> Double {
        guard case .number(let value, _) = self[key], value.isFinite else { throw ExchangeError.invalid("\(key) must be a finite number, not text or a boolean.") }
        return value
    }
    func integer(_ key: String, range: ClosedRange<Int>) throws -> Int {
        let value = try number(key)
        guard case .number(_, let integral) = self[key], integral, value.rounded(.towardZero) == value,
              value >= Double(range.lowerBound), value <= Double(range.upperBound) else {
            throw ExchangeError.invalid("\(key) must be an integer from \(range.lowerBound) to \(range.upperBound).")
        }
        return Int(value)
    }
    func uuid(_ key: String) throws -> UUID {
        let value = try text(key, maximum: 36)
        guard value.range(of: #"^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$"#, options: .regularExpression) != nil,
              let uuid = UUID(uuidString: value) else { throw ExchangeError.invalid("\(key) must be a full hyphenated UUID.") }
        return uuid
    }
    func object(_ key: String) throws -> [String: ExchangeJSON] {
        guard case .object(let value) = self[key] else { throw ExchangeError.invalid("\(key) must be an object.") }; return value
    }
    func array(_ key: String, minimum: Int, maximum: Int) throws -> [ExchangeJSON] {
        guard case .array(let value) = self[key], (minimum...maximum).contains(value.count) else {
            throw ExchangeError.invalid("\(key) must be an array containing \(minimum)–\(maximum) entries.")
        }; return value
    }
}

/// Small strict tokenizer/parser detects duplicate keys before Foundation could discard them.
private struct ExchangeJSONParser {
    private let bytes: [UInt8]
    private var cursor = 0
    init(data: Data) throws {
        guard !data.isEmpty, data.count <= ShutterTesterExchange.maximumFileBytes, String(data: data, encoding: .utf8) != nil else {
            throw ExchangeError.invalid("Exchange files must be nonempty UTF-8 JSON of at most 8 MiB.")
        }
        bytes = Array(data)
    }
    mutating func parse() throws -> ExchangeJSON {
        let value = try value(depth: 0)
        whitespace()
        guard cursor == bytes.count else { throw ExchangeError.invalid("Unexpected trailing content after the JSON document.") }
        return value
    }
    private mutating func value(depth: Int) throws -> ExchangeJSON {
        guard depth <= 32 else { throw ExchangeError.invalid("JSON nesting exceeds 32 levels.") }
        whitespace()
        guard cursor < bytes.count else { throw ExchangeError.invalid("Unexpected end of JSON.") }
        switch bytes[cursor] {
        case 123:
            cursor += 1; whitespace()
            var fields: [String: ExchangeJSON] = [:]
            if consume(125) { return .object(fields) }
            while true {
                whitespace(); let key = try string()
                guard fields[key] == nil else { throw ExchangeError.invalid("Duplicate JSON key: \(key.prefix(100)).") }
                guard fields.count < 256 else { throw ExchangeError.invalid("A JSON object exceeds 256 fields.") }
                whitespace(); guard consume(58) else { throw syntax() }
                fields[key] = try value(depth: depth + 1)
                whitespace(); if consume(125) { break }
                guard consume(44) else { throw syntax() }
            }
            return .object(fields)
        case 91:
            cursor += 1; whitespace(); var entries: [ExchangeJSON] = []
            if consume(93) { return .array(entries) }
            while true {
                guard entries.count < 10_000 else { throw ExchangeError.invalid("A JSON array exceeds 10,000 entries.") }
                entries.append(try value(depth: depth + 1))
                whitespace(); if consume(93) { break }
                guard consume(44) else { throw syntax() }
            }
            return .array(entries)
        case 34: return .string(try string())
        case 116: try literal("true"); return .boolean(true)
        case 102: try literal("false"); return .boolean(false)
        case 110: throw ExchangeError.invalid("Explicit null values are not supported. Omit unknown optional fields.")
        case 45, 48...57: return try number()
        default: throw syntax()
        }
    }
    private mutating func string() throws -> String {
        let start = cursor
        guard consume(34) else { throw syntax() }
        var escaped = false
        while cursor < bytes.count {
            let byte = bytes[cursor]; cursor += 1
            guard byte >= 32 else { throw syntax() }
            if escaped { escaped = false; continue }
            if byte == 92 { escaped = true; continue }
            if byte == 34 {
                let data = Data(bytes[start..<cursor])
                guard let decoded = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) as? String,
                      decoded.utf8.count <= 65_536 else { throw ExchangeError.invalid("Invalid JSON string or string exceeding 64 KiB.") }
                return decoded
            }
            guard cursor - start <= 6 * 65_536 + 2 else { throw ExchangeError.invalid("JSON string exceeds the supported size.") }
        }
        throw syntax()
    }
    private mutating func number() throws -> ExchangeJSON {
        let start = cursor
        _ = consume(45)
        if !consume(48) {
            guard cursor < bytes.count, (49...57).contains(bytes[cursor]) else { throw syntax() }
            digits()
        }
        if consume(46) {
            let before = cursor; digits(); guard cursor > before else { throw syntax() }
        }
        if consume(101) || consume(69) {
            if !consume(43) { _ = consume(45) }
            let before = cursor; digits(); guard cursor > before else { throw syntax() }
        }
        let spelling = String(decoding: bytes[start..<cursor], as: UTF8.self)
        guard let value = Double(spelling), value.isFinite else { throw ExchangeError.invalid("JSON contains an invalid or nonfinite number.") }
        // Check integer spelling exactly before Double rounding can conceal a fractional revision.
        let parts = spelling.lowercased().split(separator: "e", omittingEmptySubsequences: false)
        let significand = String(parts[0])
        let digits = significand.filter { $0.isNumber }
        let fractionCount = significand.split(separator: ".", omittingEmptySubsequences: false).dropFirst().first?.count ?? 0
        let trailingZeros = digits.reversed().prefix { $0 == "0" }.count
        let exponent = parts.count == 2 ? Int(parts[1]) : 0
        let integral: Bool
        if trailingZeros == digits.count { integral = true }
        else if let exponent { integral = exponent >= fractionCount - trailingZeros }
        else { integral = !parts[1].hasPrefix("-") }
        return .number(value, integral: integral)
    }
    private mutating func digits() { while cursor < bytes.count, (48...57).contains(bytes[cursor]) { cursor += 1 } }
    private mutating func literal(_ value: String) throws {
        for byte in value.utf8 { guard consume(byte) else { throw syntax() } }
    }
    private mutating func consume(_ byte: UInt8) -> Bool {
        guard cursor < bytes.count, bytes[cursor] == byte else { return false }; cursor += 1; return true
    }
    private mutating func whitespace() { while cursor < bytes.count, [9, 10, 13, 32].contains(bytes[cursor]) { cursor += 1 } }
    private func syntax() -> ExchangeError { .invalid("Malformed JSON near byte \(cursor + 1).") }
}
