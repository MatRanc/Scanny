import SwiftUI

/// Reorder and delete pages. Editing is always on; changes persist immediately.
struct EditPagesView: View {
    @Environment(DocumentStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let documentID: UUID

    private var document: ScanDocument? { store.document(withID: documentID) }

    var body: some View {
        NavigationStack {
            Group {
                if let document, !document.pageFiles.isEmpty {
                    List {
                        ForEach(Array(document.pageFiles.enumerated()), id: \.element) { index, _ in
                            HStack(spacing: 14) {
                                DocumentThumbnail(document: document, side: 48, page: index)
                                Text("Page \(index + 1)")
                                    .font(.body)
                            }
                            .padding(.vertical, 2)
                        }
                        .onMove { source, destination in
                            store.movePage(in: document, from: source, to: destination)
                        }
                        .onDelete { offsets in
                            for index in offsets.sorted(by: >) {
                                store.deletePage(at: index, from: document)
                            }
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
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
