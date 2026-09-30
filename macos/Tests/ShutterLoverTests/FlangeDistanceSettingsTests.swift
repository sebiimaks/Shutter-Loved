import XCTest
@testable import ShutterLover

final class FlangeDistanceSettingsTests: XCTestCase {
    @MainActor
    private func withModel(_ body: (AppModel, UserDefaults) throws -> Void) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("flange-settings-\(UUID().uuidString)")
        let suite = "flange-settings-tests-\(UUID().uuidString)"
        let preferences = try XCTUnwrap(UserDefaults(suiteName: suite))
        let store = SessionStore(directory: directory)
        try store.saveLibrary(CameraLibraryArchive(sessions: [CaptureSession(cameraName: "Camera", demo: false)]))
        let model = AppModel(store: store, startDiscovery: false, preferences: preferences)
        defer {
            model.shutDown()
            preferences.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: directory)
        }
        try body(model, preferences)
    }

    @MainActor
    func testDefaultsLoadWithoutWritingPreferences() throws {
        try withModel { model, preferences in
            XCTAssertFalse(model.flangeSettingsLoadFailed)
            XCTAssertNil(model.flangeSettingsError)
            XCTAssertNil(preferences.object(forKey: AppModel.flangeDistanceSettingsKey))
            XCTAssertEqual(model.flangeMountRows.count, FlangeDistanceCatalogue.mounts.count)
            XCTAssertTrue(model.flangeMountRows.allSatisfy { !$0.isCustom && !$0.isOverride && $0.distanceMM == $0.defaultDistanceMM })
            XCTAssertTrue(model.flangeMatches("").isEmpty)
        }
    }

    @MainActor
    func testOverridePersistsAcrossReloadAndResetRemovesOverride() throws {
        let mount = try XCTUnwrap(FlangeDistanceCatalogue.mounts.first)
        try withModel { model, preferences in
            let distance = mount.defaultDistanceMM + 0.1234
            XCTAssertTrue(model.saveFlangeDistance(mountID: mount.id, distanceMM: distance))
            XCTAssertEqual(model.flangeMatches(mount.name).first?.distanceMM, distance)
            XCTAssertTrue(try XCTUnwrap(model.flangeMountRows.first { $0.id == mount.id }).isOverride)
            let reloaded = AppModel(store: model.store, startDiscovery: false, preferences: preferences)
            defer { reloaded.shutDown() }
            XCTAssertEqual(reloaded.flangeMatches(mount.name).first?.distanceMM, distance)
            if let alias = mount.aliases.first {
                XCTAssertEqual(reloaded.flangeMatches(alias).first { $0.id == mount.id }?.distanceMM, distance)
            }
            XCTAssertTrue(reloaded.resetFlangeDistance(mountID: mount.id))
            model.loadFlangeDistanceSettings()
            XCTAssertEqual(model.flangeMatches(mount.name).first?.distanceMM, mount.defaultDistanceMM)
            XCTAssertTrue(model.flangeDistanceConfiguration.overrides.isEmpty)
            XCTAssertFalse(try XCTUnwrap(model.flangeMountRows.first { $0.id == mount.id }).isOverride)
        }
    }

    @MainActor
    func testInvalidDistancesLeaveStoredAndPublishedValuesUnchanged() throws {
        let mount = try XCTUnwrap(FlangeDistanceCatalogue.mounts.first)
        try withModel { model, preferences in
            XCTAssertTrue(model.saveFlangeDistance(mountID: mount.id, distanceMM: 42))
            let before = preferences.data(forKey: AppModel.flangeDistanceSettingsKey)
            let original = model.flangeDistanceConfiguration
            for value in [-1.0, 0, 1000.001, .infinity, .nan] {
                XCTAssertFalse(model.saveFlangeDistance(mountID: mount.id, distanceMM: value))
                XCTAssertEqual(preferences.data(forKey: AppModel.flangeDistanceSettingsKey), before)
                XCTAssertEqual(model.flangeDistanceConfiguration, original)
            }
            XCTAssertFalse(model.saveFlangeDistance(mountID: "unknown-mount", distanceMM: 40))
            XCTAssertFalse(model.resetFlangeDistance(mountID: "unknown-mount"))
            XCTAssertEqual(preferences.data(forKey: AppModel.flangeDistanceSettingsKey), before)
        }
    }

    @MainActor
    func testCustomMountCanBeEditedReloadedAndRemovedWithStableID() throws {
        try withModel { model, preferences in
            XCTAssertTrue(model.addCustomFlangeMount(name: " Laboratory reference mount ", distanceMM: 123.456, notes: "Measured reference"))
            let custom = try XCTUnwrap(model.flangeMatches("laboratory reference mount").first)
            XCTAssertTrue(custom.isCustom)
            XCTAssertNil(custom.defaultDistanceMM)
            XCTAssertEqual(custom.name, "Laboratory reference mount")
            XCTAssertTrue(model.updateCustomFlangeMount(id: custom.id, name: "Lab reference revised", distanceMM: 124.5, notes: "Rechecked"))
            XCTAssertTrue(model.flangeMatches(custom.name).isEmpty)
            let reloaded = AppModel(store: model.store, startDiscovery: false, preferences: preferences)
            defer { reloaded.shutDown() }
            let revised = try XCTUnwrap(reloaded.flangeMatches("Lab reference revised").first)
            XCTAssertEqual(revised.id, custom.id)
            XCTAssertEqual(revised.distanceMM, 124.5)
            XCTAssertEqual(revised.notes, "Rechecked")
            XCTAssertTrue(reloaded.removeCustomFlangeMount(id: revised.id))
            model.loadFlangeDistanceSettings()
            XCTAssertTrue(model.flangeDistanceConfiguration.customMounts.isEmpty)
            XCTAssertTrue(model.flangeMatches("Lab reference revised").isEmpty)
        }
    }

    @MainActor
    func testCustomNamesCannotShadowBuiltInNamesAliasesOrOtherCustomMounts() throws {
        let mount = try XCTUnwrap(FlangeDistanceCatalogue.mounts.first)
        try withModel { model, preferences in
            for name in [mount.name] + mount.aliases {
                XCTAssertFalse(model.addCustomFlangeMount(name: name.uppercased(), distanceMM: 50, notes: ""))
            }
            XCTAssertNil(preferences.object(forKey: AppModel.flangeDistanceSettingsKey))
            XCTAssertTrue(model.addCustomFlangeMount(name: "Lab custom mount", distanceMM: 50, notes: ""))
            let before = preferences.data(forKey: AppModel.flangeDistanceSettingsKey)
            XCTAssertFalse(model.addCustomFlangeMount(name: "  LAB CUSTOM MOUNT ", distanceMM: 60, notes: ""))
            XCTAssertFalse(model.addCustomFlangeMount(name: "", distanceMM: 50, notes: ""))
            XCTAssertFalse(model.addCustomFlangeMount(name: "Mount\nname", distanceMM: 50, notes: ""))
            XCTAssertFalse(model.addCustomFlangeMount(name: String(repeating: "x", count: 151), distanceMM: 50, notes: ""))
            XCTAssertFalse(model.addCustomFlangeMount(name: "Other", distanceMM: 50, notes: String(repeating: "x", count: 4001)))
            let customID = try XCTUnwrap(model.flangeDistanceConfiguration.customMounts.first?.id)
            XCTAssertFalse(model.updateCustomFlangeMount(id: customID, name: mount.name, distanceMM: 60, notes: ""))
            XCTAssertEqual(preferences.data(forKey: AppModel.flangeDistanceSettingsKey), before)
        }
    }

    @MainActor
    func testCorruptSettingsRemainUntouchedUntilExplicitRecovery() throws {
        let mount = try XCTUnwrap(FlangeDistanceCatalogue.mounts.first)
        try withModel { model, preferences in
            let unreadable = Data("{ unfinished settings".utf8)
            preferences.set(unreadable, forKey: AppModel.flangeDistanceSettingsKey)
            model.loadFlangeDistanceSettings()
            XCTAssertTrue(model.flangeSettingsLoadFailed)
            XCTAssertNotNil(model.flangeSettingsError)
            XCTAssertTrue(model.flangeMatches(mount.name).isEmpty)
            XCTAssertFalse(model.saveFlangeDistance(mountID: mount.id, distanceMM: 42))
            XCTAssertFalse(model.addCustomFlangeMount(name: "New mount", distanceMM: 42, notes: ""))
            XCTAssertFalse(model.resetFlangeDistance(mountID: mount.id))
            XCTAssertEqual(preferences.data(forKey: AppModel.flangeDistanceSettingsKey), unreadable)
            XCTAssertTrue(model.restoreFlangeDistanceDefaults())
            XCTAssertEqual(preferences.data(forKey: AppModel.flangeDistanceRecoveryKey), unreadable)
            XCTAssertFalse(model.flangeSettingsLoadFailed)
            XCTAssertNil(model.flangeSettingsError)
            XCTAssertEqual(model.flangeMatches(mount.name).first?.distanceMM, mount.defaultDistanceMM)
            let reloaded = AppModel(store: model.store, startDiscovery: false, preferences: preferences)
            defer { reloaded.shutDown() }
            XCTAssertFalse(reloaded.flangeSettingsLoadFailed)
            XCTAssertEqual(reloaded.flangeMatches(mount.name).first?.distanceMM, mount.defaultDistanceMM)
        }
    }

    @MainActor
    func testUnsupportedSchemasUnknownIDsAndInvalidCustomSettingsBlockLoading() throws {
        let custom = CustomFlangeMount(name: "Lab mount", distanceMM: 40)
        var invalidConfigurations: [FlangeDistanceConfiguration] = []
        var unsupported = FlangeDistanceConfiguration(); unsupported.version = 2; invalidConfigurations.append(unsupported)
        var unknown = FlangeDistanceConfiguration(); unknown.overrides = ["missing-mount": 45]; invalidConfigurations.append(unknown)
        var duplicated = FlangeDistanceConfiguration(); duplicated.customMounts = [custom, custom]; invalidConfigurations.append(duplicated)
        var invalidID = FlangeDistanceConfiguration(); invalidID.customMounts = [CustomFlangeMount(id: "bad", name: "Lab mount", distanceMM: 40)]; invalidConfigurations.append(invalidID)
        var invalidDistance = FlangeDistanceConfiguration(); invalidDistance.customMounts = [CustomFlangeMount(name: "Lab mount", distanceMM: -5)]; invalidConfigurations.append(invalidDistance)
        try withModel { model, preferences in
            for configuration in invalidConfigurations {
                let raw = try JSONEncoder().encode(configuration)
                preferences.set(raw, forKey: AppModel.flangeDistanceSettingsKey)
                model.loadFlangeDistanceSettings()
                XCTAssertTrue(model.flangeSettingsLoadFailed)
                XCTAssertEqual(preferences.data(forKey: AppModel.flangeDistanceSettingsKey), raw)
            }
            preferences.set("wrong object type", forKey: AppModel.flangeDistanceSettingsKey)
            model.loadFlangeDistanceSettings()
            XCTAssertTrue(model.flangeSettingsLoadFailed)
            XCTAssertEqual(preferences.string(forKey: AppModel.flangeDistanceSettingsKey), "wrong object type")
        }
    }

    @MainActor
    func testRestoreDefaultsRemovesAllOverridesAndCustomMounts() throws {
        let mount = try XCTUnwrap(FlangeDistanceCatalogue.mounts.first)
        try withModel { model, preferences in
            XCTAssertTrue(model.saveFlangeDistance(mountID: mount.id, distanceMM: mount.defaultDistanceMM + 1))
            XCTAssertTrue(model.addCustomFlangeMount(name: "Temporary reference", distanceMM: 22, notes: ""))
            XCTAssertTrue(model.restoreFlangeDistanceDefaults())
            XCTAssertEqual(model.flangeDistanceConfiguration, FlangeDistanceConfiguration())
            let saved = try JSONDecoder().decode(FlangeDistanceConfiguration.self, from: XCTUnwrap(preferences.data(forKey: AppModel.flangeDistanceSettingsKey)))
            XCTAssertEqual(saved, FlangeDistanceConfiguration())
            XCTAssertEqual(model.flangeMountRows.count, FlangeDistanceCatalogue.mounts.count)
        }
    }
}
