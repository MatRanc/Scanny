import SwiftUI
import UIKit

/// Owns the on-disk library of scanned documents and the in-memory list the UI
/// observes. All page bytes live under `Documents/Scans/<doc-id>/`.
///
/// Pages are stored as their **original (uncropped) source** images; the crop is
/// applied on the fly from `ScanDocument.cropCorners`, so cropping is
/// non-destructive and re-editable.
@MainActor
@Observable
final class DocumentStore {
    private(set) var documents: [ScanDocument] = []

    private let fileManager = FileManager.default
    private let sourceCache = NSCache<NSString, UIImage>()   // raw source images
    private let pageCache = NSCache<NSString, UIImage>()     // source cropped by corners

    init() {
        sourceCache.countLimit = 60
        pageCache.countLimit = 60
        try? fileManager.createDirectory(at: scansRoot, withIntermediateDirectories: true)
        load()
    }

    // MARK: - Locations

    private var scansRoot: URL {
        let docs = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent("Scans", isDirectory: true)
    }

    func directory(for document: ScanDocument) -> URL {
        scansRoot.appendingPathComponent(document.id.uuidString, isDirectory: true)
    }

    func fileURL(for document: ScanDocument, page index: Int) -> URL? {
        guard document.pageFiles.indices.contains(index) else { return nil }
        return directory(for: document).appendingPathComponent(document.pageFiles[index])
    }

    // MARK: - Loading

    private func load() {
        guard let dirs = try? fileManager.contentsOfDirectory(
            at: scansRoot, includingPropertiesForKeys: nil) else { return }
        var loaded: [ScanDocument] = []
        for dir in dirs where dir.hasDirectoryPath {
            let metaURL = dir.appendingPathComponent("meta.json")
            guard let data = try? Data(contentsOf: metaURL),
                  var doc = try? JSONDecoder().decode(ScanDocument.self, from: data)
            else { continue }
            // Drop never-finished drafts (created but no page ever added).
            guard !doc.pageFiles.isEmpty else {
                try? fileManager.removeItem(at: dir)
                continue
            }
            // Backfill explicit per-page looks for documents saved before pages
            // carried their own override. Values are identical to today's resolved
            // look, but pinning them keeps pages independent going forward.
            for filename in doc.pageFiles {
                if doc.pageFilters[filename] == nil { doc.pageFilters[filename] = doc.filter(forFile: filename) }
                if doc.pageBW[filename] == nil { doc.pageBW[filename] = doc.bwAdjustment(forFile: filename) }
            }
            loaded.append(doc)
        }
        documents = loaded.sorted { $0.modifiedAt > $1.modifiedAt }
    }

    /// Remove any documents that have no pages (abandoned drafts).
    func purgeEmptyDocuments() {
        for doc in documents where doc.pageFiles.isEmpty {
            delete(doc)
        }
    }

    // MARK: - Mutations

    @discardableResult
    func createDocument(title: String, pages: [PageInput], filter: ScanFilter) -> ScanDocument {
        var doc = ScanDocument(title: title, filter: filter)
        try? fileManager.createDirectory(at: directory(for: doc), withIntermediateDirectories: true)
        write(pages, into: &doc)
        persist(doc)
        documents.insert(doc, at: 0)
        return doc
    }

    func addPages(_ pages: [PageInput], to document: ScanDocument) {
        guard var doc = current(document) else { return }
        write(pages, into: &doc)
        touch(&doc)
        replace(doc)
    }

    func deletePage(at index: Int, from document: ScanDocument) {
        guard var doc = current(document), doc.pageFiles.indices.contains(index) else { return }
        let filename = doc.pageFiles.remove(at: index)
        doc.cropCorners[filename] = nil
        doc.pageFilters[filename] = nil
        doc.pageBW[filename] = nil
        try? fileManager.removeItem(at: directory(for: doc).appendingPathComponent(filename))
        invalidate(filename)
        if doc.pageFiles.isEmpty {
            delete(doc)
        } else {
            touch(&doc)
            replace(doc)
        }
    }

    func movePage(in document: ScanDocument, from source: IndexSet, to destination: Int) {
        guard var doc = current(document) else { return }
        doc.pageFiles.move(fromOffsets: source, toOffset: destination)
        touch(&doc)
        replace(doc)
    }

    /// Re-crop: overwrite the page's source (rotation may have changed it) and
    /// store the new crop quad.
    func updatePageCrop(_ document: ScanDocument, page index: Int,
                        source: UIImage, corners: [CGPoint]) {
        guard var doc = current(document), doc.pageFiles.indices.contains(index) else { return }
        let filename = doc.pageFiles[index]
        let normalized = source.normalizedUp().downscaled(maxDimension: 2600)
        if let data = normalized.jpegData(compressionQuality: 0.9) {
            try? data.write(to: directory(for: doc).appendingPathComponent(filename), options: .atomic)
        }
        doc.cropCorners[filename] = corners
        invalidate(filename)
        touch(&doc)
        replace(doc)
    }

    /// Set the filter for a single page. Also remembered as the document
    /// default so subsequently added pages inherit the last-used look.
    func setFilter(_ filter: ScanFilter, forPage index: Int, in document: ScanDocument) {
        guard var doc = current(document), doc.pageFiles.indices.contains(index) else { return }
        let filename = doc.pageFiles[index]
        guard doc.pageFilters[filename] != filter else { return }
        doc.pageFilters[filename] = filter
        doc.filter = filter
        touch(&doc)
        replace(doc)
    }

    /// Set the B&W adjustment for a single page. Also remembered as the
    /// document default for subsequently added pages.
    func setBWAdjustment(_ bw: BWAdjustment, forPage index: Int, in document: ScanDocument) {
        guard var doc = current(document), doc.pageFiles.indices.contains(index) else { return }
        let filename = doc.pageFiles[index]
        guard doc.pageBW[filename] != bw else { return }
        doc.pageBW[filename] = bw
        doc.bw = bw
        touch(&doc)
        replace(doc)
    }

    /// Apply one look (filter + B&W adjustment) to every page, overwriting any
    /// per-page overrides, and make it the document default for future pages.
    func applyLookToAllPages(filter: ScanFilter, bw: BWAdjustment, in document: ScanDocument) {
        guard var doc = current(document), !doc.pageFiles.isEmpty else { return }
        doc.filter = filter
        doc.bw = bw
        for filename in doc.pageFiles {
            doc.pageFilters[filename] = filter
            doc.pageBW[filename] = bw
        }
        touch(&doc)
        replace(doc)
    }

    func rename(_ document: ScanDocument, to title: String) {
        guard var doc = current(document) else { return }
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        doc.title = trimmed.isEmpty ? doc.title : trimmed
        touch(&doc)
        replace(doc)
    }

    func updateOCRText(_ text: String?, for document: ScanDocument) {
        guard var doc = current(document) else { return }
        doc.ocrText = text
        persist(doc)
        if let idx = documents.firstIndex(where: { $0.id == doc.id }) {
            documents[idx] = doc
        }
    }

    func delete(_ document: ScanDocument) {
        try? fileManager.removeItem(at: directory(for: document))
        documents.removeAll { $0.id == document.id }
        sourceCache.removeAllObjects()
        pageCache.removeAllObjects()
    }

    // MARK: - Reading images

    /// The raw, uncropped source for a page (used by the crop editor).
    func loadSource(_ document: ScanDocument, page index: Int) -> UIImage? {
        guard let url = fileURL(for: document, page: index) else { return nil }
        let key = "src:\(url.lastPathComponent)" as NSString
        if let cached = sourceCache.object(forKey: key) { return cached }
        guard let image = UIImage(contentsOfFile: url.path) else { return nil }
        sourceCache.setObject(image, forKey: key)
        return image
    }

    /// The page as displayed/exported: source cropped by its corners (cached).
    func loadPageImage(_ document: ScanDocument, page index: Int) -> UIImage? {
        guard document.pageFiles.indices.contains(index) else { return nil }
        let filename = document.pageFiles[index]
        let corners = document.cropCorners[filename]
        let key = cacheKey(filename, corners) as NSString
        if let cached = pageCache.object(forKey: key) { return cached }
        guard let source = loadSource(document, page: index) else { return nil }
        let result = corners.map { DocumentDetector.crop(source, normalizedCorners: $0) } ?? source
        pageCache.setObject(result, forKey: key)
        return result
    }

    func cropCorners(_ document: ScanDocument, page index: Int) -> [CGPoint]? {
        guard document.pageFiles.indices.contains(index) else { return nil }
        return document.cropCorners[document.pageFiles[index]]
    }

    func current(_ document: ScanDocument) -> ScanDocument? {
        documents.first { $0.id == document.id }
    }

    func document(withID id: UUID) -> ScanDocument? {
        documents.first { $0.id == id }
    }

    // MARK: - Private helpers

    private func write(_ pages: [PageInput], into document: inout ScanDocument) {
        let dir = directory(for: document)
        for page in pages {
            let normalized = page.image.normalizedUp().downscaled(maxDimension: 2600)
            guard let data = normalized.jpegData(compressionQuality: 0.9) else { continue }
            let name = "\(UUID().uuidString).jpg"
            try? data.write(to: dir.appendingPathComponent(name), options: .atomic)
            document.pageFiles.append(name)
            if let corners = page.corners {
                document.cropCorners[name] = corners
            }
            // Stamp the current defaults as this page's explicit look so it stays
            // independent — later changes to the document default (a template for
            // *future* pages) never retroactively alter existing pages.
            document.pageFilters[name] = document.filter
            document.pageBW[name] = document.bw
        }
    }

    private func cacheKey(_ filename: String, _ corners: [CGPoint]?) -> String {
        guard let corners else { return filename }
        let sig = corners.map { "\(Int($0.x * 1000)),\(Int($0.y * 1000))" }.joined(separator: ";")
        return "\(filename)|\(sig)"
    }

    private func invalidate(_ filename: String) {
        sourceCache.removeObject(forKey: "src:\(filename)" as NSString)
        pageCache.removeAllObjects()   // page keys embed corners; simplest to clear
    }

    private func persist(_ document: ScanDocument) {
        let url = directory(for: document).appendingPathComponent("meta.json")
        if let data = try? JSONEncoder().encode(document) {
            try? data.write(to: url, options: .atomic)
        }
    }

    private func touch(_ document: inout ScanDocument) {
        document.modifiedAt = Date()
    }

    private func replace(_ document: ScanDocument) {
        persist(document)
        if let idx = documents.firstIndex(where: { $0.id == document.id }) {
            documents.remove(at: idx)
        }
        documents.insert(document, at: 0)
    }
}
