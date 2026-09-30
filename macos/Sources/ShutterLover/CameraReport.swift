import AppKit
import Foundation
import MeasurementCore
import CoreText

/// Printable evidence summary. Photo and metadata are local; no report service is contacted.
@MainActor
enum CameraReport {
    static func pdf(camera: CameraProfile, image: NSImage?, session: CaptureSession?) throws -> Data {
        let data = NSMutableData()
        guard let consumer = CGDataConsumer(data: data) else { throw SessionStoreError.invalid("PDF output could not be created.") }
        var bounds = CGRect(x: 0, y: 0, width: 595, height: 842)
        guard let context = CGContext(consumer: consumer, mediaBox: &bounds, nil) else { throw SessionStoreError.invalid("PDF output could not be created.") }
        var y: CGFloat = 792
        var page = 0
        func beginPage() {
            context.beginPDFPage(nil)
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
            page += 1
            y = 792
        }
        func endPage() {
            let footer = "Shutter Loved · Camera report · Page \(page)"
            NSAttributedString(string: footer, attributes: [.font: NSFont.systemFont(ofSize: 9), .foregroundColor: NSColor.darkGray]).draw(at: NSPoint(x: 40, y: 25))
            NSGraphicsContext.restoreGraphicsState()
            context.endPDFPage()
        }
        func text(_ string: String, size: CGFloat = 10, bold: Bool = false, width: CGFloat = 515, x: CGFloat = 40, gap: CGFloat = 8) {
            let paragraph = NSMutableParagraphStyle()
            paragraph.lineBreakMode = .byWordWrapping
            let attributed = NSAttributedString(string: string, attributes: [.font: bold ? NSFont.boldSystemFont(ofSize: size) : NSFont.systemFont(ofSize: size), .foregroundColor: NSColor.black, .paragraphStyle: paragraph])
            let setter = CTFramesetterCreateWithAttributedString(attributed)
            var offset = 0
            while offset < attributed.length {
                if y < 78 { endPage(); beginPage() }
                let path = CGPath(rect: CGRect(x: x, y: 52, width: width, height: y - 52), transform: nil)
                let frame = CTFramesetterCreateFrame(setter, CFRange(location: offset, length: 0), path, nil)
                let visible = CTFrameGetVisibleStringRange(frame)
                guard visible.length > 0 else { break }
                CTFrameDraw(frame, context)
                let drawn = attributed.attributedSubstring(from: NSRange(location: offset, length: visible.length))
                let usedHeight = ceil(drawn.boundingRect(with: NSSize(width: width, height: .greatestFiniteMagnitude), options: [.usesLineFragmentOrigin, .usesFontLeading]).height)
                y -= usedHeight + gap
                offset += visible.length
                if offset < attributed.length { endPage(); beginPage() }
            }
        }
        func value(_ string: String) -> String { string.isEmpty ? "Not recorded" : string }
        beginPage()
        text(camera.name, size: 24, bold: true)
        text("Shutter timing report · \(Date().formatted(date: .abbreviated, time: .shortened))", size: 10)
        let photoTop = y
        if let image {
            let destination = CGRect(x: 40, y: photoTop - 120, width: 180, height: 120)
            context.saveGState()
            context.clip(to: destination)
            let factor = camera.photoFit ? min(180 / image.size.width, 120 / image.size.height) : max(180 / image.size.width, 120 / image.size.height)
            let size = CGSize(width: image.size.width * factor, height: image.size.height * factor)
            image.draw(in: NSRect(x: destination.midX - size.width / 2, y: destination.midY - size.height / 2, width: size.width, height: size.height), from: .zero, operation: .sourceOver, fraction: 1)
            context.restoreGState()
            text("Make / model: \(value(camera.manufacturer)) · \(value(camera.model))", width: 305, x: 250)
            text("Serial: \(value(camera.serial))", width: 305, x: 250)
            text("Collection ID: \(value(camera.inventoryID))", width: 305, x: 250)
            text("Format: \(value(camera.format))", width: 305, x: 250)
            text("Shutter: \(value(camera.shutterType))", width: 305, x: 250)
            y = min(y, photoTop - 140)
        } else {
            text("Make / model: \(value(camera.manufacturer)) · \(value(camera.model))")
            text("Serial: \(value(camera.serial))     Collection ID: \(value(camera.inventoryID))")
        }
        if let session {
            text(session.displayTitle, size: 16, bold: true)
            text("Test started: \(session.createdAt.formatted(date: .long, time: .shortened)) · Revision \(session.effectiveRevision)")
            if let assignedAt = session.cameraAssignedAt {
                text("Original recorded camera name: \(value(session.cameraName))")
                text("Assigned camera identity: \(value(session.cameraSnapshot?.name ?? ""))")
                text("Assigned after capture: \(assignedAt.formatted(date: .long, time: .shortened))")
            } else {
                text("Camera at test time: \(session.cameraSnapshot?.name ?? session.cameraName)")
            }
            text("Operator: \(value(session.operatorName ?? "")) · Light: \(value(session.lightSource ?? ""))")
            text("Conditions: \(value(session.testConditions ?? ""))")
            text("Tester used: \(session.testerSummary)")
            let tolerance = session.toleranceStops ?? (1.0 / 3.0)
            text(String(format: "Chosen timing tolerance: ±%.3f stops. This is an operator comparison rule, not an overall camera grade.", tolerance))
            let complete = session.records.filter { !$0.isExcluded && $0.result.quality == .complete }
            let rows = CameraResultGroup.groups(for: session)
            let tableTitle = session.records.contains(where: \.isManual) ? "Exposure by setting and measurement method" : "Center exposure by setting"
            text(tableTitle, size: 13, bold: true)
            // Each column has a real frame; spaces in a proportional font cannot
            // align values with their headings or contain longer custom settings.
            let columns: [(x: CGFloat, width: CGFloat)] = [(40, 150), (202, 86), (300, 90), (402, 82), (496, 59)]
            let headings = ["Setting / tester / method", "Mean", "Difference", "SD", "Count"]
            func tableRow(_ cells: [String], heading: Bool = false) {
                let attributed = cells.map { cell in
                    let paragraph = NSMutableParagraphStyle()
                    paragraph.lineBreakMode = .byWordWrapping
                    return NSAttributedString(string: cell, attributes: [
                        .font: NSFont.monospacedDigitSystemFont(ofSize: 9, weight: heading ? .semibold : .regular),
                        .foregroundColor: NSColor.black,
                        .paragraphStyle: paragraph
                    ])
                }
                let heights = zip(attributed, columns).map { cell, column in
                    CTFramesetterSuggestFrameSizeWithConstraints(CTFramesetterCreateWithAttributedString(cell),
                                                               CFRange(location: 0, length: cell.length), nil,
                                                               CGSize(width: column.width, height: .greatestFiniteMagnitude), nil).height
                }
                let rowHeight = max(24, ceil(heights.max() ?? 0) + 10)
                if y - rowHeight < 60 {
                    endPage()
                    beginPage()
                    text(tableTitle + " (continued)", size: 13, bold: true)
                    if !heading { tableRow(headings, heading: true) }
                }
                if heading {
                    context.setFillColor(NSColor(calibratedWhite: 0.94, alpha: 1).cgColor)
                    context.fill(CGRect(x: 36, y: y - rowHeight, width: 523, height: rowHeight))
                }
                for (cell, column) in zip(attributed, columns) {
                    let path = CGPath(rect: CGRect(x: column.x, y: y - rowHeight + 5,
                                                  width: column.width, height: rowHeight - 10), transform: nil)
                    let frame = CTFramesetterCreateFrame(CTFramesetterCreateWithAttributedString(cell),
                                                        CFRange(location: 0, length: cell.length), path, nil)
                    CTFrameDraw(frame, context)
                }
                y -= rowHeight
                context.setStrokeColor(NSColor(calibratedWhite: 0.85, alpha: 1).cgColor)
                context.setLineWidth(0.5)
                context.move(to: CGPoint(x: 36, y: y))
                context.addLine(to: CGPoint(x: 559, y: y))
                context.strokePath()
            }
            if !rows.isEmpty { tableRow(headings, heading: true) }
            for group in rows {
                let stops = group.errorStops
                let sdText = group.sampleSD.map { String(format: "%.3f ms", $0) } ?? "—"
                let setting = "\(MeasurementFormat.speed(group.denominator)) · \(group.direction.title)\n\(group.contextDescription)"
                    + (abs(stops) > tolerance ? "\nOutside chosen range" : "")
                tableRow([setting, String(format: "%.3f ms", group.meanMS), String(format: "%+.3f stops", stops), sdText, "n=\(group.count)"])
            }
            y -= 8
            if rows.isEmpty { text("No included complete measurements are available.") }
            let excluded = session.records.filter(\.isExcluded).count
            let incomplete = session.records.filter { !$0.isExcluded && $0.result.quality != .complete }.count
            text("\(complete.count) included complete readings · \(excluded) excluded · \(incomplete) partial or invalid. Grouping keeps settings, directions, tester identities, measurement sources, modes and recorded calibration distances separate.", size: 9)
            text("Positive differences mean longer exposure. Sample standard deviation (SD) describes repeatability and requires at least two readings. Missing measurements are never treated as zero.", size: 9)
            let planned = session.plannedSpeeds ?? camera.plannedSpeeds
            text("Planned settings: \(planned.map { MeasurementFormat.speed($0) }.joined(separator: ", ")). Target: \(session.repeatsPerSpeed ?? 3) readings per speed.", size: 9)
            if session.records.contains(where: { !$0.isManual }) {
                text("USB timestamps record receipt time. Shutter Lover sensor geometry is 32 × 20 mm; current full-frame estimates support 36 × 24 mm only.", size: 9)
            }
            text("Firmware: \(value(Set(session.records.map(\.firmwareVersion).filter { !$0.isEmpty }).sorted().joined(separator: ", ")))", size: 9)
            if session.records.contains(where: \.isManual) {
                text("Manual readings", size: 12, bold: true)
                text("Manual timestamps are operator-recorded. No raw USB events, corner exposures or curtain travel are available. Mk II effective exposure is illumination-dependent and must not be interpreted as a three-sensor timing measurement.", size: 9)
                for (index, record) in session.records.enumerated() where record.isManual {
                    let status = record.isExcluded ? "Excluded" : "Included"
                    text("Reading \(index + 1) · \(status) · \(record.capturedAt.formatted(date: .abbreviated, time: .shortened)) · \(record.testerDescription)", bold: true)
                    text(record.manualProvenanceDescription ?? "", size: 9)
                    text("Recorded setting: \(MeasurementFormat.speed(record.nominalDenominator)) · \(record.measurementLabel): \(MeasurementFormat.milliseconds(record.result.center.durationMS))", size: 9)
                    // Keep the complete evidence identifier together, so a line
                    // break inside its hyphens cannot obstruct reading or copying.
                    text("Reading UUID: \(record.id.uuidString.lowercased())", size: 9)
                }
            }
            if !session.notes.isEmpty { text("Test notes", size: 12, bold: true); text(session.notes) }
            text("Original manual entries, packets where available, corrections and individual readings are retained in the complete camera archive. This report summarises the selected test only.", size: 9)
        } else {
            text("No tests recorded", size: 16, bold: true)
            text("This camera has no measurement evidence yet.")
        }
        endPage()
        context.closePDF()
        return data as Data
    }
}

@MainActor
extension AppModel {
    func exportCameraReport(_ cameraID: UUID, sessionID: UUID?) {
        guard let camera = cameras.first(where: { $0.id == cameraID }) else { return }
        let session = cameraSessions(cameraID).first { $0.id == sessionID } ?? cameraSessions(cameraID).first
        do {
            let data = try CameraReport.pdf(camera: camera, image: cameraImage(camera), session: session)
            save(data: data, filename: "\(safeFilename(camera.name))-report.pdf", type: .pdf)
        } catch { errorMessage = "Report could not be created: \(error.localizedDescription)" }
    }
}
