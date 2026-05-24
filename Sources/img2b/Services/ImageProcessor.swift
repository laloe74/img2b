import CryptoKit
import Foundation
import ImageIO
struct ImageProcessor: Sendable {
    enum Error: Swift.Error, LocalizedError {
        case loadFailed
        case encodeFailed
        case fileReadError

        var errorDescription: String? {
            switch self {
            case .loadFailed: "Could not load image"
            case .encodeFailed: "AVIF encoding failed"
            case .fileReadError: "Could not read image file"
            }
        }
    }

    func processImage(at url: URL, quality: Int = 90, lossless: Bool = false,
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

        // Step 1: encode at requested quality
        onStep?("Converting (Q\(quality))...")
        let q = min(100, max(1, quality))
        var encoded = try await encodeAVIF(from: url, quality: q, lossless: lossless, effort: 4)

        // Step 2: retry with max effort
        if !lossless, encoded.count > maxSizeKB * 1024 {
            onStep?("Recompressing (max effort)...")
            encoded = try await encodeAVIF(from: url, quality: q, lossless: false, effort: 9)
        }

        // Step 3: resize then encode
        if !lossless, encoded.count > maxSizeKB * 1024 {
            onStep?("Resizing to 1920px...")
            encoded = try await encodeResizedAVIF(from: url, maxDimension: 1920, quality: q)
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

    private func encodeAVIF(from url: URL, quality: Int, lossless: Bool, effort: Int) async throws -> Data {
        try await Task.detached {
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                  let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil)
            else { throw Error.loadFailed }

            let data = NSMutableData()
            guard let dest = CGImageDestinationCreateWithData(data, "public.avif" as CFString, 1, nil)
            else { throw Error.encodeFailed }

            let options: [CFString: Any] = [
                kCGImageDestinationLossyCompressionQuality: CGFloat(quality) / 100.0,
                ]

            CGImageDestinationAddImage(dest, cgImage, options as CFDictionary)
            guard CGImageDestinationFinalize(dest) else { throw Error.encodeFailed }
            return data as Data
        }.value
    }

    private func encodeResizedAVIF(from url: URL, maxDimension: Int, quality: Int) async throws -> Data {
        try await Task.detached {
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                  let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil)
            else { throw Error.loadFailed }

            let origW = CGFloat(cgImage.width)
            let origH = CGFloat(cgImage.height)
            let scale = min(CGFloat(maxDimension) / max(origW, origH), 1.0)
            let newW = Int(origW * scale)
            let newH = Int(origH * scale)

            // Resize using CGContext
            let ctx = CGContext(
                data: nil, width: newW, height: newH,
                bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )!
            ctx.interpolationQuality = .high
            ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: newW, height: newH))

            guard let resized = ctx.makeImage() else { throw Error.encodeFailed }

            let data = NSMutableData()
            guard let dest = CGImageDestinationCreateWithData(data, "public.avif" as CFString, 1, nil)
            else { throw Error.encodeFailed }

            let options: [CFString: Any] = [
                kCGImageDestinationLossyCompressionQuality: CGFloat(quality) / 100.0,
                ]

            CGImageDestinationAddImage(dest, resized, options as CFDictionary)
            guard CGImageDestinationFinalize(dest) else { throw Error.encodeFailed }
            return data as Data
        }.value
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
