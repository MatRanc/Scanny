import SwiftUI

/// The "scanner look" applied to each page.
enum ScanFilter: String, Codable, CaseIterable, Identifiable {
    case bw          // High-contrast black & white "photocopy" (adjustable)
    case grayscale   // Neutral grayscale
    case original    // No processing

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .bw: return "B&W"
        case .grayscale: return "Grayscale"
        case .original: return "Original"
        }
    }

    var systemImage: String {
        switch self {
        case .bw: return "doc.plaintext"
        case .grayscale: return "circle.lefthalf.filled"
        case .original: return "photo"
        }
    }
}

/// Brightness/contrast adjustment for the B&W look (the "curves" the user tunes).
struct BWAdjustment: Codable, Equatable, Hashable {
    var brightness: Double
    var contrast: Double

    static let `default` = BWAdjustment(brightness: 0.0, contrast: 1.35)

    /// Slider ranges.
    static let brightnessRange: ClosedRange<Double> = -0.4...0.4
    static let contrastRange: ClosedRange<Double> = 1.0...2.2
}
