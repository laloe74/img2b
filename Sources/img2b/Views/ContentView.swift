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
    @State private var cachedPreview: (url: URL, image: NSImage)?

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
        .onAppear { Task { await updater.checkForUpdates() } }
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
                        NSApp.activate(ignoringOtherApps: true)
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

    private var sidebarRows: some View {
        ForEach(imageItems) { item in
            SidebarRow(
                item: item,
                isSelected: selectedItemIDs.contains(item.id),
                config: r2Config,
                uploader: uploader,
                clipboard: clipboard,
                onUpdate: { updateItem($0) },
                onDelete: { handleDelete(item) },
                onUploadComplete: { handleUploadResult($0) }
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
        VStack(spacing: 0) {
            if let cached = cachedPreview, cached.url == localURL {
                Image(nsImage: cached.image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if case .uploaded(let url) = item.status, let imageURL = URL(string: url) {
                AsyncImage(url: imageURL) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().aspectRatio(contentMode: .fit)
                    case .failure:
                        ContentUnavailableView("Load Failed", systemImage: "wifi.slash", description: Text(url))
                    case .empty:
                        ProgressView()
                    @unknown default:
                        ProgressView()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if item.webpSize > 0 || item.webpURL != nil {
                ProgressView()
                    .scaleEffect(0.8)
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

            VStack(spacing: 0) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(item.title + ".avif").font(.caption).fontWeight(.medium)
                            .padding(.bottom, 4)
                        Text(item.webpSize > 0
                             ? "\(Int((1 - item.compressionRatio) * 100))% smaller"
                             : " ")
                            .font(.caption2).foregroundStyle(.green)
                            .fontDesign(.monospaced)
                        previewRow(label: "Original", format: originalFormat, size: item.formattedOriginalSize,
                                   resolution: item.formattedOriginalDimensions != "-"
                                       ? item.formattedOriginalDimensions
                                       : (resolutionFor(url: item.originalURL) ?? "-"),
                                   colorSpace: item.displayColorSpace != "-"
                                       ? item.displayColorSpace
                                       : (colorSpaceFor(url: item.originalURL) ?? "-"))
                        previewRow(label: "Now", format: "AVIF", size: item.formattedWebPSize,
                                   resolution: item.formattedDimensions,
                                   colorSpace: item.webpSize > 0
                                       ? (colorSpaceFor(url: item.webpURL ?? ImageProcessor.cacheURL(for: item.title)) ?? "-")
                                       : "-")
                    }
                    Spacer()
                    Button { selectedItemIDs = []; previewItemID = nil } label: {
                        Image(systemName: "xmark.circle.fill").font(.title3).foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 10)
        }
        .task(id: localURL) {
            cachedPreview = nil
            let url = localURL
            if let img = await Task.detached(priority: .userInitiated) { () -> NSImage? in
                NSImage(contentsOf: url)
            }.value {
                cachedPreview = (url, img)
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

    private func previewRow(label: String, format: String, size: String, resolution: String, colorSpace: String) -> some View {
        HStack(spacing: 12) {
            Text(label)
                .font(.caption2).fontWeight(.medium).foregroundStyle(.secondary)
                .frame(width: 56, alignment: .leading)
            Text(format)
                .font(.caption2).foregroundStyle(.secondary)
                .frame(width: 36, alignment: .leading)
                .fontDesign(.monospaced)
            Text(size)
                .font(.caption2).foregroundStyle(.secondary)
                .frame(width: 64, alignment: .trailing)
                .fontDesign(.monospaced)
            Text(resolution)
                .font(.caption2).foregroundStyle(.secondary)
                .frame(width: 88, alignment: .trailing)
                .fontDesign(.monospaced)
            Text(colorSpace)
                .font(.caption2).foregroundStyle(.secondary)
                .frame(width: 160, alignment: .leading)
                .lineLimit(1)
        }
    }

    private var originalFormat: String {
        selectedItem?.originalURL?.pathExtension.uppercased()
            ?? selectedItem?.originalFilename.components(separatedBy: ".").last?.uppercased()
            ?? "-"
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
        // If already selected, toggle back to none
        imageItems[idx].category = sel.category == name ? "none" : name
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
        selectedItemIDs.remove(item.id)
        previewItemID = nil
        imageItems.remove(at: idx)
        // Auto-select next
        if !imageItems.isEmpty {
            let next = idx < imageItems.count ? imageItems[idx] : imageItems[imageItems.count - 1]
            selectedItemIDs = [next.id]
        }
        let cacheURL = ImageProcessor.cacheURL(for: item.title)
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
                    imageItems[idx].status = .error("Delete failed: \(error.localizedDescription)")
                }
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
                        imageItems[idx].status = .error(error.localizedDescription)
                    }
                }
            }
            isUploading = false
        }
    }
    private func handleUploadResult(_ item: ImageItem) {
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
                NSApp.activate(ignoringOtherApps: true)

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

    init(item: ImageItem, isSelected: Bool, config: R2Config, uploader: R2Uploader, clipboard: ClipboardService,
         onUpdate: @escaping (ImageItem) -> Void, onDelete: @escaping () -> Void,
         onUploadComplete: @escaping (ImageItem) -> Void) {
        self.item = item; self.isSelected = isSelected
        self.config = config; self.uploader = uploader
        self.clipboard = clipboard; self.onUpdate = onUpdate; self.onDelete = onDelete
        self.onUploadComplete = onUploadComplete
    }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            statusIcon
                .padding(.top, 5)

            if case .processing = item.status {
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.displayName)
                        .font(.system(.callout, design: .rounded))
                        .lineLimit(1).truncationMode(.middle)
                    Text("Processing...")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(" ")
                        .font(.caption2)
                }
            } else if case .uploading = item.status {
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.displayName)
                        .font(.system(.callout, design: .rounded))
                        .lineLimit(1).truncationMode(.middle)
                    Text("Uploading...")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(" ")
                        .font(.caption2)
                }
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.displayName)
                        .font(.system(.callout, design: .rounded))
                        .lineLimit(1).truncationMode(.middle)

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

                    if case .uploaded(let url) = item.status {
                        Text(url).font(.caption2)
                            .foregroundStyle(.secondary).lineLimit(1)
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
                Button(action: copyURL) { Label("Export URL", systemImage: "link") }
                Button(action: copyOne) { Label("Export TOML", systemImage: "doc.on.clipboard") }
            }
            Divider()
            Button(role: .destructive, action: onDelete) { Label("Delete", systemImage: "trash") }
        }
    }

    private var cat: String { item.category }
    private var formattedDate: String {
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
