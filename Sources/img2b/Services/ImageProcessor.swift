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

        // Step 1
        let q = min(100, max(1, quality))
        onStep?("Converting (Q\(q))...")
        var encoded = try await encode(data: data, quality: q, lossless: lossless)

        // Step 2: retry with higher compression
        if !lossless, encoded.count > maxSizeKB * 1024 {
            onStep?("Recompressing...")
            let q2 = max(50, q - 20)
            encoded = try await encode(data: data, quality: q2, lossless: false)
        }

        // Step 3: resize
        if !lossless, encoded.count > maxSizeKB * 1024 {
            onStep?("Resizing...")
            encoded = try await encodeResized(data: data, maxDimension: 1920, quality: q)
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

    private func encode(data: Data, quality: Int, lossless: Bool) async throws -> Data {
        try await Task.detached {
            guard let source = CGImageSourceCreateWithData(data as CFData, nil),
                  let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil)
            else { throw Error.loadFailed }

            let output = NSMutableData()
            guard let dest = CGImageDestinationCreateWithData(output, "public.avif" as CFString, 1, nil)
            else { throw Error.encodeFailed }

            let q = CGFloat(quality) / 100.0
            CGImageDestinationAddImage(dest, cgImage, [kCGImageDestinationLossyCompressionQuality: q] as CFDictionary)

            guard CGImageDestinationFinalize(dest) else { throw Error.encodeFailed }
            return output as Data
        }.value
    }

    private func encodeResized(data: Data, maxDimension: Int, quality: Int) async throws -> Data {
        try await Task.detached {
            guard let source = CGImageSourceCreateWithData(data as CFData, nil),
                  let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil)
            else { throw Error.loadFailed }

            let w = CGFloat(cgImage.width)
            let h = CGFloat(cgImage.height)
            let scale = min(CGFloat(maxDimension) / max(w, h), 1.0)
            let nw = Int(w * scale)
            let nh = Int(h * scale)

            guard let ctx = CGContext(
                data: nil, width: nw, height: nh,
                bitsPerComponent: 8, bytesPerRow: 0,
                space: cgImage.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: cgImage.bitmapInfo.rawValue
            ) else { throw Error.encodeFailed }

            ctx.interpolationQuality = .high
            ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: nw, height: nh))

            guard let resized = ctx.makeImage() else { throw Error.encodeFailed }

            let output = NSMutableData()
            guard let dest = CGImageDestinationCreateWithData(output, "public.avif" as CFString, 1, nil)
            else { throw Error.encodeFailed }

            let q = CGFloat(quality) / 100.0
            CGImageDestinationAddImage(dest, resized, [kCGImageDestinationLossyCompressionQuality: q] as CFDictionary)

            guard CGImageDestinationFinalize(dest) else { throw Error.encodeFailed }
            return output as Data
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
