import ImageIO
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @Binding var imageItems: [ImageItem]
    @Binding var r2Config: R2Config

    @State private var processor = ImageProcessor()
    @State private var uploader = R2Uploader()
    @State private var clipboard = ClipboardService()
    @State private var updater = Updater()
    @State private var showSettings = false
    @State private var isProcessing = false
    @State private var isUploading = false
    @State private var processingProgress: (current: Int, total: Int) = (0, 0)
    @State private var currentStep = ""
    @State private var showDeleteConfirm = false
    @State private var itemsToDelete: [ImageItem] = []
    @State private var selectedItemIDs: Set<UUID> = []
    @State private var previewItemID: UUID?
    @State private var showCategoryModal = false
    @State private var previewCache: [URL: (image: NSImage, width: Int, height: Int)] = [:]
    @State private var isSyncing = false
    @State private var showError = false
    @State private var errorDetail = ""

    private var selectedItem: ImageItem? {
        let id = previewItemID ?? selectedItemIDs.first
        guard let id else { return nil }
        return imageItems.first { $0.id == id }
    }

    var body: some View {
        NavigationSplitView {
            List(selection: $selectedItemIDs) {
                Section {
                    if imageItems.isEmpty {
                        Text("No images yet")
                            .font(.callout)
                            .foregroundStyle(.tertiary)
                    } else {
                        sidebarRows
                    }
                } header: {
                    sidebarHeader
                }
            }
            .listStyle(.sidebar)
            .onSidebarEmptyClick(selectedItemIDs: $selectedItemIDs)
            .navigationTitle("")
            .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 340)
        } detail: {
            detailContent
                .navigationTitle("")
        }
        .toolbar { appToolbar }
        .sheet(isPresented: $showSettings) {
            SettingsView(config: $r2Config, imageItems: $imageItems)
        }
        .sheet(isPresented: $showError) {
            VStack(spacing: 0) {
                HStack {
                    Text("Error").font(.headline)
                    Spacer()
                    Button("Copy") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(errorDetail, forType: .string)
                    }
                    .buttonStyle(.bordered).controlSize(.small)
                    Button("Close") { showError = false }
                        .buttonStyle(.borderedProminent).controlSize(.small)
                        .keyboardShortcut(.return)
                }
                .padding()
                Divider()
                ScrollView([.vertical, .horizontal]) {
                    Text(verbatim: errorDetail.isEmpty ? "(empty)" : errorDetail)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                        .textSelection(.enabled)
                }
            }
            .frame(width: 640, height: 360)
        }
        .confirmationDialog("Delete from R2?", isPresented: $showDeleteConfirm) {
            Button(deleteDialogTitle, role: .destructive) {
                for item in itemsToDelete { deleteFromR2(item) }
            }
            Button("Remove from List Only") {
                for item in itemsToDelete { removeFromList(item) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(deleteDialogMessage)
        }
        .categoryModal(
            isPresented: $showCategoryModal,
            categories: $r2Config.categories,
            defaultCategory: $r2Config.defaultCategory,
            onSave: { r2Config.save() }
        )
        .onChange(of: selectedItemIDs) { _, newValue in
            if newValue.count <= 1 { previewItemID = nil }
        }
        .onExitCommand { selectedItemIDs = []; previewItemID = nil }
        .background(WindowSeparatorRemover())
        .onAppear {
            Task { await updater.checkForUpdates() }
            // One-time migration: populate upload dates
            if !UserDefaults.standard.bool(forKey: "migratedUploadDates") {
                UserDefaults.standard.set(true, forKey: "migratedUploadDates")
                let now = Date()
                for i in imageItems.indices {
                    if case .uploaded = imageItems[i].status, imageItems[i].uploadedAt == nil {
                        imageItems[i].uploadedAt = now
                    }
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .openSettings)) { _ in
            showSettings = true
        }
    }

    private var detailContent: some View {
        VStack {
            if let item = selectedItem {
                previewView(for: item)
            } else {
                DropZoneView(
                    imageItems: $imageItems,
                    processor: processor,
                    isProcessing: $isProcessing,
                    processingProgress: $processingProgress,
                    currentStep: $currentStep,
                    r2Config: r2Config,
                    onNewItems: { ids, firstID in
                        selectedItemIDs = ids
                        previewItemID = firstID
                        NSApp.activate()
                    }
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            handleDetailDrop(providers: providers)
            return true
        }
    }

    private var sortedItems: [ImageItem] {
        imageItems.sorted { a, b in
            let da = a.uploadedAt ?? .distantFuture
            let db = b.uploadedAt ?? .distantFuture
            return da > db
        }
    }

    private var sidebarRows: some View {
        ForEach(sortedItems) { item in
            SidebarRow(
                item: item,
                isSelected: selectedItemIDs.contains(item.id),
                config: r2Config,
                uploader: uploader,
                clipboard: clipboard,
                onUpdate: { updateItem($0) },
                onDelete: { handleDelete(item) },
                onUploadComplete: { handleUploadResult($0) },
                onRename: { renameItem(item, to: $0) }
            )
            .tag(item.id)
        }
        .onDelete { indexSet in
            for idx in indexSet { handleDelete(imageItems[idx]) }
        }
    }

    private var sidebarHeader: some View {
        Text("Image List")
    }

    private func syncFromR2() {
        isSyncing = true
        Task {
            defer { isSyncing = false }
            do {
                let objects = try await uploader.listObjects(config: r2Config)
                let r2Keys = Set(objects.map(\.key))

                // Update existing items and track matched keys
                var matchedR2Keys: Set<String> = []
                var localR2ItemIndices: [Int] = []
                for i in imageItems.indices {
                    let ext = imageItems[i].outputFormat.isEmpty ? "avif" : imageItems[i].outputFormat
                    let localKey = imageItems[i].title.isEmpty ? nil : "\(imageItems[i].title).\(ext)"
                    let rk = imageItems[i].r2Key
                    let matchKey: String? = if let rk = !rk.isEmpty ? rk : nil, r2Keys.contains(rk) { rk }
                        else if let k = localKey, r2Keys.contains(k) { k }
                        else { nil }
                    guard let key = matchKey else { continue }
                    matchedR2Keys.insert(key)
                    localR2ItemIndices.append(i)
                    if let obj = objects.first(where: { $0.key == key }) {
                        imageItems[i].webpSize = obj.size
                        imageItems[i].fileSize = obj.size
                        imageItems[i].r2Key = key
                        imageItems[i].outputFormat = (key as NSString).pathExtension
                        // Only sync date if not already set (preserve original upload date)
                        if imageItems[i].uploadedAt == nil {
                            let df = DateFormatter(); df.dateFormat = "yyyyMMdd"
                            imageItems[i].dateString = df.string(from: obj.lastModified)
                            imageItems[i].uploadedAt = obj.lastModified
                        }
                    }
                    let encodedPath = key.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? key
                    let url = "\(r2Config.publicURLBaseNormalized)/\(encodedPath)"
                    if case .uploaded = imageItems[i].status { continue }
                    imageItems[i].status = .uploaded(url: url)
                }
                // Items marked uploaded but NOT on R2 → downgrade to ready
                for i in imageItems.indices where !localR2ItemIndices.contains(i) {
                    if case .uploaded = imageItems[i].status {
                        imageItems[i].status = .ready
                    }
                }

                // All known local keys (for dedup)
                var localKeys: Set<String> = []
                for item in imageItems {
                    if !item.r2Key.isEmpty { localKeys.insert(item.r2Key) }
                    else if !item.title.isEmpty {
                        let ext = item.outputFormat.isEmpty ? "avif" : item.outputFormat
                        localKeys.insert("\(item.title).\(ext)")
                    }
                }
                let newObjects = objects.filter { !localKeys.contains($0.key) }

                // Concurrent HEAD: new objects + existing items (for metadata refresh)
                let allMetaKeys = newObjects.map(\.key) + Array(matchedR2Keys)
                let metaResults = await withTaskGroup(of: (String, String?).self) { group in
                    for key in Set(allMetaKeys) {
                        group.addTask {
                            let meta = try? await uploader.headObject(key: key, config: r2Config)
                            return (key, meta)
                        }
                    }
                    var results: [String: String?] = [:]
                    for await (key, meta) in group { results[key] = meta }
                    return results
                }

                // Apply metadata to existing items
                for i in imageItems.indices {
                    let rk = imageItems[i].r2Key
                    guard !rk.isEmpty, let metaJSON = metaResults[rk] ?? nil else { continue }
                    imageItems[i].applyMetadataJSON(metaJSON)
                }

                // Import new objects
                var newIDs = Set<UUID>()
                for obj in newObjects {
                    let title = (obj.key as NSString).deletingPathExtension
                    var item = ImageItem()
                    item.title = title
                    item.r2Key = obj.key
                    item.originalFilename = obj.key
                    item.outputFormat = (obj.key as NSString).pathExtension
                    item.webpSize = obj.size
                    item.fileSize = obj.size
                    item.uploadedAt = obj.lastModified
                    let df = DateFormatter(); df.dateFormat = "yyyyMMdd"
                    item.dateString = df.string(from: obj.lastModified)
                    let encodedPath = obj.key.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? obj.key
                    item.status = .uploaded(url: "\(r2Config.publicURLBaseNormalized)/\(encodedPath)")
                    if let metaJSON = metaResults[obj.key] ?? nil {
                        item.applyMetadataJSON(metaJSON)
                    }
                    newIDs.insert(item.id)
                    imageItems.insert(item, at: 0)
                }
                // Select all newly imported items
                if !newIDs.isEmpty {
                    selectedItemIDs = newIDs
                }
            } catch {
                print("Sync failed: \(error)")
            }
            isSyncing = false
        }
    }

    @ToolbarContentBuilder
    private var appToolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .navigation) {
            Button(action: uploadSelected) {
                Image(systemName: "icloud.and.arrow.up")
            }
            .disabled(selectedUploadable.isEmpty)
            .help("Upload")
            Button(action: deleteSelected) {
                Image(systemName: "trash")
            }
            .disabled(selectedItemIDs.isEmpty)
            .help("Delete")
            if !uploadedOnly.isEmpty {
                Button(action: copyURLs) {
                    Image(systemName: "link")
                }
                .help("Copy URL")
            }
        }


        ToolbarItemGroup {
            if r2Config.isValid {
                Button(action: syncFromR2) {
                    if isSyncing {
                        ProgressView().scaleEffect(0.6)
                    } else {
                        Image(systemName: "arrow.triangle.2.circlepath")
                    }
                }
                .disabled(isSyncing)
                .help("Sync with R2")
            }
            Button(action: { showSettings = true }) {
                Image(systemName: "gearshape")
            }
            .help("Settings")
        }
    }

    private var deleteDialogTitle: String { "Delete from R2 (\(itemsToDelete.count))" }
    private var deleteDialogMessage: String { "\(itemsToDelete.count) file(s) will be permanently deleted from R2 storage." }

    // MARK: - Preview

    @ViewBuilder
    private func previewView(for item: ImageItem) -> some View {
        let localURL = item.webpURL ?? ImageProcessor.cacheURL(for: item.title)
        let r2URL: URL? = {
            if case .uploaded(let url) = item.status { return URL(string: url) }
            return nil
        }()
        let previewURL = (localURL.isFileURL && FileManager.default.fileExists(atPath: localURL.path))
            ? localURL
            : (r2URL ?? localURL)
        VStack(spacing: 0) {
            if let cached = previewCache[previewURL], cached.image.isValid {
                Image(nsImage: cached.image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let imageURL = r2URL {
                AsyncImage(url: imageURL) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().aspectRatio(contentMode: .fit)
                    case .failure:
                        ContentUnavailableView("Load Failed", systemImage: "wifi.slash", description: Text(imageURL.absoluteString))
                    case .empty:
                        ProgressView()
                    @unknown default:
                        ProgressView()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(spacing: 12) {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text(isProcessing ? "Processing..." : "Waiting...")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    if !currentStep.isEmpty {
                        Text(currentStep)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            Divider()

            // Category selector
            let cats = r2Config.categories.filter { $0.name != "none" }
            if !cats.isEmpty {
                HStack(spacing: 4) {
                    ForEach(cats) { cat in
                        let selected = item.category == cat.name || (item.category.isEmpty && cat.name == r2Config.defaultCategory)
                        Image(systemName: cat.icon)
                            .font(.system(size: 12, weight: .medium))
                            .frame(width: 28, height: 28)
                            .background(Circle().fill(selected ? .blue : .clear))
                            .overlay { if !selected { Circle().stroke(.quaternary, lineWidth: 1) } }
                            .foregroundStyle(selected ? .white : .secondary)
                            .contentShape(Circle())
                            .onTapGesture { toggleCategory(cat.name) }
                            .help(cat.name)
                    }
                    Spacer()
                }
                .padding(.horizontal, 12).padding(.vertical, 6)
                Divider()
            }

            VStack(alignment: .leading, spacing: 6) {
                // Header
                HStack {
                    Text(item.displayName)
                        .font(.caption).fontWeight(.medium)
                        .lineLimit(1).truncationMode(.middle)
                    if item.webpSize > 0 && item.fileSize > 0 {
                        Text("\(Int((1 - item.compressionRatio) * 100))%")
                            .font(.caption2).fontWeight(.medium)
                            .foregroundStyle(.green)
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .background(.green.opacity(0.1), in: RoundedRectangle(cornerRadius: 3))
                    }
                    Spacer()
                }

                // Metadata rows
                let hasOriginal = item.originalWidth > 0 || item.fileSize > item.webpSize
                previewRow(label: "Original",
                           format: hasOriginal ? originalFormat : "—",
                           size: hasOriginal ? item.formattedOriginalSize : "—",
                           resolution: hasOriginal ? item.formattedOriginalDimensions : "—")
                if item.webpSize > 0 {
                    let nowFormat: String = {
                        if !item.r2Key.isEmpty {
                            return (item.r2Key as NSString).pathExtension.uppercased()
                        }
                        return item.outputFormat.uppercased()
                    }()
                    let nowDim: String = {
                        if item.width > 0 { return item.formattedDimensions }
                        if let c = previewCache[previewURL], c.width > 0 {
                            return "\(c.width)\u{2009}\u{00d7}\u{2009}\(c.height)"
                        }
                        return "—"
                    }()
                    previewRow(label: "Now", format: nowFormat, size: item.formattedWebPSize,
                               resolution: nowDim)
                } else {
                    previewRow(label: "Now", format: "—", size: "—", resolution: "—")
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
        }
        .task(id: previewURL) {
            // Don't reload if already cached
            guard previewCache[previewURL] == nil else { return }
            let url = previewURL
            let result: (Data, Int, Int)? = await Task.detached(priority: .userInitiated) {
                guard let data = try? Data(contentsOf: url), data.count > 0 else { return nil }
                guard let src = CGImageSourceCreateWithData(data as CFData, nil),
                      let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any],
                      let w = props[kCGImagePropertyPixelWidth] as? Int,
                      let h = props[kCGImagePropertyPixelHeight] as? Int
                else { return nil }
                return (data, w, h)
            }.value
            if let result, let img = NSImage(data: result.0), img.isValid {
                previewCache[url] = (img, result.1, result.2)
            }
        }
    }

    // MARK: - Helpers

    private func propertiesFor(url: URL?) -> [CFString: Any]? {
        guard let url,
              let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        else { return nil }
        return props
    }

    private func resolutionFor(url: URL?) -> String? {
        guard let props = propertiesFor(url: url),
              let w = props[kCGImagePropertyPixelWidth] as? Int,
              let h = props[kCGImagePropertyPixelHeight] as? Int
        else { return nil }
        return "\(w)\u{2009}\u{00d7}\u{2009}\(h)"
    }

    private func previewRow(label: String, format: String, size: String, resolution: String) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.caption2).fontWeight(.medium)
                .foregroundStyle(.secondary)
                .frame(width: 42, alignment: .leading)
            Text(format)
                .font(.caption2).foregroundStyle(.secondary)
                .frame(width: 34, alignment: .leading)
                .fontDesign(.monospaced)
            Text(size)
                .font(.caption2).foregroundStyle(.secondary)
                .frame(width: 50, alignment: .trailing)
                .fontDesign(.monospaced)
            Text(resolution)
                .font(.caption2).foregroundStyle(.secondary)
                .frame(width: 90, alignment: .trailing)
                .fontDesign(.monospaced)
        }
    }

    private var originalFormat: String {
        selectedItem?.originalURL?.pathExtension.uppercased()
            ?? selectedItem?.originalFilename.components(separatedBy: ".").last?.uppercased()
            ?? "—"
    }

    private func colorSpaceFor(url: URL?) -> String? {
        guard let props = propertiesFor(url: url) else { return nil }
        if let profile = props[kCGImagePropertyProfileName] as? String { return profile }
        return props[kCGImagePropertyColorModel] as? String
    }

    private var selectedUploadable: [ImageItem] {
        imageItems.filter { item in
            if case .ready = item.status { return selectedItemIDs.contains(item.id) }
            return false
        }
    }

    private var readyItems: [ImageItem] {
        imageItems.filter { if case .ready = $0.status { true } else { false } }
    }
    private var uploadedOnly: [ImageItem] {
        imageItems.filter { if case .uploaded = $0.status { true } else { false } }
    }


    private func toggleCategory(_ name: String) {
        guard let sel = selectedItem,
              let idx = imageItems.firstIndex(where: { $0.id == sel.id })
        else { return }
        let newCat = sel.category == name ? "none" : name
        imageItems[idx].category = newCat

        // Sync category to R2 metadata if uploaded
        if case .uploaded = imageItems[idx].status {
            let item = imageItems[idx]
            Task {
                do {
                    try await uploader.updateMetadata(item: item, config: r2Config)
                } catch {
                    errorDetail = "Metadata sync failed: \(error.localizedDescription)"
                    showError = true
                }
            }
        }
    }

    private func updateItem(_ updated: ImageItem) {
        if let idx = imageItems.firstIndex(where: { $0.id == updated.id }) {
            imageItems[idx] = updated
        }
    }

    private func isSelected(_ cat: String) -> Bool {
        guard let sel = selectedItem else { return false }
        return sel.category == cat
    }

    // MARK: - Actions

    private func handleDelete(_ item: ImageItem) {
        if case .uploaded = item.status {
            itemsToDelete = [item]; showDeleteConfirm = true
        } else {
            removeFromList(item)
        }
    }
    private func removeFromList(_ item: ImageItem) {
        guard let idx = imageItems.firstIndex(where: { $0.id == item.id }) else { return }
        let sorted = sortedItems
        let sortedIdx = sorted.firstIndex(where: { $0.id == item.id })
        selectedItemIDs.remove(item.id)
        previewItemID = nil
        imageItems.remove(at: idx)
        // Auto-select next in sorted order
        if let si = sortedIdx, !sorted.isEmpty {
            let next = si < sorted.count - 1 ? sorted[si + 1] : (si > 0 ? sorted[si - 1] : nil)
            if let next { selectedItemIDs = [next.id] }
        }
        let ext = item.outputFormat.isEmpty ? "avif" : item.outputFormat
        let cacheURL = ImageProcessor.cacheURL(for: item.title)
            .deletingPathExtension().appendingPathExtension(ext)
        try? FileManager.default.removeItem(at: cacheURL)
    }
    private func deleteSelected() {
        let selected = imageItems.filter { selectedItemIDs.contains($0.id) }
        let (uploaded, local) = selected.reduce(into: ([ImageItem](), [ImageItem]())) { acc, item in
            if case .uploaded = item.status { acc.0.append(item) } else { acc.1.append(item) }
        }
        for item in local { removeFromList(item) }
        if !uploaded.isEmpty {
            itemsToDelete = uploaded; showDeleteConfirm = true
        }
    }
    private func deleteFromR2(_ item: ImageItem) {
        if let idx = imageItems.firstIndex(where: { $0.id == item.id }) { imageItems[idx].status = .processing }
        Task {
            do {
                try await uploader.delete(item: item, config: r2Config)
                removeFromList(item)
            } catch {
                if let idx = imageItems.firstIndex(where: { $0.id == item.id }) {
                    imageItems[idx].status = .error("Delete failed")
                }
                errorDetail = error.localizedDescription
                showError = true
            }
        }
    }
    private func uploadSelected() {
        uploadItems(selectedUploadable)
    }

    private func uploadAll() {
        uploadItems(readyItems)
    }

    private func uploadItems(_ toUpload: [ImageItem]) {
        guard !toUpload.isEmpty else { return }
        isUploading = true
        Task {
            for item in toUpload {
                var updated = item; updated.status = .uploading
                if let idx = imageItems.firstIndex(where: { $0.id == item.id }) { imageItems[idx] = updated }
                do {
                    let result = try await uploader.upload(item: updated, config: r2Config)
                    if let idx = imageItems.firstIndex(where: { $0.id == result.id }) {
                        imageItems[idx] = result
                        handleUploadResult(result)
                    }
                } catch {
                    if let idx = imageItems.firstIndex(where: { $0.id == item.id }) {
                        imageItems[idx].status = .error("Upload failed")
                    }
                    errorDetail = error.localizedDescription
                    showError = true
                }
            }
            isUploading = false
        }
    }
    private func renameItem(_ item: ImageItem, to newBase: String) {
        guard let idx = imageItems.firstIndex(where: { $0.id == item.id }) else { return }
        var ext = (item.r2Key as NSString).pathExtension
        if ext.isEmpty { ext = item.outputFormat.isEmpty ? "avif" : item.outputFormat }
        let newKey = "\(newBase).\(ext)"

        // Update local state immediately
        imageItems[idx].title = newBase
        imageItems[idx].r2Key = newKey
        imageItems[idx].outputFormat = ext

        if case .uploaded = item.status {
            let oldCacheURL = ImageProcessor.cacheURL(for: item.title).deletingPathExtension().appendingPathExtension(ext)
            Task {
                do {
                    let localURL = item.webpURL ?? oldCacheURL
                    if FileManager.default.fileExists(atPath: localURL.path) {
                        _ = try await uploader.upload(item: imageItems[idx], config: r2Config)
                    } else if case .uploaded(let urlString) = item.status, let url = URL(string: urlString) {
                        let (data, _) = try await URLSession.shared.data(from: url)
                        let tmpURL = FileManager.default.temporaryDirectory.appendingPathComponent(newKey)
                        try data.write(to: tmpURL)
                        var tmpItem = imageItems[idx]
                        tmpItem.webpURL = tmpURL
                        _ = try await uploader.upload(item: tmpItem, config: r2Config)
                        try? FileManager.default.removeItem(at: tmpURL)
                    }
                    do { try await uploader.delete(item: item, config: r2Config) } catch {
                        print("Rename: failed to delete old key: \(error)")
                    }
                    let encodedPath = newKey.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? newKey
                    imageItems[idx].status = .uploaded(url: "\(r2Config.publicURLBaseNormalized)/\(encodedPath)")
                    let newCacheURL = ImageProcessor.cacheURL(for: newBase).deletingPathExtension().appendingPathExtension(ext)
                    if FileManager.default.fileExists(atPath: oldCacheURL.path) {
                        try? FileManager.default.moveItem(at: oldCacheURL, to: newCacheURL)
                    }
                    imageItems[idx].webpURL = newCacheURL
                } catch {
                    errorDetail = "\(error)"
                    showError = true
                }
            }
        }
    }

    private func handleUploadResult(_ item: ImageItem) {
        // Track the actual R2 key and upload date
        if let idx = imageItems.firstIndex(where: { $0.id == item.id }) {
            let ext = item.outputFormat.isEmpty ? "avif" : item.outputFormat
            imageItems[idx].r2Key = "\(item.title).\(ext)"
            if imageItems[idx].uploadedAt == nil { imageItems[idx].uploadedAt = Date() }
        }
        let cat = item.category.isEmpty ? r2Config.defaultCategory : item.category
        if cat == "none", case .uploaded(let url) = item.status {
            clipboard.copyToClipboard("![](" + url + ")")
        } else {
            clipboard.appendToFile(item: item, config: r2Config)
            if case .uploaded(let url) = item.status { clipboard.copyToClipboard(url) }
        }
    }

    private func copyURLs() {
        let urls = imageItems.filter { selectedItemIDs.contains($0.id) }.compactMap { item -> String? in
            guard case .uploaded(let url) = item.status else { return nil }
            return url
        }
        clipboard.copyToClipboard(urls.joined(separator: "\n"))
    }

    private func handleDetailDrop(providers: [NSItemProvider]) {
        let count = providers.count
        let results = UnsafeMutablePointer<URL?>.allocate(capacity: count)
        results.initialize(repeating: nil, count: count)
        let group = DispatchGroup()
        for (i, provider) in providers.enumerated() {
            group.enter()
            provider.loadItem(forTypeIdentifier: "public.file-url", options: nil) { item, _ in
                defer { group.leave() }
                if let data = item as? Data { results[i] = URL(dataRepresentation: data, relativeTo: nil) }
            }
        }
        group.notify(queue: .main) {
            let urls = (0..<count).compactMap { results[$0] }
            results.deallocate()
            let validURLs = urls.filter { url in
                guard let type = UTType(filenameExtension: url.pathExtension) else { return false }
                let supported: [UTType] = [.png, .jpeg, .tiff, .bmp, .gif, .webP, .heic, .heif, .icns, .rawImage, .image]
                return supported.contains(where: { type.conforms(to: $0) || $0.conforms(to: type) })
            }
            guard !validURLs.isEmpty else { return }
            isProcessing = true; processingProgress = (0, validURLs.count)
            Task {
                // Phase 1: insert all items, highlight them together
                var newIDs = Set<UUID>()
                var firstID: UUID?
                for url in validURLs {
                    let item = ImageItem(originalURL: url)
                    var newItem = item; newItem.category = r2Config.defaultCategory
                    imageItems.insert(newItem, at: 0)
                    newIDs.insert(newItem.id)
                    if firstID == nil { firstID = item.id }
                }
                selectedItemIDs = newIDs
                previewItemID = firstID
                NSApp.activate()

                // Phase 2: process each one
                for (index, url) in validURLs.enumerated() {
                    guard let idx = imageItems.firstIndex(where: { $0.originalURL == url }) else { continue }
                    let accessing = url.startAccessingSecurityScopedResource()
                    defer { if accessing { url.stopAccessingSecurityScopedResource() } }
                    do {
                        let processed = try await processor.processImage(
                            at: url,
                            level: r2Config.compressionLevel,
                            maxWidth: r2Config.maxWidth,
                            namePattern: r2Config.namePattern,
                            onStep: { step in DispatchQueue.main.async { currentStep = step ?? "" } }
                        )
                        var updated = processed
                        updated.id = imageItems[idx].id
                        updated.category = imageItems[idx].category
                        updated.originalFilename = imageItems[idx].originalFilename
                        imageItems[idx] = updated
                    } catch {
                        imageItems[idx].status = .error(error.localizedDescription)
                    }
                    processingProgress = (index + 1, validURLs.count)
                }
                isProcessing = false
            }
        }
    }
}

// MARK: - Window Separator

struct WindowSeparatorRemover: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            guard let window = view.window else { return }
            window.titlebarSeparatorStyle = .none
            window.titlebarAppearsTransparent = true
        }
        return view
    }
    func updateNSView(_ nsView: NSView, context: Context) {}
}

// MARK: - Sidebar Row

struct SidebarRow: View {
    let item: ImageItem
    let isSelected: Bool
    let config: R2Config
    let uploader: R2Uploader
    let clipboard: ClipboardService
    let onUpdate: (ImageItem) -> Void
    let onDelete: () -> Void
    let onUploadComplete: (ImageItem) -> Void
    let onRename: (String) -> Void

    @FocusState private var nameFieldFocused: Bool
    @State private var isEditingName = false
    @State private var editName: String = ""

    private func startRename() {
        editName = item.displayName
        isEditingName = true
        nameFieldFocused = true
    }

    private func commitRename() {
        isEditingName = false
        nameFieldFocused = false
        let newName = editName.trimmingCharacters(in: .whitespaces)
        guard !newName.isEmpty else { return }
        // Strip extension if user typed it, renameItem will add the correct one
        let baseName = (newName as NSString).deletingPathExtension
        guard baseName != (item.displayName as NSString).deletingPathExtension else { return }
        onRename(baseName)
    }

    init(item: ImageItem, isSelected: Bool, config: R2Config, uploader: R2Uploader, clipboard: ClipboardService,
         onUpdate: @escaping (ImageItem) -> Void, onDelete: @escaping () -> Void,
         onUploadComplete: @escaping (ImageItem) -> Void,
         onRename: @escaping (String) -> Void) {
        self.item = item; self.isSelected = isSelected
        self.config = config; self.uploader = uploader
        self.clipboard = clipboard; self.onUpdate = onUpdate; self.onDelete = onDelete
        self.onUploadComplete = onUploadComplete
        self.onRename = onRename
    }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            statusIcon
                .padding(.top, 5)

            VStack(alignment: .leading, spacing: 2) {
                if isEditingName {
                    TextField("", text: $editName)
                        .textFieldStyle(.plain)
                        .font(.system(.callout, design: .rounded))
                        .focused($nameFieldFocused)
                        .onSubmit { commitRename() }
                } else {
                    Text(item.displayName)
                        .font(.system(.callout, design: .rounded))
                        .lineLimit(1).truncationMode(.middle)
                }

                if case .processing = item.status {
                    Color.clear.frame(height: 12).overlay(alignment: .leading) { ShimmerBlock(width: 80, height: 10) }
                    Color.clear.frame(height: 12).overlay(alignment: .leading) { ShimmerBlock(width: 50, height: 10) }
                } else if case .uploading = item.status {
                    Color.clear.frame(height: 12).overlay(alignment: .leading) { ShimmerBlock(width: 80, height: 10) }
                    Color.clear.frame(height: 12).overlay(alignment: .leading) { ShimmerBlock(width: 50, height: 10) }
                } else {
                    Text("Type: \(cat)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)

                    HStack {
                        Text(formattedDate).font(.caption2)
                            .foregroundStyle(.secondary)
                        Spacer()
                        if item.webpSize > 0 {
                            Text(item.formattedWebPSize).font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }

                    if case .error(let msg) = item.status {
                        Text(msg).font(.caption2)
                            .foregroundStyle(.red).lineLimit(1)
                    }
                }
            }
        }
        .padding(.vertical, 3)
        .contextMenu {
            if case .ready = item.status {
                Button(action: uploadSingle) {
                    Label("Upload as \(cat)", systemImage: "icloud.and.arrow.up")
                }
            }
            if case .ready = item.status {
                Button(action: copyPredictedURL) { Label("Export URL", systemImage: "link") }
                Button(action: copyPredictedTOML) { Label("Export TOML", systemImage: "doc.on.clipboard") }
            }
            if case .uploaded = item.status {
                Button(action: startRename) { Label("Rename", systemImage: "pencil") }
                Button(action: copyURL) { Label("Copy URL", systemImage: "link") }
                Button(action: copyMarkdown) { Label("Copy Markdown", systemImage: "m.square") }
                Button(action: copyOne) { Label("Copy TOML", systemImage: "t.square") }
            }
            Divider()
            Button(role: .destructive, action: onDelete) { Label("Delete", systemImage: "trash") }
        }
    }

    private var cat: String { item.category }
    private var formattedDate: String {
        if let d = item.uploadedAt {
            let df = DateFormatter(); df.dateFormat = "yyyy-MM-dd"
            return df.string(from: d)
        }
        let ds = item.dateString
        guard ds.count == 8 else { return ds }
        return "\(ds.prefix(4))-\(ds.dropFirst(4).prefix(2))-\(ds.suffix(2))"
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch item.status {
        case .processing, .uploading:
            ProgressView().scaleEffect(0.45).frame(width: 10, height: 10)
        case .ready:
            Circle()
                .stroke(.secondary.opacity(0.35), lineWidth: 1.5)
                .frame(width: 10, height: 10)
        case .uploaded:
            Circle().fill(.green).frame(width: 10, height: 10)
        case .error:
            Circle().fill(.red).frame(width: 10, height: 10)
        }
    }

    private func uploadSingle() {
        var updated = item; updated.status = .uploading; onUpdate(updated)
        Task {
            do {
                let result = try await uploader.upload(item: updated, config: config)
                var final = result; final.category = cat; onUpdate(final)
                onUploadComplete(final)
            } catch {
                var failed = item; failed.status = .error(error.localizedDescription); onUpdate(failed)
            }
        }
    }
    private func copyOne() { clipboard.copyToClipboard(clipboard.generateTOML(for: item, config: config)) }
    private func copyMarkdown() {
        if case .uploaded(let url) = item.status {
            clipboard.copyToClipboard("![](\(url))")
        }
    }

    private func copyURL() {
        if case .uploaded(let url) = item.status { clipboard.copyToClipboard(url) }
    }
    private func copyPredictedURL() {
        clipboard.copyToClipboard("\(config.publicURLBaseNormalized)/\(item.title).avif")
    }
    private func copyPredictedTOML() {
        let ds = item.dateString
        var d = ds
        if ds.count == 8 { d = "\(ds.prefix(4))-\(ds.dropFirst(4).prefix(2))-\(ds.suffix(2))" }
        let predictedURL = "\(config.publicURLBaseNormalized)/\(item.title).avif"

        if !config.tomlTemplate.isEmpty {
            let result = config.tomlTemplate
                .replacingOccurrences(of: "{category}", with: cat)
                .replacingOccurrences(of: "{date}", with: d)
                .replacingOccurrences(of: "{date8}", with: item.dateString)
                .replacingOccurrences(of: "{title}", with: item.title)
                .replacingOccurrences(of: "{url}", with: predictedURL)
                .replacingOccurrences(of: "{width}", with: String(item.width))
                .replacingOccurrences(of: "{height}", with: String(item.height))
            clipboard.copyToClipboard(result)
        } else {
            clipboard.copyToClipboard("""
                [[items]]
                category = "\(cat)"
                date = \(d)
                title = "\(item.title)"
                url = "\(predictedURL)"
                width = \(item.width)
                height = \(item.height)

                """)
        }
    }
}

// MARK: - Shimmer

struct ShimmerModifier: ViewModifier {
    var isSelected: Bool = false
    @State private var phase: CGFloat = -1
    func body(content: Content) -> some View {
        content.overlay(
            GeometryReader { geo in
                Color.white.opacity(isSelected ? 0.15 : 0.3)
                    .frame(width: geo.size.width * 0.6)
                    .offset(x: phase * geo.size.width * 1.4)
                    .mask(content)
            }
        )
        .onAppear { withAnimation(.linear(duration: 1.2).repeatForever(autoreverses: false)) { phase = 1 } }
    }
}

struct ShimmerBlock: View {
    let width: CGFloat
    let height: CGFloat
    @State private var phase: CGFloat = -1

    var body: some View {
        RoundedRectangle(cornerRadius: 2)
            .fill(.quaternary)
            .frame(width: width, height: height)
            .overlay {
                GeometryReader { geo in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(.quaternary.opacity(0.6))
                        .frame(width: geo.size.width * 0.6)
                        .offset(x: phase * geo.size.width * 1.4)
                }
            }
            .clipped()
            .onAppear {
                withAnimation(.linear(duration: 1.2).repeatForever(autoreverses: false)) {
                    phase = 1
                }
            }
    }
}
