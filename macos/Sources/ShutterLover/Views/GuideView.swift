import SwiftUI

struct GuideView: View {
    @State private var selectedID = TesterGuideCatalog.guides.first?.id ?? ""
    @State private var searchText = ""

    private var selectedGuide: TesterGuide? {
        TesterGuideCatalog.guides.first { $0.id == selectedID }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Measurement guide", systemImage: "book.closed")
                        .font(.system(size: 27, weight: .semibold, design: .rounded))
                    Text("Choose your tester for the correct preparation and measurement steps.")
                        .foregroundStyle(.secondary)
                }
                Picker("Your tester", selection: $selectedID) {
                    ForEach(TesterGuideCatalog.guides) { guide in
                        Text(guide.title).tag(guide.id)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 580)
                if let guide = selectedGuide {
                    testerGuide(guide)
                }
                applicationGuide
            }
            .padding(28)
            .frame(maxWidth: 850, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .navigationTitle("Measurement guide")
        .searchable(text: $searchText, prompt: "Find a function or measurement")
    }

    private func testerGuide(_ guide: TesterGuide) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 10) {
                Text(guide.title).font(.title2.weight(.semibold))
                Text(guide.summary).foregroundStyle(.secondary)
                Label {
                    Text(guide.compatibility)
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: "info.circle")
                }
                .font(.callout)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.accentColor.opacity(0.07), in: RoundedRectangle(cornerRadius: 9))
                Link(destination: guide.manualURL) {
                    Label(guide.manualTitle, systemImage: "arrow.up.right.square")
                }
                .font(.callout)
                Text("The manufacturer manual is the source for the tester-specific instructions below.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            ForEach(guide.sections.filter { matches($0.title + " " + $0.body) }) { section in
                GuideCard(title: section.title, bodyText: section.body)
            }
            if !searchText.isEmpty && !guide.sections.contains(where: { matches($0.title + " " + $0.body) }) {
                Text("No tester instructions match “\(searchText)”. Try another term or choose the other tester.")
                    .font(.callout).foregroundStyle(.secondary)
            }
        }
    }

    private var applicationGuide: some View {
        VStack(alignment: .leading, spacing: 14) {
            Divider().padding(.vertical, 8)
            Text("Using the Mac app with Shutter Lover").font(.title2.weight(.semibold))
            ForEach(Self.appSections.filter { matches($0.title + " " + $0.body) }) { section in
                GuideCard(title: section.title, bodyText: section.body)
            }
        }
    }

    private func matches(_ text: String) -> Bool {
        searchText.isEmpty || text.localizedCaseInsensitiveContains(searchText)
    }

    private struct AppGuideSection: Identifiable {
        let title: String
        let body: String
        var id: String { title }
    }

    private static let appSections: [AppGuideSection] = [
        AppGuideSection(title: "Start a session", body: "Use New session to keep a separate set of measurements for a camera or service visit. Enter the camera name, notes, actual camera setting, and curtain direction. Previous sessions remain in the sidebar. Settings apply to future readings; every reading keeps its own setup."),
        AppGuideSection(title: "Camera setting and next speed", body: "The camera setting is the intended exposure and provides the reference for timing comparisons. Choose a familiar fraction or enter a custom duration. The app cannot change the camera. Suggest next speed advances through 1/15, 1/30, 1/60, 1/125, 1/250, 1/500, and 1/1000 s after a complete reading; change the physical camera yourself."),
        AppGuideSection(title: "Understand exposure measurements", body: "Center, bottom-left, and top-right exposures describe how long each sensor was exposed to light. Each is shown in milliseconds and as an equivalent reciprocal speed. For example, 8 ms equals 1/125 s. The app applies the supplied corner calibration offsets. A dash means the measurement is unavailable; it is never treated as zero."),
        AppGuideSection(title: "Read timing difference", body: "Timing difference compares the center exposure with the camera setting recorded for that reading. Positive stops indicate longer exposure; negative stops indicate shorter exposure. An 8.2 ms reading against 1/125 s (8 ms) is about +0.04 stops, or 2.5% longer. This is a timing comparison, not a measurement of the total photographic exposure."),
        AppGuideSection(title: "Curtain direction and estimates", body: "Opening and closing travel are measured between corner sensors. Full-frame travel is an estimate for a 36 × 24 mm frame: horizontal travel uses 36/32, while vertical travel uses 24/20. These estimates assume approximately uniform curtain speed. Unknown direction keeps sensor measurements available and leaves full-frame estimates blank. Travel segments are available in the reading inspector."),
        AppGuideSection(title: "Complete, partial, and invalid readings", body: "Complete means the required sensor events are present; it does not certify camera accuracy. Partial readings retain every available measurement and explain what is missing. Invalid readings flag data that cannot be interpreted safely. Inspect the quality notes and original measurement data before repeating a test. Incomplete results can be useful when diagnosing setup or illumination."),
        AppGuideSection(title: "Review, correct, and exclude", body: "Select a table row to see its captured setup and original data. Turn off Follow latest to inspect older readings as new ones arrive. Correct recorded setting fixes the reference speed for the selected reading without changing the original sensor data. Exclude from statistics keeps a reading in the session but omits it from summaries. Deleted readings can be restored with Undo delete."),
        AppGuideSection(title: "Repeatability statistics", body: "The summary groups included readings by the same camera setting and curtain direction, using their valid center exposure durations. Mean is the average duration. SD is the sample standard deviation, a measure of variation between repeats, and needs at least two readings. Excluded and invalid readings are omitted. Reciprocal speed denominators are not averaged."),
        AppGuideSection(title: "Save, export, and demo", body: "The status bar reports whether the current session is saved locally. Export complete session preserves original measurement data and setup in a portable file. Export CSV produces a spreadsheet table. Copy results puts a table on the clipboard. Demo sessions contain visibly marked synthetic measurements, including an optional partial example; use a separate device session for hardware results.")
    ]
}

private struct GuideCard: View {
    let title: String
    let bodyText: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.headline)
            Text(bodyText)
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 11))
        .overlay(RoundedRectangle(cornerRadius: 11).stroke(.quaternary))
    }
}
