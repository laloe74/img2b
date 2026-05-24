import AppKit

struct Updater: Sendable {
    let owner = "laloe74"
    let repo = "img2b"
    var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    func checkForUpdates(manual: Bool = false) async {
        let url = URL(string: "https://api.github.com/repos/\(owner)/\(repo)/releases/latest")!
        var request = URLRequest(url: url, timeoutInterval: 10)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")

        guard let (data, _) = try? await URLSession.shared.data(for: request),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tag = json["tag_name"] as? String,
              let htmlURL = json["html_url"] as? String
        else {
            if manual { showAlert(message: "Unable to check for updates.", url: nil) }
            return
        }

        let latest = tag.replacingOccurrences(of: "v", with: "")
        if latest == currentVersion {
            if manual { showAlert(message: "img2b \(currentVersion) is the latest version.", url: nil) }
            return
        }

        // Compare versions
        if compareVersions(latest, currentVersion) > 0 {
            await MainActor.run {
                let alert = NSAlert()
                alert.messageText = "Update Available"
                alert.informativeText = "img2b \(tag) is available. You have \(currentVersion)."
                alert.addButton(withTitle: "Download")
                alert.addButton(withTitle: "Later")
                if alert.runModal() == .alertFirstButtonReturn {
                    NSWorkspace.shared.open(URL(string: htmlURL)!)
                }
            }
        } else if manual {
            showAlert(message: "img2b \(currentVersion) is the latest version.", url: nil)
        }
    }

    private func compareVersions(_ a: String, _ b: String) -> Int {
        let aParts = a.split(separator: ".").compactMap { Int($0) }
        let bParts = b.split(separator: ".").compactMap { Int($0) }
        for i in 0..<max(aParts.count, bParts.count) {
            let av = i < aParts.count ? aParts[i] : 0
            let bv = i < bParts.count ? bParts[i] : 0
            if av != bv { return av - bv }
        }
        return 0
    }

    private func showAlert(message: String, url: String?) {
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = "Updates"
            alert.informativeText = message
            alert.addButton(withTitle: "OK")
            alert.runModal()
        }
    }
}
