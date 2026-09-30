import XCTest
import DeviceTransport
@testable import ShutterLover

final class TesterPositioningTests: XCTestCase {
    private func session(camera: CameraProfile? = nil, tester: OwnedTester? = nil) -> CaptureSession {
        var result = CaptureSession(cameraName: camera?.name ?? "Unassigned camera", demo: false)
        result.cameraID = camera?.id
        result.cameraSnapshot = camera.map(CameraIdentitySnapshot.init(camera:))
        result.tester = tester.map { TesterSnapshot(tester: $0) }
        return result
    }

    @MainActor
    private func withModel(cameras: [CameraProfile], sessions: [CaptureSession], testers: [OwnedTester],
                           _ body: (AppModel) throws -> Void) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("tester-positioning-\(UUID().uuidString)")
        let suite = "tester-positioning-preferences-\(UUID().uuidString)"
        let preferences = try XCTUnwrap(UserDefaults(suiteName: suite))
        let store = SessionStore(directory: directory)
        try store.saveLibrary(CameraLibraryArchive(cameras: cameras, sessions: sessions, ownedTesters: testers))
        let model = AppModel(store: store, startDiscovery: false, preferences: preferences)
        defer {
            model.shutDown()
            preferences.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: directory)
        }
        try body(model)
    }

    private func ready(_ guidance: TesterPositioningGuidance, file: StaticString = #filePath, line: UInt = #line) throws -> TesterPositioningRecommendation {
        let recommendation: TesterPositioningRecommendation?
        if case .ready(let result) = guidance { recommendation = result }
        else { recommendation = nil }
        return try XCTUnwrap(recommendation, "Expected positioning guidance, received \(guidance)", file: file, line: line)
    }

    private func unavailable(_ guidance: TesterPositioningGuidance, containing phrase: String,
                             file: StaticString = #filePath, line: UInt = #line) {
        guard case .unavailable(let message) = guidance else {
            XCTFail("Expected unavailable guidance, received \(guidance)", file: file, line: line)
            return
        }
        XCTAssertTrue(message.localizedCaseInsensitiveContains(phrase), "Expected ‘\(phrase)’ in ‘\(message)’", file: file, line: line)
    }

    func testLEDToMountDistanceSubtractsFlangeFromCalibrationAndRejectsInvalidGeometry() {
        XCTAssertEqual(TesterPositioningRecommendation.ledToMountDistance(calibrationMM: 250, flangeMM: 42), 208)
        XCTAssertEqual(TesterPositioningRecommendation.ledToMountDistance(calibrationMM: 250, flangeMM: 46.5), 203.5)
        for invalid in [0.0, -1, Double.nan, Double.infinity, -Double.infinity] {
            XCTAssertNil(TesterPositioningRecommendation.ledToMountDistance(calibrationMM: invalid, flangeMM: 42))
            XCTAssertNil(TesterPositioningRecommendation.ledToMountDistance(calibrationMM: 250, flangeMM: invalid))
        }
        XCTAssertNil(TesterPositioningRecommendation.ledToMountDistance(calibrationMM: 42, flangeMM: 42))
        XCTAssertNil(TesterPositioningRecommendation.ledToMountDistance(calibrationMM: 40, flangeMM: 42))
        XCTAssertNil(TesterPositioningRecommendation.ledToMountDistance(calibrationMM: 10_001, flangeMM: 42))
        XCTAssertNil(TesterPositioningRecommendation.ledToMountDistance(calibrationMM: 2_000, flangeMM: 1_001))
    }

    @MainActor
    func testKnownTesterAndCameraMountProduceGuidanceAndOverrideUpdatesNextRecommendation() throws {
        let camera = CameraProfile(name: "Canon body", mount: "Canon FD")
        let tester = OwnedTester(name: "Calibrated unit", model: .shutterLover, calibratedOptimalDistanceMM: 250)
        let test = session(camera: camera, tester: tester)
        try withModel(cameras: [camera], sessions: [test], testers: [tester]) { model in
            let original = try ready(model.positioningGuidance(for: test))
            XCTAssertEqual(original.testerName, TesterSnapshot(tester: tester).displayName)
            XCTAssertEqual(original.cameraName, camera.name)
            XCTAssertEqual(original.mountName, "Canon FD")
            XCTAssertEqual(original.calibrationDistanceMM, 250)
            XCTAssertEqual(original.flangeDistanceMM, 42)
            XCTAssertEqual(original.ledToMountDistanceMM, 208)
            XCTAssertFalse(original.usesCustomDistance)

            let row = try XCTUnwrap(model.flangeMatches(camera.mount).first)
            XCTAssertTrue(model.saveFlangeDistance(mountID: row.id, distanceMM: 43))
            let updated = try ready(model.positioningGuidance(for: test))
            XCTAssertEqual(updated.flangeDistanceMM, 43)
            XCTAssertEqual(updated.ledToMountDistanceMM, 207)
            XCTAssertTrue(updated.usesCustomDistance)
            XCTAssertEqual(original.ledToMountDistanceMM, 208)
            XCTAssertEqual(model.sessions.first?.tester, test.tester)
        }
    }

    @MainActor
    func testUnconnectedGuidanceUsesCurrentOwnedCalibrationWithoutChangingSessionSnapshot() throws {
        let camera = CameraProfile(name: "Canon body", mount: "Canon FD")
        var tester = OwnedTester(name: "My unit", model: .shutterLover, calibratedOptimalDistanceMM: 200)
        let test = session(camera: camera, tester: tester)
        tester.calibratedOptimalDistanceMM = 250
        try withModel(cameras: [camera], sessions: [test], testers: [tester]) { model in
            let guidance = try ready(model.positioningGuidance(for: test))
            XCTAssertEqual(guidance.calibrationDistanceMM, 250)
            XCTAssertEqual(guidance.ledToMountDistanceMM, 208)
            XCTAssertEqual(model.sessions.first?.tester?.calibratedOptimalDistanceMM, 200)
        }
    }

    @MainActor
    func testMissingCalibrationAndCameraGiveActionableGuidanceWithoutPosition() throws {
        let camera = CameraProfile(name: "Canon body", mount: "Canon FD")
        let uncalibrated = OwnedTester(name: "Uncalibrated unit", model: .shutterLover)
        let calibrated = OwnedTester(name: "Calibrated unit", model: .shutterLover, calibratedOptimalDistanceMM: 250)
        let noCalibration = session(camera: camera, tester: uncalibrated)
        let noCamera = session(tester: calibrated)
        try withModel(cameras: [camera], sessions: [noCalibration, noCamera], testers: [uncalibrated, calibrated]) { model in
            unavailable(model.positioningGuidance(for: noCalibration), containing: "Add the calibrated")
            unavailable(model.positioningGuidance(for: noCamera), containing: "Assign this test to a camera")
        }
    }

    @MainActor
    func testUnknownEmptyAndAmbiguousMountsNeverInventPosition() throws {
        let tester = OwnedTester(name: "My unit", model: .shutterLover, calibratedOptimalDistanceMM: 250)
        let unknown = CameraProfile(name: "Unknown camera", mount: "Some unknown mount")
        let empty = CameraProfile(name: "Unset camera")
        let ambiguous = CameraProfile(name: "M39 camera", mount: "M39")
        let unknownTest = session(camera: unknown, tester: tester)
        let emptyTest = session(camera: empty, tester: tester)
        let ambiguousTest = session(camera: ambiguous, tester: tester)
        try withModel(cameras: [unknown, empty, ambiguous], sessions: [unknownTest, emptyTest, ambiguousTest], testers: [tester]) { model in
            unavailable(model.positioningGuidance(for: unknownTest), containing: "No flange distance")
            unavailable(model.positioningGuidance(for: emptyTest), containing: "Set the lens mount")
            XCTAssertGreaterThan(model.flangeMatches("M39").count, 1)
            unavailable(model.positioningGuidance(for: ambiguousTest), containing: "more than one mount")
        }
    }

    @MainActor
    func testRemovedUnidentifiedAndBabyTestersDoNotProvideShutterLoverPositioning() throws {
        let camera = CameraProfile(name: "Canon body", mount: "Canon FD")
        let removed = OwnedTester(name: "Removed unit", model: .shutterLover, calibratedOptimalDistanceMM: 250)
        let baby = OwnedTester(name: "Baby unit", model: .babyShutterTesterMkII)
        let removedTest = session(camera: camera, tester: removed)
        let babyTest = session(camera: camera, tester: baby)
        var unidentifiedTest = session(camera: camera)
        unidentifiedTest.tester = TesterSnapshot(model: .shutterLover)
        unidentifiedTest.tester?.calibratedOptimalDistanceMM = 250
        try withModel(cameras: [camera], sessions: [removedTest, babyTest, unidentifiedTest], testers: [baby]) { model in
            for test in [removedTest, babyTest, unidentifiedTest] {
                unavailable(model.positioningGuidance(for: test), containing: "saved Shutter Lover")
            }
        }
    }

    @MainActor
    func testActiveCaptureUsesConnectionSnapshotAndCameraWhenBrowsingOtherCameraOrTest() throws {
        let recordingCamera = CameraProfile(name: "Recording Canon", mount: "Canon FD")
        let browsingCamera = CameraProfile(name: "Browsing Nikon", mount: "Nikon F")
        var connectedTester = OwnedTester(name: "Connected unit", model: .shutterLover, calibratedOptimalDistanceMM: 200)
        let recordingTest = session(camera: recordingCamera, tester: connectedTester)
        connectedTester.calibratedOptimalDistanceMM = 250
        let connectionSnapshot = TesterSnapshot(tester: connectedTester)
        // A current inventory value must not replace the snapshot frozen at connection.
        connectedTester.calibratedOptimalDistanceMM = 300
        let browsingTester = OwnedTester(name: "Other unit", model: .shutterLover, calibratedOptimalDistanceMM: 400)
        let browsingTest = session(camera: browsingCamera, tester: browsingTester)
        try withModel(cameras: [recordingCamera, browsingCamera], sessions: [recordingTest, browsingTest], testers: [connectedTester, browsingTester]) { model in
            model.activeCaptureSessionID = recordingTest.id
            model.connectionTesterSnapshot = connectionSnapshot
            model.isConnected = true
            model.selectSession(recordingTest.id)
            model.selectCamera(browsingCamera.id)
            let whileBrowsingCamera = try ready(model.connectionPositioningGuidance)
            XCTAssertEqual(whileBrowsingCamera.cameraName, recordingCamera.name)
            XCTAssertEqual(whileBrowsingCamera.testerName, connectionSnapshot.displayName)
            XCTAssertEqual(whileBrowsingCamera.calibrationDistanceMM, 250)
            XCTAssertEqual(whileBrowsingCamera.ledToMountDistanceMM, 208)

            model.selectSession(browsingTest.id)
            XCTAssertEqual(model.currentSession?.id, browsingTest.id)
            XCTAssertEqual(model.activeCaptureSessionID, recordingTest.id)
            XCTAssertEqual(try ready(model.connectionPositioningGuidance), whileBrowsingCamera)
            XCTAssertEqual(try ready(model.positioningGuidance(for: recordingTest)), whileBrowsingCamera)
            XCTAssertEqual(try ready(model.positioningGuidance(for: browsingTest)).ledToMountDistanceMM, 353.5)
        }
    }

    @MainActor
    func testRecognisedUSBPreviewUsesVisibleCameraBeforeConnecting() throws {
        let oldCamera = CameraProfile(name: "Old Canon", mount: "Canon FD")
        let visibleCamera = CameraProfile(name: "Visible Nikon", mount: "Nikon F")
        let identity = TesterUSBIdentity(vendorID: 0x2341, productID: 0x0043, serialNumber: "KNOWN-UNIT")
        let tester = OwnedTester(name: "Known USB unit", model: .shutterLover, calibratedOptimalDistanceMM: 250, usbBinding: identity)
        let oldTest = session(camera: oldCamera, tester: tester)
        let device = SerialDevice(name: "Known", path: "/dev/cu.synthetic-positioning", usbVendorID: identity.vendorID,
                                  usbProductID: identity.productID, usbSerialNumber: identity.serialNumber)
        try withModel(cameras: [oldCamera, visibleCamera], sessions: [oldTest], testers: [tester]) { model in
            model.devices = [device]
            model.selectedPortPath = device.path
            model.selectSession(oldTest.id)
            model.selectCamera(visibleCamera.id)
            let preview = try ready(model.connectionPositioningGuidance)
            XCTAssertEqual(preview.cameraName, visibleCamera.name)
            XCTAssertEqual(preview.calibrationDistanceMM, 250)
            XCTAssertEqual(preview.ledToMountDistanceMM, 203.5)
            XCTAssertNil(model.activeCaptureSessionID)
            XCTAssertFalse(model.isConnected)
            XCTAssertFalse(model.isConnecting)
        }
    }

    @MainActor
    func testPrepareConnectionCreatesTestForVisibleCameraInsteadOfStaleOtherCamera() throws {
        let oldCamera = CameraProfile(name: "Old Canon", mount: "Canon FD")
        let visibleCamera = CameraProfile(name: "Visible Nikon", mount: "Nikon F")
        let oldTest = session(camera: oldCamera)
        try withModel(cameras: [oldCamera, visibleCamera], sessions: [oldTest], testers: []) { model in
            model.selectSession(oldTest.id)
            model.selectCamera(visibleCamera.id)
            XCTAssertEqual(model.currentSession?.cameraID, oldCamera.id)
            XCTAssertTrue(model.prepareCameraForConnection())
            let prepared = try XCTUnwrap(model.currentSession)
            XCTAssertEqual(prepared.cameraID, visibleCamera.id)
            XCTAssertNotEqual(prepared.id, oldTest.id)
            XCTAssertEqual(model.sessions.count, 2)
            XCTAssertFalse(model.showCameraLibrary)
            XCTAssertTrue(model.canRecordUSB(in: prepared))
            XCTAssertNil(model.activeCaptureSessionID)
            XCTAssertFalse(model.isConnecting)
            XCTAssertFalse(model.isConnected)
            XCTAssertEqual(try model.store.loadLibrary().sessions.first?.cameraID, visibleCamera.id)
        }
    }

    @MainActor
    func testPrepareConnectionReusesSuitableCameraTestAndReplacesManualTest() throws {
        let camera = CameraProfile(name: "Canon body", mount: "Canon FD")
        let usbTest = session(camera: camera)
        let baby = OwnedTester(name: "Baby", model: .babyShutterTesterMkII)
        let babyTest = session(camera: camera, tester: baby)
        try withModel(cameras: [camera], sessions: [usbTest, babyTest], testers: [baby]) { model in
            model.selectSession(usbTest.id)
            model.selectCamera(camera.id)
            XCTAssertTrue(model.prepareCameraForConnection())
            XCTAssertEqual(model.currentSession?.id, usbTest.id)
            XCTAssertEqual(model.sessions.count, 2)

            model.selectSession(babyTest.id)
            model.selectCamera(camera.id)
            XCTAssertTrue(model.prepareCameraForConnection())
            let prepared = try XCTUnwrap(model.currentSession)
            XCTAssertNotEqual(prepared.id, babyTest.id)
            XCTAssertEqual(prepared.cameraID, camera.id)
            XCTAssertTrue(model.canRecordUSB(in: prepared))
            XCTAssertEqual(model.sessions.count, 3)
            XCTAssertEqual(model.sessions.first(where: { $0.id == babyTest.id })?.tester, babyTest.tester)
        }
    }
}
