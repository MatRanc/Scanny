import SwiftUI
import PhotosUI

/// Multi-select photo importer. Loads picked images in the order chosen.
struct PhotoPicker: UIViewControllerRepresentable {
    var onComplete: ([UIImage]) -> Void
    var onCancel: () -> Void

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration()
        config.filter = .images
        config.selectionLimit = 0
        config.preferredAssetRepresentationMode = .current
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ picker: PHPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        private let parent: PhotoPicker
        init(_ parent: PhotoPicker) { self.parent = parent }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            guard !results.isEmpty else {
                parent.onCancel()
                return
            }

            // Preserve selection order while loading asynchronously.
            var images = [UIImage?](repeating: nil, count: results.count)
            let group = DispatchGroup()

            for (index, result) in results.enumerated() {
                let provider = result.itemProvider
                guard provider.canLoadObject(ofClass: UIImage.self) else { continue }
                group.enter()
                provider.loadObject(ofClass: UIImage.self) { object, _ in
                    if let image = object as? UIImage {
                        images[index] = image
                    }
                    group.leave()
                }
            }

            group.notify(queue: .main) { [parent] in
                let ordered = images.compactMap { $0 }
                if ordered.isEmpty {
                    parent.onCancel()
                } else {
                    parent.onComplete(ordered)
                }
            }
        }
    }
}
