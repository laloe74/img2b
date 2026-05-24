import AppKit

struct ClipboardService: Sendable {

    // MARK: - Clipboard

    func copyToClipboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    // MARK: - TOML Generation (template-first, hardcoded fallback)

    func generateTOML(for items: [ImageItem], config: R2Config) -> String {
        items.compactMap { toml(for: $0, config: config) }.joined(separator: "\n")
    }

    func generateTOML(for item: ImageItem, config: R2Config) -> String {
        toml(for: item, config: config) ?? ""
    }

    private func toml(for item: ImageItem, config: R2Config) -> String? {
        guard case .uploaded(let url) = item.status else { return nil }

        if !config.tomlTemplate.isEmpty {
            let category = item.category.isEmpty ? config.defaultCategory : item.category
            let dateFormatted = formatDate(item.dateString)

            return config.tomlTemplate
                .replacingOccurrences(of: "{category}", with: category)
                .replacingOccurrences(of: "{date}", with: dateFormatted)
                .replacingOccurrences(of: "{date8}", with: item.dateString)
                .replacingOccurrences(of: "{title}", with: item.title)
                .replacingOccurrences(of: "{url}", with: url)
                .replacingOccurrences(of: "{width}", with: String(item.width))
                .replacingOccurrences(of: "{height}", with: String(item.height))
        }

        // Hardcoded fallback
        let category = item.category.isEmpty ? "photography" : item.category
        let dateFormatted = formatDate(item.dateString)

        return """
            [[items]]
            category = "\(category)"
            date = \(dateFormatted)
            title = "\(item.title)"
            url = "\(url)"
            width = \(item.width)
            height = \(item.height)

            """
    }

    // MARK: - File writing

    func appendToFile(item: ImageItem, config: R2Config) {
        guard !config.tomlFilePath.isEmpty else { return }
        guard let entry = toml(for: item, config: config) else { return }

        let path = (config.tomlFilePath as NSString).expandingTildeInPath
        let url = URL(fileURLWithPath: path)

        do {
            let existing = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
            let newContent = entry + "\n" + existing
            try newContent.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            print("TOML append failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Helpers

    private func formatDate(_ ds: String) -> String {
        guard ds.count == 8 else { return ds }
        return "\(ds.prefix(4))-\(ds.dropFirst(4).prefix(2))-\(ds.suffix(2))"
    }
}
