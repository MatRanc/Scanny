import SwiftUI
import VisionKit

struct DocumentListView: View {
    @Environment(DocumentStore.self) private var store

    @State private var path: [ScanDocument] = []
    @State private var activeSheet: Sheet?
    @State private var activeCover: Cover?
    @State private var renameTarget: ScanDocument?
    @State private var renameText = ""

    private enum Sheet: Int, Identifiable { case photos, about; var id: Int { rawValue } }
    private enum Cover: Identifiable {
        case camera
        case crop([UIImage])
        var id: Int { switch self { case .camera: 0; case .crop: 1 } }
    }

    private var visibleDocuments: [ScanDocument] {
        store.documents.filter { $0.pageCount > 0 }
    }

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if visibleDocuments.isEmpty {
                    emptyState
                } else {
                    list
                }
            }
            .navigationTitle("Scanny")
            .toolbar { addToolbar }
            .navigationDestination(for: ScanDocument.self) { doc in
                DocumentDetailView(documentID: doc.id)
            }
            // Returning to the root clears out any abandoned empty draft.
            .onChange(of: path) { _, newPath in
                if newPath.isEmpty { store.purgeEmptyDocuments() }
            }
        }
        .task {
            #if DEBUG
            if LaunchFlags.seedSelfTest {
                await DebugSeeder.run(store: store)
            }
            if LaunchFlags.openFirst, let first = store.documents.first, path.isEmpty {
                path = [first]
            }
            if LaunchFlags.openAbout {
                activeSheet = .about
            }
            if LaunchFlags.openCrop {
                activeCover = .crop([DebugSeeder.sampleImportPhoto()])
            }
            if LaunchFlags.renderIcon {
                DebugSeeder.renderIcon()
            }
            #endif
        }
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .photos:
                PhotoPicker { images in
                    activeSheet = nil
                    beginPhotoImport(images)
                } onCancel: {
                    activeSheet = nil
                }
                .ignoresSafeArea()
            case .about:
                AboutView()
            }
        }
        .fullScreenCover(item: $activeCover) { cover in
            switch cover {
            case .camera:
                DocumentCameraView { images in
                    activeCover = nil
                    createDocumentDeferred(pages: images.map { PageInput(image: $0, corners: nil) })
                } onCancel: {
                    activeCover = nil
                }
                .ignoresSafeArea()
            case .crop(let images):
                CropFlowView(images: images) { results in
                    activeCover = nil
                    createDocumentDeferred(pages: results.map { PageInput(image: $0.source, corners: $0.corners) })
                } onCancel: {
                    activeCover = nil
                }
            }
        }
        .alert("Rename Scan", isPresented: renameBinding) {
            TextField("Name", text: $renameText)
            Button("Cancel", role: .cancel) { renameTarget = nil }
            Button("Save") {
                if let target = renameTarget { store.rename(target, to: renameText) }
                renameTarget = nil
            }
        }
    }

    // MARK: - Subviews

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No Scans Yet", systemImage: "doc.viewfinder")
        } description: {
            Text("Create a new PDF, then scan with the camera or import photos.")
        } actions: {
            Button {
                newPDF()
            } label: {
                Label("New PDF", systemImage: "plus")
                    .frame(maxWidth: 240)
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private var list: some View {
        List {
            ForEach(visibleDocuments) { doc in
                NavigationLink(value: doc) {
                    DocumentRow(document: doc)
                }
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) {
                        store.delete(doc)
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                    Button {
                        renameTarget = doc
                        renameText = doc.title
                    } label: {
                        Label("Rename", systemImage: "pencil")
                    }
                    .tint(.indigo)
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    @ToolbarContentBuilder
    private var addToolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button {
                activeSheet = .about
            } label: {
                Image(systemName: "info.circle")
            }
            .accessibilityLabel("About Scanny")
        }
        ToolbarItem(placement: .primaryAction) {
            Button {
                newPDF()
            } label: {
                Image(systemName: "plus")
                    .font(.body.weight(.semibold))
            }
            .accessibilityLabel("New PDF")
        }
    }

    private var renameBinding: Binding<Bool> {
        Binding(get: { renameTarget != nil }, set: { if !$0 { renameTarget = nil } })
    }

    // MARK: - Actions

    /// Create an empty document and open it; the editor's add-page card is
    /// where the user actually scans or imports.
    private func newPDF() {
        let doc = store.createDocument(
            title: Formatters.defaultDocumentTitle(),
            pages: [],
            filter: .bw
        )
        path.append(doc)
    }

    /// Imported photos go through the manual crop editor first.
    private func beginPhotoImport(_ images: [UIImage]) {
        guard !images.isEmpty else { return }
        Task {
            try? await Task.sleep(for: .milliseconds(350))   // let the picker dismiss
            activeCover = .crop(images)
        }
    }

    /// Creates the document after the presenting cover has dismissed, then
    /// navigates to it.
    private func createDocumentDeferred(pages: [PageInput]) {
        guard !pages.isEmpty else { return }
        Task {
            try? await Task.sleep(for: .milliseconds(300))
            let doc = store.createDocument(
                title: Formatters.defaultDocumentTitle(),
                pages: pages,
                filter: .bw
            )
            path.append(doc)
        }
    }
}

// MARK: - Row

private struct DocumentRow: View {
    let document: ScanDocument

    var body: some View {
        HStack(spacing: 14) {
            DocumentThumbnail(document: document, side: 54)
            VStack(alignment: .leading, spacing: 4) {
                Text(document.title)
                    .font(.headline)
                    .lineLimit(1)
                Text("\(Formatters.pageCountLabel(document.pageCount)) · \(Formatters.rowDate.string(from: document.modifiedAt))")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 4)
    }
}
