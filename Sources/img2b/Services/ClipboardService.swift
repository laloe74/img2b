import AppKit

struct ClipboardService: Sendable {

    // MARK: - Clipboard

    func copyToClipboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    // MARK: - TOML Generation

    func generateTOML(for items: [ImageItem]) -> String {
        items.compactMap { formatItem($0) }.joined(separator: "\n")
    }

    func generateTOML(for item: ImageItem) -> String {
        formatItem(item) ?? ""
    }

    private func formatItem(_ item: ImageItem) -> String? {
        guard case .uploaded(let url) = item.status else { return nil }

        let category = item.category.isEmpty ? "photography" : item.category
        let dateFormatted = formatDate(item.dateString)

        return """
            [[items]]
            category = "\(category)"
            date = \(dateFormatted)
            title = "\(item.title)"
            url = "\(url)"

            """
    }

    // MARK: - Template-based TOML

    func formatWithTemplate(item: ImageItem, config: R2Config) -> String? {
        guard case .uploaded(let url) = item.status else { return nil }

        let category = item.category.isEmpty ? config.defaultCategory : item.category
        let dateFormatted = formatDate(item.dateString)

        return config.tomlTemplate.isEmpty ? nil : config.tomlTemplate
            .replacingOccurrences(of: "{category}", with: category)
            .replacingOccurrences(of: "{date}", with: dateFormatted)
            .replacingOccurrences(of: "{date8}", with: item.dateString)
            .replacingOccurrences(of: "{title}", with: item.title)
            .replacingOccurrences(of: "{url}", with: url)
    }

    // MARK: - File writing

    func appendToFile(item: ImageItem, config: R2Config) {
        guard !config.tomlFilePath.isEmpty else { return }

        let entry = config.tomlTemplate.isEmpty
            ? (formatItem(item) ?? "")
            : (formatWithTemplate(item: item, config: config) ?? "")

        guard !entry.isEmpty else { return }

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
