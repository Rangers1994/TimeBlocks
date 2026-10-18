//
//  CategoriesView.swift
//  TimeBlocks
//
//  Category management (DESIGN.md §5.4): edit name/emoji/color of any
//  category, add custom ones, delete custom ones (blocks remap to Free Time).
//

import SwiftUI
import SwiftData

struct CategoriesView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \ActivityCategory.sortOrder) private var categories: [ActivityCategory]
    @State private var editing: ActivityCategory?
    @State private var showingNew = false

    var body: some View {
        NavigationStack {
            List {
                ForEach(categories) { cat in
                    Button {
                        editing = cat
                    } label: {
                        HStack(spacing: 12) {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(cat.color)
                                .frame(width: 40, height: 40)
                                .overlay(Text(cat.emoji).font(.title3))
                            Text(cat.name)
                                .font(.system(.body, design: .rounded, weight: .bold))
                            Spacer()
                            if cat.isBuiltIn {
                                Text("Built-in")
                                    .font(.system(.caption2, design: .rounded))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
                .onDelete(perform: delete)
                .onMove(perform: move)
            }
            .scrollIndicators(.visible)
            .navigationTitle("Categories")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    EditButton()
                        .tint(.tbOrange)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showingNew = true } label: {
                        Image(systemName: "plus.circle.fill")
                    }
                    .tint(.tbOrange)
                }
            }
            .sheet(item: $editing) { cat in
                CategoryEditorSheet(category: cat)
            }
            .sheet(isPresented: $showingNew) {
                CategoryEditorSheet(category: nil)
            }
        }
    }

    /// Deleting a category remaps its blocks to Free Time (id 0) in all saved
    /// days. Built-ins can't be deleted.
    /// Persists a drag-reorder by rewriting sortOrder to match the new positions.
    /// The order applies everywhere categories are listed, including the
    /// day editor's brush palette.
    private func move(from source: IndexSet, to destination: Int) {
        var ordered = categories
        ordered.move(fromOffsets: source, toOffset: destination)
        for (index, cat) in ordered.enumerated() {
            cat.sortOrder = index
        }
        try? context.save()
    }

    private func delete(at offsets: IndexSet) {
        for index in offsets {
            let cat = categories[index]
            guard !cat.isBuiltIn else { continue }
            CategorySeeder.remapBlocks(from: UInt8(cat.id), to: 0, in: context)
            context.delete(cat)
        }
        try? context.save()
    }
}

// MARK: - Editor sheet

private struct CategoryEditorSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \ActivityCategory.sortOrder) private var categories: [ActivityCategory]

    let category: ActivityCategory?   // nil = create new
    @State private var name = ""
    @State private var emoji = "🎯"
    @State private var color = Color.tbOrange
    @State private var customEmoji = ""

    /// Curated picks that read well at grid-cell size.
    private static let emojiChoices: [String] = [
        "🎯", "🎵", "🎸", "🎹", "🥁", "🎤", "🎧",
        "🎨", "🎭", "🩰", "🎬", "📷", "🧶", "🪄",
        "⚽️", "🏀", "🏈", "⚾️", "🎾", "🏐", "🏒",
        "🏊", "🚴", "🤸", "🛹", "⛸️", "🥋", "🏃",
        "📚", "✏️", "📝", "🧮", "🔬", "🧪", "💻",
        "📱", "🎮", "🕹️", "📺", "🎲", "♟️", "🧩",
        "🛁", "🚿", "🧼", "🛏️", "💤", "⏰", "🧹",
        "🍽️", "🍎", "🥪", "🍕", "🧁", "🛒", "🐶",
        "👨‍👩‍👧‍👦", "🧑‍🤝‍🧑", "❤️", "🌈", "⭐️", "🌙", "☀️",
        "🚌", "🚗", "✈️", "⛪️", "🕍", "🕌", "🧸",
    ]

    var body: some View {
        NavigationStack {
            Form {
                TextField("Name", text: $name)
                    .font(.system(.body, design: .rounded, weight: .bold))
                ColorPicker("Color", selection: $color, supportsOpacity: false)

                Section {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 7), spacing: 6) {
                        ForEach(Self.emojiChoices, id: \.self) { choice in
                            Button {
                                emoji = choice
                            } label: {
                                Text(choice)
                                    .font(.title2)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 5)
                                    .background(
                                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                                            .fill(emoji == choice ? color.opacity(0.35) : .clear)
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                                            .stroke(emoji == choice ? Color.tbOrange : .clear, lineWidth: 2)
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    HStack {
                        Text("Or type any emoji")
                            .foregroundStyle(.secondary)
                        Spacer()
                        TextField("😀", text: $customEmoji)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 60)
                            .onChange(of: customEmoji) { _, newValue in
                                // Accept only actual emoji characters; ignore plain text
                                if let lastEmoji = newValue.reversed().first(where: \.isEmojiLike) {
                                    emoji = String(lastEmoji)
                                    customEmoji = String(lastEmoji)
                                } else if !newValue.isEmpty {
                                    customEmoji = ""
                                }
                            }
                    }
                } header: {
                    HStack {
                        Text("Emoji")
                        Spacer()
                        Text(emoji)
                            .font(.title3)
                    }
                }
            }
            .navigationTitle(category == nil ? "New Category" : "Edit Category")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { saveAndDismiss() }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear {
                if let category {
                    name = category.name
                    emoji = category.emoji
                    color = category.color
                }
            }
        }
        .presentationDetents([.large])
    }

    private func saveAndDismiss() {
        if let category {
            category.name = name
            category.emoji = emoji
            category.colorHex = color.hexString
        } else {
            let nextID = (categories.map(\.id).max() ?? 11) + 1
            guard nextID <= 255 else { return }
            context.insert(ActivityCategory(
                id: nextID, name: name, emoji: emoji,
                colorHex: color.hexString, sortOrder: nextID
            ))
        }
        try? context.save()
        dismiss()
    }
}

private extension Character {
    /// True for characters that render as emoji (excludes plain digits/letters
    /// that technically carry the emoji property).
    var isEmojiLike: Bool {
        guard let first = unicodeScalars.first else { return false }
        return first.properties.isEmojiPresentation
            || unicodeScalars.contains { $0.properties.isEmojiPresentation }
            || (first.properties.isEmoji && first.value >= 0x1F000)
    }
}
