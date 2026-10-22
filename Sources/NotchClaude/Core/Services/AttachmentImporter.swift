import AppKit
import ImageIO
import UniformTypeIdentifiers

enum AttachmentImporter {
    private static let passthroughTypes: [String: String] = [
        "png": "image/png",
        "jpg": "image/jpeg",
        "jpeg": "image/jpeg",
        "gif": "image/gif",
        "webp": "image/webp"
    ]
    private static let maxBytes = 3_700_000
    private static let maxPixels: CGFloat = 2000

    static func importFiles(_ urls: [URL]) -> [Attachment] {
        urls.compactMap(importFile)
    }

    static func importFile(_ url: URL) -> Attachment? {
        let ext = url.pathExtension.lowercased()
        let isImage = UTType(filenameExtension: ext)?.conforms(to: .image) ?? false
        guard isImage else { return copy(url, mediaType: nil) }

        if let mediaType = passthroughTypes[ext], fitsLimits(url) {
            return copy(url, mediaType: mediaType)
        }
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return copy(url, mediaType: nil) }
        return encode(source: source, preferPNG: ext == "png", originalName: url.lastPathComponent)
    }

    static func importImageData(_ data: Data, name: String) -> Attachment? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return encode(source: source, preferPNG: true, originalName: name)
    }

    static func importFromPasteboard(_ pasteboard: NSPasteboard = .general) -> [Attachment] {
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL], !urls.isEmpty {
            return importFiles(urls)
        }
        for type in [NSPasteboard.PasteboardType.png, .tiff] {
            if let data = pasteboard.data(forType: type), let attachment = importImageData(data, name: "Imagem colada.png") {
                return [attachment]
            }
        }
        return []
    }

    static func pasteboardHasAttachments(_ pasteboard: NSPasteboard = .general) -> Bool {
        let types = pasteboard.types ?? []
        if types.contains(.png) || types.contains(.tiff) { return true }
        return types.contains(.fileURL)
    }

    static func remove(_ attachments: [Attachment]) {
        attachments.forEach { try? FileManager.default.removeItem(at: $0.url) }
    }

    private static func fitsLimits(_ url: URL) -> Bool {
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? .max
        guard size <= maxBytes,
              let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else { return false }
        let width = (properties[kCGImagePropertyPixelWidth] as? CGFloat) ?? .infinity
        let height = (properties[kCGImagePropertyPixelHeight] as? CGFloat) ?? .infinity
        return max(width, height) <= maxPixels
    }

    private static func copy(_ url: URL, mediaType: String?) -> Attachment? {
        let ext = url.pathExtension.isEmpty ? "" : ".\(url.pathExtension.lowercased())"
        let fileName = UUID().uuidString + ext
        let destination = AppPaths.attachments.appendingPathComponent(fileName)
        do {
            try FileManager.default.copyItem(at: url, to: destination)
        } catch {
            return nil
        }
        return Attachment(fileName: fileName, originalName: url.lastPathComponent, mediaType: mediaType)
    }

    private static func encode(source: CGImageSource, preferPNG: Bool, originalName: String) -> Attachment? {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixels
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        let bitmap = NSBitmapImageRep(cgImage: image)

        if preferPNG, let png = bitmap.representation(using: .png, properties: [:]), png.count <= maxBytes {
            return write(png, ext: "png", mediaType: "image/png", originalName: originalName)
        }
        for quality in [0.85, 0.7, 0.55] {
            if let jpeg = bitmap.representation(using: .jpeg, properties: [.compressionFactor: quality]), jpeg.count <= maxBytes {
                return write(jpeg, ext: "jpg", mediaType: "image/jpeg", originalName: originalName)
            }
        }
        return nil
    }

    private static func write(_ data: Data, ext: String, mediaType: String, originalName: String) -> Attachment? {
        let fileName = "\(UUID().uuidString).\(ext)"
        do {
            try data.write(to: AppPaths.attachments.appendingPathComponent(fileName))
        } catch {
            return nil
        }
        return Attachment(fileName: fileName, originalName: originalName, mediaType: mediaType)
    }
}
