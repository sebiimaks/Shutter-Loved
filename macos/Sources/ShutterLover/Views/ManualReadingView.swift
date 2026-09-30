import SwiftUI
import MeasurementCore

struct TesterSelectionView: View {
    @EnvironmentObject private var model: AppModel
    let session: CaptureSession

    private var selection: Binding<String> {
        Binding(get: {
            if let id = session.tester?.id, model.ownedTesters.contains(where: { $0.id == id }) { return id.uuidString }
            return (session.tester?.model ?? .shutterLover).rawValue
        }, set: { value in
            let snapshot: TesterSnapshot
            if let owned = model.ownedTesters.first(where: { $0.id.uuidString == value }) { snapshot = TesterSnapshot(tester: owned) }
            else if let testerModel = TesterModel(rawValue: value) { snapshot = TesterSnapshot(model: testerModel) }
            else { return }
            model.setSessionTester(session.id, tester: snapshot)
        })
    }

    var body: some View {
        if !session.demo {
            HStack(alignment: .center, spacing: 12) {
                Picker("Tester", selection: selection) {
                    Section("Model only · individual unit not recorded") {
                        ForEach(TesterModel.allCases) { tester in Text(tester.displayName).tag(tester.rawValue) }
                    }
                    if !model.ownedTesters.isEmpty {
                        Section("My testers") {
                            ForEach(model.ownedTesters) { tester in Text("\(tester.displayName) · \(tester.model.displayName)").tag(tester.id.uuidString) }
                        }
                    }
                }
                .disabled(model.activeCaptureSessionID == session.id)
                .help("Choose a model or a saved physical tester. Each reading retains its own tester details; changing this selection does not relabel past readings.")
                Button("My testers…") { model.showTesters = true }
            }
            .font(.callout)
            .controlSize(.small)
        }
    }
}

struct ManualReadingView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let sessionID: UUID
    @State private var testerKey = TesterModel.babyShutterTesterMkII.rawValue
    @State private var enteredValue = ""
    @State private var unit: ManualTimeUnit = .milliseconds
    @State private var nominal = "125"
    @State private var mode: BabyMeasurementMode = .unspecified
    @State private var illumination = ""
    @State private var seriesIllumination = ""
    @State private var notes = ""
    @State private var capturedAt = Date()
    @State private var savedCount = 0
    @State private var saveError: String?

    private var tester: TesterSnapshot? {
        if let owned = model.ownedTesters.first(where: { $0.id.uuidString == testerKey && $0.model.supportsManualEntry }) {
            return TesterSnapshot(tester: owned)
        }
        if let type = TesterModel(rawValue: testerKey), type.supportsManualEntry { return TesterSnapshot(model: type) }
        return nil
    }

    private func number(_ text: String, reciprocal: Bool = false) -> Double? {
        var value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if reciprocal && value.hasPrefix("1/") { value = String(value.dropFirst(2)) }
        if !value.contains(".") { value = value.replacingOccurrences(of: ",", with: ".") }
        guard let result = Double(value), result.isFinite else { return nil }
        return result
    }

    private var draft: ManualMeasurement? {
        guard let value = number(enteredValue, reciprocal: unit == .reciprocalSeconds) else { return nil }
        return ManualMeasurement(enteredValue: value, unit: unit,
                                 mode: tester?.model == .babyShutterTesterMkII ? mode : .unspecified,
                                 illumination: tester?.model == .babyShutterTesterMkII ? number(illumination) : nil,
                                 seriesIllumination: tester?.model == .babyShutterTesterMkII && mode == .global ? number(seriesIllumination) : nil,
                                 notes: notes)
    }

    private var validationMessage: String? {
        guard let tester else { return "Choose a Baby Shutter Tester model or an owned tester." }
        guard let reference = number(nominal, reciprocal: true), SessionStore.validSetting(reference) else { return "Enter a valid camera setting, such as 125 or 1/125." }
        guard let draft else { return "Enter the measured value from the tester display." }
        if tester.model == .babyShutterTesterMkII {
            if !illumination.isEmpty && number(illumination) == nil { return "Enter E₀ as a number between 0 and 100, or leave it blank." }
            if mode == .global && !seriesIllumination.isEmpty && number(seriesIllumination) == nil { return "Enter the series E₀ as a number between 0 and 100, or leave it blank." }
        }
        do { try SessionStore.validateManualMeasurement(draft, model: tester.model); return nil }
        catch SessionStoreError.invalid(let reason) { return reason.prefix(1).uppercased() + reason.dropFirst() + "." }
        catch { return error.localizedDescription }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Add manual reading").font(.title2.bold())
            Text("Copy the displayed result from your Baby tester. The original value, units and tester details are saved with this reading.")
                .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Form {
                Section("Tester") {
                    Picker("Model / owned tester", selection: $testerKey) {
                        ForEach(TesterModel.allCases.filter(\.supportsManualEntry)) { type in
                            Text("\(type.displayName) · model only").tag(type.rawValue)
                        }
                        ForEach(model.ownedTesters.filter { $0.model.supportsManualEntry }) { owned in
                            Text("\(owned.displayName) · \(owned.model.displayName)").tag(owned.id.uuidString)
                        }
                    }
                    Text(tester?.id == nil ? "Individual tester not recorded. Add your unit in My testers to retain its UUID, serial number and calibration details." : "The saved details of this physical tester will be copied into the reading.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("Display reading") {
                    TextField("Camera setting (1/… s)", text: $nominal)
                        .help("The exposure selected on the camera, for example 125 for 1/125 second.")
                    Picker("Displayed units", selection: $unit) {
                        ForEach(ManualTimeUnit.allCases) { value in Text(value.displayName).tag(value) }
                    }
                    TextField(tester?.model.measurementLabel ?? "Measured exposure", text: $enteredValue)
                        .help(unit == .reciprocalSeconds ? "Enter 122 or 1/122 for a display of 1/122 second." : "Enter only the number shown on the tester.")
                    if let draft, validationMessage == nil {
                        Text("\(MeasurementFormat.milliseconds(draft.seconds * 1_000)) · ≈ \(MeasurementFormat.speed(1 / draft.seconds))")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    DatePicker("Measured at", selection: $capturedAt)
                }
                if tester?.model == .babyShutterTesterMkII {
                    Section("Measurement conditions · optional") {
                        Picker("Mode", selection: $mode) {
                            ForEach(BabyMeasurementMode.allCases) { value in Text(value.displayName).tag(value) }
                        }
                        TextField("E₀ for this reading (0–100)", text: $illumination)
                        if mode == .global { TextField("Series maximum E₀ (0–100)", text: $seriesIllumination) }
                        Text("E₀ records illumination on the tester. Keep it blank if it was not recorded.")
                            .font(.caption).foregroundStyle(.secondary)
                        if let value = number(illumination), value < 10 || value > 90 {
                            Text(value < 10 ? "Low illumination can reduce reliability. Check the tester's lighting before accepting the result." : "Illumination is near saturation. Reduce the light and repeat if needed.")
                                .font(.caption).foregroundStyle(.orange)
                        }
                    }
                } else {
                    Text("Mark I uses a different measurement and calibration procedure. Copy its displayed exposure; mk II modes and E₀ fields do not apply.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("Notes") { TextField("Lighting, aperture, calibration or observations", text: $notes, axis: .vertical).lineLimit(2...4) }
            }.formStyle(.grouped)
            if savedCount > 0 {
                Text("Saved \(savedCount) reading\(savedCount == 1 ? "" : "s") in this entry session.").font(.caption).foregroundStyle(.green)
            }
            if let message = saveError ?? validationMessage {
                Text(message).font(.caption).foregroundStyle(saveError == nil ? Color.secondary : Color.red)
            }
            HStack {
                Button(savedCount == 0 ? "Cancel" : "Done") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("Save & add another") { save(keepOpen: true) }.disabled(validationMessage != nil)
                Button("Add reading") { save(keepOpen: false) }.keyboardShortcut(.defaultAction).disabled(validationMessage != nil)
            }
        }
        .padding(22).frame(width: 590, height: 720)
        .onAppear {
            guard let session = model.sessions.first(where: { $0.id == sessionID }) else { return }
            nominal = String(session.nominalDenominator)
            if let snapshot = session.tester {
                if let id = snapshot.id, model.ownedTesters.contains(where: { $0.id == id }) { testerKey = id.uuidString }
                else if snapshot.model.supportsManualEntry { testerKey = snapshot.model.rawValue }
            }
        }
    }

    private func save(keepOpen: Bool) {
        guard validationMessage == nil, let tester, let draft, let reference = number(nominal, reciprocal: true) else { return }
        if model.addManualReading(sessionID: sessionID, measurement: draft, tester: tester, nominalDenominator: reference, capturedAt: capturedAt) {
            savedCount += 1
            saveError = nil
            if keepOpen { enteredValue = ""; illumination = ""; capturedAt = Date() }
            else { dismiss() }
        } else {
            saveError = model.errorMessage
            model.errorMessage = nil
        }
    }
}
