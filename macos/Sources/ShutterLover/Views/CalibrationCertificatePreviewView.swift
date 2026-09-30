import SwiftUI
import PDFKit
import ImageIO

struct CalibrationCertificatePreviewView: View {
    @Environment(\.dismiss) private var dismiss
    let certificate: CalibrationCertificate
    @State private var imagePage = 0

    private var imageSource: CGImageSource? {
        CGImageSourceCreateWithData(certificate.data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary)
    }

    private var imagePageCount: Int { imageSource.map(CGImageSourceGetCount) ?? 0 }

    private var image: NSImage? {
        guard let source = imageSource,
              let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, imagePage, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: 2_048,
                kCGImageSourceCreateThumbnailWithTransform: true
              ] as CFDictionary) else { return nil }
        return NSImage(cgImage: thumbnail, size: .zero)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Calibration certificate").font(.title2.weight(.semibold))
                    Text(certificate.filename).foregroundStyle(.secondary).textSelection(.enabled)
                }
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.cancelAction)
            }.padding(20)
            Divider()
            if certificate.contentType == .pdf {
                CertificatePDFView(data: certificate.data)
            } else if let image {
                VStack {
                    if imagePageCount > 1 {
                        HStack {
                            Button("Previous page") { imagePage -= 1 }.disabled(imagePage == 0)
                            Text("Page \(imagePage + 1) of \(imagePageCount)")
                            Button("Next page") { imagePage += 1 }.disabled(imagePage + 1 >= imagePageCount)
                        }.padding(.top, 12)
                    }
                    ScrollView([.horizontal, .vertical]) {
                        Image(nsImage: image).resizable().scaledToFit().frame(width: 690)
                            .padding(18).accessibilityLabel("Scanned calibration certificate, page \(imagePage + 1)")
                    }
                }
            } else {
                ContentUnavailableView("Preview unavailable", systemImage: "doc", description: Text("Save a copy to open the certificate in another application."))
            }
        }.frame(width: 760, height: 700)
    }
}

private struct CertificatePDFView: NSViewRepresentable {
    let data: Data

    func makeNSView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.document = PDFDocument(data: data)
        return view
    }

    func updateNSView(_ view: PDFView, context: Context) {}
}
