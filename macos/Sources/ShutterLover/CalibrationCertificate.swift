import Foundation
import ImageIO
import PDFKit
import UniformTypeIdentifiers

enum CalibrationCertificateError: LocalizedError {
    case invalid(String)
    case tooLarge

    var errorDescription: String? {
        switch self {
        case .invalid(let reason): return reason
        case .tooLarge: return "Calibration certificates must be no larger than 10 MB."
        }
    }
}

/// A copied document belongs to the equipment library, not an external file URL.
/// Reading snapshots retain the calibration distance without duplicating this file.
struct CalibrationCertificate: Identifiable, Codable, Equatable {
    static let maximumBytes = 10 * 1024 * 1024
    static let allowedContentTypes: [UTType] = [.pdf, .png, .jpeg, .tiff, .heic]

    var id = UUID()
    var filename: String
    var data: Data
    var importedAt = Date()

    /// The actual document format, rather than a filename's unchecked extension.
    /// Invalid stored attachments use the generic data type and fail validation.
    var contentType: UTType {
        if data.starts(with: Data("%PDF-".utf8)) { return .pdf }
        guard let source = CGImageSourceCreateWithData(data as CFData, Self.imageOptions),
              let identifier = CGImageSourceGetType(source) else { return .data }
        return UTType(identifier as String) ?? .data
    }

    /// Metadata validation runs on every library load/save. Import additionally
    /// performs a bounded image decode; ordinary saves do not rasterize images.
    func validate() throws {
        guard !filename.isEmpty, filename != ".", filename != "..", filename.utf8.count <= 255,
              !filename.contains("/"), !filename.contains("\\"), !filename.contains(":"),
              !filename.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else {
            throw CalibrationCertificateError.invalid("The calibration certificate must have a single safe filename.")
        }
        guard importedAt.timeIntervalSince1970.isFinite else {
            throw CalibrationCertificateError.invalid("The calibration certificate has an invalid attachment date.")
        }
        guard !data.isEmpty else { throw CalibrationCertificateError.invalid("The calibration certificate is empty.") }
        guard data.count <= Self.maximumBytes else { throw CalibrationCertificateError.tooLarge }
        let extensionType: UTType
        switch URL(fileURLWithPath: filename).pathExtension.lowercased() {
        case "pdf": extensionType = .pdf
        case "png": extensionType = .png
        case "jpg", "jpeg": extensionType = .jpeg
        case "tif", "tiff": extensionType = .tiff
        case "heic": extensionType = .heic
        default:
            throw CalibrationCertificateError.invalid("Choose a PDF, PNG, JPEG, TIFF or HEIC calibration certificate.")
        }
        guard contentType == extensionType else {
            throw CalibrationCertificateError.invalid("The certificate's filename extension does not match its contents.")
        }
        if extensionType == .pdf {
            guard let document = PDFDocument(data: data), !document.isLocked,
                  document.pageCount > 0, document.pageCount <= 1_000 else {
                throw CalibrationCertificateError.invalid("Choose a readable PDF certificate with 1–1,000 pages that does not require a password.")
            }
            for index in 0..<document.pageCount {
                guard let page = document.page(at: index) else {
                    throw CalibrationCertificateError.invalid("The PDF certificate contains an unreadable page.")
                }
                let bounds = page.bounds(for: .mediaBox)
                guard bounds.origin.x.isFinite, bounds.origin.y.isFinite,
                      bounds.width.isFinite, bounds.height.isFinite,
                      bounds.width > 0, bounds.height > 0,
                      bounds.width <= 14_400, bounds.height <= 14_400 else {
                    throw CalibrationCertificateError.invalid("The PDF certificate contains invalid page dimensions.")
                }
            }
        } else {
            guard let source = CGImageSourceCreateWithData(data as CFData, Self.imageOptions),
                  CGImageSourceGetStatus(source) == .statusComplete else {
                throw CalibrationCertificateError.invalid("The certificate image is incomplete or unreadable.")
            }
            let count = CGImageSourceGetCount(source)
            guard (1...128).contains(count) else {
                throw CalibrationCertificateError.invalid("Certificate images must contain between 1 and 128 pages.")
            }
            var pixels = 0.0
            for index in 0..<count {
                guard CGImageSourceGetStatusAtIndex(source, index) == .statusComplete,
                      let properties = CGImageSourceCopyPropertiesAtIndex(source, index, Self.imageOptions) as? [CFString: Any],
                      let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.doubleValue,
                      let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.doubleValue,
                      width.isFinite, height.isFinite, width > 0, height > 0,
                      width <= 20_000, height <= 20_000, width * height <= 100_000_000 else {
                    throw CalibrationCertificateError.invalid("Each certificate image page must be readable, no more than 20,000 pixels per side and no more than 100 megapixels.")
                }
                pixels += width * height
                guard pixels <= 400_000_000 else {
                    throw CalibrationCertificateError.invalid("The certificate image contains too many pixels across its pages.")
                }
            }
        }
    }

    /// The caller owns the security-scoped URL access. Read at most the limit
    /// plus one byte, even if a file grows between the size check and the read.
    static func read(from url: URL) throws -> CalibrationCertificate {
        let properties = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        guard properties.isRegularFile == true else {
            throw CalibrationCertificateError.invalid("Choose a regular certificate file.")
        }
        guard let size = properties.fileSize, size <= maximumBytes else { throw CalibrationCertificateError.tooLarge }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let bytes = try handle.read(upToCount: maximumBytes + 1) ?? Data()
        let certificate = CalibrationCertificate(filename: url.lastPathComponent, data: bytes)
        try certificate.validate()
        if certificate.contentType != .pdf {
            guard let source = CGImageSourceCreateWithData(bytes as CFData, imageOptions) else {
                throw CalibrationCertificateError.invalid("The certificate image could not be opened.")
            }
            // Decode a bounded preview once at import, including every TIFF page.
            let options = [kCGImageSourceCreateThumbnailFromImageAlways: true,
                           kCGImageSourceThumbnailMaxPixelSize: 2_048,
                           kCGImageSourceCreateThumbnailWithTransform: true,
                           kCGImageSourceShouldCacheImmediately: true] as CFDictionary
            for index in 0..<CGImageSourceGetCount(source) {
                guard CGImageSourceCreateThumbnailAtIndex(source, index, options) != nil else {
                    throw CalibrationCertificateError.invalid("The certificate image contains unreadable image data.")
                }
            }
        }
        return certificate
    }

    private static var imageOptions: CFDictionary {
        [kCGImageSourceShouldCache: false] as CFDictionary
    }
}
