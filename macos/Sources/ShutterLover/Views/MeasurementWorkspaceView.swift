import SwiftUI
import MeasurementCore

struct MeasurementWorkspaceView: View {
    @EnvironmentObject private var model: AppModel
    @State private var editingTest: CaptureSession?
    @State private var pendingAssignment: UUID?

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    workspaceHeader
                    cameraMembership
                    SessionSetupView()
                    capturePrompt
                    summaryMetrics
                    RepeatabilitySummaryView()
                    if let session = model.currentSession, session.cameraID != nil {
                        CameraCoverageView(session: session, plannedSpeeds: session.plannedSpeeds ?? [])
                    }
                }
                .padding(22)
            }
            .frame(maxHeight: 450)
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
            Text("Choose the camera that produced these readings. The original name and measurements are retained, and the date of this assignment is recorded. An Armarium-linked camera enables results export back to that exact catalogue item.")
        }
    }

    @ViewBuilder private var cameraMembership: some View {
        if let session = model.currentSession {
            HStack(spacing: 12) {
                if session.demo {
                    Label("Demo test", systemImage: "play.rectangle")
                        .foregroundStyle(.orange)
                } else if let cameraID = session.cameraID, let camera = model.cameras.first(where: { $0.id == cameraID }) {
                    Button { model.selectCamera(cameraID) } label: { Label(camera.name, systemImage: "camera") }
                    Text(session.displayTitle).font(.caption).foregroundStyle(.secondary)
                } else {
                    Menu("Assign this test to a camera") {
                        ForEach(model.cameras) { camera in
                            Button(camera.name) { pendingAssignment = camera.id }
                        }
                        Divider()
                        Button("Add a camera first…", action: model.newCamera)
                        Button("Import Armarium camera catalogue…", action: model.importCameraCatalogue)
                    }
                    .help("Choose the physical camera tested. Names are never matched automatically.")
                }
                Spacer()
                Button("Test details") { editingTest = session }
                Button("Delete test…", role: .destructive) { model.pendingDeleteSessionID = session.id }
                    .disabled(!model.canTrashSession(session.id))
                    .help(model.canTrashSession(session.id)
                          ? "Move this test and its readings to Trash. You can restore it later."
                          : "Disconnect the tester before deleting the test that is receiving readings.")
                if !session.demo && model.activeCaptureSessionID != nil && model.activeCaptureSessionID != session.id {
                    Button("Record into this test", action: model.recordIntoSelectedTest)
                        .help("Explicitly change the destination for future readings to this test.")
                }
            }
        }
    }

    private var workspaceHeader: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 5) {
                Text("Measure with confidence")
                    .font(.system(size: 24, weight: .semibold, design: .rounded))
                Text("Set the camera, take a reading, understand the result.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            Spacer()
            if model.isDemoMode {
                Label("SIMULATED DATA", systemImage: "play.rectangle.fill")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.orange)
                    .padding(.horizontal, 10).padding(.vertical, 7)
                    .background(.orange.opacity(0.1), in: Capsule())
            }
        }
    }

    private var capturePrompt: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: model.isDemoMode ? "play.circle" : "camera.aperture")
                .font(.title2)
                .foregroundStyle(model.isDemoMode ? Color.orange : Color.accentColor)
            VStack(alignment: .leading, spacing: 3) {
                Text(model.isDemoMode ? "Explore without a connected tester" : "Set your camera to \(MeasurementFormat.speed(model.nominalDenominator))")
                    .font(.callout.weight(.semibold))
                Text(model.isDemoMode ? "Demo readings are simulated and saved separately." : "For Shutter Lover: physically reset the tester, then release the camera shutter.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            if model.isDemoMode {
                Menu {
                    Button("Add partial demo reading") { model.addDemoReading(partial: true) }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuStyle(.borderlessButton)
                .frame(width: 24)
                .help("Add a demo reading with a missing sensor event.")
                Button("Add demo reading") { model.addDemoReading() }
                    .buttonStyle(.borderedProminent)
            } else {
                Button("Setup guide") { model.showGuide = true }
            }
        }
        .padding(12)
        .background(model.isDemoMode ? Color.orange.opacity(0.055) : Color.accentColor.opacity(0.055), in: RoundedRectangle(cornerRadius: 10))
    }

    private var summaryMetrics: some View {
        let record = model.selectedRecord ?? model.currentRecords.last
        let result = record?.result
        return HStack(spacing: 12) {
            SummaryMetricCard(
                title: "Center exposure",
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
                detail: "Measured between corner sensors",
                symbol: "arrow.right.to.line"
            )
        }
    }

    private var statusBar: some View {
        HStack(spacing: 8) {
            Image(systemName: model.isDemoMode ? "play.rectangle" : model.isConnected ? "cable.connector" : "cable.connector.slash")
            Text(model.isDemoMode ? "Demo session" : model.connectionStatus)
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
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 18) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("CAMERA").setupLabel()
                    TextField("Camera name or serial number", text: $model.cameraName)
                        .textFieldStyle(.roundedBorder)
                        .help("Identify the camera being measured. The name is saved with this session.")
                }
                .frame(maxWidth: .infinity)
                VStack(alignment: .leading, spacing: 6) {
                    Text("CAMERA SETTING").setupLabel()
                    NominalSpeedPicker(value: $model.nominalDenominator)
                }
                .frame(width: 165)
                VStack(alignment: .leading, spacing: 6) {
                    Text("CURTAIN DIRECTION").setupLabel()
                    Picker("Curtain direction", selection: $model.direction) {
                        Text("Unknown").tag(CurtainDirection.unknown)
                        Text("Horizontal").tag(CurtainDirection.horizontal)
                        Text("Vertical").tag(CurtainDirection.vertical)
                    }
                    .labelsHidden()
                    .help("Choose the direction the shutter curtains cross the frame. This affects full-frame travel estimates only.")
                }
                .frame(width: 140)
            }
            HStack(alignment: .center, spacing: 16) {
                Toggle("Suggest next speed", isOn: $model.autoAdvance)
                    .toggleStyle(.checkbox)
                    .help("After a complete reading, advance the suggested setting from 1/15 through 1/1000 s. Change the camera speed yourself.")
                Text("Settings apply to future readings. Change the camera manually.")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer(minLength: 0)
                Button {
                    showNotes.toggle()
                } label: {
                    Label("Notes", systemImage: showNotes ? "chevron.up" : "note.text")
                }
                .buttonStyle(.borderless)
            }
            if showNotes {
                TextField("Session notes: camera condition, lighting, service history…", text: $model.sessionNotes, axis: .vertical)
                    .lineLimit(2...4)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel("Session notes")
            }
        }
        .padding(14)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(.quaternary))
    }
}

private struct SummaryMetricCard: View {
    let title: String
    let value: String
    let detail: String
    let symbol: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: symbol)
                .font(.caption.weight(.medium)).foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 25, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .minimumScaleFactor(0.7).lineLimit(1)
                .textSelection(.enabled)
            Text(detail).font(.caption2).foregroundStyle(.secondary).lineLimit(2)
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 82, alignment: .leading)
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
        let durations = model.currentRecords.filter {
            !$0.isExcluded && $0.nominalDenominator == target && $0.direction == direction && $0.result.quality != .invalid
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
        .help("Mean and sample standard deviation use valid center durations at the same camera setting and curtain direction. Excluded readings are omitted; at least two readings are needed for standard deviation.")
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
            .padding(.horizontal, 22).padding(.vertical, 13)
            if model.currentRecords.isEmpty {
                ContentUnavailableView {
                    Label("Ready for your first reading", systemImage: "waveform.path")
                } description: {
                    Text(model.isDemoMode ? "Use Add demo reading to explore measurements and explanations." : "Connect your Shutter Lover, check the setup guide, and release the camera shutter.")
                } actions: {
                    Button("Read the setup guide") { model.showGuide = true }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Table(model.currentRecords, selection: $model.selectedRecordID) {
                    TableColumn("#") { record in
                        Text("\((model.currentRecords.firstIndex { $0.id == record.id } ?? 0) + 1)")
                            .foregroundStyle(.secondary)
                    }.width(30)
                    TableColumn("Received") { record in
                        Text(record.capturedAt, format: .dateTime.hour().minute().second())
                    }.width(min: 74, ideal: 80)
                    TableColumn("Camera setting") { record in
                        Text(MeasurementFormat.speed(record.nominalDenominator))
                    }.width(min: 85, ideal: 100)
                    TableColumn("Center") { record in
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
        .frame(minHeight: 220, maxHeight: .infinity)
    }
}

private extension Text {
    func setupLabel() -> some View {
        font(.system(size: 9, weight: .semibold)).tracking(0.8).foregroundStyle(.secondary)
    }
}
