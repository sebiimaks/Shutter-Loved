import SwiftUI

struct FlangeDistanceSettingsView: View {
    @EnvironmentObject private var model: AppModel
    @State private var search = ""
    @State private var selectedID: String?
    @State private var editing: FlangeMountEditRequest?
    @State private var pendingRemoval: FlangeDistanceRow?
    @State private var showingRestoreConfirmation = false

    private var rows: [FlangeDistanceRow] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return model.flangeMountRows }
        let matches = Set(model.flangeMatches(query).map(\.id))
        return model.flangeMountRows.filter {
            $0.name.localizedStandardContains(query) || $0.notes.localizedStandardContains(query) || matches.contains($0.id)
        }
    }

    private var selectedRow: FlangeDistanceRow? { model.flangeMountRows.first { $0.id == selectedID } }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Label("Flange focal distances", systemImage: "ruler").font(.title2.weight(.semibold))
                Text("The distance from the lens-mount seating surface to the film or image plane, in millimetres. Used with a Shutter Lover’s calibrated distance to suggest its position for the camera being tested.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            if let error = model.flangeSettingsError {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.callout).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                TextField("Search mounts", text: $search).textFieldStyle(.roundedBorder)
                Button { editing = FlangeMountEditRequest(row: nil) } label: {
                    Label("Add custom mount", systemImage: "plus")
                }.disabled(model.flangeSettingsLoadFailed)
            }
            Table(rows, selection: $selectedID) {
                TableColumn("Camera mount") { row in Text(row.name) }.width(min: 185, ideal: 270)
                TableColumn("Distance (mm)") { row in
                    Text(row.distanceMM, format: .number.precision(.fractionLength(0...4)).grouping(.never)).monospacedDigit()
                }.width(105)
                TableColumn("Value") { row in
                    Text(row.status).foregroundStyle(row.isOverride ? Color.orange : .secondary)
                }.width(80)
                TableColumn("") { row in
                    Button("Edit…") { editing = FlangeMountEditRequest(row: row) }
                        .buttonStyle(.borderless)
                        .disabled(model.flangeSettingsLoadFailed)
                        .accessibilityLabel("Edit flange distance: \(row.name)")
                }.width(58)
            }
            .frame(minHeight: 235)
            .overlay {
                if rows.isEmpty {
                    ContentUnavailableView.search(text: search)
                }
            }
            selectedMountDetails
            Divider()
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Reference data checked 30 September 2026").font(.caption).foregroundStyle(.secondary)
                    HStack(spacing: 14) {
                        Link("Brian Smith’s guide", destination: URL(string: "https://briansmith.com/flange-focal-distance-guide/")!)
                        Link("Wikipedia table", destination: URL(string: "https://en.wikipedia.org/wiki/Flange_focal_distance")!)
                    }.font(.caption)
                }
                Spacer()
                Button("Restore all defaults…") { showingRestoreConfirmation = true }
            }
        }
        .padding(22)
        .frame(minWidth: 750, idealWidth: 800, minHeight: 540, idealHeight: 640)
        .sheet(item: $editing) { request in
            FlangeMountEditorView(row: request.row).environmentObject(model)
        }
        .confirmationDialog("Restore all reference distances?", isPresented: $showingRestoreConfirmation, titleVisibility: .visible) {
            Button("Restore defaults", role: .destructive) {
                if model.restoreFlangeDistanceDefaults() { selectedID = nil }
            }
        } message: {
            Text("This removes your distance overrides and custom mounts. Positioning will use the reference table. Existing camera details and readings are unchanged. Any unreadable settings will be retained as a recovery copy.")
        }
        .confirmationDialog("Remove custom mount?", isPresented: Binding(get: { pendingRemoval != nil }, set: { if !$0 { pendingRemoval = nil } }), titleVisibility: .visible, presenting: pendingRemoval) { row in
            Button("Remove mount", role: .destructive) {
                if model.removeCustomFlangeMount(id: row.id) { selectedID = nil }
                pendingRemoval = nil
            }
        } message: { row in
            Text("Remove \(row.name) from this table? Cameras using that mount will need another matching entry before a positioning distance can be calculated.")
        }
    }

    @ViewBuilder private var selectedMountDetails: some View {
        if let row = selectedRow {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(row.name).font(.headline)
                    Spacer()
                    if row.isOverride, let reference = row.defaultDistanceMM {
                        Button("Reset to \(reference.formatted(.number.precision(.fractionLength(0...4)).grouping(.never))) mm") {
                            _ = model.resetFlangeDistance(mountID: row.id)
                        }.disabled(model.flangeSettingsLoadFailed)
                    }
                    if row.isCustom {
                        Button("Remove custom mount…", role: .destructive) { pendingRemoval = row }
                            .disabled(model.flangeSettingsLoadFailed)
                    }
                }
                if !row.notes.isEmpty { Text(row.notes).font(.caption).foregroundStyle(.secondary).lineLimit(3) }
                HStack(spacing: 14) {
                    ForEach(row.sourceURLs, id: \.absoluteString) { url in
                        Link(url.host == "briansmith.com" ? "Brian Smith source" : "Wikipedia source", destination: url)
                    }
                    if row.isCustom { Text("User-supplied distance").foregroundStyle(.secondary) }
                }.font(.caption)
            }.frame(minHeight: 65, alignment: .top)
        } else {
            Text("Select a mount to see its source and notes. Modified values take effect immediately for positioning; existing results remain unchanged.")
                .font(.callout).foregroundStyle(.secondary).frame(minHeight: 65, alignment: .top)
        }
    }
}

private struct FlangeMountEditRequest: Identifiable {
    let id = UUID()
    let row: FlangeDistanceRow?
}

private struct FlangeMountEditorView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let row: FlangeDistanceRow?
    @State private var name: String
    @State private var distance: String
    @State private var notes: String
    @State private var failure: String?

    init(row: FlangeDistanceRow?) {
        self.row = row
        _name = State(initialValue: row?.name ?? "")
        _distance = State(initialValue: row.map { String($0.distanceMM) } ?? "")
        _notes = State(initialValue: row?.isCustom == true ? row!.notes : "")
    }

    private var isCustom: Bool { row?.isCustom ?? true }
    private var parsedDistance: Double? {
        Double(distance.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: ",", with: "."))
    }
    private var valid: Bool {
        guard let value = parsedDistance, value.isFinite, value > 0, value <= 1_000 else { return false }
        return !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && name.count <= 150 && notes.count <= 4_000
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(row == nil ? "Add custom mount" : "Edit flange distance").font(.title2.weight(.semibold)).padding(22)
            Divider()
            Form {
                if isCustom { TextField("Mount name", text: $name) }
                else { LabeledContent("Camera mount", value: name) }
                TextField("Flange focal distance (mm)", text: $distance)
                Text("Enter a value greater than 0 and no more than 1,000 mm.").font(.caption).foregroundStyle(.secondary)
                if let reference = row?.defaultDistanceMM {
                    LabeledContent("Reference value", value: "\(reference.formatted(.number.precision(.fractionLength(0...4)).grouping(.never))) mm")
                }
                if isCustom {
                    TextField("Source or notes (optional)", text: $notes, axis: .vertical).lineLimit(2...4)
                } else if let row, !row.notes.isEmpty {
                    Text(row.notes).font(.callout).foregroundStyle(.secondary)
                }
                if let row {
                    ForEach(row.sourceURLs, id: \.absoluteString) { url in
                        Link(url.host == "briansmith.com" ? "Read Brian Smith’s source" : "Read Wikipedia source", destination: url)
                    }
                }
            }.formStyle(.grouped)
            Divider()
            VStack(alignment: .leading, spacing: 9) {
                if let failure { Text(failure).font(.callout).foregroundStyle(.red) }
                HStack {
                    Spacer()
                    Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                    Button("Save distance", action: save).keyboardShortcut(.defaultAction).disabled(!valid)
                }
            }.padding(20)
        }.frame(width: 540, height: 430)
    }

    private func save() {
        guard let value = parsedDistance else { return }
        let success: Bool
        if let row {
            success = row.isCustom
                ? model.updateCustomFlangeMount(id: row.id, name: name, distanceMM: value, notes: notes)
                : model.saveFlangeDistance(mountID: row.id, distanceMM: value)
        } else { success = model.addCustomFlangeMount(name: name, distanceMM: value, notes: notes) }
        if success { dismiss() }
        else { failure = model.flangeSettingsError ?? "The distance could not be saved." }
    }
}
