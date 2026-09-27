import SwiftUI
import MeasurementCore

struct ReadingInspectorView: View {
    @EnvironmentObject private var model: AppModel
    @State private var showExplanations = false
    @State private var showCorrectSetting = false

    var body: some View {
        Group {
            if let record = model.selectedRecord {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        header(record)
                        Divider()
                        quality(record)
                        SensorDetailsView(record: record, showExplanations: showExplanations)
                        CurtainDetailsView(record: record, showExplanations: showExplanations)
                        context(record)
                        rawData(record)
                        actions(record)
                    }
                    .padding(18)
                }
                .sheet(isPresented: $showCorrectSetting) {
                    SpeedEditorView(initialValue: record.nominalDenominator, title: "Correct recorded setting") {
                        model.updateSelectedSetting($0)
                    }
                }
            } else {
                ContentUnavailableView {
                    Label("Reading details", systemImage: "sidebar.right")
                } description: {
                    Text("Select a reading to explore the sensor measurements, curtain timing, and original data.")
                }
            }
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private func header(_ record: MeasurementRecord) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Text("Reading \((model.currentRecords.firstIndex { $0.id == record.id } ?? 0) + 1)")
                    .font(.title3.weight(.semibold))
                Spacer()
                if record.isDemo {
                    Text("DEMO").font(.caption2.weight(.bold)).foregroundStyle(.orange)
                }
            }
            Text(record.capturedAt, format: .dateTime.month(.abbreviated).day().hour().minute().second())
                .font(.caption).foregroundStyle(.secondary)
            Toggle("Explain measurements", isOn: $showExplanations)
                .font(.caption).toggleStyle(.switch).controlSize(.small)
                .help("Show plain-language explanations beside the selected reading's measurements.")
        }
    }

    private func quality(_ record: MeasurementRecord) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Label(record.result.quality.title, systemImage: MeasurementFormat.qualitySymbol(record.result.quality))
                .font(.callout.weight(.semibold))
                .foregroundStyle(MeasurementFormat.qualityColor(record.result.quality))
            if record.result.issues.isEmpty {
                if showExplanations {
                    Text("All required sensor events are available. Complete describes the data, not the camera's condition.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            } else {
                ForEach(Array(record.result.issues.enumerated()), id: \.offset) { item in
                    Text(item.element).font(.caption).foregroundStyle(.secondary)
                }
            }
            if record.isExcluded {
                Label("Excluded from statistics", systemImage: "minus.circle")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private func context(_ record: MeasurementRecord) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Recorded setup").font(.headline)
            ExplainedValueRow(title: "Camera setting", value: MeasurementFormat.speed(record.nominalDenominator),
                              explanation: "The reference setting recorded for this reading. Later camera setup changes do not alter it; explicit corrections are listed below.", showExplanation: showExplanations)
            ExplainedValueRow(title: "Curtain direction", value: record.direction.title,
                              explanation: "The direction saved with this reading determines its full-frame estimates.", showExplanation: showExplanations)
            ExplainedValueRow(title: "Timing difference", value: MeasurementFormat.stops(record.result.exposureErrorStops),
                              explanation: "Positive means longer than the target; negative means shorter. This compares timing, not total photographic exposure.", showExplanation: showExplanations)
            ExplainedValueRow(title: "Difference (%)", value: MeasurementFormat.percent(record.result.exposureErrorPercent),
                              explanation: "The percentage by which center exposure differs from the recorded camera setting.", showExplanation: showExplanations)
            Button("Correct recorded setting…") { showCorrectSetting = true }
                .font(.caption)
                .help("Fix the reference setting for this reading while preserving the measured sensor data.")
            if !record.settingCorrections.isEmpty {
                DisclosureGroup("Setting correction history") {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(Array(record.settingCorrections.enumerated()), id: \.offset) { item in
                            VStack(alignment: .leading, spacing: 3) {
                                Text("\(MeasurementFormat.speed(item.element.previousValue)) → \(MeasurementFormat.speed(item.element.newValue))")
                                    .monospacedDigit()
                                Text(item.element.changedAt, format: .dateTime.month(.abbreviated).day().hour().minute())
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding(.top, 8)
                }
                .font(.caption)
            }
        }
    }

    private func rawData(_ record: MeasurementRecord) -> some View {
        DisclosureGroup("Original measurement data") {
            VStack(alignment: .leading, spacing: 8) {
                Text("The original line received from the tester is preserved with this reading.")
                    .font(.caption).foregroundStyle(.secondary)
                Text(record.rawLine)
                    .font(.system(size: 10, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.top, 8)
        }
        .font(.caption.weight(.medium))
    }

    private func actions(_ record: MeasurementRecord) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Divider()
            Button(record.isExcluded ? "Include in statistics" : "Exclude from statistics") {
                model.toggleExcluded(record.id)
            }
            .help("Keep the reading and its original data while choosing whether it contributes to summaries.")
            Button("Delete reading", role: .destructive) { model.deleteReading(record.id) }
                .help("Delete this reading from the session. You can undo deletion.")
        }
        .font(.caption)
    }
}

private struct SensorDetailsView: View {
    let record: MeasurementRecord
    let showExplanations: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Sensor exposures").font(.headline)
            sensor("Center", exposure: record.result.center, explanation: "Time the center sensor was exposed to light. This is the reference measurement for comparison with the camera setting.")
            sensor("Bottom left", exposure: record.result.bottomLeft, explanation: "Exposure duration at the bottom-left corner, after the tester's calibration offsets are applied.")
            sensor("Top right", exposure: record.result.topRight, explanation: "Exposure duration at the top-right corner, after the tester's calibration offsets are applied.")
            if showExplanations {
                Text("The equivalent 1/s value is another way to express the same duration. A dash means there is no valid value.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func sensor(_ title: String, exposure: SensorExposure, explanation: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            ExplainedValueRow(title: title, value: MeasurementFormat.milliseconds(exposure.durationMS), explanation: explanation, showExplanation: showExplanations)
            HStack {
                Text("Equivalent speed")
                Spacer()
                Text(exposure.reciprocalSeconds.map { "≈ \(MeasurementFormat.speed($0))" } ?? "—")
                    .monospacedDigit().textSelection(.enabled)
            }
            .font(.caption).foregroundStyle(.secondary)
        }
    }
}

private struct CurtainDetailsView: View {
    let record: MeasurementRecord
    let showExplanations: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Curtain travel").font(.headline)
            row("Opening", record.result.openingTravelMS,
                "Time between the opening curtain reaching the two corner sensors.")
            row("Closing", record.result.closingTravelMS,
                "Time between the closing curtain reaching the two corner sensors.")
            Divider()
            Text("Full-frame estimates").font(.callout.weight(.semibold))
            row("Opening estimate", record.result.openingFullFrameMS,
                "Estimated travel across a 36 × 24 mm frame, assuming approximately uniform curtain speed.")
            row("Closing estimate", record.result.closingFullFrameMS,
                "The measured corner-to-corner time scaled by the saved curtain direction.")
            if record.direction == .unknown {
                Text("No full-frame estimate: curtain direction was unknown when this reading arrived.")
                    .font(.caption).foregroundStyle(.secondary)
            } else if showExplanations {
                Text("The sensor rectangle is 32 × 20 mm. Horizontal measurements use 36/32; vertical measurements use 24/20.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            DisclosureGroup("Travel segments") {
                VStack(alignment: .leading, spacing: 12) {
                    row("Opening: BL ↔ center", record.result.openingFirstSegmentMS, "Opening-curtain travel between the bottom-left and center sensors. The sensor pair does not imply the order of travel.")
                    row("Opening: center ↔ TR", record.result.openingSecondSegmentMS, "Opening-curtain travel between the center and top-right sensors.")
                    row("Closing: BL ↔ center", record.result.closingFirstSegmentMS, "Closing-curtain travel between the bottom-left and center sensors. The sensor pair does not imply the order of travel.")
                    row("Closing: center ↔ TR", record.result.closingSecondSegmentMS, "Closing-curtain travel between the center and top-right sensors.")
                }
                .padding(.top, 10)
            }
            .font(.caption.weight(.medium))
        }
    }

    private func row(_ title: String, _ value: Double?, _ explanation: String) -> some View {
        ExplainedValueRow(title: title, value: MeasurementFormat.milliseconds(value), explanation: explanation, showExplanation: showExplanations)
    }
}
