import SwiftUI
import MeasurementCore

struct MeasurementWorkspaceView: View {
    @EnvironmentObject private var model: AppModel
    @State private var editingTest: CaptureSession?
    @State private var pendingAssignment: UUID?
    @State private var showCoverage = false

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                VStack(alignment: .leading, spacing: 10) {
                    cameraMembership
                    if let session = model.currentSession { TesterSelectionView(session: session) }
                    SessionSetupView()
                    if let session = model.currentSession { TesterPositioningView(session: session) }
                }
                .padding(12)
                .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(.quaternary))
                capturePrompt
                summaryMetrics
                HStack(spacing: 8) {
                    RepeatabilitySummaryView()
                    if let session = model.currentSession, session.cameraID != nil {
                        Button("Speed coverage…") { showCoverage = true }
                            .font(.caption)
                            .popover(isPresented: $showCoverage) {
                                ScrollView {
                                    CameraCoverageView(session: session, plannedSpeeds: session.plannedSpeeds ?? [])
                                        .padding(12)
                                }
                                .frame(width: 540, height: 360)
                            }
                    }
                }
            }
            .padding(14)
            .fixedSize(horizontal: false, vertical: true)
            Divider()
            MeasurementTableView()
            Divider()
            statusBar
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .navigationTitle(model.cameraName.isEmpty ? "Measurement session" : model.cameraName)
        .sheet(item: $editingTest) { session in
            CameraTestEditorView(session: session) { model.updateTestDetails($0) }
        }
        .confirmationDialog("Assign this existing test to the selected physical camera?", isPresented: Binding(get: { pendingAssignment != nil }, set: { if !$0 { pendingAssignment = nil } }), titleVisibility: .visible) {
            if let id = pendingAssignment, let camera = model.cameras.first(where: { $0.id == id }), let session = model.currentSession {
                Button("Assign to \(camera.name)") { model.assignSession(session.id, to: id); pendingAssignment = nil }
                Button("Cancel", role: .cancel) { pendingAssignment = nil }
            }
        } message: {
            Text("Choose the camera that produced these readings. The original name and measurements are retained, and the date of this assignment is recorded."
                 + (LucisIntegration.isEnabled ? " An Armarium-linked camera enables results export back to that exact catalogue item." : ""))
        }
    }

    @ViewBuilder private var cameraMembership: some View {
        if let session = model.currentSession {
            HStack(spacing: 8) {
                Image(systemName: session.demo ? "play.rectangle" : "camera")
                    .foregroundStyle(session.demo ? Color.orange : Color.secondary)
                TextField("Camera name or serial number", text: $model.cameraName)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel("Camera name")
                    .help("Identify the camera being measured. The name is saved with this session.")
                    .frame(minWidth: 120, maxWidth: .infinity)
                if session.demo {
                    Text("Demo").font(.caption.weight(.medium)).foregroundStyle(.orange)
                } else if let cameraID = session.cameraID, let camera = model.cameras.first(where: { $0.id == cameraID }) {
                    Button("Camera record") { model.selectCamera(cameraID) }
                        .help("Open the camera record for \(camera.name).")
                } else {
                    Menu("Assign camera…") {
                        ForEach(model.cameras) { camera in
                            Button(camera.name) { pendingAssignment = camera.id }
                        }
                        Divider()
                        Button("Add a camera first…", action: model.newCamera)
                        if LucisIntegration.isEnabled {
                            Button("Import Armarium camera catalogue…", action: model.importCameraCatalogue)
                        }
                    }
                    .fixedSize()
                    .help("Choose the physical camera tested. Names are never matched automatically.")
                }
                Button { editingTest = session } label: {
                    Text(session.cameraID == nil ? "Test details" : "Test: \(session.displayTitle)")
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(maxWidth: session.cameraID == nil ? 80 : 150)
                }
                .accessibilityLabel("Test details: \(session.displayTitle)")
                .help("\(session.displayTitle) — edit the test title, planned speeds, operator and conditions.")
                Button(role: .destructive) { model.pendingDeleteSessionID = session.id } label: {
                    Image(systemName: "trash")
                }
                .accessibilityLabel("Delete test…")
                .disabled(!model.canTrashSession(session.id))
                .help(model.canTrashSession(session.id)
                      ? "Move this test and its readings to Trash. You can restore it later."
                      : "Disconnect the tester before deleting the test that is receiving readings.")
            }
            .controlSize(.small)
        }
    }

    private var capturePrompt: some View {
        HStack(spacing: 8) {
            Image(systemName: model.isDemoMode ? "play.circle" : "camera.aperture")
                .foregroundStyle(model.isDemoMode ? Color.orange : Color.accentColor)
            Text(model.isDemoMode ? "Simulated readings · no tester required" : model.currentSession?.tester?.model.supportsManualEntry == true ? "Copy the result displayed on your Baby tester." : "Set \(MeasurementFormat.speed(model.nominalDenominator)), reset the tester, then release the shutter.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            if model.isDemoMode {
                Menu {
                    Button("Add partial demo reading") { model.addDemoReading(partial: true) }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuStyle(.borderlessButton)
                .frame(width: 20)
                .help("Add a demo reading with a missing sensor event.")
                Button("Add demo reading") { model.addDemoReading() }
                    .buttonStyle(.borderedProminent)
            } else if let session = model.currentSession, session.tester?.model.supportsManualEntry == true {
                Button("Add manual reading…") { model.manualEntrySessionID = session.id }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.activeCaptureSessionID == session.id)
            } else if let session = model.currentSession, model.canRecordUSB(in: session),
                      model.activeCaptureSessionID != nil, model.activeCaptureSessionID != session.id {
                Button("Record into this test", action: model.recordIntoSelectedTest)
                    .help("Explicitly change the destination for future readings to this test.")
            } else {
                Button("Setup guide") { model.showGuide = true }
            }
        }
        .controlSize(.small)
        .padding(.horizontal, 2)
    }

    private var summaryMetrics: some View {
        let record = model.selectedRecord ?? model.currentRecords.last
        let result = record?.result
        return HStack(spacing: 12) {
            SummaryMetricCard(
                title: record?.measurementLabel ?? model.currentSession?.tester?.model.measurementLabel ?? "Center exposure",
                value: MeasurementFormat.milliseconds(result?.center.durationMS),
                detail: result?.center.reciprocalSeconds.map { "≈ \(MeasurementFormat.speed($0))" } ?? "Waiting for a reading",
                symbol: "timer"
            )
            SummaryMetricCard(
                title: "Timing difference",
                value: MeasurementFormat.stops(result?.exposureErrorStops),
                detail: record.map { "Compared with \(MeasurementFormat.speed($0.nominalDenominator))" } ?? "Compared with the camera setting",
                symbol: "plusminus"
            )
            SummaryMetricCard(
                title: "Opening travel",
                value: MeasurementFormat.milliseconds(result?.openingTravelMS),
                detail: (record?.isManual ?? (model.currentSession?.tester?.model.supportsManualEntry == true)) ? "Not measured by this single-sensor tester" : "Measured between corner sensors",
                symbol: "arrow.right.to.line"
            )
        }
    }

    private var statusBar: some View {
        HStack(spacing: 8) {
            Image(systemName: model.isDemoMode ? "play.rectangle" : model.isConnected ? "cable.connector" : "cable.connector.slash")
            Text(model.isDemoMode ? "Demo session" : model.currentSession?.tester?.model.supportsManualEntry == true ? "Manual entry · no connection required" : model.connectionStatus)
                .lineLimit(1)
            Spacer()
            Text(model.saveStatus)
                .lineLimit(1)
                .accessibilityLabel("Save status: \(model.saveStatus)")
        }
        .font(.caption).foregroundStyle(.secondary)
        .padding(.horizontal, 18).padding(.vertical, 9)
    }
}

private struct SessionSetupView: View {
    @EnvironmentObject private var model: AppModel
    @State private var showNotes = false

    var body: some View {
        HStack(alignment: .bottom, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("CAMERA SETTING").setupLabel()
                NominalSpeedPicker(value: $model.nominalDenominator)
            }
            .frame(width: 140)
            VStack(alignment: .leading, spacing: 4) {
                Text("CURTAIN DIRECTION").setupLabel()
                Picker("Curtain direction", selection: $model.direction) {
                    Text("Unknown").tag(CurtainDirection.unknown)
                    Text("Horizontal").tag(CurtainDirection.horizontal)
                    Text("Vertical").tag(CurtainDirection.vertical)
                }
                .labelsHidden()
                .disabled(model.currentSession?.tester?.model.supportsManualEntry == true)
                .help("Choose the direction the shutter curtains cross the frame. This affects full-frame travel estimates only.")
            }
            .frame(width: 124)
            Toggle("Suggest next speed", isOn: $model.autoAdvance)
                .disabled(model.currentSession?.tester?.model.supportsManualEntry == true)
                .toggleStyle(.checkbox)
                .font(.caption)
                .fixedSize()
                .help("After a complete reading, advance the suggested setting from 1/15 through 1/1000 s. Settings apply to future readings; change the camera speed yourself.")
                .padding(.bottom, 3)
            Spacer(minLength: 0)
            Button { showNotes.toggle() } label: {
                Label("Notes", systemImage: model.sessionNotes.isEmpty ? "note.text" : "note.text.badge.plus")
            }
            .sheet(isPresented: $showNotes) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Test notes").font(.headline)
                    Text("Camera condition, lighting or observations. Changes are saved with this test.")
                        .font(.caption).foregroundStyle(.secondary)
                    TextField("Camera condition, lighting or observations…", text: $model.sessionNotes, axis: .vertical)
                        .lineLimit(5...8)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityLabel("Session notes")
                    HStack { Spacer(); Button("Done") { showNotes = false }.keyboardShortcut(.defaultAction) }
                }
                .padding(20).frame(width: 420)
            }
        }
        .controlSize(.small)
    }
}

private struct SummaryMetricCard: View {
    let title: String
    let value: String
    let detail: String
    let symbol: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(title, systemImage: symbol)
                .font(.caption.weight(.medium)).foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 22, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .minimumScaleFactor(0.7).lineLimit(1)
                .textSelection(.enabled)
            Text(detail).font(.caption2).foregroundStyle(.secondary)
                .lineLimit(2, reservesSpace: true)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .padding(10)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(.quaternary))
        .accessibilityElement(children: .combine)
    }
}

private struct RepeatabilitySummaryView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        let target = model.selectedRecord?.nominalDenominator ?? model.nominalDenominator
        let direction = model.selectedRecord?.direction ?? model.direction
        let context = (model.selectedRecord ?? model.currentRecords.last)?.resultContextID
        let durations = model.currentRecords.filter {
            !$0.isExcluded && $0.nominalDenominator == target && $0.direction == direction && $0.result.quality != .invalid && $0.resultContextID == context
        }.compactMap { $0.result.center.durationMS }.filter { $0 > 0 }
        let mean = durations.isEmpty ? nil : durations.reduce(0, +) / Double(durations.count)
        let deviation: Double? = {
            guard let mean, durations.count > 1 else { return nil }
            let variance = durations.reduce(0) { $0 + pow($1 - mean, 2) } / Double(durations.count - 1)
            return sqrt(variance)
        }()
        return HStack(spacing: 7) {
            Image(systemName: "chart.bar.xaxis")
            Text("\(durations.count) included at \(MeasurementFormat.speed(target))")
            if let mean {
                Text("· Mean \(MeasurementFormat.milliseconds(mean))")
            }
            if let deviation {
                Text("· SD \(MeasurementFormat.milliseconds(deviation))")
            }
            Spacer(minLength: 0)
        }
        .font(.caption).foregroundStyle(.secondary)
        .help("Mean and sample standard deviation use valid exposures at the same camera setting, direction, tester identity, measurement method and mode. Excluded readings are omitted; at least two readings are needed for standard deviation.")
    }
}

private struct MeasurementTableView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Text("Readings").font(.headline)
                Text("\(model.currentRecords.count)")
                    .font(.caption.weight(.medium)).foregroundStyle(.secondary)
                Spacer()
                if model.canUndoDelete {
                    Button("Undo delete") { model.undoDelete() }.buttonStyle(.borderless)
                }
                Button(role: .destructive) {
                    model.deleteSelectedReading()
                } label: {
                    Label("Delete reading", systemImage: "trash")
                }
                .disabled(model.selectedRecord == nil)
                .help("Delete the selected reading. Undo delete restores it, including its original data.")
                Toggle("Follow latest", isOn: $model.followLatest)
                    .toggleStyle(.checkbox).font(.caption)
                    .help("Select each new reading as it arrives. Turn this off to keep inspecting an earlier reading.")
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            if model.currentRecords.isEmpty {
                VStack(spacing: 8) {
                    Label("Ready for your first reading", systemImage: "waveform.path")
                        .font(.headline)
                    Text(model.isDemoMode ? "Choose Add demo reading to explore measurements." : model.currentSession?.tester?.model.supportsManualEntry == true ? "Choose Add manual reading to copy the tester’s result." : "Connect your Shutter Lover and release the camera shutter.")
                        .font(.callout).foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(16)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Table(model.currentRecords, selection: $model.selectedRecordID) {
                    TableColumn("#") { record in
                        Text("\((model.currentRecords.firstIndex { $0.id == record.id } ?? 0) + 1)")
                            .foregroundStyle(.secondary)
                    }.width(30)
                    TableColumn("Time") { record in
                        Text(record.capturedAt, format: .dateTime.hour().minute().second())
                    }.width(min: 74, ideal: 80)
                    TableColumn("Camera setting") { record in
                        Text(MeasurementFormat.speed(record.nominalDenominator))
                    }.width(min: 85, ideal: 100)
                    TableColumn("Exposure") { record in
                        Text(MeasurementFormat.milliseconds(record.result.center.durationMS))
                    }.width(min: 82, ideal: 100)
                    TableColumn("Difference") { record in
                        Text(MeasurementFormat.stops(record.result.exposureErrorStops))
                    }.width(min: 80, ideal: 100)
                    TableColumn("Quality") { record in
                        HStack(spacing: 5) {
                            Image(systemName: record.isExcluded ? "minus.circle" : MeasurementFormat.qualitySymbol(record.result.quality))
                            Text(record.isExcluded ? "Excluded" : record.result.quality.title)
                        }
                        .foregroundStyle(record.isExcluded ? Color.secondary : MeasurementFormat.qualityColor(record.result.quality))
                    }.width(min: 85, ideal: 100)
                }
                .monospacedDigit()
                .onDeleteCommand(perform: model.deleteSelectedReading)
                .contextMenu(forSelectionType: UUID.self) { recordIDs in
                    if let id = recordIDs.first, let record = model.currentRecords.first(where: { $0.id == id }) {
                        Button(record.isExcluded ? "Include in statistics" : "Exclude from statistics") {
                            model.toggleExcluded(record.id)
                        }
                        Button("Show reading details") {
                            model.selectedRecordID = record.id
                            model.showInspector = true
                        }
                        Divider()
                        Button("Delete reading", role: .destructive) { model.deleteReading(record.id) }
                    }
                }
            }
        }
        .frame(minHeight: 150, maxHeight: .infinity)
    }
}

private extension Text {
    func setupLabel() -> some View {
        font(.system(size: 9, weight: .semibold)).tracking(0.8).foregroundStyle(.secondary)
    }
}
