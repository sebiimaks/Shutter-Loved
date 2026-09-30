import Foundation

extension MeasurementRecord {
    /// Grouping is deliberately conservative. A port path can split unidentified
    /// captures, but is never presented as a durable hardware identity.
    var resultContextID: String {
        var parts = [tester?.model.rawValue ?? "legacyShutterLover", isManual ? "manual" : "usb"]
        if let tester {
            if let id = tester.id { parts.append("owned:" + id.uuidString.lowercased()) }
            else if let usb = tester.usbIdentity { parts.append("usb:" + usb.stableIdentityKey) }
            else if !tester.serialNumber.isEmpty { parts.append("serial:" + tester.serialNumber) }
            else { parts.append("unidentified:" + (tester.devicePath ?? devicePath ?? "unknown")) }
        } else {
            parts.append("unidentified:" + (devicePath ?? "unknown"))
        }
        parts.append(manual?.mode.rawValue ?? "deviceTiming")
        if let distance = tester?.calibratedOptimalDistanceMM {
            // A changed recorded calibration must not be pooled with the old
            // one. This describes the recommendation, not observed placement.
            parts.append("calibratedOptimalDistanceMM:" + String(distance))
        }
        // Length prefixes keep arbitrary user-entered serials unambiguous.
        return parts.map { "\($0.utf8.count):\($0)" }.joined()
    }

    var resultContextDescription: String {
        let method = isDemo ? "Simulated · Center exposure" : (isManual ? "Manual · \(measurementLabel)" : "USB · Center exposure")
        let mode = manual.flatMap { $0.mode == .unspecified ? nil : $0.mode.displayName + " mode" }
        let calibration = tester?.calibratedOptimalDistanceDescription.map { "Calibrated optimal distance: " + $0 }
        return ([testerDescription, method] + [mode, calibration].compactMap { $0 }).joined(separator: " · ")
    }

    var testerProvenanceDescription: String {
        guard let tester else { return isDemo ? "Shutter Lover demonstration · simulated readings" : "Shutter Lover · physical tester not recorded" }
        var parts = [tester.model.manufacturer, tester.displayName]
        if !tester.serialNumber.isEmpty { parts.append("Serial: " + tester.serialNumber) }
        if let id = tester.id { parts.append("Owned tester UUID: " + id.uuidString.lowercased()) }
        else { parts.append("Owned tester not identified") }
        if let usb = tester.usbIdentity { parts.append("USB identity: " + usb.stableIdentityKey) }
        if let distance = tester.calibratedOptimalDistanceDescription {
            parts.append("Calibrated optimal distance: \(distance) (recommended LED-to-sensor distance; actual placement not recorded)")
        }
        return parts.joined(separator: " · ")
    }

    var manualProvenanceDescription: String? {
        guard let manual else { return nil }
        var parts = ["Manually transcribed \(measurementLabel.lowercased()); original display value \(manual.enteredValue) \(manual.unit.symbol); mode \(manual.mode.displayName.lowercased()); sensor position not recorded."]
        if let value = manual.illumination { parts.append("Illumination E0: \(value).") }
        if let value = manual.seriesIllumination { parts.append("Series maximum illumination E0: \(value).") }
        if !manual.notes.isEmpty { parts.append("Entry notes: " + manual.notes) }
        return parts.joined(separator: " ")
    }
}

extension TesterSnapshot {
    var calibratedOptimalDistanceDescription: String? {
        calibratedOptimalDistanceMM.map {
            // Exported notes must remain stable if the Mac's locale changes.
            let number = String($0)
            return (number.hasSuffix(".0") ? String(number.dropLast(2)) : number) + " mm"
        }
    }
}

extension CaptureSession {
    /// Describe the immutable reading snapshots, not the currently selected unit.
    var testerSummary: String {
        let values = Set(records.map(\.testerProvenanceDescription)).sorted()
        if !values.isEmpty { return values.joined(separator: "\n") }
        if let tester { return "Selected for new readings: \(tester.model.manufacturer) · \(tester.displayName)" }
        return "No tester recorded yet"
    }
}
