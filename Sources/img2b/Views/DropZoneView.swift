import SwiftUI
import UniformTypeIdentifiers

struct DropZoneView: View {
    @Binding var imageItems: [ImageItem]
    let processor: ImageProcessor
    @Binding var isProcessing: Bool
    @Binding var processingProgress: (current: Int, total: Int)
    @Binding var currentStep: String
    let r2Config: R2Config
    var onNewItems: ((Set<UUID>, UUID?) -> Void)?

    @State private var isTargeted = false

    var body: some View {
        VStack {
            if isProcessing {
                VStack(spacing: 8) {
                    ProgressView(value: Double(processingProgress.current),
                                 total: Double(processingProgress.total))
                        .progressViewStyle(.linear)

                    Text(currentStep)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text("\(processingProgress.current) of \(processingProgress.total) images")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: 280)
            } else if imageItems.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: isTargeted ? "arrow.down.to.line.compact" : "photo.on.rectangle.angled")
                        .font(.system(size: 36, weight: .light))
                        .foregroundStyle(isTargeted ? .primary : .tertiary)
                        .scaleEffect(isTargeted ? 1.1 : 1.0)

                    Text(isTargeted ? "Release to Add" : "Drop Images Here")
                        .font(.title3)
                        .foregroundStyle(isTargeted ? .primary : .secondary)
                }
            } else {
                VStack(spacing: 12) {
                    Image(systemName: isTargeted ? "arrow.down.to.line.compact" : "plus.rectangle.on.rectangle")
                        .font(.system(size: 24, weight: .light))
                        .foregroundStyle(isTargeted ? .primary : .quaternary)
                        .scaleEffect(isTargeted ? 1.1 : 1.0)

                    Text(isTargeted ? "Release to Add More" : "Drop More Images")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .aspectRatio(1, contentMode: .fit)
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(isTargeted ? Color.accentColor : Color.secondary.opacity(0.2),
                        style: StrokeStyle(lineWidth: isTargeted ? 2.5 : 2, dash: [8, 4]))
                .padding(20)
        }
        .animation(.smooth(duration: 0.2), value: isTargeted)
        .onDrop(of: [.fileURL], isTargeted: $isTargeted) { providers in
            handleDrop(providers: providers)
            return true
        }
    }

    private func handleDrop(providers: [NSItemProvider]) {
        let count = providers.count
        let results = UnsafeMutablePointer<URL?>.allocate(capacity: count)
        results.initialize(repeating: nil, count: count)
        let group = DispatchGroup()

        for (i, provider) in providers.enumerated() {
            group.enter()
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
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
                onNewItems?(newIDs, firstID)

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
