import AppKit

/// Stores contact photos as PNG files next to the other user data and keeps a
/// small in-memory cache so SwiftUI views can render avatars cheaply.
enum AvatarStorage {
    private static let cache = NSCache<NSString, NSImage>()
    private static let pixelSize: CGFloat = 512

    static var directory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base
            .appendingPathComponent("SIPPhone", isDirectory: true)
            .appendingPathComponent("Avatars", isDirectory: true)
    }

    static func url(for filename: String) -> URL {
        directory.appendingPathComponent(filename)
    }

    static func image(named filename: String) -> NSImage? {
        let key = filename as NSString
        if let cached = cache.object(forKey: key) { return cached }
        guard let image = NSImage(contentsOf: url(for: filename)) else { return nil }
        cache.setObject(image, forKey: key)
        return image
    }

    /// Imports an image file, crops it to a centered square, scales it down and
    /// stores it as PNG. Returns the generated file name.
    static func importImage(from sourceURL: URL) -> String? {
        let scoped = sourceURL.startAccessingSecurityScopedResource()
        defer { if scoped { sourceURL.stopAccessingSecurityScopedResource() } }

        guard let source = NSImage(contentsOf: sourceURL),
              let bitmap = NSBitmapImageRep(
                bitmapDataPlanes: nil,
                pixelsWide: Int(pixelSize),
                pixelsHigh: Int(pixelSize),
                bitsPerSample: 8,
                samplesPerPixel: 4,
                hasAlpha: true,
                isPlanar: false,
                colorSpaceName: .deviceRGB,
                bytesPerRow: 0,
                bitsPerPixel: 0
              ),
              let context = NSGraphicsContext(bitmapImageRep: bitmap)
        else { return nil }

        let sourceSize = source.size
        guard sourceSize.width > 0, sourceSize.height > 0 else { return nil }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        context.imageInterpolation = .high

        let scale = max(pixelSize / sourceSize.width, pixelSize / sourceSize.height)
        let width = sourceSize.width * scale
        let height = sourceSize.height * scale
        let rect = NSRect(
            x: (pixelSize - width) / 2,
            y: (pixelSize - height) / 2,
            width: width,
            height: height
        )
        source.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1)

        NSGraphicsContext.restoreGraphicsState()

        guard let data = bitmap.representation(using: .png, properties: [:]) else { return nil }

        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let filename = UUID().uuidString + ".png"
        do {
            try data.write(to: url(for: filename), options: .atomic)
        } catch {
            return nil
        }
        return filename
    }

    static func delete(named filename: String) {
        cache.removeObject(forKey: filename as NSString)
        try? FileManager.default.removeItem(at: url(for: filename))
    }
}
