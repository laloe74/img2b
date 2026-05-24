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
    @State private var itemToDelete: ImageItem?
    @State private var selectedItemIDs: Set<UUID> = []
    @State private var previewItemID: UUID?
    @State private var showCategoryModal = false

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
                        ForEach(imageItems) { item in
                            SidebarRow(
                                item: item,
                                isSelected: selectedItemIDs.contains(item.id),
                                config: r2Config,
                                uploader: uploader,
                                clipboard: clipboard,
                                onUpdate: { updated in
                                    if let idx = imageItems.firstIndex(where: { $0.id == updated.id }) {
                                        imageItems[idx] = updated
                                    }
                                },
                                onDelete: { handleDelete(item) }
                            )
                            .tag(item.id)
                        }
                        .onDelete { indexSet in
                            for idx in indexSet { handleDelete(imageItems[idx]) }
                        }
                    }
                } header: {
                    Text("Image List")
                }
            }
            .listStyle(.sidebar)
            .onSidebarEmptyClick(selectedItemIDs: $selectedItemIDs)
            .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 340)
        } detail: {
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
        .toolbar {
            ToolbarItemGroup(placement: .navigation) {
                Button(action: deleteSelected) {
                    Image(systemName: "trash")
                }
                .disabled(selectedItemIDs.isEmpty)
                .help("Delete (\(selectedItemIDs.count))")
                .tint(.red)
                if !uploadedOnly.isEmpty {
                    Button(action: copyAll) {
                        Image(systemName: "doc.on.clipboard")
                    }
                    .help("Copy TOML (\(uploadedOnly.count))")
                }
            }
            if !imageItems.isEmpty, r2Config.categories.count > 1 {
                ToolbarItem(placement: .principal) {
                    HStack(spacing: 4) {
                        ForEach(r2Config.categories, id: \.self) { cat in
                            Button {
                                guard let sel = selectedItem,
                                      let idx = imageItems.firstIndex(where: { $0.id == sel.id })
                                else { return }
                                imageItems[idx].category = cat
                            } label: {
                                Image(systemName: categoryIcon(for: cat))
                                    .font(.system(size: 14, weight: .medium))
                            }
                            .buttonStyle(.borderless)
                            .frame(width: 30, height: 30)
                            .background(isSelected(cat) ? Circle().fill(.blue) : Circle().fill(.clear))
                            .foregroundStyle(isSelected(cat) ? .white : .secondary)
                            .help(cat)
                        }
                        Button {
                            showCategoryModal = true
                        } label: {
                            Image(systemName: "plus")
                                .font(.system(size: 12, weight: .bold))
                        }
                        .buttonStyle(.borderless)
                        .frame(width: 30, height: 30)
                        .background(Circle().fill(.clear))
                        .foregroundStyle(.secondary)
                        .help("New category")
                    }
                    .padding(4)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                }
            }
            ToolbarItemGroup {
                if !readyItems.isEmpty {
                    Button(action: uploadAll) {
                        Label("Upload All (\(readyItems.count))", systemImage: "icloud.and.arrow.up")
                    }
                }
                Button(action: { showSettings = true }) {
                    Label("Settings", systemImage: "gearshape")
                }
            }
        }
        .sheet(isPresented: $showSettings) {
            SettingsView(config: $r2Config)
        }
        .confirmationDialog("Delete from R2?", isPresented: $showDeleteConfirm, presenting: itemToDelete) { item in
            Button("Delete from R2", role: .destructive) { deleteFromR2(item) }
            Button("Remove from List Only") { removeFromList(item) }
            Button("Cancel", role: .cancel) {}
        } message: { item in
            Text("\"\(item.title).avif\" will be permanently deleted from R2 storage.")
        }
        .categoryModal(
            isPresented: $showCategoryModal,
            categories: $r2Config.categories,
            defaultCategory: $r2Config.defaultCategory,
            onSave: { r2Config.save() }
        )
        .navigationTitle("")
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

    // MARK: - Preview

    @ViewBuilder
    private func previewView(for item: ImageItem) -> some View {
        VStack(spacing: 0) {
            let localURL = item.webpURL ?? ImageProcessor.cacheURL(for: item.title)
            if let nsImage = NSImage(contentsOf: localURL) {
                Image(nsImage: nsImage)
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
            } else {
                ContentUnavailableView("No Preview", systemImage: "eye.slash",
                    description: Text("Compressed image not available"))
            }

            Divider()

            VStack(spacing: 0) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(item.title + ".avif").font(.caption).fontWeight(.medium)
                            .padding(.bottom, 4)
                        if item.webpSize > 0 {
                            Text("\(Int((1 - item.compressionRatio) * 100))% smaller")
                                .font(.caption2).foregroundStyle(.green)
                                .fontDesign(.monospaced)
                        }
                        previewRow(label: "Original", format: originalFormat, size: item.formattedOriginalSize,
                                   url: item.originalURL)
                        if item.webpSize > 0 {
                            previewRow(label: "Now", format: "AVIF", size: item.formattedWebPSize,
                                       url: item.webpURL ?? ImageProcessor.cacheURL(for: item.title))
                        }
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

    private func previewRow(label: String, format: String, size: String, url: URL?) -> some View {
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
            Text(resolutionFor(url: url) ?? "-")
                .font(.caption2).foregroundStyle(.secondary)
                .frame(width: 88, alignment: .trailing)
                .fontDesign(.monospaced)
            Text(colorSpaceFor(url: url) ?? "-")
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

    private var readyItems: [ImageItem] {
        imageItems.filter { if case .ready = $0.status { !$0.category.isEmpty } else { false } }
    }
    private var uploadedOnly: [ImageItem] {
        imageItems.filter { if case .uploaded = $0.status { true } else { false } }
    }

    private func categoryIcon(for cat: String) -> String {
        switch cat.lowercased() {
        case "design": return "building.2"
        case "photography": return "camera"
        case "physics": return "circle.dotted.circle"
        case "typography": return "doc.richtext"
        default: return "tag"
        }
    }

    private func isSelected(_ cat: String) -> Bool {
        guard let sel = selectedItem else { return false }
        return sel.category == cat
    }

    // MARK: - Actions

    private func handleDelete(_ item: ImageItem) {
        if case .uploaded = item.status {
            itemToDelete = item; showDeleteConfirm = true
        } else {
            removeFromList(item)
        }
    }
    private func removeFromList(_ item: ImageItem) {
        selectedItemIDs.remove(item.id)
        imageItems.removeAll { $0.id == item.id }
        // Clean up cached file
        let cacheURL = ImageProcessor.cacheURL(for: item.title)
        try? FileManager.default.removeItem(at: cacheURL)
    }
    private func deleteSelected() {
        let items = imageItems.filter { selectedItemIDs.contains($0.id) }
        for item in items { handleDelete(item) }
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
    private func uploadAll() {
        let toUpload = readyItems
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
                        clipboard.appendToFile(item: result, config: r2Config)
                        if case .uploaded(let url) = result.status { clipboard.copyToClipboard(url) }
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
    private func copyAll() {
        clipboard.copyToClipboard(clipboard.generateTOML(for: imageItems, config: r2Config))
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
                    imageItems.insert(item, at: 0)
                    newIDs.insert(item.id)
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
                            at: url, quality: r2Config.quality,
                            lossless: r2Config.useLossless,
                            maxSizeKB: r2Config.maxFileSizeKB,
                            namePattern: r2Config.namePattern,
                            onStep: { step in DispatchQueue.main.async { currentStep = step ?? "" } }
                        )
                        var updated = processed
                        updated.id = imageItems[idx].id  // preserve original ID
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

    init(item: ImageItem, isSelected: Bool, config: R2Config, uploader: R2Uploader, clipboard: ClipboardService,
         onUpdate: @escaping (ImageItem) -> Void, onDelete: @escaping () -> Void) {
        self.item = item; self.isSelected = isSelected
        self.config = config; self.uploader = uploader
        self.clipboard = clipboard; self.onUpdate = onUpdate; self.onDelete = onDelete
    }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            statusIcon
                .padding(.top, 5)

            if case .processing = item.status {
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.displayName)
                        .font(.system(.callout, design: .rounded))
                        .foregroundStyle(isSelected ? Color.white : Color.primary)
                        .lineLimit(1).truncationMode(.middle)
                    Text("Processing...")
                        .font(.caption2)
                        .foregroundStyle(isSelected ? Color.white.opacity(0.7) : Color.secondary)
                    Text(" ")
                        .font(.caption2)
                }
            } else if case .uploading = item.status {
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.displayName)
                        .font(.system(.callout, design: .rounded))
                        .foregroundStyle(isSelected ? Color.white : Color.primary)
                        .lineLimit(1).truncationMode(.middle)
                    Text("Uploading...")
                        .font(.caption2)
                        .foregroundStyle(isSelected ? Color.white.opacity(0.7) : Color.secondary)
                    Text(" ")
                        .font(.caption2)
                }
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.displayName)
                        .font(.system(.callout, design: .rounded))
                        .foregroundStyle(isSelected ? Color.white : Color.primary)
                        .lineLimit(1).truncationMode(.middle)

                    Text(cat.isEmpty ? "Set a category" : "Type: \(cat)")
                        .font(.caption2)
                        .foregroundStyle(cat.isEmpty
                            ? (isSelected ? Color.white.opacity(0.7) : Color.orange)
                            : (isSelected ? Color.white.opacity(0.7) : Color.secondary))

                    HStack {
                        Text(formattedDate).font(.caption2)
                            .foregroundStyle(isSelected ? Color.white.opacity(0.7) : Color.secondary)
                        Spacer()
                        if item.webpSize > 0 {
                            Text(item.formattedWebPSize).font(.caption2)
                                .foregroundStyle(isSelected ? Color.white.opacity(0.7) : Color.secondary)
                        }
                    }

                    if case .uploaded(let url) = item.status {
                        Text(url).font(.caption2)
                            .foregroundStyle(isSelected ? Color.white.opacity(0.7) : Color.secondary).lineLimit(1)
                    }
                    if case .error(let msg) = item.status {
                        Text(msg).font(.caption2)
                            .foregroundStyle(isSelected ? Color.white : Color.red).lineLimit(1)
                    }
                }
            }
        }
        .padding(.vertical, 3)
        .contextMenu {
            if case .ready = item.status, !cat.isEmpty {
                Button(action: uploadSingle) { Label("Upload as \(cat)", systemImage: "icloud.and.arrow.up") }
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
            ProgressView().scaleEffect(0.45).frame(width: 8, height: 8)
                .tint(isSelected ? .white : .accentColor)
        case .ready:
            Circle().stroke(isSelected ? Color.white.opacity(0.5) : Color.secondary.opacity(0.3), lineWidth: 1.5)
                .frame(width: 8, height: 8)
        case .uploaded:
            Circle().fill(isSelected ? Color.green : Color.green).frame(width: 8, height: 8)
        case .error:
            Circle().fill(isSelected ? Color.red : Color.red).frame(width: 8, height: 8)
        }
    }

    private func uploadSingle() {
        guard !cat.isEmpty else { return }
        var updated = item; updated.category = cat; updated.status = .uploading; onUpdate(updated)
        Task {
            do {
                let result = try await uploader.upload(item: updated, config: config)
                var final = result; final.category = cat; onUpdate(final)
                clipboard.appendToFile(item: final, config: config)
                if case .uploaded(let url) = result.status { clipboard.copyToClipboard(url) }
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
