import SwiftUI
import VisionKit

struct DocumentDetailView: View {
    @Environment(DocumentStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let documentID: UUID

    @State private var selectedFilter: ScanFilter = .original
    @State private var bwAdjustment: BWAdjustment = .default
    @State private var processedPages: [String: UIImage] = [:]
    @State private var currentPage = 0
    @State private var bwRendering = false
    @State private var bwPending: BWAdjustment?
    @State private var bwCommitTask: Task<Void, Never>?

    @State private var isExporting = false
    @State private var activeSheet: Sheet?
    @State private var activeCover: Cover?

    @State private var showRename = false
    @State private var renameText = ""
    @State private var showDeleteConfirm = false
    @State private var showApplyAllConfirm = false
    @State private var didConfigure = false

    private enum Sheet: Identifiable {
        case share(URL), editPages, photos
        var id: Int { switch self { case .share: 0; case .editPages: 1; case .photos: 2 } }
    }
    private enum Cover: Identifiable {
        case camera, crop([UIImage]), recrop(Int)
        var id: Int { switch self { case .camera: 0; case .crop: 1; case .recrop: 2 } }
    }

    private var document: ScanDocument? { store.document(withID: documentID) }

    var body: some View {
        Group {
            if let document {
                content(for: document)
            } else {
                Color(.systemGroupedBackground)
                    .onAppear { dismiss() }
            }
        }
    }

    // MARK: - Content

    private func content(for document: ScanDocument) -> some View {
        VStack(spacing: 0) {
            pager(for: document)
            controls(for: document)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(document.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbar(for: document) }
        .overlay {
            if isExporting {
                ProcessingOverlay(text: "Creating PDF…")
            }
        }
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .share(let url):
                ShareSheet(items: [url])
            case .editPages:
                EditPagesView(documentID: documentID)
                    .environment(store)
            case .photos:
                PhotoPicker { images in
                    activeSheet = nil
                    beginPhotoImport(images)
                } onCancel: {
                    activeSheet = nil
                }
                .ignoresSafeArea()
            }
        }
        .fullScreenCover(item: $activeCover) { cover in
            coverContent(cover)
        }
        .alert("Rename Scan", isPresented: $showRename) {
            TextField("Name", text: $renameText)
            Button("Cancel", role: .cancel) {}
            Button("Save") { store.rename(document, to: renameText) }
        }
        .alert("Delete this scan?", isPresented: $showDeleteConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                store.delete(document)
                dismiss()
            }
        } message: {
            Text("This permanently removes the scan and its pages.")
        }
        .confirmationDialog(
            "Apply \(selectedFilter.displayName) to all \(document.pageCount) pages?",
            isPresented: $showApplyAllConfirm,
            titleVisibility: .visible
        ) {
            Button("Apply to All Pages") { applyLookToAllPages(document) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This replaces each page's filter and any per-page adjustments.")
        }
        .task(id: documentID) { configureIfNeeded(document) }
        .onChange(of: document.pageFiles) { _, _ in regenerate() }
        .onChange(of: currentPage) { _, _ in syncControlsToCurrentPage() }
    }

    @ViewBuilder
    private func coverContent(_ cover: Cover) -> some View {
        switch cover {
        case .camera:
            ScanCameraView { results in
                activeCover = nil
                addScannedPages(results)
            } onCancel: {
                activeCover = nil
            }
            .ignoresSafeArea()
        case .crop(let images):
            CropFlowView(images: images) { results in
                activeCover = nil
                addCroppedPages(results)
            } onCancel: {
                activeCover = nil
            }
        case .recrop(let index):
            if let document, let source = store.loadSource(document, page: index) {
                CropEditorView(
                    original: source,
                    initialCorners: store.cropCorners(document, page: index),
                    pageLabel: "Crop Page \(index + 1)",
                    isLast: true,
                    doneTitle: "Apply",
                    onDone: { result in
                        activeCover = nil
                        store.updatePageCrop(document, page: index, source: result.source, corners: result.corners)
                        processedPages.removeAll()
                        regenerate()
                    },
                    onCancel: { activeCover = nil }
                )
            } else {
                Color.black.onAppear { activeCover = nil }
            }
        }
    }

    private func pager(for document: ScanDocument) -> some View {
        TabView(selection: $currentPage) {
            ForEach(Array(document.pageFiles.enumerated()), id: \.element) { index, filename in
                PageImageView(image: processedPages[filename])
                    .tag(index)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
            }
            // Always-present trailing card to add another page.
            AddPageCard(
                isFirst: document.pageFiles.isEmpty,
                onCamera: { activeCover = .camera },
                onImport: { activeSheet = .photos }
            )
            .tag(document.pageCount)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .tabViewStyle(.page(indexDisplayMode: document.pageCount >= 1 ? .always : .never))
        .indexViewStyle(.page(backgroundDisplayMode: .interactive))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// True when the trailing "add page" card is the current slide.
    private var isOnAddCard: Bool {
        guard let document else { return true }
        return currentPage >= document.pageCount
    }

    private func controls(for document: ScanDocument) -> some View {
        let onAddCard = isOnAddCard
        let hasPages = document.pageCount > 0

        return VStack(spacing: 10) {
            if !onAddCard {
                Picker("Filter", selection: $selectedFilter) {
                    ForEach(ScanFilter.allCases) { filter in
                        Text(filter.displayName).tag(filter)
                    }
                }
                .pickerStyle(.segmented)
                .onChange(of: selectedFilter) { _, newValue in
                    guard document.pageFiles.indices.contains(currentPage) else { return }
                    let filename = document.pageFiles[currentPage]
                    guard document.filter(forFile: filename) != newValue else { return }
                    store.setFilter(newValue, forPage: currentPage, in: document)
                    processedPages[filename] = nil
                    regenerate()
                }
                .transition(.opacity)

                if selectedFilter == .bw {
                    bwSliders(for: document)
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                }

                if document.pageCount > 1 {
                    HStack {
                        Spacer()
                        Button {
                            showApplyAllConfirm = true
                        } label: {
                            Label("Apply to All Pages", systemImage: "square.stack.3d.up")
                                .font(.caption)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                    .transition(.opacity)
                }
            }

            if !onAddCard || hasPages {
                HStack(spacing: 12) {
                    if !onAddCard {
                        Button {
                            activeCover = .recrop(currentPage)
                        } label: {
                            Label("Crop", systemImage: "crop")
                                .font(.callout)
                        }
                        .buttonStyle(.bordered)
                        .transition(.opacity)
                    }

                    Spacer()

                    if hasPages {
                        Button {
                            exportAndShare(document)
                        } label: {
                            Label("Share PDF", systemImage: "square.and.arrow.up")
                                .font(.callout.weight(.semibold))
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(isExporting)
                    }
                }
            }

            Text(footerText(for: document, onAddCard: onAddCard))
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity)
        .background(.bar)
        .animation(.smooth(duration: 0.28), value: onAddCard)
        .animation(.smooth(duration: 0.28), value: selectedFilter)
    }

    private func bwSliders(for document: ScanDocument) -> some View {
        VStack(spacing: 4) {
            adjustmentSlider("Brightness", value: $bwAdjustment.brightness,
                             range: BWAdjustment.brightnessRange)
            adjustmentSlider("Contrast", value: $bwAdjustment.contrast,
                             range: BWAdjustment.contrastRange)
            HStack {
                Spacer()
                Button("Reset to Default") { bwAdjustment = .default }
                    .font(.caption)
                    .disabled(bwAdjustment == .default)
            }
        }
        .onChange(of: bwAdjustment) { _, newValue in
            guard document.pageFiles.indices.contains(currentPage) else { return }
            let filename = document.pageFiles[currentPage]
            guard document.bwAdjustment(forFile: filename) != newValue else { return }
            livePreview(for: document)
        }
    }

    private func footerText(for document: ScanDocument, onAddCard: Bool) -> String {
        guard document.pageCount > 0 else { return "Add a page to get started" }
        let count = Formatters.pageCountLabel(document.pageCount)
        return onAddCard ? "\(count) · add another page" : "\(count) · searchable PDF"
    }

    private func adjustmentSlider(_ title: String, value: Binding<Double>,
                                  range: ClosedRange<Double>) -> some View {
        HStack(spacing: 10) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 74, alignment: .leading)
            Slider(value: value, in: range)
        }
    }

    @ToolbarContentBuilder
    private func toolbar(for document: ScanDocument) -> some ToolbarContent {
        ToolbarItem(placement: .principal) {
            Button {
                renameText = document.title
                showRename = true
            } label: {
                HStack(spacing: 4) {
                    Text(document.title)
                        .font(.headline)
                        .lineLimit(1)
                    Image(systemName: "pencil")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .foregroundStyle(.primary)
            }
            .accessibilityLabel("Rename PDF")
        }
        ToolbarItem(placement: .primaryAction) {
            Menu {
                if VNDocumentCameraViewController.isSupported {
                    Button {
                        activeCover = .camera
                    } label: {
                        Label("Add from Camera", systemImage: "camera.viewfinder")
                    }
                }
                Button {
                    activeSheet = .photos
                } label: {
                    Label("Add from Photos", systemImage: "photo.on.rectangle")
                }
                Button {
                    activeSheet = .editPages
                } label: {
                    Label("Reorder / Delete Pages", systemImage: "square.grid.2x2")
                }
                Button {
                    renameText = document.title
                    showRename = true
                } label: {
                    Label("Rename PDF", systemImage: "pencil")
                }
                Divider()
                Button(role: .destructive) {
                    showDeleteConfirm = true
                } label: {
                    Label("Delete PDF", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
        }
    }

    // MARK: - Logic

    private func configureIfNeeded(_ document: ScanDocument) {
        guard !didConfigure else { return }
        didConfigure = true
        syncControlsToCurrentPage()
        regenerate()
    }

    /// Point the filter picker and B&W sliders at the page now on screen.
    private func syncControlsToCurrentPage() {
        guard let document, document.pageFiles.indices.contains(currentPage) else { return }
        let filename = document.pageFiles[currentPage]
        selectedFilter = document.filter(forFile: filename)
        bwAdjustment = document.bwAdjustment(forFile: filename)
    }

    /// Generates screen-resolution processed images for any page that isn't
    /// already cached, each using its own per-page filter + B&W adjustment.
    private func regenerate() {
        guard let document else { return }
        // Valid indices are 0...pageCount (the last being the add-page card).
        if currentPage > document.pageCount {
            currentPage = document.pageCount
        }
        for (index, filename) in document.pageFiles.enumerated() where processedPages[filename] == nil {
            let filter = document.filter(forFile: filename)
            let bw = document.bwAdjustment(forFile: filename)
            Task {
                guard let page = store.loadPageImage(document, page: index) else { return }
                let processed = await Task.detached(priority: .userInitiated) {
                    ImageProcessor.processedThumbnail(page, filter: filter, bw: bw, maxDimension: 1800)
                }.value
                // Drop stale renders if this page's settings changed meanwhile.
                guard let latest = store.document(withID: documentID),
                      latest.filter(forFile: filename) == filter,
                      latest.bwAdjustment(forFile: filename) == bw else { return }
                processedPages[filename] = processed
            }
        }
    }

    /// Live B&W preview: re-render the visible page on every slider change
    /// (serialised so renders don't pile up), and persist the adjustment for
    /// that page shortly after the user stops adjusting.
    private func livePreview(for document: ScanDocument) {
        guard selectedFilter == .bw else { return }
        bwPending = bwAdjustment
        if !bwRendering { renderPending(for: document) }

        bwCommitTask?.cancel()
        let bw = bwAdjustment
        let index = currentPage
        bwCommitTask = Task {
            try? await Task.sleep(for: .milliseconds(300))
            if Task.isCancelled { return }
            store.setBWAdjustment(bw, forPage: index, in: document)
        }
    }

    private func renderPending(for document: ScanDocument) {
        guard let bw = bwPending, document.pageFiles.indices.contains(currentPage) else { return }
        bwPending = nil
        bwRendering = true
        let index = currentPage
        let filename = document.pageFiles[index]
        let source = store.loadPageImage(document, page: index)
        Task {
            let processed: UIImage? = await Task.detached(priority: .userInitiated) {
                guard let source else { return nil }
                return ImageProcessor.processedThumbnail(source, filter: .bw, bw: bw, maxDimension: 1600)
            }.value
            bwRendering = false
            if let processed, selectedFilter == .bw {
                processedPages[filename] = processed
            }
            if bwPending != nil {
                renderPending(for: document)
            }
        }
    }

    /// Camera scans carry their auto-detected crop quad; store it non-destructively.
    private func addScannedPages(_ results: [CropResult]) {
        guard let document, !results.isEmpty else { return }
        let firstNew = document.pageCount
        Task {
            try? await Task.sleep(for: .milliseconds(300))
            store.addPages(results.map { PageInput(image: $0.source, corners: $0.corners) }, to: document)
            regenerate()
            withAnimation { currentPage = firstNew }
        }
    }

    /// Imported photos go through the manual crop editor first.
    private func beginPhotoImport(_ images: [UIImage]) {
        guard !images.isEmpty else { return }
        Task {
            try? await Task.sleep(for: .milliseconds(350))
            activeCover = .crop(images)
        }
    }

    private func addCroppedPages(_ results: [CropResult]) {
        guard let document, !results.isEmpty else { return }
        let firstNew = document.pageCount
        Task {
            try? await Task.sleep(for: .milliseconds(300))
            store.addPages(results.map { PageInput(image: $0.source, corners: $0.corners) }, to: document)
            regenerate()
            withAnimation { currentPage = firstNew }
        }
    }

    /// Push the current page's look onto every page, then re-render them all.
    private func applyLookToAllPages(_ document: ScanDocument) {
        store.applyLookToAllPages(filter: selectedFilter, bw: bwAdjustment, in: document)
        processedPages.removeAll()
        regenerate()
    }

    private func exportAndShare(_ document: ScanDocument) {
        isExporting = true
        Task {
            defer { isExporting = false }
            do {
                let url = try await PDFExportService.export(document, store: store)
                activeSheet = .share(url)
            } catch {
                // Surfacing a full error UI is out of scope; keep the user in place.
            }
        }
    }
}

// MARK: - Page image

/// Shows a processed page fitted on a card, with a spinner until it's ready.
private struct PageImageView: View {
    let image: UIImage?

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.12), radius: 6, y: 2)
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .padding(6)
            } else {
                ProgressView()
            }
        }
    }
}

// MARK: - Add page card

/// The trailing slide in the pager: a dashed placeholder offering the same
/// "take photo / import" actions, so adding pages always lives in one place.
private struct AddPageCard: View {
    let isFirst: Bool
    let onCamera: () -> Void
    let onImport: () -> Void

    private let cameraAvailable = VNDocumentCameraViewController.isSupported

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(.systemBackground).opacity(0.4))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(
                            Color.secondary.opacity(0.45),
                            style: StrokeStyle(lineWidth: 1.5, dash: [7, 5]))
                )

            VStack(spacing: 18) {
                Image(systemName: "plus.viewfinder")
                    .font(.system(size: 46, weight: .light))
                    .foregroundStyle(.secondary)

                Text(isFirst ? "Add your first page" : "Add another page")
                    .font(.headline)
                    .foregroundStyle(.secondary)

                VStack(spacing: 10) {
                    if cameraAvailable {
                        Button(action: onCamera) {
                            Label("Take Photo", systemImage: "camera.viewfinder")
                                .frame(maxWidth: 220)
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    Button(action: onImport) {
                        Label("Import Photo", systemImage: "photo.on.rectangle")
                            .frame(maxWidth: 220)
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding(24)
        }
    }
}
