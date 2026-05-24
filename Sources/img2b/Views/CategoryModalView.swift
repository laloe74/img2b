import SwiftUI

// MARK: - Category Modal

struct CategoryModalView: View {
    @Binding var categories: [CategoryItem]
    @Binding var defaultCategory: String
    var onDismiss: () -> Void

    @State private var name: String = ""
    @State private var selectedIcon: String = "tag"
    @FocusState private var isFocused: Bool

    private let iconOptions: [(name: String, label: String)] = [
        ("circle", "Circle"), ("tag", "Tag"), ("folder", "Folder"),
        ("photo", "Photo"), ("camera", "Camera"), ("paintpalette", "Art"),
        ("pencil.and.ruler", "Design"), ("textformat", "Text"), ("link", "Link"),
        ("globe", "Globe"), ("star", "Star"), ("heart", "Heart"),
        ("book", "Book"), ("music.note", "Music"), ("film", "Film"),
        ("atom", "Atom"), ("sparkles", "Spark"), ("square.grid.2x2", "Grid"),
        ("circle.dotted.circle", "Physics"), ("building.2", "Building"),
        ("doc.richtext", "Typography"),
    ]

    private var isValid: Bool {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        return !trimmed.isEmpty && !categories.contains(where: { $0.name == trimmed })
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("New Category").font(.headline)
                Spacer()
                Button(action: onDismiss) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3).foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20).padding(.top, 20).padding(.bottom, 16)

            Divider()

            VStack(spacing: 16) {
                TextField("Category name", text: $name)
                    .textFieldStyle(.roundedBorder)
                    .focused($isFocused)
                    .onSubmit { add() }
                    .font(.body)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Icon").font(.subheadline).foregroundStyle(.secondary)
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 8), spacing: 4) {
                        ForEach(iconOptions, id: \.name) { icon in
                            Button {
                                selectedIcon = icon.name
                            } label: {
                                Image(systemName: icon.name)
                                    .font(.system(size: 16))
                                    .frame(width: 32, height: 32)
                                    .background(selectedIcon == icon.name
                                        ? RoundedRectangle(cornerRadius: 6).fill(.blue)
                                        : RoundedRectangle(cornerRadius: 6).fill(.clear))
                                    .foregroundStyle(selectedIcon == icon.name ? .white : .secondary)
                            }
                            .buttonStyle(.plain).help(icon.label)
                        }
                    }
                }
            }
            .padding(20)

            Divider()

            HStack(spacing: 12) {
                Spacer()
                Button("Cancel", action: onDismiss).keyboardShortcut(.escape, modifiers: [])
                Button("Add") { add() }.keyboardShortcut(.return, modifiers: []).disabled(!isValid)
            }
            .padding(20)
        }
        .frame(width: 340)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.15), radius: 24, y: 8)
        .onAppear { isFocused = true }
    }

    private func add() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !categories.contains(where: { $0.name == trimmed }) else { return }
        categories.append(CategoryItem(name: trimmed, icon: selectedIcon))
        if categories.count == 1 { defaultCategory = trimmed }
        onDismiss()
    }
}

// MARK: - Modal Modifier

struct CategoryModalModifier: ViewModifier {
    @Binding var isPresented: Bool
    @Binding var categories: [CategoryItem]
    @Binding var defaultCategory: String
    var onSave: () -> Void

    func body(content: Content) -> some View {
        content.overlay {
            if isPresented {
                ZStack {
                    Color.black.opacity(0.2)
                        .ignoresSafeArea()
                        .onTapGesture { dismiss() }
                        .transition(.opacity)

                    CategoryModalView(
                        categories: $categories,
                        defaultCategory: $defaultCategory,
                        onDismiss: { dismiss() }
                    )
                    .transition(.scale(scale: 0.85).combined(with: .opacity))
                }
                .animation(.spring(response: 0.28, dampingFraction: 0.82), value: isPresented)
            }
        }
        .onChange(of: categories.count) { _, _ in onSave() }
    }

    private func dismiss() {
        withAnimation(.spring(response: 0.22, dampingFraction: 0.85)) {
            isPresented = false
        }
    }
}

extension View {
    func categoryModal(
        isPresented: Binding<Bool>,
        categories: Binding<[CategoryItem]>,
        defaultCategory: Binding<String>,
        onSave: @escaping () -> Void = {}
    ) -> some View {
        modifier(CategoryModalModifier(
            isPresented: isPresented,
            categories: categories,
            defaultCategory: defaultCategory,
            onSave: onSave
        ))
    }
}
