import SwiftUI
import AppKit
import MeasurementCore

struct CameraDetailView: View {
    @EnvironmentObject private var model: AppModel
    @State private var tab: CameraPageTab = .results
    @State private var selectedTestID: UUID?
    @State private var editingTest: CaptureSession?
    @State private var editingService: CameraServiceEvent?
    @State private var showingComparison = false
    @State private var comparisonBefore: UUID?
    @State private var comparisonAfter: UUID?

    private var camera: CameraProfile? { model.selectedCamera }
    private var tests: [CaptureSession] {
        guard let camera else { return [] }
        return model.cameraSessions(camera.id).sorted { $0.createdAt > $1.createdAt }
    }
    private var selectedTest: CaptureSession? { tests.first { $0.id == selectedTestID } ?? tests.first }

    var body: some View {
        Group {
            if let camera {
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        CameraHeaderView(camera: camera, latestTest: tests.first, selectedTest: selectedTest)
                        Picker("Camera section", selection: $tab) {
                            ForEach(CameraPageTab.allCases) { Text($0.rawValue).tag($0) }
                        }.pickerStyle(.segmented).labelsHidden()
                        page(camera)
                    }.padding(24).frame(maxWidth: 1200, alignment: .leading).frame(maxWidth: .infinity)
                }
                .navigationTitle(camera.name)
                .onChange(of: camera.id) { _, _ in selectedTestID = nil; tab = .results }
            } else {
                ContentUnavailableView {
                    Label("Your camera library", systemImage: "camera.on.rectangle")
                } description: {
                    Text("Add one record for each physical camera, then keep its photographs, tests and service history together.")
                } actions: {
                    Button("Add camera") { model.newCamera() }.buttonStyle(.borderedProminent)
                }
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .sheet(item: $editingTest) { test in
            CameraTestEditorView(session: test) { model.updateTestDetails($0) }
        }
        .sheet(item: $editingService) { event in
            CameraServiceEditorView(event: event, sessions: tests) { updated in
                guard var camera = model.selectedCamera else { return }
                if let index = camera.serviceEvents.firstIndex(where: { $0.id == updated.id }) {
                    camera.serviceEvents[index] = updated
                } else { camera.serviceEvents.append(updated) }
                model.saveCamera(camera)
            }
        }
        .sheet(isPresented: $showingComparison) {
            CameraComparisonView(tests: tests, beforeID: comparisonBefore, afterID: comparisonAfter)
        }
    }

    @ViewBuilder private func page(_ camera: CameraProfile) -> some View {
        switch tab {
        case .results: results(camera)
        case .history: history(camera)
        case .details: CameraMetadataView(camera: camera)
        case .service: services(camera)
        }
    }

    private func results(_ camera: CameraProfile) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            if let test = selectedTest {
                HStack {
                    Picker("Test", selection: Binding(get: { test.id }, set: { selectedTestID = $0 })) {
                        ForEach(tests) { test in
                            Text(test.title?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
                                 ? "\(test.displayTitle) · \(test.createdAt.formatted(date: .abbreviated, time: .shortened))"
                                 : test.displayTitle).tag(test.id)
                        }
                    }.frame(maxWidth: 480)
                    Spacer()
                    Button("Edit test details") { editingTest = test }
                    Button("Inspect readings") { model.openCameraTest(test.id) }
                }
                if test.demo { Label("Simulated test · not device measurements", systemImage: "play.rectangle").foregroundStyle(.orange) }
                CameraTestResultsView(session: test, camera: camera) { recordID in
                    model.openCameraTest(test.id)
                    model.selectedRecordID = recordID
                    model.showInspector = true
                }
                CameraTestProvenanceView(session: test)
            } else {
                CameraEmptyState(title: "No tests yet", symbol: "waveform.path", message: "Start a test to save measurements against this camera. Older unassigned sessions can be linked from the sidebar.")
                Button("Start first test") { model.newCameraTest(camera.id) }.buttonStyle(.borderedProminent)
            }
        }
    }

    private func history(_ camera: CameraProfile) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Test history").font(.title3.weight(.semibold))
                    Text("Each dated test keeps its own readings and captured camera identity.").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Compare tests", systemImage: "arrow.left.arrow.right") {
                    comparisonBefore = tests.dropFirst().first?.id
                    comparisonAfter = tests.first?.id
                    showingComparison = true
                }.disabled(tests.filter { !$0.demo }.count < 2)
            }
            if tests.isEmpty { CameraEmptyState(title: "No test history", symbol: "clock", message: "Your first test will appear here.") }
            ForEach(tests) { test in
                historyRow(test)
            }
            if !camera.serviceEvents.isEmpty {
                Divider().padding(.vertical, 5)
                Text("Service milestones").font(.headline)
                ForEach(camera.serviceEvents.sorted { $0.date > $1.date }) { event in
                    HStack(spacing: 12) {
                        Image(systemName: "wrench.and.screwdriver").foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(event.title).font(.callout.weight(.medium))
                            Text(event.date, format: .dateTime.day().month(.abbreviated).year()).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("View service") { tab = .service }
                    }.cameraCard()
                }
            }
        }
    }

    private func historyRow(_ test: CaptureSession) -> some View {
        HStack(spacing: 14) {
            Image(systemName: test.demo ? "play.rectangle" : "waveform.path").font(.title2).foregroundStyle(Color.accentColor)
            VStack(alignment: .leading, spacing: 5) {
                Text(test.displayTitle).font(.headline)
                Text(test.createdAt, format: .dateTime.day().month(.abbreviated).year().hour().minute()).font(.caption).foregroundStyle(.secondary)
                let summaries = CameraResultGroup.groups(for: test)
                Text("\(test.records.count) readings · \(summaries.reduce(0) { $0 + $1.count }) included complete · \(summaries.count) setting/direction groups")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button("Results") { selectedTestID = test.id; tab = .results }
            Menu {
                Button("Edit test details…") { editingTest = test }
                Button("Inspect original readings") { model.openCameraTest(test.id) }
                Button("Save photo report…") { if let camera { model.exportCameraReport(camera.id, sessionID: test.id) } }
                Button("Export ArmariumLucis results…") { model.exportTesterResults(test.id) }
                    .disabled(test.demo || test.cameraSnapshot?.catalogueCameraID == nil)
                Divider()
                Button("Delete test…", role: .destructive) { model.pendingDeleteSessionID = test.id }
                    .disabled(!model.canTrashSession(test.id))
            } label: { Image(systemName: "ellipsis.circle") }.menuStyle(.borderlessButton).frame(width: 24)
                .help("Test actions")
        }.cameraCard()
    }

    private func services(_ camera: CameraProfile) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Service & notes").font(.title3.weight(.semibold))
                Spacer()
                Button("Add service event", systemImage: "plus") { editingService = CameraServiceEvent(title: "") }
            }
            if camera.serviceEvents.isEmpty {
                CameraEmptyState(title: "Build a service timeline", symbol: "wrench.and.screwdriver", message: "Record repairs, adjustments and cleaning. Link tests before and after the work to keep the evidence together.")
            }
            ForEach(camera.serviceEvents.sorted { $0.date > $1.date }) { event in serviceCard(event) }
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Camera notes").font(.headline)
                    Spacer()
                    Button("Edit notes") { model.editingCamera = camera }
                }
                Text(camera.notes.isEmpty ? "No camera notes yet." : camera.notes)
                    .foregroundStyle(camera.notes.isEmpty ? .secondary : .primary)
                    .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
            }.cameraCard()
        }
    }

    private func serviceCard(_ event: CameraServiceEvent) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                Image(systemName: "wrench.and.screwdriver").foregroundStyle(Color.accentColor)
                VStack(alignment: .leading, spacing: 4) {
                    Text(event.title).font(.headline)
                    Text(event.date, format: .dateTime.day().month(.abbreviated).year()).font(.caption).foregroundStyle(.secondary)
                    if !event.provider.isEmpty { Text(event.provider).font(.callout).foregroundStyle(.secondary) }
                }
                Spacer()
                Button("Edit") { editingService = event }
            }
            if !event.notes.isEmpty { Text(event.notes).font(.callout).textSelection(.enabled) }
            HStack(spacing: 12) {
                if let id = event.beforeSessionID, let test = tests.first(where: { $0.id == id }) {
                    Button("Before: \(test.displayTitle)") { selectedTestID = id; tab = .results }.buttonStyle(.link)
                }
                if let id = event.afterSessionID, let test = tests.first(where: { $0.id == id }) {
                    Button("After: \(test.displayTitle)") { selectedTestID = id; tab = .results }.buttonStyle(.link)
                }
                Spacer()
                if let before = event.beforeSessionID, let after = event.afterSessionID,
                   tests.contains(where: { $0.id == before }), tests.contains(where: { $0.id == after }) {
                    Button("Compare") {
                        comparisonBefore = before; comparisonAfter = after; showingComparison = true
                    }
                }
            }
        }.cameraCard()
    }
}

private enum CameraPageTab: String, CaseIterable, Identifiable {
    case results = "Results", history = "Test history", details = "Camera details", service = "Service & notes"
    var id: String { rawValue }
}

private struct CameraHeaderView: View {
    @EnvironmentObject private var model: AppModel
    let camera: CameraProfile
    let latestTest: CaptureSession?
    let selectedTest: CaptureSession?

    var body: some View {
        HStack(alignment: .top, spacing: 24) {
            VStack(spacing: 8) {
                Button { model.chooseCameraPhoto(camera.id) } label: {
                    GeometryReader { proxy in
                        Group {
                            if let image = model.cameraImage(camera) {
                                Image(nsImage: image).resizable()
                                    .aspectRatio(contentMode: camera.photoFit ? .fit : .fill)
                                    .frame(width: proxy.size.width, height: proxy.size.height)
                                    .clipped()
                            } else {
                                VStack(spacing: 10) {
                                    Image(systemName: "camera.badge.ellipsis").font(.system(size: 34, weight: .light))
                                    Text("Add camera photo").font(.callout.weight(.medium))
                                    Text("3:2 · click or drop an image").font(.caption)
                                }.foregroundStyle(.secondary).frame(width: proxy.size.width, height: proxy.size.height)
                            }
                        }
                    }
                    .aspectRatio(3.0 / 2.0, contentMode: .fit)
                    .background(Color(nsColor: .controlBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(.quaternary))
                }.buttonStyle(.plain).help("Choose or replace the camera photograph.")
                    .accessibilityLabel("Camera photograph. Add or replace photo.")
                    .dropDestination(for: URL.self) { urls, _ in
                        guard let url = urls.first else { return false }
                        model.importCameraPhoto(url, cameraID: camera.id)
                        return true
                    }
                if camera.photoFilename != nil {
                    Picker("Photo presentation", selection: Binding(get: { camera.photoFit }, set: { fit in
                        var updated = camera; updated.photoFit = fit; model.saveCamera(updated)
                    })) {
                        Text("Crop to fill").tag(false)
                        Text("Fit entire photo").tag(true)
                    }.pickerStyle(.segmented).controlSize(.small)
                }
            }.frame(width: 250)
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Text("CAMERA RECORD").font(.system(size: 10, weight: .semibold)).tracking(1.3).foregroundStyle(.secondary)
                    if camera.archived { Text("Archived").font(.caption).foregroundStyle(.secondary) }
                    if camera.catalogueCameraID != nil { Label("ArmariumLucis", systemImage: "link").font(.caption).foregroundStyle(.secondary) }
                }
                Text(camera.name).font(.system(size: 28, weight: .semibold, design: .rounded)).textSelection(.enabled)
                let identity = [camera.manufacturer, camera.model].filter { !$0.isEmpty }.joined(separator: " · ")
                if !identity.isEmpty { Text(identity).font(.callout).foregroundStyle(.secondary) }
                HStack(spacing: 18) {
                    if !camera.serial.isEmpty { Label(camera.serial, systemImage: "number") }
                    if !camera.inventoryID.isEmpty { Label(camera.inventoryID, systemImage: "tag") }
                }.font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                Text(latestTest.map { "Last tested \($0.createdAt.formatted(date: .abbreviated, time: .shortened))" } ?? "Not yet tested")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer(minLength: 4)
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 10) { actions }
                    VStack(alignment: .leading, spacing: 10) { actions }
                }
            }.frame(maxWidth: .infinity, minHeight: 166, alignment: .leading)
        }
    }

    @ViewBuilder private var actions: some View {
        Button("New test", systemImage: "plus") { model.newCameraTest(camera.id) }.buttonStyle(.borderedProminent)
        Button("Edit camera") { model.editingCamera = camera }
        Menu {
            Button("Save photo report…", systemImage: "doc.richtext") { model.exportCameraReport(camera.id, sessionID: selectedTest?.id) }
            Button("Export camera archive…", systemImage: "archivebox") { model.exportCameraArchive(camera.id) }
            Divider()
            Button("Export ArmariumLucis results…", systemImage: "arrow.up.doc") {
                if let selectedTest { model.exportTesterResults(selectedTest.id) }
            }.disabled(selectedTest == nil || selectedTest?.demo == true || selectedTest?.cameraSnapshot?.catalogueCameraID == nil)
            Text("ArmariumLucis export requires a test linked to an imported catalogue profile.")
        } label: { Label("Export", systemImage: "square.and.arrow.up") }
        .fixedSize()
    }
}

private struct CameraTestResultsView: View {
    let session: CaptureSession
    let camera: CameraProfile
    let onInspect: (UUID) -> Void
    private var groups: [CameraResultGroup] { CameraResultGroup.groups(for: session) }
    private var tolerance: Double { session.toleranceStops ?? 1.0 / 3.0 }
    private var includedCount: Int { groups.reduce(0) { $0 + $1.count } }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            assessment
            CameraCoverageView(session: session, plannedSpeeds: session.plannedSpeeds ?? camera.plannedSpeeds)
            VStack(alignment: .leading, spacing: 12) {
                Text("Timing by camera setting").font(.headline)
                Text("Means use complete, included readings from this test, grouped by setting and curtain direction. Positive timing difference means a longer exposure; negative means shorter. SD is sample standard deviation and needs two readings.")
                    .font(.caption).foregroundStyle(.secondary)
                if groups.isEmpty {
                    Text("No complete included readings yet. Partial and excluded readings remain available in the original record.").foregroundStyle(.secondary).padding(.vertical, 8)
                } else {
                    ScrollView(.horizontal) {
                        Grid(alignment: .leading, horizontalSpacing: 20, verticalSpacing: 12) {
                            GridRow {
                                Text("Setting / direction"); Text("Mean center"); Text("Difference"); Text("SD"); Text("n"); Text("Mean assessment"); Text("")
                            }.font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                            Divider().gridCellUnsizedAxes(.horizontal)
                            ForEach(groups) { group in
                                CameraTimingRow(group: group, tolerance: tolerance) {
                                    if let record = group.records.last { onInspect(record.id) }
                                }
                            }
                        }.frame(minWidth: 650, alignment: .leading)
                    }
                }
            }.cameraCard()
            DisclosureGroup("All readings · retained evidence") {
                LazyVStack(spacing: 0) {
                    ForEach(session.records.reversed()) { record in
                        Button { onInspect(record.id) } label: { CameraReadingRow(record: record) }.buttonStyle(.plain)
                        Divider()
                    }
                }.padding(.top, 10)
            }.font(.callout).cameraCard()
        }
    }

    private var assessment: some View {
        let within = groups.filter { abs($0.errorStops) <= tolerance }.count
        let excluded = session.records.filter(\.isExcluded).count
        let incomplete = session.records.filter { !$0.isExcluded && $0.result.quality != .complete }.count
        return HStack(alignment: .top, spacing: 18) {
            CameraStatistic(title: "Timing assessment", value: groups.isEmpty ? "No assessment" : "\(within) / \(groups.count)", detail: "Setting/direction means within ±\(String(format: "%.2f", tolerance)) stops")
            CameraStatistic(title: "Included complete", value: "\(includedCount)", detail: "\(excluded) excluded · \(incomplete) partial or invalid")
            CameraStatistic(title: "Chosen tolerance", value: "±\(String(format: "%.2f", tolerance))", detail: "Stops · operator choice, not a camera health grade")
        }
    }
}

private struct CameraTimingRow: View {
    let group: CameraResultGroup
    let tolerance: Double
    let onInspect: () -> Void
    var body: some View {
        GridRow {
            VStack(alignment: .leading, spacing: 3) {
                Text(MeasurementFormat.speed(group.denominator)).fontWeight(.medium)
                Text(group.direction.title).font(.caption2).foregroundStyle(.secondary)
            }
            Text(MeasurementFormat.milliseconds(group.meanMS))
            VStack(alignment: .leading, spacing: 3) {
                Text(MeasurementFormat.stops(group.errorStops))
                Text(MeasurementFormat.percent(group.errorPercent)).font(.caption2).foregroundStyle(.secondary)
            }
            Text(MeasurementFormat.milliseconds(group.sampleSD))
            Text("\(group.count)")
            VStack(alignment: .leading, spacing: 3) {
                Label(abs(group.errorStops) <= tolerance ? "Within tolerance" : "Outside tolerance", systemImage: abs(group.errorStops) <= tolerance ? "checkmark.circle" : "exclamationmark.circle")
                    .foregroundStyle(abs(group.errorStops) <= tolerance ? Color.green : Color.orange)
                let outside = group.records.filter { abs($0.result.exposureErrorStops ?? .infinity) > tolerance }.count
                Text("\(outside) individual readings outside").font(.caption2).foregroundStyle(.secondary)
            }
            Button("Inspect", action: onInspect).buttonStyle(.link)
        }.font(.callout).monospacedDigit()
    }
}

private struct CameraReadingRow: View {
    let record: MeasurementRecord
    var body: some View {
        HStack(spacing: 16) {
            Text(record.capturedAt, format: .dateTime.hour().minute().second()).foregroundStyle(.secondary)
            Text(MeasurementFormat.speed(record.nominalDenominator)).frame(width: 75, alignment: .leading)
            Text(record.direction.title).foregroundStyle(.secondary)
            Spacer()
            Text(MeasurementFormat.milliseconds(record.result.center.durationMS))
            Label(record.isExcluded ? "Excluded" : record.result.quality.title,
                  systemImage: record.isExcluded ? "minus.circle" : MeasurementFormat.qualitySymbol(record.result.quality))
                .foregroundStyle(record.isExcluded ? Color.secondary : MeasurementFormat.qualityColor(record.result.quality)).frame(width: 100, alignment: .leading)
            Image(systemName: "chevron.right").foregroundStyle(.tertiary)
        }.font(.caption).padding(.vertical, 9).contentShape(Rectangle())
    }
}

struct CameraCoverageView: View {
    let session: CaptureSession
    let plannedSpeeds: [Double]
    private var directions: [CurtainDirection] {
        let all = Set(CameraResultGroup.groups(for: session).map { $0.direction.rawValue } + [session.direction.rawValue])
        return CurtainDirection.allCases.filter { all.contains($0.rawValue) }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Speed coverage").font(.headline)
                Spacer()
                Text("Target: \(session.repeatsPerSpeed ?? 3) readings per speed").font(.caption).foregroundStyle(.secondary)
            }
            if plannedSpeeds.isEmpty { Text("No planned speeds have been set.").font(.caption).foregroundStyle(.secondary) }
            ForEach(directions, id: \.self) { direction in
                let groups = CameraResultGroup.groups(for: session).filter { $0.direction == direction }
                VStack(alignment: .leading, spacing: 7) {
                    Text("\(direction.title) curtain direction · \(plannedSpeeds.filter { speed in groups.contains { $0.denominator == speed } }.count) / \(plannedSpeeds.count) planned speeds measured")
                        .font(.caption).foregroundStyle(.secondary)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 95), spacing: 8)], spacing: 8) {
                        ForEach(plannedSpeeds, id: \.self) { speed in
                            let count = groups.first { $0.denominator == speed }?.count ?? 0
                            VStack(spacing: 4) {
                                Text(MeasurementFormat.speed(speed)).font(.callout.weight(.medium))
                                Text(count == 0 ? "Untested" : "\(count) / \(session.repeatsPerSpeed ?? 3) readings").font(.caption2).foregroundStyle(.secondary)
                            }.frame(maxWidth: .infinity).padding(9)
                                .background(count >= (session.repeatsPerSpeed ?? 3) ? Color.accentColor.opacity(0.09) : Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 7))
                        }
                    }
                }
            }
            Text("Only complete, included readings count. Reaching a repeat target describes coverage; it does not assess camera condition.")
                .font(.caption).foregroundStyle(.secondary)
        }.cameraCard()
    }
}

private struct CameraTestProvenanceView: View {
    let session: CaptureSession
    var body: some View {
        DisclosureGroup("Test setup & provenance") {
            VStack(alignment: .leading, spacing: 10) {
                if let assignedAt = session.cameraAssignedAt {
                    CameraFieldRow(title: "Original recorded camera name", value: session.cameraName)
                    CameraFieldRow(title: "Assigned camera", value: session.cameraSnapshot?.name ?? "")
                    CameraFieldRow(title: "Serial at assignment", value: session.cameraSnapshot?.serial ?? "")
                    CameraFieldRow(title: "Camera association assigned", value: assignedAt.formatted(date: .abbreviated, time: .shortened))
                } else {
                    CameraFieldRow(title: "Captured camera", value: session.cameraSnapshot?.name ?? session.cameraName)
                    CameraFieldRow(title: "Captured serial", value: session.cameraSnapshot?.serial ?? "")
                }
                CameraFieldRow(title: "Operator", value: session.operatorName ?? "")
                CameraFieldRow(title: "Light source", value: session.lightSource ?? "")
                CameraFieldRow(title: "Conditions", value: session.testConditions ?? "")
                CameraFieldRow(title: "Firmware observed", value: Set(session.records.map { $0.packet.firmware_version }).sorted().joined(separator: ", "))
                CameraFieldRow(title: "Sensor / frame geometry", value: "32 × 20 mm / 36 × 24 mm")
                CameraFieldRow(title: "Test ID", value: session.id.uuidString)
                CameraFieldRow(title: "Revision", value: String(session.effectiveRevision))
                if let revision = session.cameraSnapshot?.catalogueRevision {
                    CameraFieldRow(title: session.cameraAssignedAt == nil ? "Catalogue revision at capture" : "Catalogue revision at assignment", value: String(revision))
                }
                if !session.notes.isEmpty { CameraFieldRow(title: "Notes", value: session.notes) }
                Text(session.cameraAssignedAt == nil
                     ? "This is the identity captured with the test. Later camera edits do not rewrite it. Original packets, per-reading settings, exclusions and correction history remain in the reading inspector and full archive."
                     : "This test was explicitly associated with a camera after creation. The association records the camera details at assignment; it is not evidence that those details were recorded when the readings arrived. Original packets, setup and the original camera name are retained.")
                    .font(.caption).foregroundStyle(.secondary)
            }.padding(.top, 14)
        }.font(.callout).cameraCard()
    }
}

private struct CameraMetadataView: View {
    @EnvironmentObject private var model: AppModel
    let camera: CameraProfile
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text("Camera details").font(.title3.weight(.semibold))
                Spacer()
                Button("Edit details") { model.editingCamera = camera }
            }
            Text("Entered catalogue information is descriptive. Unknown values stay blank; no specification is inferred from a model name.")
                .font(.caption).foregroundStyle(.secondary)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 290), alignment: .top)], alignment: .leading, spacing: 18) {
                metadataSection("Identity", fields: [("Manufacturer", camera.manufacturer), ("Model", camera.model), ("Nickname", camera.nickname), ("Body serial", camera.serial), ("Collection ID", camera.inventoryID), ("Tags", camera.tags)])
                metadataSection("Camera & lens", fields: [("Format", camera.format), ("Frame size", camera.frameSize), ("Shutter type", camera.shutterType), ("Lens mount", camera.mount), ("Lens", camera.lens), ("Lens serial", camera.lensSerial), ("Production year", camera.productionYear)])
                metadataSection("Ownership", fields: [("Acquired", camera.acquisitionDate), ("Source", camera.acquisitionSource), ("Purchase", [camera.purchasePrice, camera.currency].filter { !$0.isEmpty }.joined(separator: " ")), ("Storage", camera.storageLocation), ("Status", camera.archived ? "Archived" : "In collection")])
                metadataSection("New-test defaults", fields: [("Curtain direction", camera.defaultDirection.title), ("Planned speeds", camera.plannedSpeeds.map(MeasurementFormat.speed).joined(separator: ", ")), ("Created", camera.createdAt.formatted(date: .abbreviated, time: .omitted)), ("Updated", camera.updatedAt.formatted(date: .abbreviated, time: .shortened))])
            }
            VStack(alignment: .leading, spacing: 10) {
                Text("Condition observations").font(.headline)
                Text(camera.condition.isEmpty ? "No observations recorded." : camera.condition).foregroundStyle(camera.condition.isEmpty ? .secondary : .primary).textSelection(.enabled)
            }.cameraCard()
            Label("Calculations support the documented 32 × 20 mm sensor rectangle and 36 × 24 mm frame. Other camera formats can be catalogued, but their full-frame travel estimates are not supported.", systemImage: "info.circle")
                .font(.caption).foregroundStyle(.secondary)
            if let catalogueID = camera.catalogueID, let cameraID = camera.catalogueCameraID {
                metadataSection("ArmariumLucis identity", fields: [("Catalogue ID", catalogueID.uuidString), ("Camera ID", cameraID.uuidString), ("Imported revision", camera.catalogueRevision.map(String.init) ?? "Unknown"), ("Retained profile snapshots", String(camera.catalogueSnapshots.count))])
            }
        }
    }
    private func metadataSection(_ title: String, fields: [(String, String)]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.headline)
            ForEach(fields.indices, id: \.self) { index in CameraFieldRow(title: fields[index].0, value: fields[index].1) }
        }.frame(maxWidth: .infinity, alignment: .leading).cameraCard()
    }
}

struct CameraResultGroup: Identifiable {
    let denominator: Double
    let direction: CurtainDirection
    let records: [MeasurementRecord]
    var id: String { "\(denominator):\(direction.rawValue)" }
    var count: Int { records.count }
    var meanMS: Double { records.compactMap { $0.result.center.durationMS }.reduce(0, +) / Double(count) }
    var errorStops: Double { log2(meanMS * denominator / 1000) }
    var errorPercent: Double { (meanMS * denominator / 1000 - 1) * 100 }
    var sampleSD: Double? {
        guard count > 1 else { return nil }
        let mean = meanMS
        return sqrt(records.compactMap { $0.result.center.durationMS }.reduce(0) { $0 + pow($1 - mean, 2) } / Double(count - 1))
    }
    static func groups(for session: CaptureSession) -> [CameraResultGroup] {
        let eligible = session.records.filter {
            !$0.isExcluded && $0.isDemo == session.demo && $0.result.quality == .complete && ($0.result.center.durationMS ?? 0) > 0
        }
        let grouped = Dictionary(grouping: eligible) { "\($0.nominalDenominator):\($0.direction.rawValue)" }
        return grouped.values.compactMap { records -> CameraResultGroup? in
            guard let first = records.first else { return nil }
            return CameraResultGroup(denominator: first.nominalDenominator, direction: first.direction, records: records)
        }.sorted { $0.denominator == $1.denominator ? $0.direction.rawValue < $1.direction.rawValue : $0.denominator < $1.denominator }
    }
}

private struct CameraStatistic: View {
    let title: String
    let value: String
    let detail: String
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.caption.weight(.medium)).foregroundStyle(.secondary)
            Text(value).font(.system(size: 25, weight: .semibold, design: .rounded)).monospacedDigit()
            Text(detail).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }.frame(maxWidth: .infinity, minHeight: 95, alignment: .topLeading).cameraCard()
    }
}

struct CameraFieldRow: View {
    let title: String
    let value: String
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value.isEmpty ? "Not recorded" : value).font(.callout).foregroundStyle(value.isEmpty ? .secondary : .primary)
                .textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct CameraEmptyState: View {
    let title: String
    let symbol: String
    let message: String
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: symbol).font(.headline)
            Text(message).font(.callout).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity, alignment: .leading).cameraCard()
    }
}

extension View {
    func cameraCard() -> some View {
        padding(16)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 11))
            .overlay(RoundedRectangle(cornerRadius: 11).stroke(.quaternary))
    }
}
