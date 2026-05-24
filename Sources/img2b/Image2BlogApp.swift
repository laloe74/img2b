import SwiftUI

extension Notification.Name {
    static let openSettings = Notification.Name("openSettings")
}

@main
struct Image2BlogApp: App {
    @State private var imageItems: [ImageItem] = loadItems()
    @State private var r2Config = R2Config.load()
    private let updater = Updater()
    private let saveTimer = Timer.publish(every: 5, on: .main, in: .common).autoconnect()

    var body: some Scene {
        WindowGroup {
            ContentView(imageItems: $imageItems, r2Config: $r2Config)
                .onChange(of: r2Config) { _, new in new.save() }
                .onReceive(saveTimer) { _ in saveItems(imageItems) }
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
                    saveItems(imageItems)
                }
        }
        .commands {
            CommandGroup(after: .appInfo) {
                Button("Check for Updates...") {
                    Task { await updater.checkForUpdates(manual: true) }
                }
            }
            CommandGroup(replacing: .appSettings) {
                Button("Settings...") {
                    NotificationCenter.default.post(name: .openSettings, object: nil)
                }
                .keyboardShortcut(",", modifiers: .command)
            }
        }
        .windowToolbarStyle(.unified)
        .defaultSize(width: 960, height: 680)
    }
}

private func loadItems() -> [ImageItem] {
    guard let data = try? Data(contentsOf: R2Config.itemsURL),
          let items = try? JSONDecoder().decode([ImageItem].self, from: data)
    else { return [] }
    // Reset processing/uploading statuses from previous session
    return items.map { item in
        var i = item
        if case .processing = i.status { i.status = .error("Interrupted") }
        if case .uploading = i.status { i.status = .ready }
        return i
    }
}

private func saveItems(_ items: [ImageItem]) {
    guard let data = try? JSONEncoder().encode(items) else { return }
    try? data.write(to: R2Config.itemsURL, options: .atomic)
}
