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
        let outputURL = tempDir.appendingPathComponent("\(item.title).avif")

        let maxBytes = maxSizeKB * 1024

        // Pre-resize huge images — resize only, keep lossless intermediate
        var workingData = data
        if let source = CGImageSourceCreateWithData(data as CFData, nil),
           let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
           let w = props[kCGImagePropertyPixelWidth] as? Int,
           let h = props[kCGImagePropertyPixelHeight] as? Int,
           max(w, h) > 4000 {
            onStep?("Pre-resizing \(w)x\(h)...")
            if let resizedPNG = try? resizeToPNG(data: data, maxDimension: 4000) {
                workingData = resizedPNG
            }
        }

        // Step 1: requested quality
        let q = min(100, max(1, quality))
        onStep?("Converting (Q\(q))...")
        var encoded = try encode(data: workingData, quality: q, lossless: lossless)

        // Step 2: step down quality to hit target, floor at Q75
        if !lossless, encoded.count > maxBytes {
            for q2 in [85, 75] where encoded.count > maxBytes {
                onStep?("Recompressing (Q\(q2))...")
                encoded = try encode(data: workingData, quality: q2, lossless: false)
            }
        }

        // Step 3: gradual resize, keep Q75 quality floor
        var didResize = false
        if !lossless, encoded.count > maxBytes {
            didResize = true
            for dim in [3200, 2560, 2048] where encoded.count > maxBytes {
                onStep?("Resizing to \(dim)px...")
                encoded = try encodeResized(data: workingData, maxDimension: dim, quality: 75)
            }
        }

        // Step 4: if at original resolution and way under target, improve quality
        if !lossless, !didResize, encoded.count < maxBytes / 3 {
            for qUp in [80, 85, 90] {
                let candidate = try encode(data: workingData, quality: qUp, lossless: false)
                if candidate.count <= maxBytes {
                    encoded = candidate
                } else {
                    break
                }
            }
        }

        try encoded.write(to: outputURL)

        // Read compressed dimensions
        if let source = CGImageSourceCreateWithData(encoded as CFData, nil),
           let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
           let w = props[kCGImagePropertyPixelWidth] as? Int,
           let h = props[kCGImagePropertyPixelHeight] as? Int {
            item.width = w
            item.height = h
        }

        onStep?(nil)

        var finalItem = item
        finalItem.webpURL = outputURL
        finalItem.webpSize = Int64(encoded.count)
        finalItem.status = .ready
        return finalItem
    }

    // MARK: - Native AVIF encoding (HEIC fallback)

    private func encode(data: Data, quality: Int, lossless: Bool) throws -> Data {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else { throw Error.loadFailed("\(data.count) bytes, type unknown") }

        return try encodeCGImage(cgImage, quality: quality)
    }

    private func resizeToPNG(data: Data, maxDimension: Int) throws -> Data {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else { throw Error.loadFailed("resize: \(data.count) bytes") }

        let w = CGFloat(cgImage.width); let h = CGFloat(cgImage.height)
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

        // Save as lossless PNG intermediate
        let output = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(output, "public.png" as CFString, 1, nil)
        else { throw Error.encodeFailed("PNG encoder unavailable") }
        CGImageDestinationAddImage(dest, resized, nil)
        guard CGImageDestinationFinalize(dest) else { throw Error.encodeFailed("PNG finalize failed") }
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

        return try encodeCGImage(resized, quality: quality)
    }

    /// Try AVIF first (native, then sRGB-normalized), fall back to HEIC
    private func encodeCGImage(_ cgImage: CGImage, quality: Int) throws -> Data {
        let q = CGFloat(quality) / 100.0

        // Attempt 1: AVIF with original pixel data
        if let data = tryEncodeAVIF(cgImage, quality: q) { return data }

        // Attempt 2: AVIF with sRGB-normalized image (some sources fail due to exotic color space)
        if let normalized = convertToSRGB(cgImage),
           let data = tryEncodeAVIF(normalized, quality: q) { return data }

        // Fallback: HEIC with original pixel data
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

    private func formatName(pattern: String, hash16: String, hash: String, date: String) -> String {
        pattern
            .replacingOccurrences(of: "{hash16}", with: hash16)
            .replacingOccurrences(of: "{hash8}", with: String(hash.prefix(8)))
            .replacingOccurrences(of: "{hash}", with: hash)
            .replacingOccurrences(of: "{date}", with: date)
    }
}
