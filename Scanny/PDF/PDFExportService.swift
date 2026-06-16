import UIKit

/// Produces a searchable PDF on disk for a document, doing the heavy image
/// processing and OCR off the main actor.
enum PDFExportService {
    enum ExportError: Error { case noPages, renderFailed }

    /// Renders the document to a PDF file and returns its URL.
    /// Also caches the recognised text back onto the document.
    @MainActor
    static func export(_ document: ScanDocument, store: DocumentStore) async throws -> URL {
        let pageInputs: [(image: UIImage, filter: ScanFilter, bw: BWAdjustment)] =
            document.pageFiles.enumerated().compactMap { index, filename in
                guard let image = store.loadPageImage(document, page: index) else { return nil }
                return (image, document.filter(forFile: filename), document.bwAdjustment(forFile: filename))
            }
        guard !pageInputs.isEmpty else { throw ExportError.noPages }
        let title = document.title

        let result = await Task.detached(priority: .userInitiated) { () -> (data: Data, text: String) in
            var pages: [PDFBuilder.Page] = []
            var transcript: [String] = []
            for input in pageInputs {
                let processed = ImageProcessor.process(input.image, filter: input.filter, bw: input.bw)
                let lines = TextRecognizer.recognize(processed)
                pages.append(PDFBuilder.Page(image: processed, lines: lines))
                let pageText = lines.map(\.text).joined(separator: "\n")
                if !pageText.isEmpty { transcript.append(pageText) }
            }
            let data = PDFBuilder.build(pages: pages, title: title)
            return (data, transcript.joined(separator: "\n\n"))
        }.value

        guard !result.data.isEmpty else { throw ExportError.renderFailed }

        let url = exportsDirectory().appendingPathComponent(filename(for: title))
        try? FileManager.default.removeItem(at: url)
        try result.data.write(to: url, options: .atomic)

        store.updateOCRText(result.text.isEmpty ? nil : result.text, for: document)
        return url
    }

    // MARK: - Helpers

    private static func exportsDirectory() -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("Exports", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private static func filename(for title: String) -> String {
        let allowed = CharacterSet(charactersIn:
            "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789 -_")
        let cleaned = String(title.unicodeScalars.filter { allowed.contains($0) })
            .trimmingCharacters(in: .whitespaces)
        let base = cleaned.isEmpty ? "Scan" : cleaned
        return "\(base).pdf"
    }
}
