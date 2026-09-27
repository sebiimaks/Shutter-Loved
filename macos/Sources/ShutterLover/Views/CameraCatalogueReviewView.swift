import SwiftUI

struct CameraCatalogueReviewView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let review: CatalogueImportReview

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Review camera catalogue").font(.title2.weight(.semibold))
            Text("\(review.sourceApplication) · \(review.rows.count) cameras").foregroundStyle(.secondary)
            Text("Camera identities and specifications are matched by catalogue IDs. Local photos, notes, service history and previous tests are retained.")
                .font(.callout).foregroundStyle(.secondary)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    ForEach(review.rows) { row in
                        VStack(alignment: .leading, spacing: 5) {
                            HStack {
                                Text(row.cameraName).font(.headline)
                                Spacer()
                                Text(row.disposition.title).font(.caption.weight(.semibold))
                                    .foregroundStyle(row.disposition == .conflict ? Color.red : .secondary)
                            }
                            Text("Revision \(row.revision) · \(row.externalCameraID.uuidString)").font(.caption.monospaced()).textSelection(.enabled)
                            Text(row.detail).font(.caption).foregroundStyle(.secondary)
                            Divider()
                        }
                    }
                }
            }
            .frame(minHeight: 160, maxHeight: 370)
            if !review.canApply {
                Label("Conflicts block the whole import. Export corrected revisions from Armarium, then review again.", systemImage: "exclamationmark.triangle")
                    .font(.callout).foregroundStyle(.orange)
            }
            HStack {
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button(review.hasChanges ? "Apply import" : "Done — no changes") { model.applyCameraCatalogue() }
                    .buttonStyle(.borderedProminent)
                    .disabled(!review.canApply)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 650)
    }
}
