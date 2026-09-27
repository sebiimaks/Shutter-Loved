import AppKit
import Combine
import DeviceTransport
import Foundation
import MeasurementCore
import UniformTypeIdentifiers

@MainActor
final class AppModel: ObservableObject {
    @Published var sessions: [CaptureSession] = []
    @Published var cameras: [CameraProfile] = []
    @Published var selectedCameraID: UUID?
    @Published var showCameraLibrary = true
    @Published var editingCamera: CameraProfile?
    @Published var activeCaptureSessionID: UUID?
    @Published var libraryID = UUID()
    @Published var catalogueReview: CatalogueImportReview?
    @Published var showCatalogueReview = false
    @Published var selectedSessionID: UUID?
    @Published var selectedRecordID: UUID?
    @Published var pendingDeleteSessionID: UUID?
    @Published var devices: [SerialDevice] = []
    @Published var selectedPortPath = ""
    @Published var connectionStatus = "Not connected"
    @Published var isConnected = false
    @Published var isConnecting = false
    @Published var isDemoMode = true
    @Published var diagnostics: [String] = []
    @Published var errorMessage: String?
    @Published var showGuide = false
    @Published var showInspector = true
    @Published private(set) var showDemoSessions: Bool
    @Published var cameraName = "" { didSet { updateSetup() } }
    @Published var nominalDenominator = 125.0 { didSet { updateSetup() } }
    @Published var direction: CurtainDirection = .unknown { didSet { updateSetup() } }
    @Published var sessionNotes = "" { didSet { updateSetup() } }
    @Published var autoAdvance = false { didSet { updateSetup() } }
    @Published var followLatest = true
    @Published private(set) var saveStatus = "Saved locally"
    @Published private var undoRecord: DeletedReading?

    private struct DeletedReading { let sessionID: UUID; let record: MeasurementRecord; let index: Int }
    let store: SessionStore
    private let preferences: UserDefaults
    private let connection = SerialConnection()
    private var framer = LineFramer()
    private var connectionToken = UUID()
    private var applyingSetup = false
    var libraryReadFailed = false
    private var saveTask: Task<Void, Never>?
    private var discoveryTimer: Timer?
    private var wantsConnection = false
    private var nextRetry = Date.distantPast
    private var retryDelay: TimeInterval = 2
    private var lastRequestedPort = ""

    var currentSession: CaptureSession? { sessions.first { $0.id == selectedSessionID && !$0.isTrashed } }
    var currentRecords: [MeasurementRecord] { currentSession?.records ?? [] }
    var selectedRecord: MeasurementRecord? { currentRecords.first { $0.id == selectedRecordID } }
    var canUndoDelete: Bool {
        guard let undoRecord else { return false }
        return sessions.contains { $0.id == undoRecord.sessionID && !$0.isTrashed }
    }
    var selectedCamera: CameraProfile? { cameras.first { $0.id == selectedCameraID } }
    var activeCaptureSession: CaptureSession? { sessions.first { $0.id == activeCaptureSessionID && !$0.isTrashed } }
    var sidebarSessions: [CaptureSession] { sessions.filter { !$0.isTrashed && $0.cameraID == nil && (showDemoSessions || !$0.demo) } }
    var demoSessionCount: Int { sessions.filter { $0.demo && !$0.isTrashed }.count }
    var trashedSessions: [CaptureSession] { sessions.filter(\.isTrashed).sorted { $0.trashedAt! > $1.trashedAt! } }

    init(store: SessionStore = .standard(), startDiscovery: Bool = true, preferences: UserDefaults = .standard) {
        self.store = store
        self.preferences = preferences
        showDemoSessions = preferences.object(forKey: "showDemoSessions") as? Bool ?? true
        do {
            let library = try store.loadLibrary()
            sessions = library.sessions
            cameras = library.cameras
            libraryID = library.libraryID
            selectedCameraID = cameras.first?.id
        } catch {
            libraryReadFailed = true
            saveStatus = "Library could not be opened"
            errorMessage = "Your saved library could not be read and has been left untouched. You can export new readings separately.\n\n\(store.libraryURL.path)\n\n\(error.localizedDescription)"
        }
        if let first = sessions.first(where: { !$0.isTrashed && (showDemoSessions || !$0.demo) }) { selectSession(first.id) }
        else if sessions.isEmpty { newSession(demo: true, revealDemo: false) }
        showCameraLibrary = true
        if startDiscovery {
            refreshDevices()
            discoveryTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
                Task { @MainActor [weak self] in self?.refreshDevices() }
            }
        }
    }

    func newSession(demo: Bool, revealDemo: Bool = true) {
        if demo && revealDemo { setShowDemoSessions(true) }
        let session = CaptureSession(cameraName: demo ? "Demo camera" : "Untitled camera", demo: demo)
        sessions.insert(session, at: 0)
        selectSession(session.id)
        if !demo && (isConnected || isConnecting || wantsConnection) { activeCaptureSessionID = session.id }
        saveNow()
    }

    func setShowDemoSessions(_ visible: Bool) {
        showDemoSessions = visible
        preferences.set(visible, forKey: "showDemoSessions")
        if !visible && currentSession?.demo == true && !showGuide && !showCameraLibrary {
            showCameraLibrary = true
        }
    }

    func selectSession(_ id: UUID) {
        guard let session = sessions.first(where: { $0.id == id && !$0.isTrashed }) else { return }
        applyingSetup = true
        selectedSessionID = id
        selectedRecordID = session.records.last?.id
        cameraName = session.cameraName
        nominalDenominator = session.nominalDenominator
        direction = session.direction
        sessionNotes = session.notes
        autoAdvance = session.autoAdvance
        isDemoMode = session.demo
        applyingSetup = false
        showGuide = false
        showCameraLibrary = false
    }

    func canTrashSession(_ id: UUID) -> Bool {
        !libraryReadFailed && activeCaptureSessionID != id && sessions.contains { $0.id == id && !$0.isTrashed }
    }

    func trashSession(_ id: UUID) {
        guard !libraryReadFailed else { errorMessage = "The saved library could not be opened; it has been left untouched."; return }
        guard activeCaptureSessionID != id else { errorMessage = "Disconnect the tester or choose another recording test before moving this test to Trash."; return }
        guard let index = sessions.firstIndex(where: { $0.id == id && !$0.isTrashed }) else { return }
        var candidate = sessions
        candidate[index].trashedAt = Date()
        do {
            try commitLibrary(cameras: cameras, sessions: candidate)
            if selectedSessionID == id {
                selectedSessionID = nil
                selectedRecordID = nil
                showCameraLibrary = true
                showGuide = false
            }
            pendingDeleteSessionID = nil
        } catch { errorMessage = "The test could not be moved to Trash: \(error.localizedDescription)" }
    }

    func restoreSession(_ id: UUID) {
        guard let index = sessions.firstIndex(where: { $0.id == id && $0.isTrashed }) else { return }
        var candidate = sessions
        candidate[index].trashedAt = nil
        do {
            try commitLibrary(cameras: cameras, sessions: candidate)
            if candidate[index].demo { setShowDemoSessions(true) }
            selectSession(id)
        } catch { errorMessage = "The test could not be restored: \(error.localizedDescription)" }
    }

    func syncSelectedSetup() {
        guard let session = currentSession else { return }
        applyingSetup = true
        cameraName = session.cameraName
        nominalDenominator = session.nominalDenominator
        direction = session.direction
        sessionNotes = session.notes
        autoAdvance = session.autoAdvance
        isDemoMode = session.demo
        applyingSetup = false
    }

    func setDemoMode(_ demo: Bool) {
        guard demo != isDemoMode else { return }
        // Separate sessions prevent simulated results from entering a real measurement series.
        newSession(demo: demo)
    }

    private func updateSetup() {
        guard !applyingSetup, let index = sessions.firstIndex(where: { $0.id == selectedSessionID && !$0.isTrashed }) else { return }
        sessions[index].cameraName = cameraName
        // Keep a committed valid reference while a field is being edited.
        if SessionStore.validSetting(nominalDenominator) { sessions[index].nominalDenominator = nominalDenominator }
        sessions[index].direction = direction
        sessions[index].notes = sessionNotes
        sessions[index].autoAdvance = autoAdvance
        sessions[index].markUpdated()
        saveStatus = "Saving…"
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            self?.saveNow()
        }
    }

    func saveNow() {
        saveTask?.cancel()
        guard !libraryReadFailed else { saveStatus = "Not saved · export this session"; return }
        do {
            try store.saveLibrary(CameraLibraryArchive(libraryID: libraryID, cameras: cameras, sessions: sessions))
            saveStatus = "Saved locally"
        } catch {
            saveStatus = "Not saved · export this session"
            appendDiagnostic("Save failed: \(error.localizedDescription)")
            errorMessage = "The latest changes remain in memory but could not be saved. Export your session before quitting.\n\n\(error.localizedDescription)"
        }
    }

    /// Persist a complete candidate before publishing changes to the UI.
    func commitLibrary(cameras candidateCameras: [CameraProfile], sessions candidateSessions: [CaptureSession]) throws {
        guard !libraryReadFailed else { throw SessionStoreError.invalid("The saved library could not be opened; it has been left untouched.") }
        saveTask?.cancel()
        try store.saveLibrary(CameraLibraryArchive(libraryID: libraryID, cameras: candidateCameras, sessions: candidateSessions))
        cameras = candidateCameras
        sessions = candidateSessions
        saveStatus = "Saved locally"
    }

    func refreshDevices() {
        let discovered = SerialDiscovery.devices()
        if devices != discovered { devices = discovered }
        if selectedPortPath.isEmpty {
            let remembered = UserDefaults.standard.string(forKey: "lastSerialPath") ?? ""
            if devices.contains(where: { $0.path == remembered }) { selectedPortPath = remembered }
        }
        if wantsConnection && !isConnected && !isConnecting && Date() >= nextRetry {
            if devices.contains(where: { $0.path == lastRequestedPort }) { beginConnection(path: lastRequestedPort) }
        }
    }

    func connect() {
        guard !selectedPortPath.isEmpty else { errorMessage = "Choose the serial device connected to your Shutter Lover."; return }
        guard devices.contains(where: { $0.path == selectedPortPath }) else { errorMessage = "That serial device is no longer available. Reconnect it and choose it again."; return }
        if currentSession == nil || isDemoMode { newSession(demo: false) }
        activeCaptureSessionID = selectedSessionID
        wantsConnection = true
        retryDelay = 2
        lastRequestedPort = selectedPortPath
        beginConnection(path: selectedPortPath)
    }

    private func beginConnection(path: String) {
        let token = UUID()
        connectionToken = token
        framer.reset()
        isConnecting = true
        isConnected = false
        connectionStatus = "Connecting…"
        connection.connect(path: path) { [weak self] event in
            // Dispatch preserves the serial queue's byte-chunk order at the UI boundary.
            DispatchQueue.main.async { [weak self] in self?.handleSerial(event, token: token) }
        }
    }

    func disconnect() {
        wantsConnection = false
        connectionToken = UUID()
        connection.disconnect()
        framer.reset()
        isConnected = false
        isConnecting = false
        connectionStatus = "Not connected"
        activeCaptureSessionID = nil
    }

    private func handleSerial(_ event: SerialEvent, token: UUID) {
        guard token == connectionToken else { return }
        switch event {
        case .opened:
            isConnected = true
            isConnecting = false
            retryDelay = 2
            connectionStatus = "Listening · awaiting device data"
            UserDefaults.standard.set(lastRequestedPort, forKey: "lastSerialPath")
            appendDiagnostic("Opened \(lastRequestedPort) at 9600/8N1. Device identity is not yet verified.")
        case .bytes(let data):
            let before = framer.droppedLineCount
            let lines = framer.append(data)
            if framer.droppedLineCount > before { appendDiagnostic("Discarded oversized serial input.") }
            for line in lines {
                switch PacketParser.parse(line) {
                case .measurement(let packet):
                    connectionStatus = "Receiving Shutter Lover measurements"
                    append(packet: packet, raw: String(decoding: line, as: UTF8.self), simulated: false)
                case .ignored(let reason): appendDiagnostic(reason)
                case .invalid(let reason): appendDiagnostic("Unreadable measurement: \(reason)")
                }
            }
        case .closed:
            serialInterrupted("Connection closed")
        case .failed(let reason):
            appendDiagnostic(reason)
            serialInterrupted(reason)
        }
    }

    private func serialInterrupted(_ reason: String) {
        isConnected = false
        isConnecting = false
        framer.reset()
        connectionStatus = wantsConnection ? "Reconnecting · \(reason)" : "Not connected"
        nextRetry = Date().addingTimeInterval(retryDelay)
        retryDelay = min(retryDelay * 2, 30)
    }

    func addDemoReading(partial: Bool = false) {
        guard isDemoMode else { return }
        let packet = DemoPackets.sample(nominalDenominator: currentSession?.nominalDenominator ?? 125, index: currentRecords.count, partial: partial)
        let raw = (try? JSONEncoder().encode(packet)).map { String(decoding: $0, as: UTF8.self) } ?? ""
        append(packet: packet, raw: raw, simulated: true)
    }

    func append(packet: MeasurementPacket, raw: String, simulated: Bool) {
        let destination = simulated ? selectedSessionID : activeCaptureSessionID
        guard let index = sessions.firstIndex(where: { $0.id == destination && !$0.isTrashed }), sessions[index].demo == simulated else {
            appendDiagnostic("No matching active session; received data was not recorded.")
            return
        }
        let snapshot = sessions[index]
        var record = MeasurementRecord(rawLine: raw, packet: packet, direction: snapshot.direction, nominalDenominator: snapshot.nominalDenominator, isDemo: simulated)
        record.devicePath = simulated ? nil : lastRequestedPort
        record.derivedSnapshot = record.result
        sessions[index].records.append(record)
        sessions[index].markUpdated()
        if sessions[index].id == selectedSessionID && (followLatest || selectedRecordID == nil) { selectedRecordID = record.id }
        saveNow()
        if snapshot.autoAdvance && record.result.quality == .complete && saveStatus == "Saved locally" {
            let speeds: [Double] = [15, 30, 60, 125, 250, 500, 1000]
            if let current = speeds.firstIndex(of: snapshot.nominalDenominator), current + 1 < speeds.count { sessions[index].nominalDenominator = speeds[current + 1] }
            else if !speeds.contains(snapshot.nominalDenominator) { sessions[index].nominalDenominator = speeds[0] }
            else {
                sessions[index].autoAdvance = false
                appendDiagnostic("Sequence complete at 1/1000 s. Choose a starting speed, then enable auto-advance for another series.")
            }
            sessions[index].markUpdated()
            if sessions[index].id == selectedSessionID {
                applyingSetup = true
                nominalDenominator = sessions[index].nominalDenominator
                autoAdvance = sessions[index].autoAdvance
                applyingSetup = false
            }
            saveNow()
        }
    }

    private func appendDiagnostic(_ text: String) {
        diagnostics.append(String(text.prefix(500)))
        if diagnostics.count > 100 { diagnostics.removeFirst(diagnostics.count - 100) }
    }

    func updateSelectedSetting(_ value: Double) {
        guard SessionStore.validSetting(value) else { errorMessage = "Enter a positive reciprocal setting between 0.001 and 1,000,000."; return }
        guard let s = sessions.firstIndex(where: { $0.id == selectedSessionID && !$0.isTrashed }),
              let r = sessions[s].records.firstIndex(where: { $0.id == selectedRecordID }) else { return }
        let previous = sessions[s].records[r].nominalDenominator
        guard previous != value else { return }
        sessions[s].records[r].settingCorrections.append(SettingCorrection(changedAt: Date(), previousValue: previous, newValue: value))
        sessions[s].records[r].nominalDenominator = value
        let record = sessions[s].records[r]
        sessions[s].records[r].derivedSnapshot = MeasurementResult.calculate(packet: record.packet, direction: record.direction, nominalDenominator: value)
        sessions[s].markUpdated()
        saveNow()
    }

    func toggleExcluded(_ id: UUID) {
        guard let s = sessions.firstIndex(where: { $0.id == selectedSessionID && !$0.isTrashed }), let r = sessions[s].records.firstIndex(where: { $0.id == id }) else { return }
        sessions[s].records[r].isExcluded.toggle()
        sessions[s].markUpdated()
        saveNow()
    }

    func deleteSelectedReading() {
        guard let id = selectedRecordID else { return }
        deleteReading(id)
    }

    func deleteReading(_ id: UUID) {
        guard let s = sessions.firstIndex(where: { $0.id == selectedSessionID && !$0.isTrashed }), let r = sessions[s].records.firstIndex(where: { $0.id == id }) else { return }
        undoRecord = DeletedReading(sessionID: sessions[s].id, record: sessions[s].records[r], index: r)
        sessions[s].records.remove(at: r)
        sessions[s].markUpdated()
        if selectedRecordID == id {
            selectedRecordID = sessions[s].records.isEmpty ? nil : sessions[s].records[min(r, sessions[s].records.count - 1)].id
        }
        saveNow()
    }

    func undoDelete() {
        guard let undo = undoRecord, let s = sessions.firstIndex(where: { $0.id == undo.sessionID && !$0.isTrashed }) else { return }
        sessions[s].records.insert(undo.record, at: min(undo.index, sessions[s].records.count))
        sessions[s].markUpdated()
        undoRecord = nil
        selectSession(undo.sessionID)
        selectedRecordID = undo.record.id
        saveNow()
    }

    func copyResults() {
        let rows = selectedRecord.map { [$0] } ?? currentRecords
        NSPasteboard.general.clearContents()
        let numbers = Dictionary(uniqueKeysWithValues: currentRecords.enumerated().map { ($0.element.id, $0.offset + 1) })
        NSPasteboard.general.setString(SessionExport.table(rows, separator: "\t", readingNumbers: numbers), forType: .string)
    }

    func exportCSV() {
        guard let session = currentSession else { return }
        save(data: Data(SessionExport.table(session.records).utf8), filename: "\(safeFilename(session.cameraName)).csv", type: .commaSeparatedText)
    }

    func exportSession() {
        guard let session = currentSession else { return }
        do { save(data: try SessionStore.encoder().encode(SessionArchive(sessions: [session])), filename: "\(safeFilename(session.cameraName)).shutterlover", type: .shutterLoverSession) }
        catch { errorMessage = error.localizedDescription }
    }

    @discardableResult
    func save(data: Data, filename: String, type: UTType) -> Bool {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [type]
        panel.nameFieldStringValue = filename
        guard panel.runModal() == .OK, let url = panel.url else { return false }
        do { try data.write(to: url, options: .atomic); return true }
        catch { errorMessage = "Export failed: \(error.localizedDescription)"; return false }
    }

    func importSession() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.shutterLoverSession, .json]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            guard size <= 64 * 1024 * 1024 else { throw SessionStoreError.tooLarge }
            var imported = try SessionStore.decode(Data(contentsOf: url))
            // Imported copies get their own identities, retaining original timestamps and raw values.
            for s in imported.indices {
                imported[s].id = UUID()
                imported[s].cameraName += " (imported)"
                imported[s].cameraID = nil
                imported[s].cameraSnapshot = nil
                imported[s].cameraAssignedAt = nil
                imported[s].revision = 1
                imported[s].lastExportedRevision = nil
                for r in imported[s].records.indices { imported[s].records[r].id = UUID() }
            }
            sessions.insert(contentsOf: imported, at: 0)
            if let first = imported.first { selectSession(first.id) }
            saveNow()
        } catch { errorMessage = "Import failed: \(error.localizedDescription)" }
    }

    func safeFilename(_ text: String) -> String {
        let filtered = text.components(separatedBy: CharacterSet(charactersIn: "/:\\")).joined(separator: "-")
        return filtered.isEmpty ? "Shutter Loved session" : String(filtered.prefix(100))
    }

    func shutDown() { discoveryTimer?.invalidate(); saveNow(); disconnect() }
}

extension UTType {
    static let shutterLoverSession = UTType(exportedAs: "com.shutterlover.session", conformingTo: .json)
}
