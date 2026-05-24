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

    nonisolated func processImage(at url: URL, quality: Int = 90, lossless: Bool = false,
                      maxSizeKB: Int = 500, namePattern: String = "img-{hash16}-{date}",
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

        let tempDir = FileManager.default.temporaryDirectory
        let outputURL = tempDir.appendingPathComponent("\(item.title).heic")

        let maxBytes = maxSizeKB * 1024

        // Pre-resize huge images — avoid OOM and encoder limits
        var workingData = data
        if let source = CGImageSourceCreateWithData(data as CFData, nil),
           let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
           let w = props[kCGImagePropertyPixelWidth] as? Int,
           let h = props[kCGImagePropertyPixelHeight] as? Int,
           max(w, h) > 4000 {
            onStep?("Pre-resizing \(w)x\(h)...")
            if let resized = try? encodeResized(data: data, maxDimension: 4000, quality: quality) {
                workingData = resized
            }
        }

        // Step 1: requested quality
        let q = min(100, max(1, quality))
        onStep?("Converting (Q\(q))...")
        var encoded = try encode(data: workingData, quality: q, lossless: lossless)

        // Step 2: step down quality to hit target (80, then 65 minimum)
        if !lossless, encoded.count > maxBytes {
            for q2 in [80, 65] where encoded.count > maxBytes {
                onStep?("Recompressing (Q\(q2))...")
                encoded = try encode(data: workingData, quality: q2, lossless: false)
            }
        }

        // Step 3: resize to 1920px at Q75 — quality floor
        if !lossless, encoded.count > maxBytes {
            onStep?("Resizing to 1920px...")
            encoded = try encodeResized(data: workingData, maxDimension: 1920, quality: 75)
        }

        try encoded.write(to: outputURL)

        onStep?(nil)

        var finalItem = item
        finalItem.webpURL = outputURL
        finalItem.webpSize = Int64(encoded.count)
        finalItem.status = .ready
        return finalItem
    }

    // MARK: - Native AVIF encoding

    private func encode(data: Data, quality: Int, lossless: Bool) throws -> Data {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else { throw Error.loadFailed("\(data.count) bytes, type unknown") }

        let output = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(output, "public.heic" as CFString, 1, nil)
        else { throw Error.encodeFailed("HEIC encoder unavailable") }

        CGImageDestinationAddImage(dest, cgImage, [kCGImageDestinationLossyCompressionQuality: CGFloat(quality) / 100.0] as CFDictionary)

        guard CGImageDestinationFinalize(dest) else { throw Error.encodeFailed("finalize failed, \(cgImage.width)x\(cgImage.height)") }
        return output as Data
    }

    private func encodeResized(data: Data, maxDimension: Int, quality: Int) throws -> Data {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else { throw Error.loadFailed("resize: \(data.count) bytes") }

        let w = CGFloat(cgImage.width)
        let h = CGFloat(cgImage.height)
        let scale = min(CGFloat(maxDimension) / max(w, h), 1.0)

        guard let ctx = CGContext(
            data: nil, width: Int(w * scale), height: Int(h * scale),
            bitsPerComponent: 8, bytesPerRow: 0,
            space: cgImage.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: cgImage.bitmapInfo.rawValue
        ) else { throw Error.encodeFailed("CGContext failed") }

        ctx.interpolationQuality = .high
        ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: Int(w * scale), height: Int(h * scale)))

        guard let resized = ctx.makeImage() else { throw Error.encodeFailed("makeImage failed") }

        let output = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(output, "public.heic" as CFString, 1, nil)
        else { throw Error.encodeFailed("HEIC encoder unavailable") }

        CGImageDestinationAddImage(dest, resized, [kCGImageDestinationLossyCompressionQuality: CGFloat(quality) / 100.0] as CFDictionary)

        guard CGImageDestinationFinalize(dest) else { throw Error.encodeFailed("resize finalize failed") }
        return output as Data
    }

    // MARK: - Helpers

    private func formatName(pattern: String, hash16: String, hash: String, date: String) -> String {
        pattern
            .replacingOccurrences(of: "{hash16}", with: hash16)
            .replacingOccurrences(of: "{hash8}", with: String(hash.prefix(8)))
            .replacingOccurrences(of: "{hash}", with: hash)
            .replacingOccurrences(of: "{date}", with: date)
    }
}
