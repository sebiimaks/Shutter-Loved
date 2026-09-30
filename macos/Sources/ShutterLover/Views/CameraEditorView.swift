import SwiftUI
import MeasurementCore

/// Edits catalogue metadata and future defaults; captured test identities remain snapshots.
struct CameraEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var model: AppModel
    @State private var camera: CameraProfile
    @State private var speedText: String
    @State private var section = 0
    @State private var showMountChooser = false
    let onSave: (CameraProfile) -> Void

    init(camera: CameraProfile, onSave: @escaping (CameraProfile) -> Void) {
        _camera = State(initialValue: camera)
        _speedText = State(initialValue: camera.plannedSpeeds.map { String(format: "%g", $0) }.joined(separator: ", "))
        self.onSave = onSave
    }

    private var speeds: [Double]? {
        let pieces = speedText.split(whereSeparator: { $0 == "," || $0.isWhitespace })
        guard !pieces.isEmpty, pieces.count <= 64 else { return nil }
        let values = pieces.compactMap { Double($0) }
        guard values.count == pieces.count, values.allSatisfy(SessionStore.validSetting) else { return nil }
        return Array(Set(values)).sorted()
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Camera details").font(.title2.weight(.semibold))
                Text("One record identifies one physical camera. Only a display name is required.")
                    .font(.callout).foregroundStyle(.secondary)
                Picker("Details section", selection: $section) {
                    Text("Identity").tag(0)
                    Text("Camera & testing").tag(1)
                    Text("Condition & ownership").tag(2)
                }.pickerStyle(.segmented)
            }.padding(22)
            Divider()
            Form {
                if section == 0 { identityFields }
                if section == 1 { equipmentFields }
                if section == 2 { ownershipFields }
            }.formStyle(.grouped)
            Divider()
            VStack(alignment: .leading, spacing: 12) {
                Label("Edits apply to this camera and future tests. Existing tests keep their captured identity and settings.", systemImage: "clock.arrow.circlepath")
                    .font(.caption).foregroundStyle(.secondary)
                HStack {
                    Spacer()
                    Button("Cancel", role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction)
                    Button("Save camera") {
                        guard let speeds else { return }
                        camera.name = camera.name.trimmingCharacters(in: .whitespacesAndNewlines)
                        camera.plannedSpeeds = speeds
                        onSave(camera)
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
                    .disabled(camera.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || speeds == nil)
                }
            }.padding(20)
        }.frame(width: 620, height: 660)
            .sheet(isPresented: $showMountChooser) {
                CameraMountChooserView(mounts: model.flangeMountRows, selectedMount: $camera.mount)
            }
    }

    @ViewBuilder private var identityFields: some View {
        Section("Identity") {
            TextField("Display name", text: $camera.name)
            TextField("Manufacturer", text: $camera.manufacturer)
            TextField("Model", text: $camera.model)
            TextField("Nickname", text: $camera.nickname)
            TextField("Body serial number", text: $camera.serial)
            TextField("Collection ID", text: $camera.inventoryID)
            TextField("Tags, separated by commas", text: $camera.tags)
        }
        if camera.catalogueCameraID != nil {
            Section("ArmariumLucis link") {
                Text("This camera is linked by its catalogue identifiers. A matching name or serial number never merges another camera into this record.")
                    .font(.caption).foregroundStyle(.secondary)
                LabeledContent("Imported revision", value: camera.catalogueRevision.map(String.init) ?? "Unknown")
            }
        }
    }

    @ViewBuilder private var equipmentFields: some View {
        Section("Camera and lens") {
            TextField("Film / image format", text: $camera.format)
            TextField("Frame dimensions (e.g. 36 × 24 mm)", text: $camera.frameSize)
            TextField("Shutter type", text: $camera.shutterType)
            HStack(alignment: .firstTextBaseline) {
                TextField("Lens mount", text: $camera.mount)
                Button("Choose mount…") { showMountChooser = true }
                    .help("Choose a specific mount from the flange-distance table. You can also enter your own mount name.")
            }
            mountDistanceStatus
            TextField("Lens", text: $camera.lens)
            TextField("Lens serial number", text: $camera.lensSerial)
            TextField("Approximate production year", text: $camera.productionYear)
        }
        Section("New-test defaults") {
            Picker("Curtain direction", selection: $camera.defaultDirection) {
                ForEach(CurtainDirection.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            TextField("Planned speed denominators", text: $speedText)
            Text("Enter denominators separated by commas: 30, 60, 125 means 1/30, 1/60, 1/125 s. For a two-second exposure, enter 0.5.")
                .font(.caption).foregroundStyle(.secondary)
            if speeds == nil { Text("Enter 1–64 positive, valid speed denominators.").font(.caption).foregroundStyle(.red) }
            Text("Format is descriptive metadata. Calculations currently support the Shutter Lover's 32 × 20 mm sensor rectangle and 36 × 24 mm frame; entering another format does not change that geometry.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private var mountDistanceStatus: some View {
        let matches = model.flangeMatches(camera.mount)
        if matches.count == 1, let match = matches.first {
            Label("Flange distance: \(match.distanceMM.formatted(.number.precision(.fractionLength(0...4)))) mm", systemImage: "ruler")
                .font(.caption).foregroundStyle(.secondary)
        } else if matches.count > 1 {
            Text("This mount name has more than one possible flange distance. Choose a specific mount for tester positioning.")
                .font(.caption).foregroundStyle(.orange)
        } else if camera.mount.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            Text("Choose a mount to calculate positioning for a calibrated Shutter Lover.")
                .font(.caption).foregroundStyle(.secondary)
        } else {
            Text("No flange distance matches this mount. You can keep this name, but automatic tester positioning needs a mount from the table.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private var ownershipFields: some View {
        Section("Condition and notes") {
            TextField("Condition, meter, light seals and quirks", text: $camera.condition, axis: .vertical).lineLimit(3...6)
            TextField("General notes", text: $camera.notes, axis: .vertical).lineLimit(3...6)
        }
        Section("Ownership · optional") {
            TextField("Acquisition date", text: $camera.acquisitionDate)
            TextField("Acquired from", text: $camera.acquisitionSource)
            TextField("Purchase amount", text: $camera.purchasePrice)
            TextField("Currency", text: $camera.currency)
            TextField("Storage location", text: $camera.storageLocation)
            Toggle("Archived camera", isOn: $camera.archived)
        }
    }
}

/// Choosing a mount only edits the camera form; its Save / Cancel action still controls persistence.
private struct CameraMountChooserView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""
    let mounts: [FlangeDistanceRow]
    @Binding var selectedMount: String

    private var filteredMounts: [FlangeDistanceRow] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        return mounts.filter { query.isEmpty || $0.name.localizedStandardContains(query) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Choose lens mount").font(.title2.weight(.semibold))
                Text("Choose the camera body's mount. Flange distance is measured from the mounting flange to the film or sensor plane.")
                    .font(.callout).foregroundStyle(.secondary)
                TextField("Search lens mounts", text: $search)
                    .textFieldStyle(.roundedBorder)
            }.padding(20)
            Divider()
            List {
                ForEach(filteredMounts, id: \.id) { mount in
                    Button {
                        selectedMount = mount.name
                        dismiss()
                    } label: {
                        HStack {
                            Text(mount.name)
                            Spacer(minLength: 12)
                            Text("\(mount.distanceMM.formatted(.number.precision(.fractionLength(0...4)))) mm")
                                .monospacedDigit().foregroundStyle(.secondary)
                            Image(systemName: "checkmark")
                                .foregroundStyle(Color.accentColor)
                                .opacity(selectedMount == mount.name ? 1 : 0)
                        }
                        .padding(.vertical, 5)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(mount.name), \(mount.distanceMM.formatted()) millimetres")
                }
            }
            .overlay {
                if filteredMounts.isEmpty {
                    ContentUnavailableView.search(text: search)
                }
            }
            Divider()
            HStack {
                Text("Flange distances can be edited in Settings.")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }.padding(20)
        }.frame(width: 570, height: 560)
    }
}

struct CameraTestEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var session: CaptureSession
    @State private var title: String
    @State private var operatorName: String
    @State private var lightSource: String
    @State private var conditions: String
    @State private var tolerance: Double
    @State private var repeats: Int
    @State private var speedText: String
    let onSave: (CaptureSession) -> Void

    init(session: CaptureSession, onSave: @escaping (CaptureSession) -> Void) {
        _session = State(initialValue: session)
        _title = State(initialValue: session.title ?? "Shutter test")
        _operatorName = State(initialValue: session.operatorName ?? "")
        _lightSource = State(initialValue: session.lightSource ?? "")
        _conditions = State(initialValue: session.testConditions ?? "")
        _tolerance = State(initialValue: session.toleranceStops ?? 1.0 / 3.0)
        _repeats = State(initialValue: session.repeatsPerSpeed ?? 3)
        _speedText = State(initialValue: (session.plannedSpeeds ?? [30, 60, 125, 250, 500, 1000]).map { String(format: "%g", $0) }.joined(separator: ", "))
        self.onSave = onSave
    }

    private var speeds: [Double]? {
        let pieces = speedText.split(whereSeparator: { $0 == "," || $0.isWhitespace })
        let values = pieces.compactMap { Double($0) }
        guard !values.isEmpty, values.count <= 64, values.count == pieces.count,
              values.allSatisfy(SessionStore.validSetting) else { return nil }
        return Array(Set(values)).sorted()
    }

    var body: some View {
        VStack(spacing: 0) {
            Text("Test details").font(.title2.weight(.semibold)).frame(maxWidth: .infinity, alignment: .leading).padding(22)
            Form {
                Section("Test context") {
                    TextField("Title / purpose", text: $title)
                    TextField("Operator", text: $operatorName)
                    TextField("Light source", text: $lightSource)
                    TextField("Lens, aperture and test conditions", text: $conditions, axis: .vertical).lineLimit(2...4)
                    TextField("Test notes", text: $session.notes, axis: .vertical).lineLimit(3...6)
                }
                Section("Assessment and coverage") {
                    TextField("Tolerance in stops (±)", value: $tolerance, format: .number.precision(.fractionLength(2...4)))
                    Text("This is your chosen timing tolerance, not a manufacturer specification or a camera health grade.")
                        .font(.caption).foregroundStyle(.secondary)
                    TextField("Planned speed denominators", text: $speedText)
                    Stepper("Target repeats per speed: \(repeats)", value: $repeats, in: 1...100)
                    if speeds == nil { Text("Enter 1–64 valid denominators, separated by commas.").font(.caption).foregroundStyle(.red) }
                }
                Section {
                    Text("These details do not change raw readings, captured camera identity, curtain direction, or nominal settings. Timing corrections are recorded separately in the reading inspector.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }.formStyle(.grouped)
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Save test") {
                    guard let speeds else { return }
                    session.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
                    session.operatorName = operatorName
                    session.lightSource = lightSource
                    session.testConditions = conditions
                    session.toleranceStops = tolerance
                    session.repeatsPerSpeed = repeats
                    session.plannedSpeeds = speeds
                    onSave(session)
                    dismiss()
                }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
                    .disabled(speeds == nil || !tolerance.isFinite || tolerance <= 0 || tolerance > 10)
            }.padding(20)
        }.frame(width: 570, height: 610)
    }
}

struct CameraServiceEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var event: CameraServiceEvent
    let sessions: [CaptureSession]
    let onSave: (CameraServiceEvent) -> Void

    init(event: CameraServiceEvent, sessions: [CaptureSession], onSave: @escaping (CameraServiceEvent) -> Void) {
        _event = State(initialValue: event)
        self.sessions = sessions
        self.onSave = onSave
    }

    var body: some View {
        VStack(spacing: 0) {
            Text("Service event").font(.title2.weight(.semibold)).frame(maxWidth: .infinity, alignment: .leading).padding(22)
            Form {
                DatePicker("Date", selection: $event.date, displayedComponents: .date)
                TextField("Work performed", text: $event.title)
                TextField("Technician / provider", text: $event.provider)
                TextField("Service notes", text: $event.notes, axis: .vertical).lineLimit(4...8)
                Section("Link the evidence") {
                    testPicker("Before service", selection: $event.beforeSessionID)
                    testPicker("After service", selection: $event.afterSessionID)
                    Text("Choose tests on this camera explicitly. Linking a test does not claim the service caused a measured difference.")
                        .font(.caption).foregroundStyle(.secondary)
                    if event.beforeSessionID != nil && event.beforeSessionID == event.afterSessionID {
                        Text("Choose two different tests for a before/after comparison.").font(.caption).foregroundStyle(.red)
                    }
                }
            }.formStyle(.grouped)
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Save event") { onSave(event); dismiss() }
                    .buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
                    .disabled(event.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || (event.beforeSessionID != nil && event.beforeSessionID == event.afterSessionID))
            }.padding(20)
        }.frame(width: 560, height: 510)
    }

    private func testPicker(_ title: String, selection: Binding<UUID?>) -> some View {
        Picker(title, selection: selection) {
            Text("None").tag(Optional<UUID>.none)
            ForEach(sessions.filter { !$0.demo }) { test in
                Text("\(test.displayTitle) · \(test.createdAt.formatted(date: .abbreviated, time: .shortened))").tag(Optional(test.id))
            }
        }
    }
}
