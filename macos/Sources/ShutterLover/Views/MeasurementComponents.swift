import SwiftUI
import MeasurementCore

enum MeasurementFormat {
    static func milliseconds(_ value: Double?) -> String {
        guard let value, value.isFinite else { return "—" }
        return String(format: "%.3f ms", value)
    }

    static func speed(_ denominator: Double) -> String {
        guard denominator.isFinite, denominator > 0 else { return "—" }
        if denominator < 1 { return String(format: "%g s", 1 / denominator) }
        return String(format: "1/%g s", (denominator * 10).rounded() / 10)
    }

    static func stops(_ value: Double?) -> String {
        guard let value, value.isFinite else { return "—" }
        return String(format: "%+.2f stops", value)
    }

    static func percent(_ value: Double?) -> String {
        guard let value, value.isFinite else { return "—" }
        return String(format: "%+.2f%%", value)
    }

    static func qualitySymbol(_ quality: ReadingQuality) -> String {
        switch quality {
        case .complete: return "checkmark.circle"
        case .partial: return "circle.lefthalf.filled"
        case .invalid: return "exclamationmark.triangle"
        }
    }

    static func qualityColor(_ quality: ReadingQuality) -> Color {
        switch quality {
        case .complete: return .green
        case .partial: return .orange
        case .invalid: return .red
        }
    }
}

struct NominalSpeedPicker: View {
    @Binding var value: Double
    @State private var showCustomSpeed = false
    private let speeds: [Double] = [0.25, 0.5, 1, 2, 4, 8, 15, 30, 60, 125, 250, 500, 1000, 2000, 4000, 8000]

    var body: some View {
        HStack(spacing: 6) {
            Picker("Camera setting", selection: $value) {
                if !speeds.contains(value) {
                    Text(MeasurementFormat.speed(value)).tag(value)
                }
                ForEach(speeds, id: \.self) { speed in
                    Text(MeasurementFormat.speed(speed)).tag(speed)
                }
            }
            .labelsHidden()
            .help("The exposure physically selected on the camera. This reference is used to calculate the timing difference.")
            Button {
                showCustomSpeed = true
            } label: {
                Image(systemName: "slider.horizontal.3")
            }
            .buttonStyle(.borderless)
            .help("Enter a custom camera exposure.")
        }
        .sheet(isPresented: $showCustomSpeed) {
            SpeedEditorView(initialValue: value, title: "Custom camera setting") { value = $0 }
        }
    }
}

struct SpeedEditorView: View {
    @Environment(\.dismiss) private var dismiss
    let title: String
    let onApply: (Double) -> Void
    @State private var durationText: String

    init(initialValue: Double, title: String, onApply: @escaping (Double) -> Void) {
        self.title = title
        self.onApply = onApply
        _durationText = State(initialValue: String(format: "%g", 1000 / initialValue))
    }

    private var duration: Double? {
        guard let value = Double(durationText), value.isFinite, value > 0,
              SessionStore.validSetting(1000 / value) else { return nil }
        return value
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title).font(.title2.weight(.semibold))
            Text("Enter the intended exposure time. For example, 1/125 s is 8 ms; 2 seconds is 2000 ms.")
                .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack {
                TextField("Duration", text: $durationText).textFieldStyle(.roundedBorder)
                    .accessibilityLabel("Exposure duration in milliseconds")
                Text("ms")
            }
            Text(duration.map { MeasurementFormat.speed(1000 / $0) } ?? "Enter a duration from 0.001 to 1,000,000 ms.")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Apply") {
                    if let duration { onApply(1000 / duration) }
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(duration == nil)
            }
        }
        .padding(24).frame(width: 370)
    }
}

struct ExplainedValueRow: View {
    let title: String
    let value: String
    let explanation: String
    var showExplanation = true

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).font(.callout)
                Spacer(minLength: 8)
                Text(value).font(.callout.weight(.medium)).monospacedDigit().textSelection(.enabled)
            }
            if showExplanation {
                Text(explanation)
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
        .help(explanation)
    }
}
