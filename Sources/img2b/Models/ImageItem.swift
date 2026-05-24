import Foundation

struct ImageItem: Identifiable, Hashable, Codable {
    let id: UUID
    var hash16: String = ""
    var title: String = ""
    var dateString: String = ""
    var fileSize: Int64 = 0
    var webpSize: Int64 = 0
    var category: String = ""
    var status: Status = .processing
    var originalFilename: String = ""

    // Not persisted
    var originalURL: URL?
    var webpURL: URL?

    init(id: UUID = UUID(), originalURL: URL? = nil) {
        self.id = id
        self.originalURL = originalURL
        self.originalFilename = originalURL?.lastPathComponent ?? ""
    }

    enum CodingKeys: String, CodingKey {
        case id, hash16, title, dateString, fileSize, webpSize, category, status, originalFilename
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
        originalFilename.isEmpty ? (title + ".avif") : originalFilename
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
}
