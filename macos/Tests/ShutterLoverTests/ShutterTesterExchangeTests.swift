import XCTest
import MeasurementCore
@testable import ShutterLover

final class ShutterTesterExchangeTests: XCTestCase {
    private func fixture(_ name: String = "camera-catalog-v1.json") throws -> Data {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        return try Data(contentsOf: root.appendingPathComponent("docs/fixtures/shutter-tester-v1/\(name)"))
    }
    private func changed(_ data: Data, _ change: (inout [String: Any]) -> Void) throws -> Data {
        var root = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        change(&root)
        return try JSONSerialization.data(withJSONObject: root, options: [.sortedKeys])
    }
    private func changedProfile(_ data: Data, _ change: (inout [String: Any]) -> Void) throws -> Data {
        try changed(data) { root in
            var profiles = root["cameras"] as! [[String: Any]]
            change(&profiles[0]); root["cameras"] = profiles
        }
    }
    private func importedCamera() throws -> CameraProfile {
        let review = try ShutterTesterExchange.reviewCatalogue(fixture(), cameras: [])
        return try XCTUnwrap(ShutterTesterExchange.applyCatalogue(review, cameras: []).first)
    }
    private func session(_ count: Int = 1) throws -> CaptureSession {
        let camera = try importedCamera()
        var session = CaptureSession(cameraName: camera.name, demo: false)
        session.cameraID = camera.id
        session.cameraSnapshot = CameraIdentitySnapshot(camera: camera)
        session.title = "Synthetic interoperability test"
        session.revision = 1
        session.lightSource = "LED"
        session.testConditions = "Independent invented test data only."
        for index in 0..<count {
            let packet = DemoPackets.sample(nominalDenominator: 125, index: index)
            session.records.append(MeasurementRecord(rawLine: String(decoding: try JSONEncoder().encode(packet), as: UTF8.self), packet: packet, direction: .horizontal, nominalDenominator: 125, isDemo: false))
        }
        return session
    }

    func testPublicSyntheticFixturesAreAcceptedWithoutNameMatching() throws {
        let data = try fixture()
        let review = try ShutterTesterExchange.reviewCatalogue(data, cameras: [CameraProfile(name: "Synthetic demonstration camera")])
        XCTAssertTrue(review.canApply)
        XCTAssertEqual(review.rows.first?.disposition, .newCamera)
        let cameras = try ShutterTesterExchange.applyCatalogue(review, cameras: [CameraProfile(name: "Other local camera")])
        XCTAssertEqual(cameras.count, 2)
        let imported = try XCTUnwrap(cameras.last)
        XCTAssertEqual(imported.catalogueID?.uuidString, "22CA47B6-D6BE-4EA9-A50A-C9AF3D81F091")
        XCTAssertEqual(imported.catalogueCameraID?.uuidString, "81466045-3803-4C94-9B12-4659D8949201")
        XCTAssertNotEqual(imported.id, imported.catalogueCameraID)
        XCTAssertEqual(imported.defaultDirection, .horizontal)
        XCTAssertEqual(imported.catalogueSnapshots.count, 1)
        let preserved = try XCTUnwrap(JSONSerialization.jsonObject(with: imported.catalogueSnapshots[0].profileJSON) as? [String: Any])
        XCTAssertEqual((preserved["shutter"] as? [String: Any])?["construction"] as? String, "Flexible curtains")
        try ShutterTesterExchange.validateResults(fixture("test-results-v1.json"))
        // Optional reverse-direction artifact from a separate receiving-application harness.
        if let path = ProcessInfo.processInfo.environment["SHUTTER_TESTER_CATALOGUE_INPUT"] {
            let actual = try Data(contentsOf: URL(fileURLWithPath: path))
            let actualReview = try ShutterTesterExchange.reviewCatalogue(actual, cameras: [])
            let actualCameras = try ShutterTesterExchange.applyCatalogue(actualReview, cameras: [])
            XCTAssertEqual(actualCameras.count, actualReview.rows.count)
            XCTAssertEqual(actualCameras.first?.catalogueID, actualReview.catalogueID)
            XCTAssertEqual(try ShutterTesterExchange.reviewCatalogue(actual, cameras: actualCameras).rows.first?.disposition, .alreadyImported)
        }
    }

    func testRevisionReviewIsAtomicAndRetainsLocalDetailsAndPriorSnapshots() throws {
        var camera = try importedCamera()
        let id = camera.id
        camera.notes = "Private ownership note"
        camera.purchasePrice = "125"
        camera.photoFilename = "camera-photo.jpg"
        let second = try changedProfile(fixture()) { $0["revision"] = 2; $0["name"] = "Updated catalogue name" }
        let review = try ShutterTesterExchange.reviewCatalogue(second, cameras: [camera])
        XCTAssertEqual(review.rows.first?.disposition, .newRevision)
        let updated = try XCTUnwrap(ShutterTesterExchange.applyCatalogue(review, cameras: [camera]).first)
        XCTAssertEqual(updated.id, id)
        XCTAssertEqual(updated.name, "Updated catalogue name")
        XCTAssertEqual(updated.notes, camera.notes)
        XCTAssertEqual(updated.purchasePrice, camera.purchasePrice)
        XCTAssertEqual(updated.photoFilename, camera.photoFilename)
        XCTAssertEqual(updated.catalogueSnapshots.map(\.revision), [1, 2])
        XCTAssertEqual(try ShutterTesterExchange.reviewCatalogue(second, cameras: [updated]).rows.first?.disposition, .alreadyImported)
        XCTAssertEqual(try ShutterTesterExchange.reviewCatalogue(fixture(), cameras: [updated]).rows.first?.disposition, .alreadyImported)
        var latestOnly = updated
        latestOnly.catalogueSnapshots.removeFirst()
        XCTAssertEqual(try ShutterTesterExchange.reviewCatalogue(fixture(), cameras: [latestOnly]).rows.first?.disposition, .olderRevision)
        let conflict = try changedProfile(second) { $0["name"] = "Same revision, different profile" }
        let conflictReview = try ShutterTesterExchange.reviewCatalogue(conflict, cameras: [updated])
        XCTAssertFalse(conflictReview.canApply)
        XCTAssertThrowsError(try ShutterTesterExchange.applyCatalogue(conflictReview, cameras: [updated]))
        XCTAssertEqual(updated.name, "Updated catalogue name")
    }

    func testApplyRequiresFreshReviewAfterLocalEditsOrInterveningImport() throws {
        var camera = try importedCamera()
        let second = try changedProfile(fixture()) { $0["revision"] = 2 }
        let review = try ShutterTesterExchange.reviewCatalogue(second, cameras: [camera])
        camera.notes = "Edited after review"
        XCTAssertThrowsError(try ShutterTesterExchange.applyCatalogue(review, cameras: [camera]))
        let emptyReview = try ShutterTesterExchange.reviewCatalogue(fixture(), cameras: [])
        XCTAssertThrowsError(try ShutterTesterExchange.applyCatalogue(emptyReview, cameras: [camera]))
    }

    func testCanonicalUUIDCaseAndFormattingAreDuplicatesButNamespacesStaySeparate() throws {
        let camera = try importedCamera()
        let lowercased = try changedProfile(fixture()) { $0["id"] = ($0["id"] as! String).lowercased() }
        let review = try ShutterTesterExchange.reviewCatalogue(lowercased, cameras: [camera])
        XCTAssertEqual(review.rows.first?.disposition, .alreadyImported)
        XCTAssertFalse(review.hasChanges)
        XCTAssertEqual(try ShutterTesterExchange.applyCatalogue(review, cameras: [camera]).first?.catalogueSnapshots.count, 1)
        let otherCatalogue = try changed(fixture()) { root in
            var source = root["source"] as! [String: Any]
            source["libraryID"] = UUID().uuidString; root["source"] = source
        }
        XCTAssertEqual(try ShutterTesterExchange.reviewCatalogue(otherCatalogue, cameras: [camera]).rows.first?.disposition, .newCamera)
    }

    func testCatalogueRejectsUnsupportedNullAmbiguousAndOversizedValues() throws {
        let original = try fixture()
        let invalid: [Data] = try [
            changed(original) { $0["version"] = 2 },
            changed(original) { $0["version"] = true },
            changed(original) { $0["requiredCapabilities"] = ["future-capability"] },
            changed(original) { $0["requiredCapabilities"] = ["shutter-timing-v1", "shutter-timing-v1"] },
            changed(original) { $0["notes"] = "unsupported" },
            changed(original) { $0["cameras"] = [] },
            changed(original) { $0["cameras"] = Array(repeating: ($0["cameras"] as! [Any])[0], count: 2) },
            changedProfile(original) { $0["serial"] = NSNull() },
            changedProfile(original) { $0["revision"] = 0 },
            changedProfile(original) { $0["revision"] = 1.5 },
            changedProfile(original) { $0["id"] = "8146604538034C949B124659D8949201" },
            changedProfile(original) { $0["name"] = " \n " },
            changedProfile(original) { $0["name"] = String(repeating: "é", count: 257) },
            changedProfile(original) { $0["manufacturer"] = String(repeating: "a", count: 65_537) },
            changedProfile(original) { profile in
                var camera = profile["camera"] as! [String: Any]; camera["undocumented"] = "x"; profile["camera"] = camera
            },
            changedProfile(original) { $0.removeValue(forKey: "mount") }
        ]
        for (index, data) in invalid.enumerated() { XCTAssertThrowsError(try ShutterTesterExchange.reviewCatalogue(data, cameras: []), "Invalid case \(index)") }
        let fractionalRevision = String(decoding: original, as: UTF8.self).replacingOccurrences(of: "\"revision\": 1", with: "\"revision\": 1.00000000000000000001")
        XCTAssertThrowsError(try ShutterTesterExchange.reviewCatalogue(Data(fractionalRevision.utf8), cameras: []))
        XCTAssertThrowsError(try ShutterTesterExchange.reviewCatalogue(Data(), cameras: []))
        XCTAssertThrowsError(try ShutterTesterExchange.reviewCatalogue(Data([0xff]), cameras: []))
        XCTAssertThrowsError(try ShutterTesterExchange.reviewCatalogue(Data(repeating: 32, count: 8 * 1024 * 1024 + 1), cameras: []))
        XCTAssertThrowsError(try ShutterTesterExchange.reviewCatalogue(original + Data("true".utf8), cameras: []))
        XCTAssertThrowsError(try ShutterTesterExchange.reviewCatalogue(Data("{\"format\":1,\"\\u0066ormat\":2}".utf8), cameras: []))
        XCTAssertThrowsError(try ShutterTesterExchange.reviewCatalogue(Data((String(repeating: "[", count: 34) + "1" + String(repeating: "]", count: 34)).utf8), cameras: []))
        XCTAssertThrowsError(try ShutterTesterExchange.reviewCatalogue(Data("{\"value\":1e999}".utf8), cameras: []))
    }

    func testTimestampsRequireCalendarValiditySecondsAndTimezone() throws {
        for value in ["2026-02-29T12:00:00Z", "2024-02-30T12:00:00Z", "2026-09-27T24:00:00Z", "2026-09-27T12:60:00Z", "2026-09-27T12:00:60Z", "2026-09-27T12:00:00", "2026-09-27T12:00:00+24:00", "2026-09-27T12:00:00+10:60"] {
            let data = try changed(fixture()) { $0["createdAt"] = value }
            XCTAssertThrowsError(try ShutterTesterExchange.reviewCatalogue(data, cameras: []), value)
        }
        for value in ["2024-02-29T12:00:00.123456789Z", "2026-09-27T12:00:00+10:00"] {
            let data = try changed(fixture()) { $0["createdAt"] = value }
            XCTAssertNoThrow(try ShutterTesterExchange.reviewCatalogue(data, cameras: []), value)
        }
    }

    func testResultsExportPreservesIDsRevisionSecondsAndReadingProvenance() throws {
        var run = try session(2)
        run.records[0].isExcluded = true
        run.revision = 7
        let producer = UUID()
        let data = try ShutterTesterExchange.exportResults(producerLibraryID: producer, session: run)
        try ShutterTesterExchange.validateResults(data)
        // Optional CI artifact for independent schema / receiving-application checks.
        if let path = ProcessInfo.processInfo.environment["SHUTTER_TESTER_INTEROP_OUTPUT"] {
            try data.write(to: URL(fileURLWithPath: path), options: .atomic)
        }
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let source = root["source"] as! [String: Any]
        let test = (root["tests"] as! [[String: Any]])[0]
        let measurements = test["measurements"] as! [[String: Any]]
        XCTAssertEqual(source["libraryID"] as? String, producer.uuidString.lowercased())
        XCTAssertEqual(root["cameraCatalogueID"] as? String, run.cameraSnapshot?.catalogueID?.uuidString.lowercased())
        XCTAssertEqual(test["cameraID"] as? String, run.cameraSnapshot?.catalogueCameraID?.uuidString.lowercased())
        XCTAssertEqual(test["id"] as? String, run.id.uuidString.lowercased())
        XCTAssertEqual(test["revision"] as? Int, 7)
        XCTAssertEqual(measurements.count, 5)
        XCTAssertTrue(measurements.allSatisfy { $0["unit"] as? String == "s" && $0["sampleIndex"] as? Int == 2 })
        XCTAssertEqual(measurements[0]["value"] as! Double, run.records[1].result.center.durationMS! / 1_000, accuracy: 1e-12)
        XCTAssertEqual(measurements[0]["nominalValue"] as! Double, 0.008, accuracy: 1e-12)
        XCTAssertEqual(measurements[3]["value"] as! Double, run.records[1].result.openingTravelMS! / 1_000, accuracy: 1e-12)
        XCTAssertNotEqual(measurements[3]["value"] as! Double, run.records[1].result.openingFullFrameMS! / 1_000)
        XCTAssertTrue((test["notes"] as! String).contains(run.records[1].id.uuidString.lowercased()))
        XCTAssertTrue((test["notes"] as! String).contains("omitted 1"))
        XCTAssertNil(test["rawLine"])
        XCTAssertNil(root["photos"])
    }

    func testExplicitAssignmentIsAuditedAndRepeatedExportsKeepCanonicalRunStable() throws {
        var run = try session()
        run.title = nil
        run.cameraName = "Original unassigned camera name"
        run.cameraAssignedAt = Date(timeIntervalSince1970: 1_800_000_000)
        let producer = UUID()
        let first = try ShutterTesterExchange.exportResults(producerLibraryID: producer, session: run, createdAt: Date(timeIntervalSince1970: 1_800_000_010))
        let second = try ShutterTesterExchange.exportResults(producerLibraryID: producer, session: run, createdAt: Date(timeIntervalSince1970: 1_800_000_020))
        func test(_ data: Data) throws -> [String: Any] {
            let envelope = try JSONSerialization.jsonObject(with: data) as! [String: Any]
            return (envelope["tests"] as! [[String: Any]])[0]
        }
        let firstTest = try test(first)
        XCTAssertEqual(NSDictionary(dictionary: firstTest), NSDictionary(dictionary: try test(second)))
        XCTAssertTrue((firstTest["notes"] as! String).contains("Camera association explicitly assigned on"))
        XCTAssertTrue((firstTest["notes"] as! String).contains("originally recorded camera name: Original unassigned camera name"))
        XCTAssertTrue((firstTest["title"] as! String).hasPrefix("Shutter test · "))
    }

    func testDemoUnlinkedEmptyAndOversizedResultExportsAreBlocked() throws {
        var run = try session()
        run.demo = true
        XCTAssertThrowsError(try ShutterTesterExchange.exportResults(producerLibraryID: UUID(), session: run))
        run = try session(); run.records[0].isDemo = true
        XCTAssertThrowsError(try ShutterTesterExchange.exportResults(producerLibraryID: UUID(), session: run))
        run = try session(); run.cameraSnapshot = nil
        XCTAssertThrowsError(try ShutterTesterExchange.exportResults(producerLibraryID: UUID(), session: run))
        run = try session(); run.records[0].isExcluded = true
        XCTAssertThrowsError(try ShutterTesterExchange.exportResults(producerLibraryID: UUID(), session: run))
        let many = try session(103)
        XCTAssertThrowsError(try ShutterTesterExchange.exportResults(producerLibraryID: UUID(), session: many)) { error in
            XCTAssertTrue(error.localizedDescription.contains("512"))
        }
    }

    func testResultsRejectUnitsBooleansNonpositiveAndUnsupportedMeasurements() throws {
        let original = try fixture("test-results-v1.json")
        func alteredMeasurement(_ change: (inout [String: Any]) -> Void) throws -> Data {
            try changed(original) { root in
                var tests = root["tests"] as! [[String: Any]]
                var measures = tests[0]["measurements"] as! [[String: Any]]
                change(&measures[0]); tests[0]["measurements"] = measures; root["tests"] = tests
            }
        }
        let invalid = try [alteredMeasurement { $0["unit"] = "ms" }, alteredMeasurement { $0["value"] = true },
                           alteredMeasurement { $0["value"] = 0 }, alteredMeasurement { $0["value"] = -1 },
                           alteredMeasurement { $0["value"] = 1e13 }, alteredMeasurement { $0["nominalValue"] = 0 },
                           alteredMeasurement { $0["value"] = "0.008" }, alteredMeasurement { $0["sampleIndex"] = 0 },
                           alteredMeasurement { $0["quantity"] = "exposureError" }, alteredMeasurement { $0["quality"] = "complete" }]
        for data in invalid { XCTAssertThrowsError(try ShutterTesterExchange.validateResults(data)) }
        let signedFlash = try alteredMeasurement { $0["quantity"] = "flashDelay"; $0["value"] = -0.01 }
        XCTAssertNoThrow(try ShutterTesterExchange.validateResults(signedFlash))
    }
}
