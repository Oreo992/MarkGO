import AppKit
import ImageIO

final class MarkdownImageCache: @unchecked Sendable {
    static let shared = MarkdownImageCache()

    private let cache = NSCache<NSURL, NSImage>()
    private let maxPixelSize: CGFloat

    private init(maxPixelSize: CGFloat = 2_400) {
        self.maxPixelSize = maxPixelSize
        cache.countLimit = 160
        cache.totalCostLimit = 256 * 1_024 * 1_024
    }

    func image(for url: URL?) -> NSImage? {
        guard let url else { return nil }
        return image(for: url, maxPixelSize: maxPixelSize)
    }

    func cachedImage(for url: URL?) -> NSImage? {
        guard let url else { return nil }
        return cachedImage(for: url, maxPixelSize: maxPixelSize)
    }

    func cachedImage(for url: URL, maxPixelSize: CGFloat) -> NSImage? {
        guard url.isFileURL else { return nil }
        let resolvedMaxPixelSize = max(1, Int(maxPixelSize.rounded(.up)))
        return cache.object(forKey: cacheKey(for: url, maxPixelSize: resolvedMaxPixelSize))
    }

    func imageAsync(for url: URL?) async -> NSImage? {
        guard let url else { return nil }
        return await imageAsync(for: url, maxPixelSize: maxPixelSize)
    }

    func imageAsync(for url: URL, maxPixelSize: CGFloat) async -> NSImage? {
        await Task.detached(priority: .userInitiated) {
            self.image(for: url, maxPixelSize: maxPixelSize)
        }.value
    }

    func image(for url: URL, maxPixelSize: CGFloat) -> NSImage? {
        guard url.isFileURL else { return nil }

        let resolvedMaxPixelSize = max(1, Int(maxPixelSize.rounded(.up)))
        let key = cacheKey(for: url, maxPixelSize: resolvedMaxPixelSize)
        if let cached = cache.object(forKey: key) {
            return cached
        }

        guard let source = CGImageSourceCreateWithURL(url as CFURL, [
            kCGImageSourceShouldCache: false
        ] as CFDictionary) else {
            return nil
        }

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: resolvedMaxPixelSize
        ]

        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }

        let image = NSImage(
            cgImage: cgImage,
            size: NSSize(width: cgImage.width, height: cgImage.height)
        )
        cache.setObject(
            image,
            forKey: key,
            cost: max(1, cgImage.bytesPerRow * cgImage.height)
        )
        return image
    }

    private func cacheKey(for url: URL, maxPixelSize: Int) -> NSURL {
        NSURL(string: "\(url.absoluteString)#markgo-max-\(maxPixelSize)") ?? url as NSURL
    }
}
