import SwiftUI

/// Drag to reorder is always available. "Select" enables checkmarks for multi-delete. Changes persist immediately.
struct EditPagesView: View {
    @Environment(DocumentStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let documentID: UUID

    private var document: ScanDocument? { store.document(withID: documentID) }
    @State private var isSelecting = false
    @State private var selection = Set<String>()
    @State private var showingDeleteConfirmation = false

    var body: some View {
        NavigationStack {
            Group {
                if let document, !document.pageFiles.isEmpty {
                    List {
                        ForEach(document.pageFiles, id: \.self) { filename in
                            let index = document.pageFiles.firstIndex(of: filename) ?? 0
                            EditPageRow(
                                document: document,
                                index: index,
                                isSelecting: isSelecting,
                                isSelected: selection.contains(filename)
                            ) {
                                if selection.contains(filename) {
                                    selection.remove(filename)
                                } else {
                                    selection.insert(filename)
                                }
                            }
                            .padding(.vertical, 2)
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    store.deletePage(at: index, from: document)
                                    selection.remove(filename)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                        .onMove { source, destination in
                            store.movePage(in: document, from: source, to: destination)
                        }
                    }
                    .environment(\.editMode, .constant(.active))
                } else {
                    Color(.systemGroupedBackground)
                        .onAppear { dismiss() }
                }
            }
            .navigationTitle("Edit Pages")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(isSelecting ? "Cancel" : "Select") {
                        isSelecting.toggle()
                        if !isSelecting { selection.removeAll() }
                    }
                }
                ToolbarItem(placement: .bottomBar) {
                    HStack {
                        Spacer()
                        Button(role: .destructive) {
                            showingDeleteConfirmation = true
                        } label: {
                            Image(systemName: "trash")
                        }
                        .disabled(!isSelecting || selection.isEmpty)
                        .confirmationDialog("Delete selected pages?", isPresented: $showingDeleteConfirmation, titleVisibility: .visible) {
                            Button("Delete \(selection.count) Page\(selection.count == 1 ? "" : "s")", role: .destructive) {
                                deleteSelected()
                            }
                            Button("Cancel", role: .cancel) {}
                        } message: {
                            Text("Are you sure you want to delete the selected page\(selection.count == 1 ? "" : "s")? This cannot be undone.")
                        }
                        Spacer()
                    }
                }
            }
        }
    }

    private func deleteSelected() {
        guard let document else { return }
        let indicesToDelete = document.pageFiles.enumerated()
            .filter { selection.contains($0.element) }
            .map { $0.offset }
            .sorted(by: >)

        for index in indicesToDelete {
            store.deletePage(at: index, from: document)
        }
        selection.removeAll()
        isSelecting = false
    }
}

struct EditPageRow: View {
    let document: ScanDocument
    let index: Int
    let isSelecting: Bool
    let isSelected: Bool
    let onToggle: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            if isSelecting {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? Color.accentColor : Color(UIColor.tertiaryLabel))
                    .font(.title3)
            }
            DocumentThumbnail(document: document, side: 48, page: index)
            Text("Page \(index + 1)")
                .font(.body)
            Spacer()
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if isSelecting { onToggle() }
        }
    }
}
