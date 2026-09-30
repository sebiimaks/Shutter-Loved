import SwiftUI
import MeasurementCore
import DeviceTransport

struct ContentView: View {
    @EnvironmentObject private var model: AppModel
    @State private var showConnection = false
    @State private var cameraSearch = ""

    private var visibleCameras: [CameraProfile] {
        model.cameras.filter { camera in
            cameraSearch.isEmpty || [camera.name, camera.manufacturer, camera.model, camera.serial, camera.inventoryID, camera.tags, camera.nickname].joined(separator: " ").localizedCaseInsensitiveContains(cameraSearch)
        }
    }

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 185, ideal: 225, max: 300)
        } detail: {
            Group {
                if model.showGuide {
                    GuideView()
                } else if model.showCameraLibrary {
                    if model.selectedCamera != nil { CameraDetailView() }
                    else { cameraLibraryWelcome }
                } else {
                    MeasurementWorkspaceView()
                }
            }
            .frame(minWidth: 610)
            .inspector(isPresented: Binding(
                get: { model.showInspector && !model.showGuide && !model.showCameraLibrary },
                set: { if !model.showGuide { model.showInspector = $0 } }
            )) {
                ReadingInspectorView()
                    .inspectorColumnWidth(min: 285, ideal: 320, max: 430)
            }
            .toolbar { workspaceToolbar }
            .safeAreaInset(edge: .bottom, spacing: 0) { captureDestination }
        }
        .sheet(item: $model.editingCamera) { camera in
            CameraEditorView(camera: camera) { model.saveCamera($0) }
        }
        .sheet(isPresented: $model.showTesters) { TesterInventoryView() }
        .sheet(isPresented: Binding(get: { model.manualEntrySessionID != nil }, set: { if !$0 { model.manualEntrySessionID = nil } })) {
            if let id = model.manualEntrySessionID { ManualReadingView(sessionID: id) }
        }
        .sheet(isPresented: $model.showCatalogueReview) {
            if let review = model.catalogueReview { CameraCatalogueReviewView(review: review).environmentObject(model) }
        }
        .confirmationDialog("Delete this test?", isPresented: Binding(
            get: { model.pendingDeleteSessionID != nil },
            set: { if !$0 { model.pendingDeleteSessionID = nil } }
        ), titleVisibility: .visible, presenting: model.sessions.first(where: { $0.id == model.pendingDeleteSessionID })) { session in
            Button("Move to Trash", role: .destructive) {
                model.trashSession(session.id)
                model.pendingDeleteSessionID = nil
            }
            Button("Cancel", role: .cancel) { model.pendingDeleteSessionID = nil }
        } message: { session in
            Text("\(session.cameraName.isEmpty ? "Untitled camera" : session.cameraName) and its \(session.records.count) readings will move to Trash. You can restore the entire test from the sidebar.")
        }
        .alert("Shutter Loved", isPresented: Binding(
            get: { model.errorMessage != nil },
            set: { if !$0 { model.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { model.errorMessage = nil }
        } message: {
            Text(model.errorMessage ?? "")
        }
    }

    private var sidebar: some View {
        List {
            Section {
                HStack(spacing: 10) {
                    Image(systemName: "camera.aperture")
                        .font(.system(size: 27, weight: .medium))
                        .foregroundStyle(Color.accentColor)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Shutter Loved").font(.headline)
                        Text("Measurement studio").font(.caption).foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 10)
            }
            Section("Cameras") {
                TextField("Search cameras", text: $cameraSearch)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel("Search cameras")
                ForEach(visibleCameras) { camera in
                    Button { model.selectCamera(camera.id) } label: {
                        HStack(alignment: .top, spacing: 9) {
                            Image(systemName: "camera").padding(.top, 2)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(camera.name).font(.system(size: 12, weight: .semibold)).lineLimit(2)
                                Text(camera.inventoryID.isEmpty ? (camera.catalogueID == nil ? "Local camera" : "Armarium linked") : camera.inventoryID).font(.caption2).foregroundStyle(.secondary)
                                Text("\(model.cameraSessions(camera.id).count) tests\(camera.archived ? " · Archived" : "")").font(.caption2).foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(9)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(model.showCameraLibrary && !model.showGuide && model.selectedCameraID == camera.id ? Color.accentColor.opacity(0.13) : .clear, in: RoundedRectangle(cornerRadius: 8))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .listRowInsets(EdgeInsets(top: 3, leading: 0, bottom: 3, trailing: 0))
                }
                if visibleCameras.isEmpty { Text(cameraSearch.isEmpty ? "Add a camera or import your Armarium catalogue." : "No matching cameras.").font(.caption).foregroundStyle(.secondary) }
            }
            Section("Unassigned tests & demos") {
                if model.demoSessionCount > 0 {
                    Button { model.setShowDemoSessions(!model.showDemoSessions) } label: {
                        Label(model.showDemoSessions ? "Hide demo tests" : "Show demo tests (\(model.demoSessionCount))", systemImage: model.showDemoSessions ? "eye.slash" : "eye")
                            .font(.caption)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Show or hide simulated tests in the sidebar. Their readings remain saved.")
                }
                ForEach(model.sidebarSessions) { session in
                    ZStack(alignment: .topTrailing) {
                        Button {
                            model.showGuide = false
                            model.selectSession(session.id)
                        } label: {
                            SessionSidebarRow(session: session, selected: !model.showGuide && !model.showCameraLibrary && session.id == model.selectedSessionID)
                        }
                        .buttonStyle(.plain)
                        Button { model.pendingDeleteSessionID = session.id } label: {
                            Image(systemName: "trash").frame(width: 24, height: 24)
                        }
                        .buttonStyle(.borderless)
                        .padding(.top, 4).padding(.trailing, 3)
                        .disabled(!model.canTrashSession(session.id))
                        .accessibilityLabel("Delete test: \(session.cameraName.isEmpty ? "Untitled camera" : session.cameraName)")
                        .help(model.activeCaptureSessionID == session.id ? "Disconnect the tester before deleting its active test." : "Delete this entire test. It can be restored from Trash.")
                    }
                    .contextMenu {
                        Button("Open test") { model.selectSession(session.id) }
                        Button("Delete test…", role: .destructive) { model.pendingDeleteSessionID = session.id }
                            .disabled(!model.canTrashSession(session.id))
                        if session.demo {
                            Divider()
                            Button("Hide demo tests") { model.setShowDemoSessions(false) }
                        }
                    }
                    .listRowInsets(EdgeInsets(top: 3, leading: 0, bottom: 3, trailing: 0))
                }
                if model.sidebarSessions.isEmpty {
                    Text("Existing and imported sessions can be assigned to a camera.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            if !model.trashedSessions.isEmpty {
                Section("Trash") {
                    ForEach(model.trashedSessions) { session in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(session.displayTitle).font(.caption.weight(.medium)).lineLimit(2)
                            HStack {
                                Text("\(session.records.count) readings").font(.caption2).foregroundStyle(.secondary)
                                Spacer()
                                Button("Restore") { model.restoreSession(session.id) }
                                    .buttonStyle(.borderless).font(.caption)
                                    .help("Restore this test with all its original readings.")
                            }
                        }.padding(.vertical, 5)
                        .contextMenu {
                            Button("Restore test") { model.restoreSession(session.id) }
                        }
                    }
                }
            }
            Section("Equipment") {
                Button { model.showTesters = true } label: {
                    Label("My testers", systemImage: "sensor.tag.radiowaves.forward")
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 6).contentShape(Rectangle())
                }.buttonStyle(.plain)
            }
            Section("Learn") {
                Button {
                    model.showGuide = true
                } label: {
                    Label("Measurement guide", systemImage: "book.closed")
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 6)
                        .foregroundStyle(model.showGuide ? Color.accentColor : .primary)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom) {
            VStack(alignment: .leading, spacing: 8) {
                Button { model.newCamera() } label: {
                    Label("Add camera", systemImage: "plus")
                        .frame(maxWidth: .infinity)
                }
                Button("Import Armarium cameras…", action: model.importCameraCatalogue).font(.caption)
                Text("Readings stay on this Mac until you export them.")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            .padding(14)
        }
    }

    private var cameraLibraryWelcome: some View {
        ContentUnavailableView {
            Label("Your tested cameras", systemImage: "camera")
        } description: {
            Text("Keep a photograph, camera details, test results and service history for each physical camera. Existing sessions remain in Unassigned tests until you link them.")
        } actions: {
            HStack(spacing: 12) {
                Button("Add camera", action: model.newCamera).buttonStyle(.borderedProminent)
                Button("Import Armarium camera catalogue…", action: model.importCameraCatalogue)
                    .buttonStyle(.bordered)
            }
            .fixedSize()
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .navigationTitle("Camera library")
    }

    @ViewBuilder private var captureDestination: some View {
        if let session = model.activeCaptureSession {
            HStack(spacing: 10) {
                Image(systemName: "record.circle").foregroundStyle(model.isConnected ? .green : .orange)
                Text("Recording to \(session.cameraName) · \(session.displayTitle)").lineLimit(1)
                Text(model.isConnected ? "Connected" : "Reconnecting").foregroundStyle(.secondary)
                Spacer()
                Button("Return to live test", action: model.returnToCapture)
            }
            .font(.caption).padding(10).background(.bar)
        }
    }

    @ToolbarContentBuilder
    private var workspaceToolbar: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            Button {
                showConnection.toggle()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "cable.connector")
                    Text(model.isConnected ? "Tester connected" : model.isConnecting ? "Connecting…" : "Connect tester")
                }.fixedSize()
            }
            .help("Choose a USB serial device and open the measurement connection.")
            .popover(isPresented: $showConnection, arrowEdge: .bottom) {
                ConnectionPopover()
            }
        }
        ToolbarItemGroup(placement: .primaryAction) {
            Menu {
                Button("Add camera…", action: model.newCamera)
                Button("New Baby tester test") { model.newManualSession(cameraID: model.showCameraLibrary ? model.selectedCameraID : nil) }
                if let camera = model.selectedCamera {
                    Button("New test for \(camera.name)") { model.newCameraTest(camera.id) }
                }
                Divider()
                Button("New device session", systemImage: "plus") {
                    model.newSession(demo: false)
                    model.showGuide = false
                }
                Button("New demo session", systemImage: "play.rectangle") {
                    model.newSession(demo: true)
                    model.showGuide = false
                }
                Divider()
                Button("Import Armarium cameras…", action: model.importCameraCatalogue)
                Button("Import full camera archive as a copy…", action: model.importCameraArchive)
                Button("Import legacy session as a copy…", systemImage: "square.and.arrow.down") { model.importSession() }
            } label: {
                Label("New session", systemImage: "plus")
            }
            .help("Start a new session or import a previously exported session.")

            if !model.showCameraLibrary && !model.showGuide {
              Menu {
                if let session = model.currentSession {
                    Button("Test results for Armarium (JSON)…") { model.exportTesterResults(session.id) }
                }
                Button("Export complete session…", systemImage: "doc") { model.exportSession() }
                Button("Export CSV table…", systemImage: "tablecells") { model.exportCSV() }
                Divider()
                Button("Copy results", systemImage: "doc.on.doc") { model.copyResults() }
            } label: {
                Label("Export", systemImage: "square.and.arrow.up")
            }
            .disabled(model.currentSession == nil)
            .help("Export the original data and setup as a session, or save a spreadsheet table.")
            }

            Button {
                model.showInspector.toggle()
            } label: {
                Label("Reading details", systemImage: "sidebar.right")
            }
            .disabled(model.showGuide || model.showCameraLibrary)
            .help("Show measurements, explanations, and original data for the selected reading.")
        }
    }
}

private struct SessionSidebarRow: View {
    let session: CaptureSession
    let selected: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: session.demo ? "play.rectangle" : "camera")
                .foregroundStyle(session.demo ? Color.orange : Color.secondary)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 4) {
                Text(session.cameraName.isEmpty ? "Untitled camera" : session.cameraName)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                Text(session.createdAt, format: .dateTime.month(.abbreviated).day())
                    .font(.caption2).foregroundStyle(.secondary)
                HStack(spacing: 5) {
                    Text("\(session.records.count) readings")
                    if session.demo { Text("· Demo").foregroundStyle(.orange) }
                }
                .font(.caption2).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.trailing, 24)
        .padding(9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(selected ? Color.accentColor.opacity(0.13) : .clear, in: RoundedRectangle(cornerRadius: 8))
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }
}

private struct ConnectionPopover: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Connect your tester", systemImage: "cable.connector")
                .font(.headline)
            Text("Choose the USB serial port for your Shutter Lover. Use a data cable and check that the tester has power.")
                .font(.callout).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Picker("Device", selection: $model.selectedPortPath) {
                    Text(model.devices.isEmpty ? "No serial devices found" : "Choose a device").tag("")
                    ForEach(model.devices) { device in
                        Text(device.name).tag(device.path)
                    }
                }
                .labelsHidden()
                .disabled(model.isConnected || model.isConnecting)
                Button { model.refreshDevices() } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .help("Refresh available USB serial devices.")
                .disabled(model.isConnecting)
            }
            if !model.selectedPortPath.isEmpty {
                Text(model.selectedPortPath).font(.caption.monospaced()).foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            if let device = model.selectedSerialDevice {
                Picker("Owned tester", selection: $model.selectedConnectionTesterID) {
                    Text("Match saved USB identity automatically").tag(UUID?.none)
                    ForEach(model.ownedTesters) { tester in
                        Text("\(tester.displayName) · \(tester.model.displayName)").tag(Optional(tester.id))
                    }
                }.disabled(model.isConnected || model.isConnecting || model.activeCaptureSessionID != nil)
                if let matched = model.matchedOwnedTester(for: device), model.selectedConnectionTesterID == nil {
                    Label("Matched: \(matched.displayName)", systemImage: "checkmark.circle").font(.caption)
                } else if model.selectedConnectionTesterID == nil {
                    Text("Individual tester not assigned. Received packets can identify the model, but not the physical unit.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if let identity = device.testerUSBIdentity {
                    Text(String(format: "USB %04X:%04X · %@", identity.vendorID, identity.productID, identity.serialNumber))
                        .font(.caption.monospaced()).textSelection(.enabled)
                } else {
                    Text("No unique USB serial is available. Select your tester for this connection; the port will not be saved as a permanent identity.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if let problem = model.connectionIdentityProblem { Text(problem).font(.caption).foregroundStyle(.orange) }
                if !model.connectionTester(for: device).model.supportsUSBRecording {
                    Text("Baby testers use manual entry in this version. Their USB identity can still be associated in My testers.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Button("Manage my testers…") { model.showTesters = true }
            }
            Label(model.connectionStatus, systemImage: model.isConnected ? "circle.fill" : "circle")
                .font(.callout)
                .foregroundStyle(model.isConnected ? Color.green : .secondary)
            if case .ready(let placement) = model.connectionPositioningGuidance {
                VStack(alignment: .leading, spacing: 5) {
                    Label("\(AppModel.positioningNumber(placement.ledToMountDistanceMM)) mm · LEDs to mount", systemImage: "ruler")
                        .font(.headline)
                    Text("\(placement.cameraName) · \(placement.mountName)\n\(AppModel.positioningNumber(placement.calibrationDistanceMM)) − \(AppModel.positioningNumber(placement.flangeDistanceMM)) mm\(placement.usesCustomDistance ? " · custom flange value" : "")")
                        .font(.caption).foregroundStyle(.secondary)
                    Text("Lens removed; sensor at the film plane. Measure to the lens-seating flange, without a mount adapter.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Text("The connection listens for measurements. Reset the tester and release the camera shutter using their physical controls.")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                if model.isConnected || model.isConnecting || model.activeCaptureSessionID != nil {
                    Button("Disconnect") { model.disconnect() }
                } else {
                    Button("Connect") { model.connect() }
                        .buttonStyle(.borderedProminent)
                        .disabled(model.selectedPortPath.isEmpty || model.connectionIdentityProblem != nil || model.selectedSerialDevice.map { !model.connectionTester(for: $0).model.supportsUSBRecording } == true)
                }
                Spacer()
                Button("Explore demo") {
                    model.newSession(demo: true)
                    model.showGuide = false
                }
                .disabled(model.isConnecting)
            }
            DisclosureGroup("Connection diagnostics") {
                ScrollView {
                    Text(model.diagnostics.isEmpty ? "No diagnostic messages yet." : model.diagnostics.joined(separator: "\n"))
                        .font(.caption.monospaced())
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
                .frame(maxHeight: 140)
            }
            .font(.caption)
        }
        .padding(20)
        .frame(width: 410)
        .onAppear { model.refreshDevices() }
    }
}
