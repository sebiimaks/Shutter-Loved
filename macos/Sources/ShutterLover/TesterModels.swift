import Foundation

/// Only documented Photography Electronics tester models can enter the library.
/// Hardware compatibility is deliberately separate from the catalogue of models.
enum TesterModel: String, Codable, CaseIterable, Identifiable {
    case shutterLover
    case babyShutterTesterMkI
    case babyShutterTesterMkII

    var id: Self { self }
    var displayName: String {
        switch self {
        case .shutterLover: "Shutter Lover"
        case .babyShutterTesterMkI: "Baby Shutter Tester Mk I"
        case .babyShutterTesterMkII: "Baby Shutter Tester Mk II"
        }
    }
    var measurementLabel: String {
        self == .babyShutterTesterMkII ? "Effective exposure" : "Measured exposure"
    }
    var manufacturer: String { "Photography Electronics" }
    var supportsManualEntry: Bool { self != .shutterLover }
    var supportsUSBRecording: Bool { self == .shutterLover }
}

/// A USB serial number identifies hardware only when combined with its vendor
/// and product identifiers. A port path alone is never a persistent identity.
struct TesterUSBIdentity: Codable, Equatable {
    var vendorID: Int
    var productID: Int
    var serialNumber: String

    var stableIdentityKey: String {
        let canonicalSerial = serialNumber.trimmingCharacters(in: .whitespacesAndNewlines)
        return "usb:" + String(format: "%04x:%04x:", vendorID, productID) + Data(canonicalSerial.utf8).base64EncodedString()
    }
}

struct OwnedTester: Identifiable, Codable, Equatable {
    var id = UUID()
    var name: String
    var model: TesterModel
    var serialNumber = ""
    var firmwareVersion = ""
    var notes = ""
    var calibrationDate: Date?
    var calibrationNotes = ""
    var calibratedOptimalDistanceMM: Double?
    var calibrationCertificate: CalibrationCertificate?
    var usbBinding: TesterUSBIdentity?

    var displayName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? model.displayName : name
    }
}

/// Copied into each reading so later inventory edits cannot rewrite evidence.
/// A nil id represents a known model without an identified owned instrument.
struct TesterSnapshot: Codable, Equatable {
    var id: UUID?
    var model: TesterModel
    var name: String
    var serialNumber: String
    var firmwareVersion: String
    var calibrationDate: Date?
    var calibrationNotes: String
    var calibratedOptimalDistanceMM: Double?
    var usbIdentity: TesterUSBIdentity?
    var devicePath: String?

    init(tester: OwnedTester, usbIdentity: TesterUSBIdentity? = nil, devicePath: String? = nil) {
        id = tester.id
        model = tester.model
        name = tester.name
        serialNumber = tester.serialNumber
        firmwareVersion = tester.firmwareVersion
        calibrationDate = tester.calibrationDate
        calibrationNotes = tester.calibrationNotes
        calibratedOptimalDistanceMM = tester.calibratedOptimalDistanceMM
        self.usbIdentity = usbIdentity
        self.devicePath = devicePath
    }

    init(model: TesterModel, name: String = "", serialNumber: String = "", firmwareVersion: String = "", usbIdentity: TesterUSBIdentity? = nil, devicePath: String? = nil) {
        id = nil
        self.model = model
        self.name = name
        self.serialNumber = serialNumber
        self.firmwareVersion = firmwareVersion
        calibrationDate = nil
        calibrationNotes = ""
        calibratedOptimalDistanceMM = nil
        self.usbIdentity = usbIdentity
        self.devicePath = devicePath
    }

    var displayName: String {
        let label = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return label.isEmpty || label == model.displayName ? model.displayName : "\(label) · \(model.displayName)"
    }
}

enum ManualTimeUnit: String, Codable, CaseIterable, Identifiable {
    case milliseconds, seconds, reciprocalSeconds

    var id: Self { self }
    var displayName: String {
        switch self {
        case .milliseconds: "Milliseconds (ms)"
        case .seconds: "Seconds (s)"
        case .reciprocalSeconds: "Reciprocal seconds (1/s)"
        }
    }
    var symbol: String {
        switch self {
        case .milliseconds: "ms"
        case .seconds: "s"
        case .reciprocalSeconds: "1/s"
        }
    }
}

enum BabyMeasurementMode: String, Codable, CaseIterable, Identifiable {
    case unspecified, automatic, global

    var id: Self { self }
    var displayName: String {
        switch self {
        case .unspecified: "Not recorded"
        case .automatic: "Automatic"
        case .global: "Global"
        }
    }
}

/// The value and unit copied from the tester display remain unchanged even when
/// the nominal camera setting is corrected or derived results are recalculated.
struct ManualMeasurement: Codable, Equatable {
    var enteredValue: Double
    var unit: ManualTimeUnit = .milliseconds
    var mode: BabyMeasurementMode = .unspecified
    var illumination: Double?
    var seriesIllumination: Double?
    var notes = ""

    var seconds: Double {
        switch unit {
        case .milliseconds: enteredValue / 1_000
        case .seconds: enteredValue
        case .reciprocalSeconds: 1 / enteredValue
        }
    }
}
