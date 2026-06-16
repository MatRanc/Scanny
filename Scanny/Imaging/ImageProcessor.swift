import UIKit
import CoreImage
import CoreImage.CIFilterBuiltins

/// Applies the "scanner look" to a page using Core Image.
enum ImageProcessor {
    /// A shared, GPU-backed context. `CIContext` is thread-safe for rendering.
    static let context: CIContext = {
        CIContext(options: [.useSoftwareRenderer: false])
    }()

    static func process(_ image: UIImage,
                        filter: ScanFilter,
                        bw: BWAdjustment = .default) -> UIImage {
        guard filter != .original else { return image }
        guard let input = CIImage(image: image) else { return image }

        let output: CIImage
        switch filter {
        case .original:  output = input
        case .grayscale: output = grayscaleScan(input)
        case .bw:        output = bwScan(input, adjustment: bw)
        }

        let extent = output.extent.isInfinite ? input.extent : output.extent
        guard let cg = context.createCGImage(output, from: extent) else { return image }
        return UIImage(cgImage: cg, scale: 1, orientation: .up)
    }

    /// Convenience for previews: downscale first, then process (much faster).
    static func processedThumbnail(_ image: UIImage,
                                   filter: ScanFilter,
                                   bw: BWAdjustment = .default,
                                   maxDimension: CGFloat) -> UIImage {
        process(image.downscaled(maxDimension: maxDimension), filter: filter, bw: bw)
    }

    // MARK: - Looks

    /// Neutral grayscale with boosted contrast.
    private static func grayscaleScan(_ input: CIImage) -> CIImage {
        var img = input.applyingFilter("CIPhotoEffectMono")
        img = img.applyingFilter("CIColorControls", parameters: [
            kCIInputContrastKey: 1.18,
            kCIInputBrightnessKey: 0.03
        ])
        img = img.applyingFilter("CIUnsharpMask", parameters: [
            kCIInputRadiusKey: 2.0,
            kCIInputIntensityKey: 0.7
        ])
        return img
    }

    /// High-contrast "photocopy" black & white.
    ///
    /// The key step is flat-field correction: estimate the background
    /// illumination with a large blur, then divide the image by it so uneven
    /// lighting / shadows disappear and the paper goes pure white. Division is
    /// done with a colour-dodge blend, which computes `backdrop / (1 - source)`:
    /// feeding `source = 1 - background` yields `gray / background`.
    ///
    /// The final brightness/contrast is user-adjustable (the "curves").
    private static func bwScan(_ input: CIImage, adjustment: BWAdjustment) -> CIImage {
        let gray = input.applyingFilter("CIPhotoEffectMono")
        let radius = max(gray.extent.width, gray.extent.height) * 0.012

        let background = gray
            .clampedToExtent()
            .applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: radius])
            .cropped(to: gray.extent)

        let invertedBackground = background.applyingFilter("CIColorInvert")
        let normalized = invertedBackground.applyingFilter("CIColorDodgeBlendMode", parameters: [
            kCIInputBackgroundImageKey: gray
        ])

        return normalized.applyingFilter("CIColorControls", parameters: [
            kCIInputContrastKey: adjustment.contrast,
            kCIInputBrightnessKey: adjustment.brightness
        ])
    }
}
