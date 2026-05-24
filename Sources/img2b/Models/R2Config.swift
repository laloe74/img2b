import Foundation

struct R2Config: Codable, Equatable {
    var endpoint: String = ""
    var accessKeyId: String = ""
    var secretAccessKey: String = ""
    var bucketName: String = ""
    var publicURLBase: String = ""
    var quality: Int = 90
    var useLossless: Bool = false
    var maxFileSizeKB: Int = 500
    var namePattern: String = "img-{hash16}-{date}"
    var tomlFilePath: String = ""
    var tomlTemplate: String = """
        [[items]]
        category = "{category}"
        date = {date}
        title = "{title}"
        url = "{url}"
        """
    var categories: [String] = ["design", "photography", "physics", "typography"]
    var defaultCategory: String = "design"

    var isValid: Bool {
        !endpoint.isEmpty && !accessKeyId.isEmpty
            && !secretAccessKey.isEmpty && !bucketName.isEmpty
            && !publicURLBase.isEmpty
    }

    var resolvedEndpoint: String {
        if endpoint.contains(".") { return endpoint }
        return "\(endpoint).r2.cloudflarestorage.com"
    }

    var publicURLBaseNormalized: String {
        publicURLBase.hasSuffix("/") ? String(publicURLBase.dropLast()) : publicURLBase
    }

    static var itemsURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("img2b")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("items.json")
    }

    private static var configURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("img2b")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("config.json")
    }

    func save() {
        let encoder = JSONEncoder(); encoder.outputFormatting = .prettyPrinted
        guard let data = try? encoder.encode(self) else { return }
        try? data.write(to: Self.configURL, options: .atomic)
    }

    static func load() -> R2Config {
        // Migrate from old Image2Blog directory
        let oldURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Image2Blog/config.json")
        if FileManager.default.fileExists(atPath: oldURL.path),
           !FileManager.default.fileExists(atPath: configURL.path) {
            try? FileManager.default.copyItem(at: oldURL, to: configURL)
        }

        guard let data = try? Data(contentsOf: configURL) else { return R2Config() }

        let decoder = JSONDecoder()
        do {
            return try decoder.decode(R2Config.self, from: data)
        } catch {
            // Try to salvage: decode what we can, keep defaults for new fields
            if let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                var config = R2Config()
                config.endpoint = dict["endpoint"] as? String ?? dict["accountId"] as? String ?? ""
                config.accessKeyId = dict["accessKeyId"] as? String ?? ""
                config.secretAccessKey = dict["secretAccessKey"] as? String ?? ""
                config.bucketName = dict["bucketName"] as? String ?? ""
                config.publicURLBase = dict["publicURLBase"] as? String ?? ""
                config.quality = dict["quality"] as? Int ?? 90
                config.useLossless = dict["useLossless"] as? Bool ?? false
                config.maxFileSizeKB = dict["maxFileSizeKB"] as? Int ?? 500
                config.namePattern = dict["namePattern"] as? String ?? "img-{hash16}-{date}"
                config.tomlFilePath = dict["tomlFilePath"] as? String ?? ""
                config.tomlTemplate = dict["tomlTemplate"] as? String ?? config.tomlTemplate
                config.categories = dict["categories"] as? [String] ?? ["design", "photography", "physics", "typography"]
                config.defaultCategory = dict["defaultCategory"] as? String ?? dict["category"] as? String ?? "design"
                // Migrate old single category
                if config.categories.count <= 1 {
                    config.categories = ["design", "photography", "physics", "typography"]
                    config.defaultCategory = "design"
                }
                config.save()
                return config
            }
            return R2Config()
        }
    }
}
