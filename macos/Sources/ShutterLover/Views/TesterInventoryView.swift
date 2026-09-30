import SwiftUI
import DeviceTransport
import UniformTypeIdentifiers

struct TesterInventoryView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var editingTester: OwnedTester?
    @State private var pendingRemoval: OwnedTester?
    @State private var failure: String?

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("My testers").font(.title2.weight(.semibold))
                    Spacer()
                    Button {
                        editingTester = OwnedTester(name: "", model: .shutterLover)
                    } label: {
                        Label("Add tester", systemImage: "plus")
                    }.buttonStyle(.borderedProminent)
                }
                Text("Keep a record for each physical tester you own. Saved readings retain the tester details recorded with them.")
                    .font(.callout).foregroundStyle(.secondary)
            }.padding(22)
            Divider()
            if model.ownedTesters.isEmpty {
                ContentUnavailableView {
                    Label("Your testing equipment", systemImage: "sensor")
                } description: {
                    Text("Add a Shutter Lover or Baby Shutter Tester, then select it when recording results.")
                } actions: {
                    Button("Add your first tester") {
                        editingTester = OwnedTester(name: "", model: .shutterLover)
                    }
                }.frame(maxHeight: .infinity)
            } else {
                List(model.ownedTesters) { tester in
                    HStack(alignment: .top, spacing: 14) {
                        Image(systemName: "sensor").font(.title2).foregroundStyle(.tint)
                            .frame(width: 30).padding(.top, 3)
                        VStack(alignment: .leading, spacing: 5) {
                            Text(tester.displayName).font(.headline)
                            if tester.displayName != tester.model.displayName {
                                Text(tester.model.displayName).foregroundStyle(.secondary)
                            }
                            if !tester.serialNumber.isEmpty {
                                Text("Serial: \(tester.serialNumber)").font(.caption).foregroundStyle(.secondary)
                            }
                            if let distance = tester.calibratedOptimalDistanceMM {
                                Text("Calibrated optimal distance: \(distance.formatted(.number.grouping(.never))) mm")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            if tester.calibrationCertificate != nil {
                                Label("Calibration certificate attached", systemImage: "doc.badge.checkmark")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            if tester.usbBinding != nil {
                                Label(isConnected(tester) ? "USB identity detected" : "USB association saved",
                                      systemImage: isConnected(tester) ? "cable.connector" : "link")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }.frame(maxWidth: .infinity, alignment: .leading)
                        Button("Edit…") { editingTester = tester }
                            .accessibilityLabel("Edit tester: \(tester.displayName)")
                        Button("Remove…", role: .destructive) { pendingRemoval = tester }
                            .accessibilityLabel("Remove tester: \(tester.displayName)")
                    }.padding(.vertical, 9).buttonStyle(.borderless)
                }.listStyle(.inset)
            }
            Divider()
            VStack(alignment: .leading, spacing: 10) {
                if let failure { Text(failure).font(.callout).foregroundStyle(.red) }
                HStack {
                    Link("Manufacturer documentation", destination: URL(string: "https://photographyelectronics.com/resources/documentation/")!)
                        .font(.caption)
                    Spacer()
                    Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
                }
            }.padding(20)
        }
        .frame(width: 680, height: 530)
        .onAppear { model.refreshDevices() }
        .sheet(item: $editingTester) { tester in
            TesterInventoryEditorView(tester: tester,
                                      isExisting: model.ownedTesters.contains { $0.id == tester.id })
                .environmentObject(model)
        }
        .confirmationDialog("Remove tester from My testers?",
                            isPresented: Binding(get: { pendingRemoval != nil }, set: { if !$0 { pendingRemoval = nil } }),
                            titleVisibility: .visible, presenting: pendingRemoval) { tester in
            Button("Remove tester", role: .destructive) {
                if !model.removeOwnedTester(tester.id) {
                    failure = model.errorMessage ?? "The tester could not be removed."
                }
                pendingRemoval = nil
            }
            Button("Cancel", role: .cancel) { pendingRemoval = nil }
        } message: { tester in
            Text("Remove \(tester.displayName) and its USB association? Historical readings and the tester details stored with them will be retained.")
        }
    }

    private func isConnected(_ tester: OwnedTester) -> Bool {
        model.devices.contains { model.matchedOwnedTester(for: $0)?.id == tester.id }
    }
}

private struct TesterInventoryEditorView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var tester: OwnedTester
    @State private var failure: String?
    @State private var optimalDistance = ""
    @State private var previewCertificate: CalibrationCertificate?
    let isExisting: Bool

    init(tester: OwnedTester, isExisting: Bool) {
        _tester = State(initialValue: tester)
        _optimalDistance = State(initialValue: tester.calibratedOptimalDistanceMM.map { String($0) } ?? "")
        self.isExisting = isExisting
    }

    private var bindableDevices: [SerialDevice] {
        model.devices.filter { device in
            guard let key = device.stableIdentityKey,
                  model.devices.filter({ $0.stableIdentityKey == key }).count == 1 else { return false }
            return !model.ownedTesters.contains { $0.id != tester.id && $0.usbBinding?.stableIdentityKey == key }
        }
    }

    private var selectedUSBKey: Binding<String> {
        Binding(get: { tester.usbBinding?.stableIdentityKey ?? "" }, set: { key in
            if key.isEmpty { tester.usbBinding = nil }
            else if let device = bindableDevices.first(where: { $0.stableIdentityKey == key }) {
                tester.usbBinding = device.testerUSBIdentity
            }
        })
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 7) {
                Text(isExisting ? "Tester details" : "Add tester").font(.title2.weight(.semibold))
                Text("Select the model printed on your tester. Names, serial numbers and calibration details are optional.")
                    .font(.callout).foregroundStyle(.secondary)
            }.frame(maxWidth: .infinity, alignment: .leading).padding(22)
            Divider()
            Form {
                identitySection
                usbSection
                calibrationSection
                Section("Notes") {
                    TextField("Ownership, accessories and other details", text: $tester.notes, axis: .vertical)
                        .lineLimit(2...5)
                }
            }.formStyle(.grouped)
            Divider()
            VStack(alignment: .leading, spacing: 10) {
                if let failure { Text(failure).font(.callout).foregroundStyle(.red) }
                Text("Changes apply to future readings. Existing readings keep their original tester details.")
                    .font(.caption).foregroundStyle(.secondary)
                HStack {
                    Spacer()
                    Button("Cancel", role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction)
                    Button("Save tester") {
                        guard distanceValidation == nil else { return }
                        var candidate = tester
                        candidate.calibratedOptimalDistanceMM = tester.model == .shutterLover ? parsedDistance : nil
                        if model.saveOwnedTester(candidate) { dismiss() }
                        else { failure = model.errorMessage ?? "The tester could not be saved." }
                    }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
                        .disabled(distanceValidation != nil)
                }
            }.padding(20)
        }.frame(width: 640, height: 690)
            .interactiveDismissDisabled()
            .onChange(of: tester.model) { _, newModel in
                if newModel != .shutterLover {
                    optimalDistance = ""
                    tester.calibratedOptimalDistanceMM = nil
                    tester.calibrationCertificate = nil
                }
            }
            .sheet(item: $previewCertificate) { certificate in
                CalibrationCertificatePreviewView(certificate: certificate)
            }
    }

    private var identitySection: some View {
        Section("Identity") {
            Picker("Model", selection: $tester.model) {
                ForEach(TesterModel.allCases) { Text($0.displayName).tag($0) }
            }.disabled(isExisting)
            Text(isExisting
                 ? "A saved tester keeps its model. Add another tester for a different physical unit."
                 : "Models are limited to Photography Electronics products, including the original Baby Mk I.")
                .font(.caption).foregroundStyle(.secondary)
            TextField("Name / nickname", text: $tester.name, prompt: Text(tester.model.displayName))
            TextField("Hardware serial number", text: $tester.serialNumber, prompt: Text("If printed on the tester"))
            TextField("Firmware version", text: $tester.firmwareVersion)
            LabeledContent("App record UUID") {
                Text(tester.id.uuidString).font(.caption.monospaced()).textSelection(.enabled)
            }
            Text("The app assigns this UUID to your equipment record. It is separate from a manufacturer's serial number or a USB identity.")
                .font(.caption).foregroundStyle(.secondary)
            Link(tester.model == .babyShutterTesterMkI ? "Choose the manual for your Mk I firmware" : "Read this model’s instructions",
                 destination: manualURL)
        }
    }

    private var usbSection: some View {
        Section("USB association · optional") {
            Picker("Recognise this tester by USB", selection: selectedUSBKey) {
                Text("No saved USB association").tag("")
                if let binding = tester.usbBinding,
                   !bindableDevices.contains(where: { $0.stableIdentityKey == binding.stableIdentityKey }) {
                    Text("Saved association · currently unavailable").tag(binding.stableIdentityKey)
                }
                ForEach(bindableDevices) { device in
                    Text("\(device.name) · \(device.usbSerialNumber ?? "")")
                        .tag(device.stableIdentityKey!)
                }
            }
            HStack {
                Text("Connect the physical tester, then refresh to find its USB identity.")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Refresh devices") { model.refreshDevices() }
            }
            if let binding = tester.usbBinding {
                LabeledContent("USB vendor / product", value: String(format: "%04X / %04X", binding.vendorID, binding.productID))
                LabeledContent("USB serial number") {
                    Text(binding.serialNumber).textSelection(.enabled)
                }
                Button("Clear USB association") { tester.usbBinding = nil }
            }
            Text("Only devices reporting a unique vendor, product and USB serial combination appear here. Devices with no USB serial, duplicate identities, or associations to another saved tester are omitted. The app never treats a USB port or location as a tester's identity.")
                .font(.caption).foregroundStyle(.secondary)
            if tester.model.supportsManualEntry {
                Text("Baby Shutter Tester results are entered manually in this app. A saved USB association identifies equipment; it does not enable automatic Baby readings.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var calibrationSection: some View {
        Section("Calibration / checks · optional") {
            if tester.model == .shutterLover {
                TextField("Calibrated optimal distance (mm)", text: $optimalDistance, prompt: Text("From your unit’s calibration document"))
                    .help("The LED-to-sensor distance specified for this individual tester. Enter millimetres; 25 cm is 250 mm. Leave blank if unknown.")
                Text("Copy the LED-to-sensor distance from your unit’s calibration document. Enter millimetres (25 cm = 250 mm), or leave blank if unknown. This is a setup reference; it does not adjust measurements.")
                    .font(.caption).foregroundStyle(.secondary)
                if let distanceValidation {
                    Text(distanceValidation).font(.caption).foregroundStyle(.red)
                }
                certificateControls
            }
            Toggle("Record a calibration or check date", isOn: Binding(
                get: { tester.calibrationDate != nil },
                set: { tester.calibrationDate = $0 ? (tester.calibrationDate ?? Date()) : nil }))
            if tester.calibrationDate != nil {
                DatePicker("Date", selection: Binding(get: { tester.calibrationDate ?? Date() },
                                                     set: { tester.calibrationDate = $0 }), displayedComponents: .date)
            }
            TextField("Calibration or verification notes", text: $tester.calibrationNotes, axis: .vertical)
                .lineLimit(2...4)
        }
    }

    @ViewBuilder
    private var certificateControls: some View {
        if let certificate = tester.calibrationCertificate {
            LabeledContent("Calibration certificate") {
                Text(certificate.filename).lineLimit(2).textSelection(.enabled)
            }
            Text("\(ByteCountFormatter.string(fromByteCount: Int64(certificate.data.count), countStyle: .file)) · Attached \(certificate.importedAt.formatted(date: .abbreviated, time: .omitted))")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Button("Preview…") { previewCertificate = certificate }
                Button("Save a copy…") { saveCertificateCopy(certificate) }
                Button("Replace…") { chooseCertificate() }
                Button("Remove", role: .destructive) { tester.calibrationCertificate = nil }
            }
        } else {
            Button { chooseCertificate() } label: {
                Label("Attach calibration certificate…", systemImage: "paperclip")
            }
        }
        Text("PDF or a scanned/photo certificate (PNG, JPEG, TIFF or HEIC), up to 10 MB. A copy is stored with this tester when you save. Attachment changes can be cancelled before saving.")
            .font(.caption).foregroundStyle(.secondary)
    }

    private var parsedDistance: Double? {
        var text = optimalDistance.trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.contains(".") { text = text.replacingOccurrences(of: ",", with: ".") }
        return Double(text)
    }

    private var distanceValidation: String? {
        guard tester.model == .shutterLover,
              !optimalDistance.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        guard let value = parsedDistance, value.isFinite, value > 0, value <= 10_000 else {
            return "Enter a distance greater than zero and no more than 10,000 mm, or leave it blank."
        }
        return nil
    }

    private func chooseCertificate() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.pdf, .png, .jpeg, .tiff, .heic]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = "Choose this Shutter Lover’s calibration certificate. A copy will be stored with the tester when you save."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do {
            tester.calibrationCertificate = try CalibrationCertificate.read(from: url)
            failure = nil
        } catch { failure = "Certificate could not be attached: \(error.localizedDescription)" }
    }

    private func saveCertificateCopy(_ certificate: CalibrationCertificate) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = certificate.filename
        panel.allowedContentTypes = [certificate.contentType]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do {
            try certificate.validate()
            try certificate.data.write(to: url, options: .atomic)
            failure = nil
        } catch { failure = "Certificate could not be saved: \(error.localizedDescription)" }
    }

    private var manualURL: URL {
        switch tester.model {
        case .shutterLover:
            URL(string: "https://photographyelectronics.com/wp-content/uploads/2025/06/ShutterLover_UserManual_en_1.1.0_-_Release.pdf")!
        case .babyShutterTesterMkI:
            URL(string: "https://github.com/sebastienroy/shutter_speed_tester/wiki/Shutter-Testers-documentation")!
        case .babyShutterTesterMkII:
            URL(string: "https://photographyelectronics.com/wp-content/uploads/2025/08/BabyShutterTester_mkII_UserManual_en_1.0.0_-B.pdf")!
        }
    }
}
