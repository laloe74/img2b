import CryptoKit
import Foundation

struct ImageProcessor: Sendable {
    enum Error: Swift.Error, LocalizedError {
        case vipsNotFound
        case conversionFailed(String)
        case fileReadError

        var errorDescription: String? {
            switch self {
            case .vipsNotFound: "vips not found. Install with: brew install vips"
            case .conversionFailed(let msg): "WebP conversion failed: \(msg)"
            case .fileReadError: "Could not read image file"
            }
        }
    }

    private let vipsPath: String

    init() {
        let paths = ["/opt/homebrew/bin/vips", "/usr/local/bin/vips", "/opt/local/bin/vips"]
        vipsPath = paths.first(where: { FileManager.default.fileExists(atPath: $0) }) ?? "vips"
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
        let webpURL = tempDir.appendingPathComponent("\(item.title).webp")

        // Pre-resize large images to avoid slow compression on huge sources
        var sourceURL = url
        if data.count > 5 * 1024 * 1024, !lossless {
            onStep?("Pre-resizing...")
            let presized = tempDir.appendingPathComponent("\(item.title)_pre.\(url.pathExtension)")
            try await runVipsThumbnail(input: url, output: presized, maxDimension: 4000)
            sourceURL = presized
        }

        let maxBytes = maxSizeKB * 1024

        // Step 1
        onStep?("Converting (Q\(quality))...")
        try await runVips(input: sourceURL, output: webpURL, quality: quality, lossless: lossless, effort: 4)
        var webpData = (try? Data(contentsOf: webpURL)) ?? Data()
        onStep?("Converted: \(ByteCountFormatter.string(fromByteCount: Int64(webpData.count), countStyle: .file))")

        // Step 2: retry with max effort
        if !lossless, webpData.count > maxBytes {
            onStep?("Recompressing (e6, \(Int(webpData.count/1024))KB > \(maxSizeKB)KB)...")
            try await runVips(input: sourceURL, output: webpURL, quality: quality, lossless: false, effort: 6)
            webpData = (try? Data(contentsOf: webpURL)) ?? Data()
            onStep?("Recompressed: \(ByteCountFormatter.string(fromByteCount: Int64(webpData.count), countStyle: .file))")
        }

        // Step 3: thumbnail resize
        if !lossless, webpData.count > maxBytes {
            onStep?("Resizing to 1920px...")
            let resized = tempDir.appendingPathComponent("\(item.title)_rs.\(url.pathExtension)")
            try await runVipsThumbnail(input: url, output: resized, maxDimension: 1920)
            try await runVips(input: resized, output: webpURL, quality: quality, lossless: false, effort: 4)
            try? FileManager.default.removeItem(at: resized)
            webpData = (try? Data(contentsOf: webpURL)) ?? Data()
            onStep?("Resized: \(ByteCountFormatter.string(fromByteCount: Int64(webpData.count), countStyle: .file))")
        }

        // Clean up temp pre-sized file
        if sourceURL != url { try? FileManager.default.removeItem(at: sourceURL) }

        onStep?(nil)

        var finalItem = item
        finalItem.webpURL = webpURL
        finalItem.webpSize = Int64(webpData.count)
        finalItem.status = .ready
        return finalItem
    }

    private func runVips(input: URL, output: URL, quality: Int, lossless: Bool, effort: Int) async throws {
        let q = min(100, max(1, quality))
        let e = min(6, max(0, effort))
        var args: [String] = ["webpsave", input.path, output.path, "--Q", "\(q)", "--effort", "\(e)"]
        if lossless { args.append("--lossless") } else { args.append("--smart-subsample") }
        try await runProcess(args: args)
    }

    private func runVipsThumbnail(input: URL, output: URL, maxDimension: Int) async throws {
        let dim = "\(maxDimension)"
        try await runProcess(args: ["thumbnail", input.path, output.path, dim, "--height", dim, "--size", "down"])
    }

    private func formatName(pattern: String, hash16: String, hash: String, date: String) -> String {
        pattern
            .replacingOccurrences(of: "{hash16}", with: hash16)
            .replacingOccurrences(of: "{hash8}", with: String(hash.prefix(8)))
            .replacingOccurrences(of: "{hash}", with: hash)
            .replacingOccurrences(of: "{date}", with: date)
    }

    private func runProcess(args: [String]) async throws {
        try await Task.detached {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: vipsPath)
            process.arguments = args
            process.standardOutput = FileHandle.nullDevice

            let errorPipe = Pipe()
            process.standardError = errorPipe

            do {
                try process.run()
                process.waitUntilExit()

                if process.terminationStatus != 0 {
                    let msg = String(data: errorPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                    throw Error.conversionFailed(msg.trimmingCharacters(in: .whitespacesAndNewlines))
                }
            } catch let e as Error {
                throw e
            } catch {
                throw Error.vipsNotFound
            }
        }.value
    }
}
