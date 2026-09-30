import Foundation

struct TesterPositioningRecommendation: Equatable {
    let testerName: String
    let cameraName: String
    let mountName: String
    let calibrationDistanceMM: Double
    let flangeDistanceMM: Double
    let ledToMountDistanceMM: Double
    let usesCustomDistance: Bool

    /// Assumes the sensor is at the film plane and the bare camera flange is
    /// the physical reference. The result is guidance, not a measured setup.
    static func ledToMountDistance(calibrationMM: Double, flangeMM: Double) -> Double? {
        guard calibrationMM.isFinite, flangeMM.isFinite,
              calibrationMM > 0, calibrationMM <= 10_000,
              flangeMM > 0, flangeMM <= 1_000 else { return nil }
        let result = calibrationMM - flangeMM
        return result > 0 ? result : nil
    }
}

enum TesterPositioningGuidance: Equatable {
    case ready(TesterPositioningRecommendation)
    case unavailable(String)
}

@MainActor
extension AppModel {
    /// Browsing another camera must not change the active recording target.
    /// Before a new connection, the visible camera page does define the target.
    func prepareCameraForConnection() -> Bool {
        guard showCameraLibrary, let camera = selectedCamera else { return true }
        if let session = currentSession, session.cameraID == camera.id, canRecordUSB(in: session) {
            selectSession(session.id)
        } else {
            newCameraTest(camera.id)
        }
        return currentSession?.cameraID == camera.id && currentSession.map(canRecordUSB(in:)) == true && !showCameraLibrary
    }

    func positioningTester(for session: CaptureSession) -> TesterSnapshot? {
        if activeCaptureSessionID == session.id { return connectionTesterSnapshot }
        if let id = session.tester?.id, let owned = ownedTesters.first(where: { $0.id == id }) {
            return TesterSnapshot(tester: owned)
        }
        return nil
    }

    func positioningGuidance(for session: CaptureSession) -> TesterPositioningGuidance {
        guard !session.demo else { return .unavailable("Positioning guidance is available for a real Shutter Lover test.") }
        let camera = session.cameraID.flatMap { id in cameras.first { $0.id == id } }
        return positioningGuidance(tester: positioningTester(for: session), camera: camera)
    }

    /// The connection panel always describes the actual recording camera, even
    /// when the user is inspecting another camera or an older test.
    var connectionPositioningGuidance: TesterPositioningGuidance {
        if let active = activeCaptureSession { return positioningGuidance(for: active) }
        let camera = showCameraLibrary ? selectedCamera : currentSession?.cameraID.flatMap { id in cameras.first { $0.id == id } }
        let tester = selectedSerialDevice.flatMap { device -> TesterSnapshot? in
            guard connectionIdentityProblem == nil else { return nil }
            return connectionTester(for: device)
        }
        return positioningGuidance(tester: tester, camera: camera)
    }

    private func positioningGuidance(tester: TesterSnapshot?, camera: CameraProfile?) -> TesterPositioningGuidance {
        guard let tester, tester.id != nil, tester.model == .shutterLover else {
            return .unavailable("Select your saved Shutter Lover in My testers, or connect its recognised USB device, to use its calibration distance.")
        }
        guard let calibrated = tester.calibratedOptimalDistanceMM else {
            return .unavailable("Add the calibrated LED-to-sensor distance for \(tester.displayName) in My testers.")
        }
        guard let camera else {
            return .unavailable("Assign this test to a camera and set its lens mount to calculate the LED-to-mount distance. Calibration: \(Self.positioningNumber(calibrated)) mm to the sensor.")
        }
        guard !flangeSettingsLoadFailed else {
            return .unavailable("Flange-distance settings could not be read. Open Settings to review or restore them before calculating a position.")
        }
        let mount = camera.mount.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !mount.isEmpty else {
            return .unavailable("Set the lens mount in \(camera.name)’s camera details to calculate the positioning distance.")
        }
        let matches = flangeMatches(mount)
        guard matches.count == 1, let entry = matches.first else {
            if matches.count > 1 {
                return .unavailable("“\(mount)” matches more than one mount. Choose the exact mount in \(camera.name)’s camera details.")
            }
            return .unavailable("No flange distance is saved for “\(mount)”. Choose a listed mount in the camera details, or add it in Settings.")
        }
        guard let spacing = TesterPositioningRecommendation.ledToMountDistance(calibrationMM: calibrated, flangeMM: entry.distanceMM) else {
            return .unavailable("The calibration distance (\(Self.positioningNumber(calibrated)) mm) must exceed the flange distance (\(Self.positioningNumber(entry.distanceMM)) mm). Check both values before positioning the tester.")
        }
        return .ready(TesterPositioningRecommendation(testerName: tester.displayName, cameraName: camera.name,
            mountName: entry.name, calibrationDistanceMM: calibrated, flangeDistanceMM: entry.distanceMM,
            ledToMountDistanceMM: spacing, usesCustomDistance: entry.isOverride || entry.defaultDistanceMM == nil))
    }

    static func positioningNumber(_ number: Double) -> String {
        number.formatted(.number.grouping(.never).precision(.fractionLength(0...3)))
    }
}
