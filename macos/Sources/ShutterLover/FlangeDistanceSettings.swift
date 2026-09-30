import Foundation

struct CustomFlangeMount: Codable, Equatable, Identifiable {
    var id: String
    var name: String
    var distanceMM: Double
    var notes: String

    init(id: String = "custom-\(UUID().uuidString)", name: String, distanceMM: Double, notes: String = "") {
        self.id = id
        self.name = name
        self.distanceMM = distanceMM
        self.notes = notes
    }
}

struct FlangeDistanceConfiguration: Codable, Equatable {
    var version = 1
    var overrides: [String: Double] = [:]
    var customMounts: [CustomFlangeMount] = []

    func validate() throws {
        guard version == 1 else { throw FlangeSettingsError.invalid("This flange-distance settings version is not supported.") }
        guard customMounts.count <= 500, overrides.count <= FlangeDistanceCatalogue.mounts.count else {
            throw FlangeSettingsError.invalid("The flange-distance table contains too many entries.")
        }
        let builtInIDs = Set(FlangeDistanceCatalogue.mounts.map(\.id))
        for (id, distance) in overrides {
            guard builtInIDs.contains(id) else { throw FlangeSettingsError.invalid("An override refers to an unknown mount.") }
            try Self.validateDistance(distance)
        }
        var identifiers = builtInIDs
        var names = Set(FlangeDistanceCatalogue.mounts.flatMap { [$0.name] + $0.aliases }.map(FlangeDistanceCatalogue.normalize))
        for mount in customMounts {
            guard mount.id.hasPrefix("custom-"), UUID(uuidString: String(mount.id.dropFirst(7))) != nil,
                  identifiers.insert(mount.id).inserted else {
                throw FlangeSettingsError.invalid("A custom mount has an invalid or repeated identifier.")
            }
            let name = mount.name.trimmingCharacters(in: .whitespacesAndNewlines)
            let normalized = FlangeDistanceCatalogue.normalize(name)
            guard !normalized.isEmpty, name.count <= 150, !name.contains(where: \.isNewline),
                  names.insert(normalized).inserted else {
                throw FlangeSettingsError.invalid("Use a unique mount name of up to 150 characters. Existing mount names and aliases cannot be reused.")
            }
            guard mount.notes.count <= 4_000 else { throw FlangeSettingsError.invalid("Mount notes must be no longer than 4,000 characters.") }
            try Self.validateDistance(mount.distanceMM)
        }
    }

    static func validateDistance(_ distance: Double) throws {
        guard distance.isFinite, distance > 0, distance <= 1_000 else {
            throw FlangeSettingsError.invalid("Enter a flange focal distance greater than 0 and no more than 1,000 mm.")
        }
    }
}

enum FlangeSettingsError: LocalizedError {
    case invalid(String)
    var errorDescription: String? { if case .invalid(let message) = self { return message }; return nil }
}

struct FlangeDistanceRow: Identifiable, Equatable {
    let id: String
    let name: String
    let distanceMM: Double
    let defaultDistanceMM: Double?
    let isOverride: Bool
    let sourceURLs: [URL]
    let notes: String
    var isCustom: Bool { defaultDistanceMM == nil }
    var status: String { isCustom ? "Custom" : isOverride ? "Modified" : "Reference" }
}

@MainActor
extension AppModel {
    static let flangeDistanceSettingsKey = "flangeDistanceConfiguration.v1"
    static let flangeDistanceRecoveryKey = "flangeDistanceConfiguration.unreadableBackup"

    var flangeMountRows: [FlangeDistanceRow] {
        let builtIn = FlangeDistanceCatalogue.mounts.map { mount in
            FlangeDistanceRow(id: mount.id, name: mount.name,
                              distanceMM: flangeDistanceConfiguration.overrides[mount.id] ?? mount.defaultDistanceMM,
                              defaultDistanceMM: mount.defaultDistanceMM,
                              isOverride: flangeDistanceConfiguration.overrides[mount.id] != nil,
                              sourceURLs: mount.sourceURLs, notes: mount.notes)
        }
        let custom = flangeDistanceConfiguration.customMounts.map { mount in
            FlangeDistanceRow(id: mount.id, name: mount.name, distanceMM: mount.distanceMM,
                              defaultDistanceMM: nil, isOverride: false, sourceURLs: [], notes: mount.notes)
        }
        return (builtIn + custom).sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    func flangeMatches(_ name: String) -> [FlangeDistanceRow] {
        guard !flangeSettingsLoadFailed else { return [] }
        let builtIn = Set(FlangeDistanceCatalogue.matches(name).map(\.id))
        let normalized = FlangeDistanceCatalogue.normalize(name)
        guard !normalized.isEmpty else { return [] }
        return flangeMountRows.filter { builtIn.contains($0.id) || ($0.isCustom && FlangeDistanceCatalogue.normalize($0.name) == normalized) }
    }

    func loadFlangeDistanceSettings() {
        guard let raw = preferences.object(forKey: Self.flangeDistanceSettingsKey) else {
            flangeDistanceConfiguration = FlangeDistanceConfiguration()
            flangeSettingsLoadFailed = false
            flangeSettingsError = nil
            return
        }
        do {
            guard let data = raw as? Data, data.count <= 1_048_576 else {
                throw FlangeSettingsError.invalid("The saved flange-distance settings have an invalid format or size.")
            }
            let saved = try JSONDecoder().decode(FlangeDistanceConfiguration.self, from: data)
            try saved.validate()
            flangeDistanceConfiguration = saved
            flangeSettingsLoadFailed = false
            flangeSettingsError = nil
        } catch {
            // Do not overwrite the unreadable object, nor use fallback values for positioning.
            flangeDistanceConfiguration = FlangeDistanceConfiguration()
            flangeSettingsLoadFailed = true
            flangeSettingsError = "Saved flange distances could not be read. Positioning calculations are paused and your settings have been left untouched. Restore defaults to continue. \(error.localizedDescription)"
        }
    }

    func saveFlangeDistance(mountID: String, distanceMM: Double) -> Bool {
        guard let mount = FlangeDistanceCatalogue.mounts.first(where: { $0.id == mountID }) else {
            flangeSettingsError = "The reference mount could not be found."
            return false
        }
        var candidate = flangeDistanceConfiguration
        if distanceMM == mount.defaultDistanceMM { candidate.overrides.removeValue(forKey: mountID) }
        else { candidate.overrides[mountID] = distanceMM }
        return commitFlangeDistanceSettings(candidate)
    }

    func resetFlangeDistance(mountID: String) -> Bool {
        guard FlangeDistanceCatalogue.mounts.contains(where: { $0.id == mountID }) else {
            flangeSettingsError = "The reference mount could not be found."
            return false
        }
        var candidate = flangeDistanceConfiguration
        candidate.overrides.removeValue(forKey: mountID)
        return commitFlangeDistanceSettings(candidate)
    }

    func addCustomFlangeMount(name: String, distanceMM: Double, notes: String) -> Bool {
        var candidate = flangeDistanceConfiguration
        candidate.customMounts.append(CustomFlangeMount(name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                                                       distanceMM: distanceMM, notes: notes))
        return commitFlangeDistanceSettings(candidate)
    }

    func updateCustomFlangeMount(id: String, name: String, distanceMM: Double, notes: String) -> Bool {
        var candidate = flangeDistanceConfiguration
        guard let index = candidate.customMounts.firstIndex(where: { $0.id == id }) else {
            flangeSettingsError = "The custom mount could not be found."
            return false
        }
        candidate.customMounts[index].name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        candidate.customMounts[index].distanceMM = distanceMM
        candidate.customMounts[index].notes = notes
        return commitFlangeDistanceSettings(candidate)
    }

    func removeCustomFlangeMount(id: String) -> Bool {
        var candidate = flangeDistanceConfiguration
        guard candidate.customMounts.contains(where: { $0.id == id }) else {
            flangeSettingsError = "The custom mount could not be found."
            return false
        }
        candidate.customMounts.removeAll { $0.id == id }
        return commitFlangeDistanceSettings(candidate)
    }

    func restoreFlangeDistanceDefaults() -> Bool {
        if flangeSettingsLoadFailed, let raw = preferences.object(forKey: Self.flangeDistanceSettingsKey) {
            preferences.set(raw, forKey: Self.flangeDistanceRecoveryKey)
        }
        return commitFlangeDistanceSettings(FlangeDistanceConfiguration(), restoring: true)
    }

    private func commitFlangeDistanceSettings(_ candidate: FlangeDistanceConfiguration, restoring: Bool = false) -> Bool {
        guard !flangeSettingsLoadFailed || restoring else {
            flangeSettingsError = "Saved flange distances could not be read. Restore defaults explicitly before making changes; the original settings will be retained as a recovery copy."
            return false
        }
        do {
            try candidate.validate()
            let data = try JSONEncoder().encode(candidate)
            guard data.count <= 1_048_576 else { throw FlangeSettingsError.invalid("The flange-distance settings are too large to save.") }
            preferences.set(data, forKey: Self.flangeDistanceSettingsKey)
            flangeDistanceConfiguration = candidate
            flangeSettingsLoadFailed = false
            flangeSettingsError = nil
            return true
        } catch {
            flangeSettingsError = error.localizedDescription
            return false
        }
    }
}
