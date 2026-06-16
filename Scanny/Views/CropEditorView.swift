import SwiftUI

/// The result of a crop session: the (possibly rotated) source image and the
/// crop quad on it. Cropping is applied later, non-destructively, by the store.
struct CropResult {
    let source: UIImage
    let corners: [CGPoint]
}

/// Steps the user through manually cropping each imported photo.
struct CropFlowView: View {
    let images: [UIImage]
    var onComplete: ([CropResult]) -> Void
    var onCancel: () -> Void

    @State private var index = 0
    @State private var results: [CropResult] = []

    var body: some View {
        Group {
            if images.isEmpty {
                Color.black.onAppear { onComplete([]) }
            } else {
                CropEditorView(
                    original: images[index],
                    pageLabel: images.count > 1 ? "Page \(index + 1) of \(images.count)" : nil,
                    isLast: index == images.count - 1,
                    onDone: { result in
                        results.append(result)
                        if index >= images.count - 1 {
                            onComplete(results)
                        } else {
                            index += 1
                        }
                    },
                    onCancel: onCancel
                )
                .id(index)
            }
        }
    }
}

/// A single-image cropper: drag the four corners over the photo (a magnifier
/// loupe follows your finger for precision), then confirm. Returns the source +
/// corners; the actual perspective correction happens non-destructively later.
struct CropEditorView: View {
    let original: UIImage
    var initialCorners: [CGPoint]?
    var pageLabel: String?
    var isLast: Bool
    var doneTitle: String?
    var onDone: (CropResult) -> Void
    var onCancel: () -> Void

    @State private var working: UIImage?      // full-res, orientation-normalised
    @State private var display: UIImage?      // downscaled copy for the UI
    @State private var corners: [CGPoint] = DocumentDetector.defaultCorners
    @State private var baselineCorners: [CGPoint]?   // the detection the screen opened with
    @State private var activeCorner: Int?

    private let loupeDiameter: CGFloat = 120

    var body: some View {
        let insets = Self.windowSafeAreaInsets()
        return ZStack {
            Color.black
            VStack(spacing: 0) {
                topBar
                    .padding(.top, insets.top + 10)
                GeometryReader { inner in
                    Group {
                        if let display {
                            editor(display, in: inner.size)
                        } else {
                            ProgressView().tint(.white)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                    }
                    .coordinateSpace(name: "crop")
                }
                bottomBar
                    .padding(.bottom, insets.bottom + 24)
            }
        }
        .ignoresSafeArea()
        .task { await setup() }
    }

    /// Real device safe-area insets from the key window (SwiftUI's insets get
    /// zeroed inside an `ignoresSafeArea` container, so read UIKit directly).
    private static func windowSafeAreaInsets() -> UIEdgeInsets {
        let window = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow }
        return window?.safeAreaInsets ?? UIEdgeInsets(top: 47, left: 0, bottom: 34, right: 0)
    }

    // MARK: - Editor surface

    private func editor(_ image: UIImage, in size: CGSize) -> some View {
        let rect = Self.fitRect(imageSize: image.size, in: size)
        let points = corners.map { Self.viewPoint($0, in: rect) }

        return ZStack {
            Image(uiImage: image)
                .resizable()
                .frame(width: rect.width, height: rect.height)
                .position(x: rect.midX, y: rect.midY)

            Canvas { ctx, canvasSize in
                var quad = Path()
                quad.move(to: points[0])
                for p in points.dropFirst() { quad.addLine(to: p) }
                quad.closeSubpath()

                var outside = Path(CGRect(origin: .zero, size: canvasSize))
                outside.addPath(quad)
                ctx.fill(outside, with: .color(.black.opacity(0.5)), style: FillStyle(eoFill: true))
                ctx.stroke(quad, with: .color(.white), lineWidth: 2)
            }
            .allowsHitTesting(false)

            ForEach(0..<4, id: \.self) { i in
                handle(index: i, at: points[i], rect: rect)
            }

            if let active = activeCorner {
                LoupeView(image: image, imageRect: rect, focus: points[active], diameter: loupeDiameter)
                    .position(loupeCenter(for: points[active], in: size))
                    .allowsHitTesting(false)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func handle(index i: Int, at point: CGPoint, rect: CGRect) -> some View {
        let isActive = activeCorner == i
        return ZStack {
            Circle().fill(Color.white.opacity(0.001)).frame(width: 46, height: 46)
            Circle()
                .strokeBorder(Color.white, lineWidth: 3)
                .background(Circle().fill(Color.blue.opacity(isActive ? 0.45 : 0.2)))
                .frame(width: isActive ? 32 : 26, height: isActive ? 32 : 26)
            Circle().fill(Color.white).frame(width: 5, height: 5)
        }
        .contentShape(Circle())
        .position(point)
        .gesture(
            DragGesture(minimumDistance: 0, coordinateSpace: .named("crop"))
                .onChanged { value in
                    activeCorner = i
                    corners[i] = Self.normalize(value.location, in: rect)
                }
                .onEnded { _ in activeCorner = nil }
        )
    }

    // MARK: - Bars

    private var topBar: some View {
        ZStack {
            Text(pageLabel ?? "Adjust Corners")
                .font(.headline)
                .foregroundStyle(.white)
            HStack {
                Button("Cancel") { onCancel() }
                    .foregroundStyle(.white)
                Spacer()
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(Color.black)
    }

    private var bottomBar: some View {
        HStack(spacing: 20) {
            Button { resetCorners() } label: {
                Label("Auto", systemImage: "wand.and.stars")
            }
            .foregroundStyle(.white)

            Spacer()

            Button { rotate() } label: {
                Image(systemName: "rotate.right")
                    .font(.title3)
            }
            .foregroundStyle(.white)

            Spacer()

            Button { confirm() } label: {
                Text(doneTitle ?? (isLast ? "Done" : "Next"))
                    .font(.body.weight(.semibold))
                    .frame(minWidth: 64)
            }
            .buttonStyle(.borderedProminent)
            .tint(.blue)
            .disabled(working == nil)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(Color.black)
    }

    // MARK: - Actions

    private func setup() async {
        let up = original.normalizedUp()
        working = up
        display = up.downscaled(maxDimension: 1800)
        if let initialCorners {
            corners = initialCorners
            baselineCorners = initialCorners
            #if DEBUG
            if ProcessInfo.processInfo.environment["DEBUG_LOUPE"] == "1" { activeCorner = 0 }
            #endif
            return
        }
        #if DEBUG
        if ProcessInfo.processInfo.environment["DEBUG_LOUPE"] == "1" { activeCorner = 0 }
        #endif
        let detected = await Task.detached(priority: .userInitiated) {
            DocumentDetector.detectQuad(up)
        }.value
        corners = detected ?? DocumentDetector.defaultCorners
        baselineCorners = corners
    }

    /// "Auto" restores the detection the screen opened with (e.g. the live
    /// camera result), rather than re-detecting on the still — which wouldn't
    /// reproduce it. After a rotation the baseline is refreshed in `rotate()`.
    private func resetCorners() {
        if let baselineCorners {
            corners = baselineCorners
            return
        }
        guard let working else { return }
        Task {
            let detected = await Task.detached(priority: .userInitiated) {
                DocumentDetector.detectQuad(working)
            }.value
            corners = detected ?? DocumentDetector.defaultCorners
            baselineCorners = corners
        }
    }

    private func rotate() {
        guard let working, let display else { return }
        let rotatedFull = working.rotated90()
        self.working = rotatedFull
        self.display = display.rotated90()
        Task {
            let detected = await Task.detached(priority: .userInitiated) {
                DocumentDetector.detectQuad(rotatedFull)
            }.value
            corners = detected ?? DocumentDetector.defaultCorners
            baselineCorners = corners
        }
    }

    private func confirm() {
        guard let working else { return }
        onDone(CropResult(source: working, corners: corners))
    }

    // MARK: - Geometry

    private func loupeCenter(for point: CGPoint, in size: CGSize) -> CGPoint {
        let r = loupeDiameter / 2
        let margin: CGFloat = 72
        var y = point.y - (r + margin)
        if y - r < 8 { y = point.y + (r + margin) }
        y = min(max(y, r + 8), size.height - r - 8)
        let x = min(max(point.x, r + 8), size.width - r - 8)
        return CGPoint(x: x, y: y)
    }

    private static func fitRect(imageSize: CGSize, in container: CGSize) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0 else { return .zero }
        let scale = min(container.width / imageSize.width, container.height / imageSize.height)
        let w = imageSize.width * scale
        let h = imageSize.height * scale
        return CGRect(x: (container.width - w) / 2, y: (container.height - h) / 2, width: w, height: h)
    }

    private static func viewPoint(_ c: CGPoint, in rect: CGRect) -> CGPoint {
        CGPoint(x: rect.minX + c.x * rect.width, y: rect.minY + c.y * rect.height)
    }

    private static func normalize(_ p: CGPoint, in rect: CGRect) -> CGPoint {
        guard rect.width > 0, rect.height > 0 else { return .zero }
        let x = min(max((p.x - rect.minX) / rect.width, 0), 1)
        let y = min(max((p.y - rect.minY) / rect.height, 0), 1)
        return CGPoint(x: x, y: y)
    }
}

/// Circular magnifier that shows a zoomed view centred on the dragged corner.
private struct LoupeView: View {
    let image: UIImage
    let imageRect: CGRect
    let focus: CGPoint
    var diameter: CGFloat = 120
    var magnification: CGFloat = 2.2

    var body: some View {
        let local = CGPoint(x: focus.x - imageRect.minX, y: focus.y - imageRect.minY)
        let offsetX = magnification * (imageRect.width / 2 - local.x)
        let offsetY = magnification * (imageRect.height / 2 - local.y)

        return ZStack {
            Color(white: 0.1)
            Image(uiImage: image)
                .resizable()
                .frame(width: imageRect.width * magnification, height: imageRect.height * magnification)
                .offset(x: offsetX, y: offsetY)
            Rectangle().fill(.white.opacity(0.85)).frame(width: 1, height: 22)
            Rectangle().fill(.white.opacity(0.85)).frame(width: 22, height: 1)
        }
        .frame(width: diameter, height: diameter)
        .clipShape(Circle())
        .overlay(Circle().strokeBorder(.white, lineWidth: 3))
        .shadow(color: .black.opacity(0.4), radius: 8, y: 2)
    }
}
