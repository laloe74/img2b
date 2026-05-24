import Foundation

struct CategoryItem: Codable, Equatable, Hashable, Identifiable {
    var name: String
    var icon: String

    var id: String { name }

    static let defaultIcon = "tag"
    static let defaults: [CategoryItem] = [
        CategoryItem(name: "none", icon: "circle"),
        CategoryItem(name: "design", icon: "paintpalette"),
        CategoryItem(name: "photography", icon: "camera"),
        CategoryItem(name: "physics", icon: "atom"),
        CategoryItem(name: "typography", icon: "textformat"),
    ]
}

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
        width = {width}
        height = {height}
        """
    var categories: [CategoryItem] = CategoryItem.defaults
    var defaultCategory: String = "none"

    var categoryNames: [String] { categories.map(\.name) }

    func icon(for category: String) -> String {
        categories.first { $0.name == category }?.icon ?? CategoryItem.defaultIcon
    }

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
            var config = try decoder.decode(R2Config.self, from: data)
            var needsSave = false
            // Ensure "none" category exists
            if !config.categoryNames.contains("none") {
                config.categories.insert(CategoryItem(name: "none", icon: "circle"), at: 0)
                config.defaultCategory = "none"
                needsSave = true
            }
            if config.defaultCategory.isEmpty || !config.categoryNames.contains(config.defaultCategory) {
                config.defaultCategory = config.categories.first?.name ?? "none"
                needsSave = true
            }
            if needsSave { config.save() }
            return config
        } catch {
            // Try to salvage
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

                // Migrate from old string array
                if let cats = dict["categories"] as? [String] {
                    config.categories = cats.map { CategoryItem(name: $0, icon: CategoryItem.defaultIcon) }
                } else if let cats = dict["categories"] as? [[String: String]] {
                    config.categories = cats.compactMap { dict in
                        guard let name = dict["name"] else { return nil }
                        return CategoryItem(name: name, icon: dict["icon"] ?? CategoryItem.defaultIcon)
                    }
                }
                if config.categories.isEmpty {
                    config.categories = CategoryItem.defaults
                }
                if !config.categoryNames.contains("none") {
                    config.categories.insert(CategoryItem(name: "none", icon: "circle"), at: 0)
                }
                config.defaultCategory = dict["defaultCategory"] as? String ?? dict["category"] as? String ?? "none"
                if config.defaultCategory.isEmpty || !config.categoryNames.contains(config.defaultCategory) {
                    config.defaultCategory = config.categories.first?.name ?? "none"
                }
                config.save()
                return config
            }
            return R2Config()
        }
    }
}
