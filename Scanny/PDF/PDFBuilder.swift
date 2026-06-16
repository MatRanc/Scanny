import UIKit

/// Builds a multi-page PDF where each page is a processed scan with an
/// invisible, selectable OCR text layer on top (a searchable PDF).
enum PDFBuilder {
    struct Page {
        let image: UIImage
        let lines: [RecognizedLine]
    }

    static func build(pages: [Page], title: String) -> Data {
        let format = UIGraphicsPDFRendererFormat()
        format.documentInfo = [
            kCGPDFContextTitle as String: title,
            kCGPDFContextCreator as String: "Scanny"
        ]

        // Each page gets its own bounds, so start from a zero rect.
        let renderer = UIGraphicsPDFRenderer(bounds: .zero, format: format)
        return renderer.pdfData { ctx in
            for page in pages {
                let pageRect = CGRect(origin: .zero, size: page.image.pointSize)
                guard pageRect.width > 0, pageRect.height > 0 else { continue }
                ctx.beginPage(withBounds: pageRect, pageInfo: [:])
                page.image.draw(in: pageRect)
                drawTextLayer(page.lines, in: pageRect)
            }
        }
    }

    /// Draws the OCR text invisibly (clear fill) but positioned over each line,
    /// so PDF readers can search and select the text.
    private static func drawTextLayer(_ lines: [RecognizedLine], in pageRect: CGRect) {
        guard !lines.isEmpty else { return }
        let pageWidth = pageRect.width
        let pageHeight = pageRect.height

        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byClipping

        for line in lines where !line.text.isEmpty {
            let box = line.boundingBox
            // Vision: normalised, origin bottom-left -> UIKit top-left rect.
            let rect = CGRect(
                x: box.minX * pageWidth,
                y: (1 - box.maxY) * pageHeight,
                width: box.width * pageWidth,
                height: box.height * pageHeight
            )
            guard rect.width > 1, rect.height > 1 else { continue }

            var fontSize = max(2, rect.height * 0.85)
            let text = line.text as NSString
            let probeWidth = text.size(withAttributes: [.font: UIFont.systemFont(ofSize: fontSize)]).width
            if probeWidth > rect.width, probeWidth > 0 {
                fontSize *= rect.width / probeWidth
            }

            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: fontSize),
                .foregroundColor: UIColor.clear,
                .paragraphStyle: paragraph
            ]
            text.draw(in: rect, withAttributes: attributes)
        }
    }
}
