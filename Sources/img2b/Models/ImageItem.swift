import Foundation

struct ImageItem: Identifiable, Hashable, Codable {
    var id: UUID
    var hash16: String = ""
    var title: String = ""
    var dateString: String = ""
    var fileSize: Int64 = 0
    var webpSize: Int64 = 0
    var width: Int = 0
    var height: Int = 0
    var originalWidth: Int = 0
    var originalHeight: Int = 0
    var originalColorSpace: String = ""
    var uploadedAt: Date?
    var outputFormat: String = ""  // actual output file extension, e.g. "avif"
    var r2Key: String = ""        // actual R2 object key
    var category: String = ""
    var status: Status = .processing
    var originalFilename: String = ""
    var warning: String = ""

    // Not persisted
    var originalURL: URL?
    var webpURL: URL?

    init(id: UUID = UUID(), originalURL: URL? = nil) {
        self.id = id
        self.originalURL = originalURL
        self.originalFilename = originalURL?.lastPathComponent ?? ""
    }

    enum CodingKeys: String, CodingKey {
        case id, hash16, title, dateString, fileSize, webpSize, width, height, originalWidth, originalHeight, originalColorSpace, uploadedAt, outputFormat, r2Key, category, status, originalFilename, warning
    }

    enum Status: Hashable, Codable {
        case processing
        case ready
        case uploading
        case uploaded(url: String)
        case error(String)

        enum CodingKeys: String, CodingKey { case type, value }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            switch try c.decode(String.self, forKey: .type) {
            case "processing": self = .processing
            case "ready": self = .ready
            case "uploading": self = .uploading
            case "uploaded": self = .uploaded(url: try c.decode(String.self, forKey: .value))
            case "error": self = .error(try c.decode(String.self, forKey: .value))
            default: self = .error("unknown status")
            }
        }

        func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            switch self {
            case .processing: try c.encode("processing", forKey: .type)
            case .ready: try c.encode("ready", forKey: .type)
            case .uploading: try c.encode("uploading", forKey: .type)
            case .uploaded(let url): try c.encode("uploaded", forKey: .type); try c.encode(url, forKey: .value)
            case .error(let msg): try c.encode("error", forKey: .type); try c.encode(msg, forKey: .value)
            }
        }
    }

    var displayName: String {
        // R2-imported: show actual R2 filename
        if uploadedAt != nil, !r2Key.isEmpty { return r2Key }
        // After local compression: show generated title with actual format
        if !title.isEmpty { return "\(title).\(outputFormat)" }
        // Before compression: show original filename
        if !originalFilename.isEmpty { return originalFilename }
        return "Untitled"
    }

    var formattedOriginalSize: String {
        ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file)
    }

    var formattedWebPSize: String {
        ByteCountFormatter.string(fromByteCount: webpSize, countStyle: .file)
    }

    var compressionRatio: Double {
        guard fileSize > 0, webpSize > 0 else { return 0 }
        return Double(webpSize) / Double(fileSize)
    }

    var formattedOriginalDimensions: String {
        guard originalWidth > 0 else { return "—" }
        return "\(originalWidth)\u{2009}\u{00d7}\u{2009}\(originalHeight)"
    }

    var formattedDimensions: String {
        guard width > 0 else { return "—" }
        return "\(width)\u{2009}\u{00d7}\u{2009}\(height)"
    }

    var displayColorSpace: String {
        originalColorSpace.isEmpty ? "—" : originalColorSpace
    }

    var metadataJSON: String {
        var parts: [String] = []
        if originalWidth > 0 { parts.append("ow=\(originalWidth)") }
        if originalHeight > 0 { parts.append("oh=\(originalHeight)") }
        if !originalColorSpace.isEmpty { parts.append("cs=\(originalColorSpace.cleanForMetadata)") }
        if !category.isEmpty, category != "none" { parts.append("cat=\(category.cleanForMetadata)") }
        let cleanOFN = originalFilename.cleanForMetadata
        if cleanOFN.contains("."), !cleanOFN.contains(";"), cleanOFN.count < 256 {
            parts.append("ofn=\(cleanOFN)")
        }
        if fileSize > 0 { parts.append("fs=\(fileSize)") }
        if let uploadedAt { parts.append("ua=\(Int(uploadedAt.timeIntervalSince1970))") }
        if width > 0 { parts.append("w=\(width)") }
        if height > 0 { parts.append("h=\(height)") }
        return parts.isEmpty ? "-" : parts.joined(separator: "&")
    }

    mutating func applyMetadataJSON(_ json: String) {
        guard json != "-" else { return }
        let pairs = json.components(separatedBy: "&")
        for pair in pairs {
            let kv = pair.components(separatedBy: "=")
            guard kv.count == 2 else { continue }
            let v = kv[1].cleanForMetadata
            switch kv[0] {
            case "ow": if let w = Int(v) { originalWidth = w }
            case "oh": if let h = Int(v) { originalHeight = h }
            case "cs": originalColorSpace = v.uncleanFromMetadata
            case "cat": category = v.uncleanFromMetadata
            case "ofn": originalFilename = v.uncleanFromMetadata
            case "fs": if let s = Int64(v) { fileSize = s }
            case "ua": if let t = Int(v) { uploadedAt = Date(timeIntervalSince1970: TimeInterval(t)) }
            case "w": if let wi = Int(v) { width = wi }
            case "h": if let hi = Int(v) { height = hi }
            default: break
            }
        }
    }
}

extension String {
    var cleanForMetadata: String {
        let cleaned = replacingOccurrences(of: "\n", with: "")
            .replacingOccurrences(of: "\r", with: "")
            .trimmingCharacters(in: .whitespaces)
        // Percent-encode non-ASCII chars so HTTP header stays ASCII-only (required for AWS4 signing)
        var allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_.~")
        allowed.insert(charactersIn: " ")
        return cleaned.addingPercentEncoding(withAllowedCharacters: allowed) ?? cleaned
    }

    /// Reverse of cleanForMetadata: decode percent-encoded non-ASCII characters
    var uncleanFromMetadata: String {
        removingPercentEncoding ?? self
    }
}
