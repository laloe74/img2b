import CryptoKit
import Foundation
import ImageIO

struct ImageProcessor: Sendable {
    enum Error: Swift.Error, LocalizedError, Sendable {
        case loadFailed(String)
        case encodeFailed(String)
        case fileReadError

        var errorDescription: String? {
            switch self {
            case .loadFailed(let msg): "Load failed: \(msg)"
            case .encodeFailed(let msg): "Encode failed: \(msg)"
            case .fileReadError: "Could not read image file"
            }
        }
    }

    /// Compression levels matching Zipic's 6-level scale.
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
            case .light: "Light"
            case .balanced: "Balanced"
            case .moderate: "Moderate"
            case .aggressive: "Aggressive"
            case .extreme: "Extreme"
            }
        }

        var description: String {
            switch self {
            case .nearLossless: "Minimal data removal, maximum quality retention"
            case .light: "Nearly imperceptible changes"
            case .balanced: "Recommended for most images"
            case .moderate: "Noticeable on close inspection"
            case .aggressive: "Significant size reduction"
            case .extreme: "Smallest files, visible quality trade-offs"
            }
        }

        /// AVIF encoding quality (1–100).
        var quality: Int {
            switch self {
            case .nearLossless: 95
            case .light: 85
            case .balanced: 78
            case .moderate: 70
            case .aggressive: 60
            case .extreme: 50
            }
        }
    }

    /// Single-pass compression: resize if over maxWidth, encode at fixed quality level.
    nonisolated func processImage(at url: URL,
                      level: Int = 3,
                      maxWidth: Int = 0,
                      namePattern: String = "img-{hash16}-{date}",
                      onStep: (@Sendable (String?) -> Void)? = nil) async throws -> ImageItem {
        var item = ImageItem(originalURL: url)

        guard let data = try? Data(contentsOf: url) else { throw Error.fileReadError }
        item.fileSize = Int64(data.count)

        let hash = SHA256.hash(data: data)
        let hashString = hash.map { String(format: "%02x", $0) }.joined()
        item.hash16 = String(hashString.prefix(16))

        let df = DateFormatter(); df.dateFormat = "yyyyMMdd"
        item.dateString = df.string(from: Date())
        item.title = formatName(pattern: namePattern, hash16: item.hash16, hash: hashString, date: item.dateString)

        let cacheDir = Self.cacheDirectory()
        let outputURL = cacheDir.appendingPathComponent("\(item.title).avif")

        let cl = Level(rawValue: min(6, max(1, level))) ?? .balanced
        let quality = cl.quality

        // Load image
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else { throw Error.loadFailed("\(data.count) bytes, type unknown") }

        // Capture original metadata
        item.originalWidth = cgImage.width
        item.originalHeight = cgImage.height
        if let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] {
            item.originalColorSpace = (props[kCGImagePropertyProfileName] as? String)
                ?? (props[kCGImagePropertyColorModel] as? String)
                ?? ""
        }

        // Resolve width: only resize if exceeding maxWidth (0 = no limit)
        let origW = cgImage.width
        let targetW = maxWidth > 0 ? min(origW, maxWidth) : origW
        let needsResize = targetW < origW

        onStep?(needsResize ? "Resizing to \(targetW)px wide..." : "Converting (L\(cl.rawValue))...")

        let encoded = try encodeImage(cgImage, toWidth: targetW, quality: quality)

        // Don't make files bigger: keep original if compression didn't help
        let finalData = encoded.count < data.count ? encoded : data

        try finalData.write(to: outputURL)

        // Read output dimensions
        if let src = CGImageSourceCreateWithData(finalData as CFData, nil),
           let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any],
           let w = props[kCGImagePropertyPixelWidth] as? Int,
           let h = props[kCGImagePropertyPixelHeight] as? Int {
            item.width = w
            item.height = h
        }

        onStep?(nil)

        var finalItem = item
        finalItem.webpURL = outputURL
        finalItem.webpSize = Int64(finalData.count)
        finalItem.status = .ready
        return finalItem
    }

    // MARK: - Resize + encode

    private func encodeImage(_ image: CGImage, toWidth targetW: Int, quality: Int) throws -> Data {
        let cgImage: CGImage
        let scale = min(CGFloat(targetW) / CGFloat(image.width), 1.0)

        if scale < 1.0 {
            let newW = Int(CGFloat(image.width) * scale)
            let newH = Int(CGFloat(image.height) * scale)
            guard let ctx = CGContext(
                data: nil, width: newW, height: newH,
                bitsPerComponent: 8, bytesPerRow: 0,
                space: image.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: image.bitmapInfo.rawValue
            ) else { throw Error.encodeFailed("CGContext failed") }

            ctx.interpolationQuality = .high
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: newW, height: newH))

            guard let resized = ctx.makeImage() else { throw Error.encodeFailed("makeImage failed") }
            cgImage = resized
        } else {
            cgImage = image
        }

        return try encodeCGImage(cgImage, quality: quality)
    }

    // MARK: - AVIF encoding (sRGB fallback, HEIC last resort)

    private func encodeCGImage(_ cgImage: CGImage, quality: Int) throws -> Data {
        let q = CGFloat(quality) / 100.0

        if let data = tryEncodeAVIF(cgImage, quality: q) { return data }

        if let normalized = convertToSRGB(cgImage),
           let data = tryEncodeAVIF(normalized, quality: q) { return data }

        let heicData = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(heicData, "public.heic" as CFString, 1, nil)
        else { throw Error.encodeFailed("HEIC encoder unavailable") }

        CGImageDestinationAddImage(dest, cgImage, [kCGImageDestinationLossyCompressionQuality: q] as CFDictionary)

        guard CGImageDestinationFinalize(dest) else { throw Error.encodeFailed("encode failed, \(cgImage.width)x\(cgImage.height)") }
        return heicData as Data
    }

    private func tryEncodeAVIF(_ image: CGImage, quality: CGFloat) -> Data? {
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(data, "public.avif" as CFString, 1, nil)
        else { return nil }
        CGImageDestinationAddImage(dest, image, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        return CGImageDestinationFinalize(dest) ? (data as Data) : nil
    }

    private func convertToSRGB(_ cgImage: CGImage) -> CGImage? {
        let w = cgImage.width, h = cgImage.height
        guard let ctx = CGContext(
            data: nil, width: w, height: h,
            bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: w, height: h))
        return ctx.makeImage()
    }

    // MARK: - Helpers

    static func cacheURL(for title: String) -> URL {
        cacheDirectory().appendingPathComponent("\(title).avif")
    }

    static func cacheDirectory() -> URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("img2b/cache")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func formatName(pattern: String, hash16: String, hash: String, date: String) -> String {
        pattern
            .replacingOccurrences(of: "{hash16}", with: hash16)
            .replacingOccurrences(of: "{hash8}", with: String(hash.prefix(8)))
            .replacingOccurrences(of: "{hash}", with: hash)
            .replacingOccurrences(of: "{date}", with: date)
    }
}
