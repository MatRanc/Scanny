import SwiftUI

/// A rounded cover thumbnail that renders the document's first page with its
/// current filter applied.
struct DocumentThumbnail: View {
    @Environment(DocumentStore.self) private var store
    let document: ScanDocument
    var side: CGFloat = 54
    var page: Int = 0

    @State private var image: UIImage?

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(.secondarySystemBackground))
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: "doc.text.image")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: side, height: side)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color.black.opacity(0.08))
        )
        .task(id: "\(document.id)-\(page)-\(document.filter.rawValue)-\(document.modifiedAt.timeIntervalSince1970)") {
            await load()
        }
    }

    private func load() async {
        guard let pageImage = store.loadPageImage(document, page: page) else {
            image = nil
            return
        }
        let filename = document.pageFiles.indices.contains(page) ? document.pageFiles[page] : nil
        let filter = filename.map { document.filter(forFile: $0) } ?? document.filter
        let bw = filename.map { document.bwAdjustment(forFile: $0) } ?? document.bw
        let target = side * 3
        let thumb = await Task.detached(priority: .utility) {
            ImageProcessor.processedThumbnail(pageImage, filter: filter, bw: bw, maxDimension: target)
        }.value
        image = thumb
    }
}

/// Full-screen translucent overlay with a spinner and label.
struct ProcessingOverlay: View {
    let text: String

    var body: some View {
        ZStack {
            Color.black.opacity(0.35).ignoresSafeArea()
            VStack(spacing: 14) {
                ProgressView()
                    .controlSize(.large)
                    .tint(.white)
                Text(text)
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.white)
            }
            .padding(28)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .transition(.opacity)
    }
}
