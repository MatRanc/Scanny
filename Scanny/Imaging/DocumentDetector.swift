import UIKit
import Vision
import CoreImage

/// Finds the page within an imported photo and perspective-corrects it.
///
/// Corners are expressed as **normalised, top-left-origin** points
/// (`x`,`y` in 0...1), ordered `[topLeft, topRight, bottomRight, bottomLeft]`,
/// to match SwiftUI's coordinate space used by the crop editor.
enum DocumentDetector {
    /// The four corners used when nothing confident is detected: a small inset
    /// from the image edges, so the user always has handles to grab.
    static let defaultCorners: [CGPoint] = [
        CGPoint(x: 0.06, y: 0.06), CGPoint(x: 0.94, y: 0.06),
        CGPoint(x: 0.94, y: 0.94), CGPoint(x: 0.06, y: 0.94)
    ]

    /// Detects the page using Vision's document-segmentation model (the same
    /// detector the live camera uses) and returns its corners, or `nil` when
    /// nothing confident is found.
    static func detectQuad(_ image: UIImage) -> [CGPoint]? {
        let up = image.normalizedUp()
        guard let cg = up.cgImage else { return nil }

        let request = VNDetectDocumentSegmentationRequest()
        let handler = VNImageRequestHandler(cgImage: cg, orientation: .up, options: [:])
        do { try handler.perform([request]) } catch { return nil }

        guard let best = request.results?.first, best.confidence >= 0.3 else { return nil }

        // Vision is normalised, origin bottom-left; flip y to top-left origin.
        func flip(_ p: CGPoint) -> CGPoint { CGPoint(x: p.x, y: 1 - p.y) }
        return [flip(best.topLeft), flip(best.topRight), flip(best.bottomRight), flip(best.bottomLeft)]
    }

    /// Perspective-corrects `image` using the given normalised top-left corners.
    static func crop(_ image: UIImage, normalizedCorners corners: [CGPoint]) -> UIImage {
        let up = image.normalizedUp()
        guard corners.count == 4, let input = CIImage(image: up) else { return up }
        let extent = input.extent

        // Normalised top-left -> Core Image space (origin bottom-left).
        func vector(_ c: CGPoint) -> CIVector {
            CIVector(x: c.x * extent.width, y: (1 - c.y) * extent.height)
        }

        let corrected = input.applyingFilter("CIPerspectiveCorrection", parameters: [
            "inputTopLeft": vector(corners[0]),
            "inputTopRight": vector(corners[1]),
            "inputBottomRight": vector(corners[2]),
            "inputBottomLeft": vector(corners[3])
        ])

        guard !corrected.extent.isInfinite,
              let cg = ImageProcessor.context.createCGImage(corrected, from: corrected.extent)
        else { return up }
        return UIImage(cgImage: cg, scale: 1, orientation: .up)
    }

    /// Convenience: auto-detect and crop in one step (falls back to the
    /// orientation-normalised original).
    static func detectAndCrop(_ image: UIImage) -> UIImage {
        let up = image.normalizedUp()
        guard let quad = detectQuad(up) else { return up }
        return crop(up, normalizedCorners: quad)
    }

    // MARK: - Helpers

    private static func area(of obs: VNRectangleObservation) -> CGFloat {
        let p = [obs.topLeft, obs.topRight, obs.bottomRight, obs.bottomLeft]
        var sum: CGFloat = 0
        for i in 0..<4 {
            let a = p[i], b = p[(i + 1) % 4]
            sum += a.x * b.y - b.x * a.y
        }
        return abs(sum) / 2
    }
}
