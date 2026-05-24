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

    private var selectedItem: ImageItem? {
        guard let id = previewItemID else { return nil }
        return imageItems.first { $0.id == id }
    }

    var body: some View {
        NavigationSplitView {
            List {
                Section {
                    if imageItems.isEmpty {
                        Text("No images yet")
                            .font(.callout)
                            .foregroundStyle(.tertiary)
                    } else {
                        ForEach(imageItems) { item in
                        SidebarRow(
                            item: item,
                            isSelected: previewItemID == item.id,
                            selectedItemIDs: $selectedItemIDs,
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
                        .contentShape(Rectangle())
                        .onTapGesture {
                            if previewItemID == item.id {
                                previewItemID = nil
                            } else {
                                previewItemID = item.id
                            }
                        }
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
                        r2Config: r2Config
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
            if !imageItems.isEmpty, r2Config.categories.count > 1 {
                ToolbarItem(placement: .principal) {
                    HStack(spacing: 4) {
                        ForEach(r2Config.categories, id: \.self) { cat in
                            Button {
                                guard let id = previewItemID,
                                      let idx = imageItems.firstIndex(where: { $0.id == id })
                                else { return }
                                imageItems[idx].category = cat
                            } label: {
                                Image(systemName: categoryIcon(for: cat))
                                    .font(.system(size: 14, weight: .medium))
                            }
                            .buttonStyle(.borderless)
                            .frame(width: 30, height: 30)
                            .background(
                                isSelected(cat)
                                    ? Circle().fill(.blue)
                                    : Circle().fill(.clear)
                            )
                            .foregroundStyle(isSelected(cat) ? .white : .secondary)
                            .help(cat)
                        }
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
        .safeAreaInset(edge: .bottom) {
            if !imageItems.isEmpty {
                HStack(spacing: 12) {
                    if !selectedItemIDs.isEmpty {
                        Button(action: deleteSelected) {
                            Label("Delete (\(selectedItemIDs.count))", systemImage: "trash")
                        }
                        .buttonStyle(.bordered).controlSize(.small)
                    }
                    if !uploadedOnly.isEmpty {
                        Button(action: copyAll) {
                            Label("Copy TOML (\(uploadedOnly.count))", systemImage: "doc.on.clipboard")
                        }
                        .buttonStyle(.bordered).controlSize(.small)
                    }
                    Spacer()
                }
                .padding(.horizontal, 20).padding(.vertical, 12)
            }
        }
        .confirmationDialog("Delete from R2?", isPresented: $showDeleteConfirm, presenting: itemToDelete) { item in
            Button("Delete from R2", role: .destructive) { deleteFromR2(item) }
            Button("Remove from List Only") { removeFromList(item) }
            Button("Cancel", role: .cancel) {}
        } message: { item in
            Text("\"\(item.title).heic\" will be permanently deleted from R2 storage.")
        }
        .onChange(of: selectedItemIDs) { _, new in
            if previewItemID == nil || !new.contains(previewItemID!) {
                previewItemID = new.first
            }
        }
        .onExitCommand { selectedItemIDs = []; previewItemID = nil }
        .onSidebarEmptyClick(selectedItemIDs: $selectedItemIDs)
        .onAppear { Task { await updater.checkForUpdates() } }
        .onReceive(NotificationCenter.default.publisher(for: .openSettings)) { _ in
            showSettings = true
        }
    }

    // MARK: - Preview

    @ViewBuilder
    private func previewView(for item: ImageItem) -> some View {
        VStack(spacing: 0) {
            if let webpURL = item.webpURL, let nsImage = NSImage(contentsOf: webpURL) {
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
                ContentUnavailableView(
                    "No Preview",
                    systemImage: "eye.slash",
                    description: Text("Compressed image not available")
                )
            }

            Divider()

            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title + ".heic").font(.caption).fontWeight(.medium)
                    HStack(spacing: 12) {
                        Text("Original: \(item.formattedOriginalSize)").font(.caption2).foregroundStyle(.secondary)
                        if item.webpSize > 0 {
                            Text("WebP: \(item.formattedWebPSize)").font(.caption2).foregroundStyle(.secondary)
                            Text("\(Int((1 - item.compressionRatio) * 100))% smaller")
                                .font(.caption2).foregroundStyle(.green)
                        }
                    }
                }
                .allowsHitTesting(false)
                Spacer()
                    .allowsHitTesting(false)
                Button { selectedItemIDs = []; previewItemID = nil } label: {
                    Image(systemName: "xmark.circle.fill").font(.title3).foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16).padding(.vertical, 10)
        }
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
        guard let id = previewItemID,
              let sel = imageItems.first(where: { $0.id == id })
        else { return false }
        return sel.category == cat
    }

    // MARK: - Data

    private var readyItems: [ImageItem] {
        imageItems.filter { if case .ready = $0.status { !$0.category.isEmpty } else { false } }
    }
    private var uploadedOnly: [ImageItem] {
        imageItems.filter { if case .uploaded = $0.status { true } else { false } }
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
    }

    private func deleteSelected() {
        let items = imageItems.filter { selectedItemIDs.contains($0.id) }
        for item in items { handleDelete(item) }
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

            isProcessing = true
            processingProgress = (0, validURLs.count)

            Task {
                for (index, url) in validURLs.enumerated() {
                    let item = ImageItem(originalURL: url)
                    imageItems.append(item)

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
                        if let idx = imageItems.firstIndex(where: { $0.id == item.id }) {
                            imageItems[idx] = processed
                        }
                    } catch {
                        if let idx = imageItems.firstIndex(where: { $0.id == item.id }) {
                            imageItems[idx].status = .error(error.localizedDescription)
                        }
                    }
                    processingProgress = (index + 1, validURLs.count)
                }
                isProcessing = false
            }
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
                        if case .uploaded(let url) = result.status {
                            clipboard.copyToClipboard(url)
                        }
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
        clipboard.copyToClipboard(clipboard.generateTOML(for: imageItems))
    }
}

// MARK: - Sidebar Row

struct SidebarRow: View {
    let item: ImageItem
    let isSelected: Bool
    @Binding var selectedItemIDs: Set<UUID>
    let config: R2Config
    let uploader: R2Uploader
    let clipboard: ClipboardService
    let onUpdate: (ImageItem) -> Void
    let onDelete: () -> Void

    init(item: ImageItem, isSelected: Bool, selectedItemIDs: Binding<Set<UUID>>,
         config: R2Config, uploader: R2Uploader, clipboard: ClipboardService,
         onUpdate: @escaping (ImageItem) -> Void, onDelete: @escaping () -> Void) {
        self.item = item; self.isSelected = isSelected
        self._selectedItemIDs = selectedItemIDs
        self.config = config; self.uploader = uploader
        self.clipboard = clipboard; self.onUpdate = onUpdate; self.onDelete = onDelete
    }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Toggle("Select", isOn: Binding(
                get: { selectedItemIDs.contains(item.id) },
                set: { checked in
                    if checked { selectedItemIDs.insert(item.id) }
                    else { selectedItemIDs.remove(item.id) }
                }
            ))
            .toggleStyle(.checkbox)
            .labelsHidden()
            .padding(.top, 1)

            statusIcon
                .padding(.top, 5)

            if case .processing = item.status {
                VStack(alignment: .leading, spacing: 4) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.secondary.opacity(0.15))
                        .frame(width: 120, height: 12)
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.secondary.opacity(0.1))
                        .frame(width: 60, height: 8)
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.secondary.opacity(0.08))
                        .frame(width: 90, height: 8)
                }
                .modifier(ShimmerModifier(isSelected: isSelected))
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    if case .error = item.status {
                        Text(item.displayName)
                            .font(.system(.callout, design: .rounded))
                            .foregroundStyle(isSelected ? Color.white : Color.primary)
                            .lineLimit(1).truncationMode(.middle)
                    } else {
                        Text(item.title + ".heic")
                            .font(.system(.callout, design: .rounded))
                            .foregroundStyle(isSelected ? Color.white : Color.primary)
                            .lineLimit(1).truncationMode(.middle)
                    }

                    Text(cat.isEmpty ? "Set a category" : "Type: \(cat)")
                        .font(.caption2)
                        .foregroundStyle(cat.isEmpty
                            ? (isSelected ? Color.white.opacity(0.7) : Color.orange)
                            : (isSelected ? Color.white.opacity(0.7) : Color.secondary))

                    HStack {
                        Text(formattedDate).font(.caption2).foregroundStyle(isSelected ? Color.white.opacity(0.7) : Color.secondary)
                        Spacer()
                        if item.webpSize > 0 {
                            Text(item.formattedWebPSize).font(.caption2).foregroundStyle(isSelected ? Color.white.opacity(0.7) : Color.secondary)
                        }
                    }

                    if case .uploaded(let url) = item.status {
                        Text(url).font(.caption2)
                            .foregroundStyle(isSelected ? Color.white.opacity(0.7) : Color.secondary)
                            .lineLimit(1)
                    }
                    if case .error(let msg) = item.status {
                        Text(msg).font(.caption2).foregroundStyle(isSelected ? Color.white : Color.red).lineLimit(1)
                    }
                }
            }
        }
        .padding(.vertical, 3)
        .contextMenu {
            if case .ready = item.status, !cat.isEmpty {
                Button(action: uploadSingle) {
                    Label("Upload as \(cat)", systemImage: "icloud.and.arrow.up")
                }
            }
            if case .ready = item.status {
                Button(action: copyPredictedURL) {
                    Label("Export URL", systemImage: "link")
                }
                Button(action: copyPredictedTOML) {
                    Label("Export TOML", systemImage: "doc.on.clipboard")
                }
            }
            if case .uploaded = item.status {
                Button(action: copyURL) { Label("Export URL", systemImage: "link") }
                Button(action: copyOne) { Label("Export TOML", systemImage: "doc.on.clipboard") }
            }
            Divider()
            Button(role: .destructive, action: onDelete) { Label("Delete", systemImage: "trash") }
        }
    }

    private var formattedDate: String {
        let ds = item.dateString
        guard ds.count == 8 else { return ds }
        let y = ds.prefix(4), m = ds.dropFirst(4).prefix(2), d = ds.suffix(2)
        return "\(y)-\(m)-\(d)"
    }

    private var cat: String {
        item.category
    }

    @ViewBuilder
    private var statusIcon: some View {
        Group {
            switch item.status {
            case .processing, .uploading:
                ProgressView()
                    .scaleEffect(0.45)
                    .tint(isSelected ? .white : .accentColor)
            case .ready:
                Circle()
                    .stroke(isSelected ? Color.white.opacity(0.5) : Color.secondary.opacity(0.3), lineWidth: 1.5)
                    .frame(width: 8, height: 8)
            case .uploaded:
                Circle().fill(isSelected ? Color.green : Color.green).frame(width: 8, height: 8)
            case .error:
                Circle().fill(isSelected ? Color.red : Color.red).frame(width: 8, height: 8)
            }
        }
        .frame(width: 8, height: 8)
    }

    private func uploadSingle() {
        guard !cat.isEmpty else { return }
        var updated = item; updated.category = cat; updated.status = .uploading; onUpdate(updated)
        Task {
            do {
                let result = try await uploader.upload(item: updated, config: config)
                var final = result; final.category = cat; onUpdate(final)
                clipboard.appendToFile(item: final, config: config)
                if case .uploaded(let url) = result.status {
                    clipboard.copyToClipboard(url)
                }
            } catch {
                var failed = item; failed.status = .error(error.localizedDescription); onUpdate(failed)
            }
        }
    }

    private func copyOne() {
        clipboard.copyToClipboard(clipboard.generateTOML(for: item))
    }
    private func copyURL() {
        if case .uploaded(let url) = item.status {
            clipboard.copyToClipboard(url)
        }
    }
    private func copyPredictedURL() {
        clipboard.copyToClipboard("\(config.publicURLBaseNormalized)/\(item.title).heic")
    }
    private func copyPredictedTOML() {
        let df = DateFormatter(); df.dateFormat = "yyyy-MM-dd"
        let ds = item.dateString
        var dateFormatted = ds
        if ds.count == 8 {
            dateFormatted = "\(ds.prefix(4))-\(ds.dropFirst(4).prefix(2))-\(ds.suffix(2))"
        }
        let toml = """
            [[items]]
            category = "\(cat)"
            date = \(dateFormatted)
            title = "\(item.title)"
            url = "\(config.publicURLBaseNormalized)/\(item.title).heic"

            """
        clipboard.copyToClipboard(toml)
    }
}

// MARK: - Shimmer Modifier

struct ShimmerModifier: ViewModifier {
    var isSelected: Bool = false
    @State private var phase: CGFloat = -1

    func body(content: Content) -> some View {
        content
            .overlay(
                GeometryReader { geo in
                    Color.white.opacity(isSelected ? 0.15 : 0.3)
                        .frame(width: geo.size.width * 0.6)
                        .offset(x: phase * geo.size.width * 1.4)
                        .mask(content)
                }
            )
            .onAppear {
                withAnimation(.linear(duration: 1.2).repeatForever(autoreverses: false)) {
                    phase = 1
                }
            }
    }
}
