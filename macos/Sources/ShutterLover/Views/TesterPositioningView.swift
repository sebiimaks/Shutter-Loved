import SwiftUI

struct TesterPositioningView: View {
    @EnvironmentObject private var model: AppModel
    let session: CaptureSession
    @State private var showingDetails = false

    var body: some View {
        if !session.demo && session.tester?.model.supportsManualEntry != true {
            HStack(spacing: 10) {
                Image(systemName: "ruler")
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                switch model.positioningGuidance(for: session) {
                case .ready(let value):
                    Text("LEDs → mount: \(AppModel.positioningNumber(value.ledToMountDistanceMM)) mm")
                        .font(.callout.weight(.medium))
                        .lineLimit(1)
                        .accessibilityLabel("LEDs to camera mount: \(AppModel.positioningNumber(value.ledToMountDistanceMM)) millimetres")
                    Text(value.mountName + (value.usesCustomDistance ? " · Modified" : ""))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .layoutPriority(-1)
                    Spacer(minLength: 0)
                    Button("Positioning details…") { showingDetails = true }
                        .fixedSize()
                case .unavailable:
                    Text("Positioning unavailable")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                    Button("Set up…") { showingDetails = true }
                        .accessibilityLabel("Set up tester positioning")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(Color.accentColor.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
            .popover(isPresented: $showingDetails, arrowEdge: .bottom) {
                positioningDetails
            }
        }
    }

    private var positioningDetails: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(model.activeCaptureSessionID == session.id ? "Position your connected Shutter Lover" : "Positioning preview", systemImage: "ruler")
                .font(.headline)
            switch model.positioningGuidance(for: session) {
            case .ready(let value):
                Text("\(AppModel.positioningNumber(value.ledToMountDistanceMM)) mm · LEDs to camera mount")
                    .font(.title3.weight(.semibold))
                    .textSelection(.enabled)
                Text("\(value.testerName) · \(value.cameraName) · \(value.mountName)")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Text("\(AppModel.positioningNumber(value.calibrationDistanceMM)) mm calibration − \(AppModel.positioningNumber(value.flangeDistanceMM)) mm flange distance\(value.usesCustomDistance ? " (custom value)" : "")")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                Text("Remove the lens. Measure from the LEDs to the camera’s lens-seating flange, with the tester sensor at the film plane and no mount adapter. Align the LEDs and sensor parallel to each other. This is a calculated guide; the app does not measure placement.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            case .unavailable(let message):
                Text(message)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Divider()
            HStack {
                SettingsLink { Text("Flange distances…") }
                Spacer(minLength: 8)
                if let cameraID = session.cameraID, let camera = model.cameras.first(where: { $0.id == cameraID }) {
                    Button("Edit camera mount…") {
                        showingDetails = false
                        model.editingCamera = camera
                    }
                }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(16)
        .frame(width: 410)
    }
}
