import UIKit

extension UIImage {
    /// Pixel dimensions expressed as points (i.e. ignoring `scale`). Useful when
    /// laying out a PDF page at 1px = 1pt.
    var pointSize: CGSize {
        CGSize(width: size.width * scale, height: size.height * scale)
    }

    /// Returns a copy whose orientation is baked into the pixels (`.up`) at
    /// scale 1, so downstream Core Image / Vision work needs no orientation math.
    func normalizedUp() -> UIImage {
        if imageOrientation == .up && scale == 1 { return self }
        let target = pointSize
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(size: target, format: format)
        return renderer.image { _ in
            draw(in: CGRect(origin: .zero, size: target))
        }
    }

    /// Returns a copy rotated 90° clockwise (orientation baked in, scale 1).
    func rotated90() -> UIImage {
        let src = normalizedUp()
        let s = src.size
        let target = CGSize(width: s.height, height: s.width)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(size: target, format: format)
        return renderer.image { ctx in
            let cg = ctx.cgContext
            cg.translateBy(x: target.width / 2, y: target.height / 2)
            cg.rotate(by: .pi / 2)
            src.draw(in: CGRect(x: -s.width / 2, y: -s.height / 2, width: s.width, height: s.height))
        }
    }

    /// Scales the image down so its longest pixel edge is `maxDimension`,
    /// preserving aspect ratio. Returns `self` if already small enough.
    func downscaled(maxDimension: CGFloat) -> UIImage {
        let pixels = pointSize
        let longest = max(pixels.width, pixels.height)
        guard longest > maxDimension, longest > 0 else { return self }
        let factor = maxDimension / longest
        let target = CGSize(width: pixels.width * factor, height: pixels.height * factor)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(size: target, format: format)
        return renderer.image { _ in
            draw(in: CGRect(origin: .zero, size: target))
        }
    }
}
