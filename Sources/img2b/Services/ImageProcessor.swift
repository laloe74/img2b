import CryptoKit
import Foundation
import ImageIO

struct ImageProcessor: Sendable {

    // MARK: - Error

    enum Error: Swift.Error, LocalizedError, Sendable {
        case fileRead(String)
        case decodeFailed(String)
        case encodeFailed(String)

        var errorDescription: String? {
            switch self {
            case .fileRead(let msg): "File read failed: \(msg)"
            case .decodeFailed(let msg): "Decode failed: \(msg)"
            case .encodeFailed(let msg): "Encode failed: \(msg)"
            }
        }
    }

    // MARK: - Compression Level

    /// 1 = best quality (near‑lossless), 6 = smallest file (extreme).
    /// Matches the slider label: left "Best Quality" → right "Lowest Quality".
    enum Level: Int, CaseIterable, Sendable {
        case nearLossless = 1
        case light = 2
        case balanced = 3
        case moderate = 4
        case aggressive = 5
        case extreme = 6

        var label: String {
            switch self {
            case .nearLossless: "Near Lossless"
            case .light:        "Light"
            case .balanced:     "Balanced"
            case .moderate:     "Moderate"
            case .aggressive:   "Aggressive"
            case .extreme:      "Extreme"
            }
        }

        var description: String {
            switch self {
            case .nearLossless: "Minimal quality loss"
            case .light:        "Nearly imperceptible changes"
            case .balanced:     "Recommended for most images"
            case .moderate:     "Good compression / quality balance"
            case .aggressive:   "Strong size reduction"
            case .extreme:      "Smallest file, visible compression"
            }
        }

        /// AVIF quality 1–100. 1=best → 6=smallest.
        var quality: CGFloat { [96, 88, 78, 60, 40, 20][rawValue - 1] }
    }

    // MARK: - Public API

    nonisolated func processImage(
        at url: URL,
        level: Int = 3,
        maxWidth: Int = 0,
        namePattern: String = "img-{hash16}-{date}",
        onStep: (@Sendable (String?) -> Void)? = nil
    ) async throws -> ImageItem {
        var item = ImageItem(originalURL: url)

        // 1. Read source file
        guard let sourceData = try? Data(contentsOf: url)
        else { throw Error.fileRead(url.path) }
        item.fileSize = Int64(sourceData.count)

        // 2. Hash
        let hash = SHA256.hash(data: sourceData)
        let hex = hash.map { String(format: "%02x", $0) }.joined()
        item.hash16 = String(hex.prefix(16))

        // 3. Name
        let df = DateFormatter(); df.dateFormat = "yyyyMMdd"
        item.dateString = df.string(from: Date())
        item.title = formatName(pattern: namePattern, hash16: item.hash16, hash: hex, date: item.dateString)

        // 4. Decode
        guard let src = CGImageSourceCreateWithData(sourceData as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(src, 0, nil)
        else { throw Error.decodeFailed("\(sourceData.count) bytes") }

        // Capture original metadata
        item.originalWidth = image.width
        item.originalHeight = image.height
        if let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any] {
            item.originalColorSpace = (props[kCGImagePropertyProfileName] as? String)
                ?? (props[kCGImagePropertyColorModel] as? String) ?? ""
        }

        // 5. Compression quality
        let cl = Level(rawValue: min(6, max(1, level))) ?? .balanced

        // 6. Resize if needed
        let needsResize = (maxWidth > 0 && image.width > maxWidth)
        onStep?(needsResize ? "Resizing to \(maxWidth)px…" : "Converting to AVIF…")

        let finalImage = needsResize
            ? try resize(image, toWidth: maxWidth)
            : image

        // 7. Encode to AVIF
        let q = cl.quality / 100
        let avifData = try encodeAVIF(finalImage, quality: q)

        // 8. Compare: only use AVIF if actually smaller
        if avifData.count < Int(item.fileSize) {
            item.outputFormat = "avif"
            item.webpSize = Int64(avifData.count)
            let cached = cacheDir.appendingPathComponent("\(item.title).avif")
            try avifData.write(to: cached)
            item.webpURL = cached

            if let s = CGImageSourceCreateWithData(avifData as CFData, nil),
               let p = CGImageSourceCopyPropertiesAtIndex(s, 0, nil) as? [CFString: Any] {
                item.width = (p[kCGImagePropertyPixelWidth] as? Int) ?? finalImage.width
                item.height = (p[kCGImagePropertyPixelHeight] as? Int) ?? finalImage.height
            }
        } else {
            // AVIF wasn't smaller — keep original format
            let ext = url.pathExtension.lowercased().nonempty ?? "jpg"
            item.outputFormat = ext
            item.webpSize = Int64(sourceData.count)
            item.width = finalImage.width
            item.height = finalImage.height
            let cached = cacheDir.appendingPathComponent("\(item.title).\(ext)")
            try sourceData.write(to: cached)
            item.webpURL = cached
        }

        item.status = .ready
        onStep?(nil)
        return item
    }

    // MARK: - Resize (Core Graphics, no external tool)

    private func resize(_ image: CGImage, toWidth maxWidth: Int) throws -> CGImage {
        let scale = CGFloat(maxWidth) / CGFloat(image.width)
        let w = Int(CGFloat(image.width) * scale)
        let h = Int(CGFloat(image.height) * scale)

        guard let ctx = CGContext(
            data: nil, width: w, height: h,
            bitsPerComponent: 8, bytesPerRow: 0,
            space: image.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: image.bitmapInfo.rawValue
        ) else { throw Error.encodeFailed("Cannot create resize context") }

        ctx.interpolationQuality = .high
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))

        guard let resized = ctx.makeImage()
        else { throw Error.encodeFailed("Resize failed") }
        return resized
    }

    // MARK: - AVIF encoding (3‑stage fallback for all color spaces)

    /// Tries direct encode → sRGB premultiplied → sRGB straight alpha.
    /// Covers virtually all macOS‑decodable images.
    private func encodeAVIF(_ image: CGImage, quality: CGFloat) throws -> Data {
        // 1. Direct: works for sRGB, Display P3 (if encoder supports it)
        if let d = avifEncode(image, quality: quality) { return d }

        // 2. Convert to sRGB with premultiplied alpha
        if let normalized = convertToSRGB(image, alpha: .premultipliedLast),
           let d = avifEncode(normalized, quality: quality) { return d }

        // 3. Convert to sRGB without alpha — handles opaque images
        if let normalized = convertToSRGB(image, alpha: .noneSkipLast),
           let d = avifEncode(normalized, quality: quality) { return d }

        throw Error.encodeFailed("AVIF encoding failed after 3 attempts")
    }

    private func avifEncode(_ image: CGImage, quality: CGFloat) -> Data? {
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(
            data, "public.avif" as CFString, 1, nil
        ) else { return nil }

        let options: [CFString: Any] = [
            kCGImageDestinationLossyCompressionQuality: quality,
            kCGImageDestinationOptimizeColorForSharing: true,
        ]

        CGImageDestinationAddImage(dest, image, options as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { return nil }
        return data as Data
    }

    private func convertToSRGB(_ image: CGImage,
                                alpha: CGImageAlphaInfo = .premultipliedLast) -> CGImage? {
        let w = image.width, h = image.height
        guard let ctx = CGContext(
            data: nil, width: w, height: h,
            bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: alpha.rawValue
        ) else { return nil }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        return ctx.makeImage()
    }

    // MARK: - Cache

    static func cacheURL(for title: String) -> URL {
        cacheDir.appendingPathComponent("\(title).avif")
    }

    private static var cacheDir: URL {
        let dir = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first!.appendingPathComponent("img2b/cache")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private var cacheDir: URL { Self.cacheDir }

    // MARK: - Name Formatting

    private func formatName(pattern: String, hash16: String, hash: String, date: String) -> String {
        pattern
            .replacingOccurrences(of: "{hash16}", with: hash16)
            .replacingOccurrences(of: "{hash8}",  with: String(hash.prefix(8)))
            .replacingOccurrences(of: "{hash}",   with: hash)
            .replacingOccurrences(of: "{date}",   with: date)
    }
}

private extension String {
    var nonempty: String? { isEmpty ? nil : self }
}
