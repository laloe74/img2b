import SwiftUI

struct SettingsView: View {
    @Binding var config: R2Config
    @Binding var imageItems: [ImageItem]

    @State private var endpoint: String
    @State private var accessKeyId: String
    @State private var secretAccessKey: String
    @State private var bucketName: String
    @State private var publicURLBase: String
    @State private var quality: Double
    @State private var useLossless: Bool
    @State private var maxFileSizeKB: Double
    @State private var namePattern: String
    @State private var tomlFilePath: String
    @State private var tomlTemplate: String
    @State private var categories: [CategoryItem]
    @State private var defaultCategory: String
    @State private var newCategory: String = ""
    @State private var renames: [String: String] = [:]  // old -> new

    @Environment(\.dismiss) private var dismiss

    init(config: Binding<R2Config>, imageItems: Binding<[ImageItem]>) {
        self._config = config
        self._imageItems = imageItems
        self._endpoint = State(initialValue: config.wrappedValue.endpoint)
        self._accessKeyId = State(initialValue: config.wrappedValue.accessKeyId)
        self._secretAccessKey = State(initialValue: config.wrappedValue.secretAccessKey)
        self._bucketName = State(initialValue: config.wrappedValue.bucketName)
        self._publicURLBase = State(initialValue: config.wrappedValue.publicURLBase)
        self._quality = State(initialValue: Double(config.wrappedValue.quality))
        self._useLossless = State(initialValue: config.wrappedValue.useLossless)
        self._namePattern = State(initialValue: config.wrappedValue.namePattern)
        self._tomlFilePath = State(initialValue: config.wrappedValue.tomlFilePath)
        self._tomlTemplate = State(initialValue: config.wrappedValue.tomlTemplate)
        self._maxFileSizeKB = State(initialValue: Double(config.wrappedValue.maxFileSizeKB))
        self._categories = State(initialValue: config.wrappedValue.categories)
        self._defaultCategory = State(initialValue: config.wrappedValue.defaultCategory)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Settings").font(.headline)
                Spacer()
                Button("Done") { save(); dismiss() }
                    .buttonStyle(.borderedProminent).controlSize(.small)
                    .keyboardShortcut(.return)
            }
            .padding()

            Divider()

            Form {
                // MARK: R2 Bucket
                Section {
                    TextField("Account ID", text: $endpoint, prompt: Text("account-id or hostname"))
                        .disableAutocorrection(true)
                    TextField("Access Key ID", text: $accessKeyId, prompt: Text("access-key-id"))
                        .disableAutocorrection(true)
                    SecureField("Secret Access Key", text: $secretAccessKey, prompt: Text("secret-access-key"))
                        .disableAutocorrection(true)
                    TextField("Bucket Name", text: $bucketName, prompt: Text("my-images"))
                        .disableAutocorrection(true)
                    TextField("Public URL Base", text: $publicURLBase, prompt: Text("https://image.example.com"))
                        .disableAutocorrection(true)
                } header: { Text("Cloudflare R2") }

                Section {
                    TextField("Name Pattern", text: $namePattern, prompt: Text("img-{hash16}-{date}"))
                        .disableAutocorrection(true)
                        .font(.system(.body, design: .monospaced))
                } header: { Text("File Naming") }

                Section {
                    TextField("TOML File Path", text: $tomlFilePath, prompt: Text("~/blog/content/photos.toml"))
                        .disableAutocorrection(true)
                        .font(.system(.body, design: .monospaced))
                } header: { Text("TOML Output") }

                Section {
                    TextEditor(text: $tomlTemplate)
                        .font(.system(.body, design: .monospaced))
                        .frame(minHeight: 100)
                        .disableAutocorrection(true)
                } header: { Text("TOML Template") }

                // MARK: Categories
                Section {
                    HStack {
                        TextField("New Category", text: $newCategory, prompt: Text("weekly"))
                        Button("Add") {
                            let t = newCategory.trimmingCharacters(in: .whitespaces)
                            if !t.isEmpty, t.lowercased() != "none", !categories.contains(where: { $0.name == t }) {
                                categories.append(CategoryItem(name: t, icon: CategoryItem.defaultIcon))
                                if categories.count == 1 { defaultCategory = t }
                                newCategory = ""
                            }
                        }
                        .disabled(newCategory.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                    ForEach($categories) { $cat in
                        if cat.name != "none" {
                            HStack(spacing: 8) {
                                Menu {
                                    ForEach(CategoryItem.defaults) { def in
                                        Button { cat.icon = def.icon } label: {
                                            Label(def.name, systemImage: def.icon)
                                        }
                                    }
                                } label: {
                                    Image(systemName: cat.icon).frame(width: 20)
                                }
                                .menuStyle(.borderlessButton)

                                TextField("", text: $cat.name)
                                    .textFieldStyle(.plain)
                                    .onSubmit {
                                        let old = renames.first(where: { $0.value == cat.name })?.key
                                            ?? config.categories.first(where: { $0.id == cat.id })?.name
                                        if let old, old != cat.name { renames[old] = cat.name }
                                    }

                                Spacer()

                                Button(role: .destructive) {
                                    categories.removeAll { $0.name == cat.name }
                                    if defaultCategory == cat.name { defaultCategory = categories.first?.name ?? "" }
                                } label: {
                                    Image(systemName: "trash").font(.caption)
                                }
                                .buttonStyle(.borderless).foregroundStyle(.red)
                            }
                        }
                    }
                } header: { Text("Categories") }

                // MARK: Image Compression
                Section {
                    Toggle("Lossless", isOn: $useLossless)

                    if !useLossless {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("Quality"); Spacer()
                                Text("\(Int(quality))%").foregroundStyle(.secondary).fontDesign(.monospaced)
                            }
                            Slider(value: $quality, in: 75...100, step: 1)
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("Max File Size"); Spacer()
                                Text("\(Int(maxFileSizeKB)) KB").foregroundStyle(.secondary).fontDesign(.monospaced)
                            }
                            Slider(value: $maxFileSizeKB, in: 100...2000, step: 50)
                        }
                    }
                } header: { Text("Image Compression") }
            }
            .formStyle(.grouped)
        }
        .frame(width: 460, height: 560)
    }

    private func save() {
        config.endpoint = endpoint.trimmingCharacters(in: .whitespaces)
        config.accessKeyId = accessKeyId.trimmingCharacters(in: .whitespaces)
        config.secretAccessKey = secretAccessKey.trimmingCharacters(in: .whitespaces)
        config.bucketName = bucketName.trimmingCharacters(in: .whitespaces)
        config.publicURLBase = publicURLBase.trimmingCharacters(in: .whitespaces)
        config.quality = Int(quality)
        config.useLossless = useLossless
        config.namePattern = namePattern.trimmingCharacters(in: .whitespaces)
        config.tomlFilePath = tomlFilePath.trimmingCharacters(in: .whitespaces)
        config.tomlTemplate = tomlTemplate
        config.maxFileSizeKB = Int(maxFileSizeKB)
        // Apply renames to existing items
        for (old, new) in renames where old != new {
            for i in imageItems.indices where imageItems[i].category == old {
                imageItems[i].category = new
            }
            if defaultCategory == old { defaultCategory = new }
        }
        config.categories = categories
        config.defaultCategory = defaultCategory
        config.save()
    }
}
