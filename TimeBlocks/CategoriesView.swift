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
            }
            .navigationTitle("Categories")
            .toolbar {
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
    private func delete(at offsets: IndexSet) {
        for index in offsets {
            let cat = categories[index]
            guard !cat.isBuiltIn else { continue }
            let id = UInt8(cat.id)
            let all = (try? context.fetch(FetchDescriptor<DaySchedule>())) ?? []
            for schedule in all {
                var bytes = [UInt8](schedule.blocks)
                guard bytes.contains(id) else { continue }
                for i in bytes.indices where bytes[i] == id { bytes[i] = 0 }
                schedule.blocks = Data(bytes)
            }
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

    var body: some View {
        NavigationStack {
            Form {
                TextField("Name", text: $name)
                    .font(.system(.body, design: .rounded, weight: .bold))
                HStack {
                    Text("Emoji")
                    Spacer()
                    TextField("", text: $emoji)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 60)
                        .onChange(of: emoji) { _, newValue in
                            // Keep only the most recent single character
                            if let last = newValue.last { emoji = String(last) }
                        }
                }
                ColorPicker("Color", selection: $color, supportsOpacity: false)
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
        .presentationDetents([.medium])
    }

    private func saveAndDismiss() {
        if let category {
            category.name = name
            category.emoji = emoji
            category.colorHex = color.hexString
        } else {
            let nextID = (categories.map(\.id).max() ?? 6) + 1
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
