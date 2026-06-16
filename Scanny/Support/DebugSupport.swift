#if DEBUG
import SwiftUI
import UIKit
import PDFKit

/// Launch-time flags used to drive automated verification in the simulator.
enum LaunchFlags {
    static let seedSelfTest = ProcessInfo.processInfo.environment["SEED_SELFTEST"] == "1"
    static let openFirst = ProcessInfo.processInfo.environment["OPEN_FIRST"] == "1"
    static let openAbout = ProcessInfo.processInfo.environment["OPEN_ABOUT"] == "1"
    static let openCrop = ProcessInfo.processInfo.environment["OPEN_CROP"] == "1"
    static let renderIcon = ProcessInfo.processInfo.environment["RENDER_ICON"] == "1"
}

/// Exercises the full imaging pipeline (auto-crop → filters → OCR → searchable
/// PDF) on a synthetic angled document, writes artifacts to
/// `Documents/_selftest/` for inspection, and seeds a real document so the UI
/// has content to display. DEBUG-only.
@MainActor
enum DebugSeeder {
    static let sampleTitle = "Self-Test Sample"

    /// A synthetic "photo" (a page on a grey background) for exercising the
    /// manual crop editor in the simulator, where the photo picker can't be driven.
    static func sampleImportPhoto() -> UIImage {
        SyntheticDocument.makePhoto()
    }

    /// Renders the app icon to `Documents/_icon/AppIcon.png` using the exact
    /// same gradient + SF Symbol as the About glyph, so the two always match.
    /// Run with `RENDER_ICON=1`, then copy the PNG into the asset catalog.
    @MainActor
    static func renderIcon() {
        let icon = ZStack {
            LinearGradient(
                colors: [Color(red: 0.23, green: 0.63, blue: 1.0),
                         Color(red: 0.07, green: 0.40, blue: 0.88)],
                startPoint: .top, endPoint: .bottom)
            Image(systemName: "doc.text.viewfinder")
                .font(.system(size: 500, weight: .regular))
                .foregroundStyle(.white)
        }
        .frame(width: 1024, height: 1024)

        let renderer = ImageRenderer(content: icon)
        renderer.scale = 1
        guard let image = renderer.uiImage, let data = image.pngData() else { return }
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("_icon", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try? data.write(to: dir.appendingPathComponent("AppIcon.png"))
    }

    static func run(store: DocumentStore) async {
        let artifacts = artifactsDirectory()
        var report: [String] = []

        // 1. Build a synthetic "photo": a white page with text, rotated on a
        //    grey background, so auto-crop has real work to do.
        let photo = SyntheticDocument.makePhoto()
        save(photo, to: artifacts.appendingPathComponent("00_input.png"))

        // 2. Auto-crop / perspective-correct (the import path).
        let cropped = await Task.detached { DocumentDetector.detectAndCrop(photo) }.value
        save(cropped, to: artifacts.appendingPathComponent("01_cropped.png"))
        let croppedShrunk = cropped.pointSize.width < photo.pointSize.width * 0.95
        report.append("auto-crop reduced width: \(croppedShrunk) (\(Int(photo.pointSize.width)) -> \(Int(cropped.pointSize.width)))")

        // 3. Each scanner look.
        for filter in ScanFilter.allCases {
            let processed = ImageProcessor.process(cropped, filter: filter)
            save(processed, to: artifacts.appendingPathComponent("02_\(filter.rawValue).png"))
        }

        // 4. OCR.
        let lines = TextRecognizer.recognize(ImageProcessor.process(cropped, filter: .bw))
        let text = lines.map(\.text).joined(separator: "\n")
        try? text.write(to: artifacts.appendingPathComponent("03_ocr.txt"), atomically: true, encoding: .utf8)
        let foundInvoice = text.localizedCaseInsensitiveContains("INVOICE")
        let foundTotal = text.contains("123.45")
        report.append("ocr lines: \(lines.count)")
        report.append("ocr found 'INVOICE': \(foundInvoice)")
        report.append("ocr found '123.45': \(foundTotal)")

        // 5. Searchable PDF, verified by extracting its text layer with PDFKit.
        let pages = [PDFBuilder.Page(image: ImageProcessor.process(cropped, filter: .bw), lines: lines)]
        let pdfData = PDFBuilder.build(pages: pages, title: "Self-Test")
        try? pdfData.write(to: artifacts.appendingPathComponent("04_output.pdf"))
        let extracted = PDFDocument(data: pdfData)?.string ?? ""
        report.append("pdf bytes: \(pdfData.count)")
        report.append("pdf text layer has 'INVOICE': \(extracted.localizedCaseInsensitiveContains("INVOICE"))")

        try? report.joined(separator: "\n")
            .write(to: artifacts.appendingPathComponent("05_report.txt"), atomically: true, encoding: .utf8)

        // 6. Seed a real document for the UI (idempotent).
        let seeded: ScanDocument
        if let existing = store.documents.first(where: { $0.title == sampleTitle }) {
            seeded = existing
        } else {
            seeded = store.createDocument(title: sampleTitle,
                                          pages: [PageInput(image: cropped, corners: nil)],
                                          filter: .bw)
        }

        // 7. Exercise the exact production export path the Share button uses.
        if let url = try? await PDFExportService.export(seeded, store: store) {
            let exists = FileManager.default.fileExists(atPath: url.path)
            report.append("PDFExportService produced file: \(exists) at \(url.lastPathComponent)")
        } else {
            report.append("PDFExportService produced file: false")
        }

        // 8. Verify non-destructive crop: the stored source stays full size, and
        //    the displayed page is the cropped derivation. (Re-crop reads the source.)
        let quad = DocumentDetector.detectQuad(photo) ?? DocumentDetector.defaultCorners
        let check = store.createDocument(title: "_recrop_check",
                                         pages: [PageInput(image: photo, corners: quad)],
                                         filter: .bw)
        let sourceWidth = Int(store.loadSource(check, page: 0)?.size.width ?? 0)
        let pageWidth = Int(store.loadPageImage(check, page: 0)?.size.width ?? 0)
        report.append("non-destructive crop: source width \(sourceWidth) (full photo), cropped width \(pageWidth)")
        store.delete(check)

        try? report.joined(separator: "\n")
            .write(to: artifacts.appendingPathComponent("05_report.txt"), atomically: true, encoding: .utf8)
    }

    private static func artifactsDirectory() -> URL {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("_selftest", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private static func save(_ image: UIImage, to url: URL) {
        try? image.pngData()?.write(to: url)
    }
}

/// Renders a believable document photograph entirely in code.
private enum SyntheticDocument {
    static func makePhoto() -> UIImage {
        let page = makePage()

        let bgSize = CGSize(width: 2000, height: 2640)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: bgSize, format: format)
        return renderer.image { ctx in
            let cg = ctx.cgContext
            // Mottled grey desk background.
            let colors = [UIColor(white: 0.74, alpha: 1).cgColor,
                          UIColor(white: 0.58, alpha: 1).cgColor] as CFArray
            let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                      colors: colors, locations: [0, 1])!
            cg.drawLinearGradient(gradient,
                                  start: .zero,
                                  end: CGPoint(x: bgSize.width, y: bgSize.height),
                                  options: [])

            // Drop the page slightly rotated.
            cg.saveGState()
            cg.translateBy(x: bgSize.width / 2, y: bgSize.height / 2)
            cg.rotate(by: 5 * .pi / 180)
            cg.setShadow(offset: CGSize(width: 0, height: 24), blur: 40,
                         color: UIColor(white: 0, alpha: 0.4).cgColor)
            let drawW: CGFloat = 1500
            let drawH = drawW * page.size.height / page.size.width
            page.draw(in: CGRect(x: -drawW / 2, y: -drawH / 2, width: drawW, height: drawH))
            cg.restoreGState()
        }
    }

    private static func makePage() -> UIImage {
        let size = CGSize(width: 1240, height: 1754) // A4-ish at 150dpi
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { _ in
            UIColor.white.setFill()
            UIRectFill(CGRect(origin: .zero, size: size))

            let margin: CGFloat = 90
            func draw(_ string: String, font: UIFont, y: CGFloat, color: UIColor = .black) {
                let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
                (string as NSString).draw(at: CGPoint(x: margin, y: y), withAttributes: attrs)
            }

            draw("INVOICE", font: .boldSystemFont(ofSize: 96), y: margin)
            draw("Scanny Test Document", font: .systemFont(ofSize: 44), y: margin + 130, color: .darkGray)

            UIColor(white: 0.8, alpha: 1).setFill()
            UIRectFill(CGRect(x: margin, y: margin + 210, width: size.width - margin * 2, height: 3))

            let body = [
                "Bill To: Mathieu",
                "Date: May 30, 2026",
                "",
                "Description                         Amount",
                "Document scanning service           $80.00",
                "Optical character recognition       $43.45",
                "",
                "The quick brown fox jumps over the lazy dog.",
                "Searchable text is embedded in the exported PDF."
            ]
            var y = margin + 270
            for line in body {
                draw(line, font: .systemFont(ofSize: 40), y: y)
                y += 64
            }

            draw("Total: $123.45", font: .boldSystemFont(ofSize: 56), y: y + 40)
        }
    }
}
#endif
