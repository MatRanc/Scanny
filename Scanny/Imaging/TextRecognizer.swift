import UIKit
import Vision

/// One recognised line of text with its location on the page.
struct RecognizedLine {
    let text: String
    /// Normalised bounding box, Vision convention: origin bottom-left, 0...1.
    let boundingBox: CGRect
}

/// Wraps Vision's text recognition for building a searchable PDF layer.
enum TextRecognizer {
    static func recognize(_ image: UIImage) -> [RecognizedLine] {
        let up = image.normalizedUp()
        guard let cg = up.cgImage else { return [] }

        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true

        let handler = VNImageRequestHandler(cgImage: cg, orientation: .up, options: [:])
        do {
            try handler.perform([request])
        } catch {
            return []
        }

        guard let observations = request.results else { return [] }
        return observations.compactMap { observation in
            guard let candidate = observation.topCandidates(1).first,
                  !candidate.string.isEmpty else { return nil }
            return RecognizedLine(text: candidate.string, boundingBox: observation.boundingBox)
        }
    }
}
