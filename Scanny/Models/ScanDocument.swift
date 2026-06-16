import UIKit

/// A scanned document: an ordered set of page image files plus metadata.
/// The image bytes live on disk inside the document's folder; this struct is
/// the persisted `meta.json`.
///
/// Cropping is **non-destructive**: `pageFiles` holds the original (uncropped)
/// source photos, and `cropCorners` holds the crop quad per file. The displayed
/// / exported page is the source cropped by its corners, so re-cropping can
/// always recover content.
struct ScanDocument: Identifiable, Codable, Equatable, Hashable {
    let id: UUID
    var title: String
    var createdAt: Date
    var modifiedAt: Date
    /// Default filter for new pages / fallback for pages without an override.
    var filter: ScanFilter
    /// Relative filenames of the source page images, in display order.
    var pageFiles: [String]
    /// Crop quad per file: normalised, top-left origin, `[TL, TR, BR, BL]`.
    /// Absent = use the whole image (e.g. camera scans, already cropped).
    var cropCorners: [String: [CGPoint]]
    /// Per-page filter override, keyed by filename. Absent = use `filter`.
    var pageFilters: [String: ScanFilter]
    /// Default B&W brightness/contrast for new pages / fallback for pages
    /// without an override.
    var bw: BWAdjustment
    /// Per-page B&W adjustment override, keyed by filename. Absent = use `bw`.
    var pageBW: [String: BWAdjustment]
    /// Cached recognised text from the most recent PDF export, if any.
    var ocrText: String?

    init(id: UUID = UUID(),
         title: String,
         createdAt: Date = Date(),
         filter: ScanFilter = .bw,
         pageFiles: [String] = [],
         cropCorners: [String: [CGPoint]] = [:],
         pageFilters: [String: ScanFilter] = [:],
         bw: BWAdjustment = .default,
         pageBW: [String: BWAdjustment] = [:],
         ocrText: String? = nil) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.modifiedAt = createdAt
        self.filter = filter
        self.pageFiles = pageFiles
        self.cropCorners = cropCorners
        self.pageFilters = pageFilters
        self.bw = bw
        self.pageBW = pageBW
        self.ocrText = ocrText
    }

    var pageCount: Int { pageFiles.count }

    /// The effective filter for a given page file (override or document default).
    func filter(forFile filename: String) -> ScanFilter {
        pageFilters[filename] ?? filter
    }

    /// The effective B&W adjustment for a given page file (override or default).
    func bwAdjustment(forFile filename: String) -> BWAdjustment {
        pageBW[filename] ?? bw
    }

    /// Backwards/robustness: tolerate older `meta.json` without the new fields.
    enum CodingKeys: String, CodingKey {
        case id, title, createdAt, modifiedAt, filter, pageFiles, cropCorners
        case pageFilters, bw, pageBW, ocrText
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        modifiedAt = try c.decode(Date.self, forKey: .modifiedAt)
        filter = (try? c.decode(ScanFilter.self, forKey: .filter)) ?? .original
        pageFiles = try c.decode([String].self, forKey: .pageFiles)
        cropCorners = (try? c.decode([String: [CGPoint]].self, forKey: .cropCorners)) ?? [:]
        pageFilters = (try? c.decode([String: ScanFilter].self, forKey: .pageFilters)) ?? [:]
        bw = (try? c.decode(BWAdjustment.self, forKey: .bw)) ?? .default
        pageBW = (try? c.decode([String: BWAdjustment].self, forKey: .pageBW)) ?? [:]
        ocrText = try? c.decode(String.self, forKey: .ocrText)
    }
}

/// A page being added to a document: a source image plus an optional crop quad.
struct PageInput {
    let image: UIImage
    /// Normalised top-left corners `[TL, TR, BR, BL]`, or nil for the whole image.
    let corners: [CGPoint]?
}
