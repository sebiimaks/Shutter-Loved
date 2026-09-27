import AppKit
import SwiftUI

@main
struct ShutterLoverApp: App {
    @StateObject private var model = AppModel()
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Window("Shutter Loved", id: "main") {
            ContentView()
                .environmentObject(model)
                .frame(minWidth: 960, minHeight: 640)
                .onAppear { appDelegate.model = model }
        }
        .defaultSize(width: 1260, height: 820)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Add Camera…", action: model.newCamera).keyboardShortcut("n", modifiers: [.command, .option])
                Button("New Measurement Session") { model.newSession(demo: false) }.keyboardShortcut("n")
                Button("New Demo Session") { model.newSession(demo: true) }.keyboardShortcut("n", modifiers: [.command, .shift])
                Divider()
                Button("Import Armarium Camera Catalogue…", action: model.importCameraCatalogue).keyboardShortcut("o")
                Button("Import Camera Archive as a Copy…", action: model.importCameraArchive)
                Button("Import Legacy Session as a Copy…", action: model.importSession)
                Divider()
                Button("Delete Test…") {
                    if let session = model.currentSession { model.pendingDeleteSessionID = session.id }
                }
                .disabled(model.showCameraLibrary || model.showGuide || model.currentSession.map { !model.canTrashSession($0.id) } != false)
                if !model.showCameraLibrary && !model.showGuide, let session = model.currentSession {
                    Button("Export Test for Armarium (JSON)…") { model.exportTesterResults(session.id) }
                    Button("Export Session…", action: model.exportSession).keyboardShortcut("s", modifiers: [.command, .shift])
                    Button("Export CSV…", action: model.exportCSV)
                }
                if model.showCameraLibrary && !model.showGuide, let camera = model.selectedCamera {
                    Button("Export Latest Test Report (PDF)…") { model.exportCameraReport(camera.id, sessionID: nil) }
                    Button("Export Full Camera Archive…") { model.exportCameraArchive(camera.id) }
                }
            }
            CommandGroup(after: .undoRedo) {
                Button("Undo Delete Reading", action: model.undoDelete).disabled(!model.canUndoDelete)
                Button("Delete Reading", action: model.deleteSelectedReading)
                    .disabled(model.showCameraLibrary || model.showGuide || model.selectedRecord == nil)
            }
            CommandGroup(after: .sidebar) {
                Toggle("Show Demo Tests", isOn: Binding(get: { model.showDemoSessions }, set: model.setShowDemoSessions))
            }
            CommandGroup(after: .pasteboard) {
                Button("Copy Measurement Table", action: model.copyResults).keyboardShortcut("c", modifiers: [.command, .shift])
                    .disabled(model.showCameraLibrary || model.showGuide)
            }
            CommandGroup(replacing: .help) {
                Button("Tester Instructions") { model.showGuide = true }.keyboardShortcut("?", modifiers: .command)
            }
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    weak var model: AppModel?
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        model?.saveNow()
        if let model, model.saveStatus.hasPrefix("Not saved") {
            let alert = NSAlert()
            alert.messageText = "Some changes have not been saved"
            alert.informativeText = "Cancel to export your session, or quit and discard the changes that could not be saved."
            alert.addButton(withTitle: "Cancel")
            alert.addButton(withTitle: "Quit Without Saving")
            if alert.runModal() == .alertFirstButtonReturn { return .terminateCancel }
        }
        model?.shutDown()
        return .terminateNow
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}
