import Foundation
import DeviceTransport
import MeasurementCore

extension SerialDevice {
    var testerUSBIdentity: TesterUSBIdentity? {
        guard stableIdentityKey != nil, let vendor = usbVendorID, let product = usbProductID,
              let serial = usbSerialNumber?.trimmingCharacters(in: .whitespacesAndNewlines) else { return nil }
        return TesterUSBIdentity(vendorID: vendor, productID: product, serialNumber: serial)
    }
}

@MainActor
extension AppModel {
    var selectedSerialDevice: SerialDevice? { devices.first { $0.path == selectedPortPath } }

    func matchedOwnedTester(for device: SerialDevice) -> OwnedTester? {
        guard let key = device.stableIdentityKey,
              devices.filter({ $0.stableIdentityKey == key }).count <= 1 else { return nil }
        let matches = ownedTesters.filter { $0.usbBinding?.stableIdentityKey == key }
        return matches.count == 1 ? matches[0] : nil
    }

    func connectionTester(for device: SerialDevice) -> TesterSnapshot {
        let profile = selectedConnectionTesterID.flatMap { id in ownedTesters.first { $0.id == id } }
            ?? matchedOwnedTester(for: device)
        if let profile {
            return TesterSnapshot(tester: profile, usbIdentity: device.testerUSBIdentity, devicePath: device.path)
        }
        return TesterSnapshot(model: .shutterLover, usbIdentity: device.testerUSBIdentity, devicePath: device.path)
    }

    var connectionIdentityProblem: String? {
        guard let device = selectedSerialDevice else { return nil }
        if let key = device.stableIdentityKey, devices.filter({ $0.stableIdentityKey == key }).count > 1 {
            return "Several connected devices report the same USB identity. Disconnect the duplicate before associating or recording a tester."
        }
        if let id = selectedConnectionTesterID, let profile = ownedTesters.first(where: { $0.id == id }),
           let binding = profile.usbBinding, binding.stableIdentityKey != device.stableIdentityKey {
            return "This port does not match the USB identity saved for \(profile.displayName). Choose its matching port or update the association in My testers."
        }
        return nil
    }

    @discardableResult
    func saveOwnedTester(_ tester: OwnedTester) -> Bool {
        var edited = tester
        edited.name = edited.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if edited.name.isEmpty { edited.name = edited.model.displayName }
        if let previous = ownedTesters.first(where: { $0.id == tester.id }), previous.model != tester.model {
            errorMessage = "A saved tester's model cannot be changed. Add a separate tester for another physical unit."
            return false
        }
        if activeCaptureSessionID != nil && connectionTesterSnapshot?.id == tester.id {
            errorMessage = "Disconnect the tester before changing its saved details."
            return false
        }
        var candidate = ownedTesters
        if let index = candidate.firstIndex(where: { $0.id == edited.id }) { candidate[index] = edited }
        else { candidate.append(edited) }
        do {
            try commitLibrary(cameras: cameras, sessions: sessions, ownedTesters: candidate)
            return true
        } catch { errorMessage = "Tester could not be saved: \(error.localizedDescription)"; return false }
    }

    @discardableResult
    func removeOwnedTester(_ id: UUID) -> Bool {
        guard activeCaptureSessionID == nil || connectionTesterSnapshot?.id != id else {
            errorMessage = "Disconnect this tester before removing it from My testers."
            return false
        }
        do {
            try commitLibrary(cameras: cameras, sessions: sessions, ownedTesters: ownedTesters.filter { $0.id != id })
            if selectedConnectionTesterID == id { selectedConnectionTesterID = nil }
            return true
        } catch { errorMessage = "Tester could not be removed: \(error.localizedDescription)"; return false }
    }

    func canRecordUSB(in session: CaptureSession) -> Bool {
        !session.isTrashed && !session.demo && session.tester?.model.supportsManualEntry != true && !session.records.contains(where: \.isManual)
    }

    func newManualSession(cameraID: UUID? = nil) {
        let camera = cameras.first { $0.id == cameraID }
        var session = CaptureSession(cameraName: camera?.name ?? "Untitled camera", demo: false)
        session.tester = TesterSnapshot(model: .babyShutterTesterMkII)
        if let camera {
            session.cameraID = camera.id
            session.cameraSnapshot = CameraIdentitySnapshot(camera: camera)
            session.plannedSpeeds = camera.plannedSpeeds
            session.title = "Baby tester test"
        }
        do {
            try commitLibrary(cameras: cameras, sessions: [session] + sessions)
            selectSession(session.id)
        } catch { errorMessage = "Manual test could not be created: \(error.localizedDescription)" }
    }

    @discardableResult
    func setSessionTester(_ sessionID: UUID, tester: TesterSnapshot) -> Bool {
        guard let index = sessions.firstIndex(where: { $0.id == sessionID && !$0.isTrashed && !$0.demo }) else { return false }
        guard activeCaptureSessionID != sessionID else {
            errorMessage = "Disconnect the tester before changing the test's instrument."
            return false
        }
        guard sessions[index].records.allSatisfy({ ($0.tester?.model ?? .shutterLover) == tester.model }) else {
            errorMessage = "Start a new test when changing tester models. Existing readings keep the tester that produced them."
            return false
        }
        guard sessions[index].tester != tester else { return true }
        var candidate = sessions
        candidate[index].tester = tester
        if tester.model.supportsManualEntry { candidate[index].autoAdvance = false; candidate[index].direction = .unknown }
        candidate[index].markUpdated()
        do {
            try commitLibrary(cameras: cameras, sessions: candidate)
            if selectedSessionID == sessionID { syncSelectedSetup() }
            return true
        } catch { errorMessage = "Tester selection could not be saved: \(error.localizedDescription)"; return false }
    }

    @discardableResult
    func addManualReading(sessionID: UUID, measurement: ManualMeasurement, tester: TesterSnapshot,
                          nominalDenominator: Double, capturedAt: Date) -> Bool {
        guard let index = sessions.firstIndex(where: { $0.id == sessionID && !$0.isTrashed && !$0.demo }),
              activeCaptureSessionID != sessionID else {
            errorMessage = "Choose a saved, non-demo test that is not receiving USB readings."
            return false
        }
        guard tester.model.supportsManualEntry,
              sessions[index].records.allSatisfy({ $0.isManual && $0.tester?.model == tester.model }) else {
            errorMessage = "Use a separate test for each tester model; Baby display readings cannot be mixed with Shutter Lover USB readings."
            return false
        }
        var snapshot = tester
        if let id = tester.id {
            guard let owned = ownedTesters.first(where: { $0.id == id && $0.model == tester.model }) else {
                errorMessage = "This owned tester has changed or been removed. Choose a tester again."
                return false
            }
            snapshot = TesterSnapshot(tester: owned)
        }
        var record = MeasurementRecord(rawLine: "", packet: nil, direction: .unknown, nominalDenominator: nominalDenominator, isDemo: false)
        record.capturedAt = capturedAt
        record.manual = measurement
        record.tester = snapshot
        record.derivedSnapshot = record.recalculatedResult
        var candidate = sessions
        candidate[index].tester = snapshot
        candidate[index].direction = .unknown
        candidate[index].nominalDenominator = nominalDenominator
        candidate[index].autoAdvance = false
        candidate[index].records.append(record)
        candidate[index].markUpdated()
        do {
            try commitLibrary(cameras: cameras, sessions: candidate)
            if selectedSessionID == sessionID {
                syncSelectedSetup()
                selectedRecordID = record.id
            }
            return true
        } catch { errorMessage = "Reading could not be added: \(error.localizedDescription)"; return false }
    }
}
