import SwiftUI
import MeasurementCore

/// An explicit pair of tests; never an implicit combination of dates or directions.
struct CameraComparisonView: View {
    @Environment(\.dismiss) private var dismiss
    let tests: [CaptureSession]
    @State private var beforeID: UUID?
    @State private var afterID: UUID?

    init(tests: [CaptureSession], beforeID: UUID?, afterID: UUID?) {
        self.tests = tests.filter { !$0.demo }
        _beforeID = State(initialValue: beforeID)
        _afterID = State(initialValue: afterID)
    }
    private var before: CaptureSession? { tests.first { $0.id == beforeID } }
    private var after: CaptureSession? { tests.first { $0.id == afterID } }
    private var matched: [ComparisonPair] {
        guard let before, let after, before.id != after.id else { return [] }
        let right = CameraResultGroup.groups(for: after)
        return CameraResultGroup.groups(for: before).compactMap { left in
            guard let matching = right.first(where: { $0.id == left.id }) else { return nil }
            return ComparisonPair(before: left, after: matching)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Compare camera tests").font(.title2.weight(.semibold))
                    Text("Select two tests. Comparison requires matching settings, directions, tester identity, measurement source and mode.")
                        .font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            HStack(spacing: 20) {
                selection("Before / reference", value: $beforeID)
                Image(systemName: "arrow.right").foregroundStyle(.secondary)
                selection("After / comparison", value: $afterID)
            }
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if beforeID == afterID && beforeID != nil {
                        Label("Choose two different tests.", systemImage: "info.circle").foregroundStyle(.orange)
                    } else if let before, let after {
                        comparisonNotes(before, after)
                        if matched.isEmpty {
                            ContentUnavailableView("No matching readings", systemImage: "square.dashed", description: Text("Both tests need complete, included readings with the same setting, direction, tester identity, source and mode."))
                        } else {
                            comparisonGrid
                        }
                        Text("Comparison uses USB center exposure or manual displayed exposure means, in separate groups. A positive change means the later exposure was longer. Effective exposure and USB timing are not interchangeable. A measured difference alone does not establish a service outcome.")
                            .font(.caption).foregroundStyle(.secondary)
                    } else {
                        ContentUnavailableView("Choose two tests", systemImage: "arrow.left.arrow.right", description: Text("The original readings and both tests remain unchanged."))
                    }
                }.padding(.vertical, 5)
            }
        }.padding(24).frame(width: 860, height: 600)
    }

    private func selection(_ title: String, value: Binding<UUID?>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            Picker(title, selection: value) {
                Text("Choose test").tag(Optional<UUID>.none)
                ForEach(tests) { test in
                    Text("\(test.displayTitle) · \(test.createdAt.formatted(date: .abbreviated, time: .shortened))").tag(Optional(test.id))
                }
            }.labelsHidden()
        }.frame(maxWidth: .infinity)
    }

    private func comparisonNotes(_ before: CaptureSession, _ after: CaptureSession) -> some View {
        let beforeGroups = CameraResultGroup.groups(for: before)
        let afterGroups = CameraResultGroup.groups(for: after)
        let unmatched = beforeGroups.count + afterGroups.count - matched.count * 2
        return VStack(alignment: .leading, spacing: 10) {
            Text("\(matched.count) matching measurement groups · \(unmatched) unmatched groups omitted")
                .font(.callout.weight(.medium))
            Text("Reference tester: \(before.testerSummary)\nComparison tester: \(after.testerSummary)")
                .font(.caption).foregroundStyle(.secondary)
            if after.createdAt < before.createdAt {
                Label("The comparison test is dated earlier than the reference. The column order follows your selection.", systemImage: "calendar.badge.exclamationmark").font(.caption).foregroundStyle(.orange)
            }
            if before.direction != after.direction {
                Label("Default curtain directions differ. Rows still require exactly matching recorded directions.", systemImage: "info.circle").font(.caption).foregroundStyle(.orange)
            }
            if before.lightSource != after.lightSource || before.testConditions != after.testConditions {
                Label("Recorded lighting or test conditions differ. Consider those differences when interpreting the results.", systemImage: "lightbulb").font(.caption).foregroundStyle(.orange)
            }
            if Set(before.records.map(\.calculationVersion)) != Set(after.records.map(\.calculationVersion)) {
                Label("Calculation versions differ between tests.", systemImage: "info.circle").font(.caption).foregroundStyle(.orange)
            }
            let beforeFirmware = Set(before.records.map(\.firmwareVersion))
            let afterFirmware = Set(after.records.map(\.firmwareVersion))
            if beforeFirmware != afterFirmware {
                Label("Observed tester firmware differs between tests.", systemImage: "cpu").font(.caption).foregroundStyle(.orange)
            }
            if before.records.contains(where: \.isManual) || after.records.contains(where: \.isManual) {
                Text("Manual values depend on transcription and the tester's illumination reference. Check each reading's E₀, Global-mode series maximum and setup before interpreting a change.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if before.records.contains(where: { $0.tester?.id == nil }) || after.records.contains(where: { $0.tester?.id == nil }) {
                Text("Some readings have no owned tester UUID. Matching unknown identity labels cannot prove the same physical tester was used.")
                    .font(.caption).foregroundStyle(.orange)
            }
            Text("Recorded tolerance: reference ±\(String(format: "%.2f", before.toleranceStops ?? 1.0 / 3.0)) stops · comparison ±\(String(format: "%.2f", after.toleranceStops ?? 1.0 / 3.0)) stops")
                .font(.caption).foregroundStyle(.secondary)
            Text("USB travel calculations use a 32 × 20 mm sensor rectangle and 36 × 24 mm frame. Manual readings contain no travel measurements.")
                .font(.caption).foregroundStyle(.secondary)
        }.cameraCard()
    }

    private var comparisonGrid: some View {
        Grid(alignment: .leading, horizontalSpacing: 22, verticalSpacing: 14) {
            GridRow {
                Text("Setting / method")
                Text("Reference mean")
                Text("Comparison mean")
                Text("Change")
            }.font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            Divider().gridCellUnsizedAxes(.horizontal)
            ForEach(matched) { pair in
                GridRow(alignment: .top) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(MeasurementFormat.speed(pair.before.denominator)).fontWeight(.medium)
                        Text(pair.before.direction.title).font(.caption).foregroundStyle(.secondary)
                        Text(pair.before.contextDescription).font(.caption2).foregroundStyle(.secondary).frame(maxWidth: 260, alignment: .leading)
                    }
                    summary(pair.before)
                    summary(pair.after)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(MeasurementFormat.stops(log2(pair.after.meanMS / pair.before.meanMS)))
                        Text(String(format: "%+.3f ms", pair.after.meanMS - pair.before.meanMS)).font(.caption).foregroundStyle(.secondary)
                    }
                }.font(.callout).monospacedDigit()
            }
        }.frame(maxWidth: .infinity, alignment: .leading).cameraCard()
    }

    private func summary(_ group: CameraResultGroup) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(MeasurementFormat.milliseconds(group.meanMS))
            Text("\(group.count) readings · SD \(MeasurementFormat.milliseconds(group.sampleSD))").font(.caption).foregroundStyle(.secondary)
            Text(MeasurementFormat.stops(group.errorStops) + " vs setting").font(.caption).foregroundStyle(.secondary)
        }
    }
}

private struct ComparisonPair: Identifiable {
    let before: CameraResultGroup
    let after: CameraResultGroup
    var id: String { before.id }
}
