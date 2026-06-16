import SwiftUI
import AVFoundation
import Vision
import UIKit

/// A custom document camera built on AVFoundation + Vision.
///
/// Keeps the "Apple feel" — live edge detection, flash, and auto-shutter when a
/// steady page is framed — but without VisionKit's multi-page thumbnail
/// collection. Each capture is auto-cropped to the detected page; the user stays
/// in the camera with a running page counter and taps Done to return.
struct ScanCameraView: UIViewControllerRepresentable {
    var onComplete: ([CropResult]) -> Void
    var onCancel: () -> Void

    func makeUIViewController(context: Context) -> ScanCameraViewController {
        let vc = ScanCameraViewController()
        vc.onComplete = onComplete
        vc.onCancel = onCancel
        return vc
    }

    func updateUIViewController(_ vc: ScanCameraViewController, context: Context) {}
}

final class ScanCameraViewController: UIViewController {
    var onComplete: (([CropResult]) -> Void)?
    var onCancel: (() -> Void)?

    // Capture
    private let session = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "scan.camera.session")
    private let videoQueue = DispatchQueue(label: "scan.camera.video")
    private let photoOutput = AVCapturePhotoOutput()
    private let videoOutput = AVCaptureVideoDataOutput()
    private var device: AVCaptureDevice?
    private var previewLayer: AVCaptureVideoPreviewLayer!

    // Detection / auto-shutter
    private let detectionRequest = VNDetectDocumentSegmentationRequest()
    private var smoothedQuad: [CGPoint]?        // normalised, top-left origin (EMA)
    private var pendingQuad: [CGPoint]?         // quad snapshotted at capture time
    private var missingFrames = 0
    private var stableFrames = 0
    private var cooldownUntil = Date.distantPast
    private var flashMode: AVCaptureDevice.FlashMode = .auto
    private var autoCaptureEnabled = true
    private var didCapture = false              // single-shot guard

    // UI
    private let overlayLayer = CAShapeLayer()
    private let shutterButton = UIButton(type: .custom)
    private let cancelButton = UIButton(type: .system)
    private let flashButton = UIButton(type: .system)
    private let autoButton = UIButton(type: .system)
    private let hintLabel = UILabel()

    // Tunables
    private let smoothing: CGFloat = 0.35           // EMA weight for new frames
    private let stableFramesNeeded = 12             // ~0.6–0.8s of stillness
    private let missingFramesToClear = 6            // hysteresis before dropping overlay
    private let minQuadArea: CGFloat = 0.22         // page must fill ≥22% of frame
    private let stabilityTolerance: CGFloat = 0.012 // per-corner movement allowed
    private let minConfidence: VNConfidence = 0.3

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        setupPreview()
        setupOverlay()
        setupControls()
        requestAccessAndConfigure()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        sessionQueue.async { if !self.session.isRunning { self.session.startRunning() } }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        sessionQueue.async { if self.session.isRunning { self.session.stopRunning() } }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer.frame = view.bounds
        overlayLayer.frame = view.bounds
    }

    override var prefersStatusBarHidden: Bool { true }

    // MARK: - Setup

    private func setupPreview() {
        previewLayer = AVCaptureVideoPreviewLayer(session: session)
        previewLayer.videoGravity = .resizeAspectFill
        previewLayer.frame = view.bounds
        view.layer.addSublayer(previewLayer)
    }

    private func setupOverlay() {
        overlayLayer.fillColor = UIColor.systemYellow.withAlphaComponent(0.16).cgColor
        overlayLayer.strokeColor = UIColor.systemYellow.cgColor
        overlayLayer.lineWidth = 3
        overlayLayer.lineJoin = .round
        view.layer.addSublayer(overlayLayer)
    }

    private func requestAccessAndConfigure() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            sessionQueue.async { self.configureSession() }
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                if granted {
                    self.sessionQueue.async { self.configureSession() }
                } else {
                    DispatchQueue.main.async { self.showPermissionDenied() }
                }
            }
        default:
            showPermissionDenied()
        }
    }

    private func configureSession() {
        session.beginConfiguration()
        session.sessionPreset = .photo

        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input) else {
            session.commitConfiguration()
            return
        }
        session.addInput(input)
        self.device = device

        if session.canAddOutput(photoOutput) {
            session.addOutput(photoOutput)
            photoOutput.maxPhotoQualityPrioritization = .quality
        }

        if session.canAddOutput(videoOutput) {
            videoOutput.alwaysDiscardsLateVideoFrames = true
            videoOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
            videoOutput.setSampleBufferDelegate(self, queue: videoQueue)
            session.addOutput(videoOutput)
        }

        // Portrait analysis so the delivered buffer is upright; we then map its
        // pixels to the preview ourselves (deterministic aspect-fill).
        if let c = videoOutput.connection(with: .video), c.isVideoRotationAngleSupported(90) {
            c.videoRotationAngle = 90
        }

        session.commitConfiguration()
        session.startRunning()

        DispatchQueue.main.async {
            if let c = self.previewLayer.connection, c.isVideoRotationAngleSupported(90) {
                c.videoRotationAngle = 90
            }
        }
    }

    // MARK: - Controls

    private func setupControls() {
        shutterButton.translatesAutoresizingMaskIntoConstraints = false
        shutterButton.backgroundColor = .white
        shutterButton.layer.cornerRadius = 36
        shutterButton.layer.borderColor = UIColor.white.cgColor
        shutterButton.layer.borderWidth = 4
        shutterButton.addTarget(self, action: #selector(didTapShutter), for: .touchUpInside)
        view.addSubview(shutterButton)

        cancelButton.translatesAutoresizingMaskIntoConstraints = false
        cancelButton.setTitle("Cancel", for: .normal)
        cancelButton.setTitleColor(.white, for: .normal)
        cancelButton.titleLabel?.font = .systemFont(ofSize: 17, weight: .medium)
        cancelButton.addTarget(self, action: #selector(didTapCancel), for: .touchUpInside)
        view.addSubview(cancelButton)

        // Top toggles
        configureToggle(flashButton, action: #selector(didTapFlash))
        configureToggle(autoButton, action: #selector(didTapAuto))
        let toggles = UIStackView(arrangedSubviews: [flashButton, autoButton])
        toggles.axis = .horizontal
        toggles.spacing = 12
        toggles.alignment = .center
        toggles.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(toggles)
        updateFlashButton()
        updateAutoButton()

        hintLabel.translatesAutoresizingMaskIntoConstraints = false
        hintLabel.text = "Point at a document"
        hintLabel.textColor = .white
        hintLabel.font = .systemFont(ofSize: 14, weight: .medium)
        hintLabel.textAlignment = .center
        hintLabel.layer.shadowColor = UIColor.black.cgColor
        hintLabel.layer.shadowOpacity = 0.5
        hintLabel.layer.shadowRadius = 3
        hintLabel.layer.shadowOffset = .zero
        view.addSubview(hintLabel)

        let guide = view.safeAreaLayoutGuide
        NSLayoutConstraint.activate([
            shutterButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            shutterButton.bottomAnchor.constraint(equalTo: guide.bottomAnchor, constant: -28),
            shutterButton.widthAnchor.constraint(equalToConstant: 72),
            shutterButton.heightAnchor.constraint(equalToConstant: 72),

            cancelButton.leadingAnchor.constraint(equalTo: guide.leadingAnchor, constant: 20),
            cancelButton.centerYAnchor.constraint(equalTo: shutterButton.centerYAnchor),

            flashButton.heightAnchor.constraint(equalToConstant: 36),
            autoButton.heightAnchor.constraint(equalToConstant: 36),

            // Toggles sit just above the shutter so they're easy to spot.
            toggles.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            toggles.bottomAnchor.constraint(equalTo: shutterButton.topAnchor, constant: -16),

            hintLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            hintLabel.bottomAnchor.constraint(equalTo: toggles.topAnchor, constant: -14),
        ])
    }

    private func configureToggle(_ button: UIButton, action: Selector) {
        button.translatesAutoresizingMaskIntoConstraints = false
        button.tintColor = .white
        button.backgroundColor = UIColor.black.withAlphaComponent(0.35)
        button.layer.cornerRadius = 18
        button.contentEdgeInsets = UIEdgeInsets(top: 6, left: 14, bottom: 6, right: 14)
        button.titleLabel?.font = .systemFont(ofSize: 14, weight: .semibold)
        button.addTarget(self, action: action, for: .touchUpInside)
    }

    private func updateFlashButton() {
        let title: String
        switch flashMode {
        case .on:   title = "Flash On"
        case .off:  title = "Flash Off"
        default:    title = "Flash Auto"
        }
        flashButton.setTitle(title, for: .normal)
        flashButton.tintColor = flashMode == .off ? .white : .systemYellow
        flashButton.setTitleColor(flashMode == .off ? .white : .systemYellow, for: .normal)
    }

    private func updateAutoButton() {
        autoButton.setTitle(autoCaptureEnabled ? "Auto Capture On" : "Auto Capture Off", for: .normal)
        let color: UIColor = autoCaptureEnabled ? .systemGreen : .white
        autoButton.tintColor = color
        autoButton.setTitleColor(color, for: .normal)
        if !autoCaptureEnabled { stableFrames = 0 }
    }

    private func showPermissionDenied() {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = "Camera access is off.\nEnable it in Settings to scan."
        label.numberOfLines = 0
        label.textAlignment = .center
        label.textColor = .white
        view.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            label.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 32),
            label.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -32),
        ])
    }

    // MARK: - Actions

    @objc private func didTapCancel() { onCancel?() }
    @objc private func didTapShutter() { capture() }

    @objc private func didTapFlash() {
        switch flashMode {
        case .auto: flashMode = .on
        case .on:   flashMode = .off
        default:    flashMode = .auto
        }
        updateFlashButton()
    }

    @objc private func didTapAuto() {
        autoCaptureEnabled.toggle()
        updateAutoButton()
    }

    private func capture() {
        guard !didCapture, Date() >= cooldownUntil else { return }
        didCapture = true   // single shot: ignore any further triggers
        cooldownUntil = Date().addingTimeInterval(1.5)
        stableFrames = 0
        // Use the live-detected page (what the overlay shows) for the crop; the
        // still and the analysis buffer share the same upright 4:3 normalised space.
        pendingQuad = smoothedQuad

        let settings = AVCapturePhotoSettings()
        if photoOutput.supportedFlashModes.contains(flashMode) {
            settings.flashMode = flashMode
        }
        settings.photoQualityPrioritization = .quality
        photoOutput.capturePhoto(with: settings, delegate: self)
    }

    private func flashScreen() {
        let flash = UIView(frame: view.bounds)
        flash.backgroundColor = .black
        view.addSubview(flash)
        UIView.animate(withDuration: 0.25) { flash.alpha = 0 } completion: { _ in flash.removeFromSuperview() }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }
}

// MARK: - Live detection

extension ScanCameraViewController: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        // Serial delegate queue + late-frame discard means each detection runs
        // to completion before the next frame is handed in.
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let bufferSize = CGSize(width: CVPixelBufferGetWidth(pixelBuffer),
                                height: CVPixelBufferGetHeight(pixelBuffer))
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up, options: [:])
        try? handler.perform([detectionRequest])
        let observation = detectionRequest.results?.first
        DispatchQueue.main.async { self.handleObservation(observation, bufferSize: bufferSize) }
    }

    private func handleObservation(_ observation: VNRectangleObservation?, bufferSize: CGSize) {
        guard let observation, observation.confidence >= minConfidence else {
            missingFrames += 1
            if missingFrames >= missingFramesToClear {
                overlayLayer.path = nil
                smoothedQuad = nil
                stableFrames = 0
                hintLabel.text = "Point at a document"
            }
            return
        }
        missingFrames = 0

        // Vision: normalised, bottom-left origin → top-left origin.
        func flip(_ p: CGPoint) -> CGPoint { CGPoint(x: p.x, y: 1 - p.y) }
        let raw = [flip(observation.topLeft), flip(observation.topRight),
                   flip(observation.bottomRight), flip(observation.bottomLeft)]

        // Temporal smoothing to kill jitter.
        let quad: [CGPoint]
        if let prev = smoothedQuad {
            quad = zip(prev, raw).map { p, n in
                CGPoint(x: p.x + (n.x - p.x) * smoothing,
                        y: p.y + (n.y - p.y) * smoothing)
            }
        } else {
            quad = raw
        }

        let bigEnough = quadArea(quad) >= minQuadArea
        // Stability is measured against the *raw* reading vs the smoothed quad:
        // small delta means the page isn't moving.
        if bigEnough, isStable(quad, raw) {
            stableFrames += 1
        } else {
            stableFrames = 0
        }
        smoothedQuad = quad
        drawOverlay(quad, bufferSize: bufferSize)

        let ready = autoCaptureEnabled && stableFrames >= stableFramesNeeded
        if bigEnough {
            hintLabel.text = autoCaptureEnabled ? "Hold steady to capture" : "Tap the shutter"
        } else {
            hintLabel.text = "Move closer to the document"
        }
        overlayLayer.strokeColor = (ready ? UIColor.systemGreen : UIColor.systemYellow).cgColor

        if ready, Date() >= cooldownUntil {
            capture()
        }
    }

    /// Map a normalised (top-left origin) point to view coords, matching the
    /// preview's `resizeAspectFill`.
    private func drawOverlay(_ quad: [CGPoint], bufferSize: CGSize) {
        guard bufferSize.width > 0, bufferSize.height > 0 else { return }
        let bounds = previewLayer.bounds
        let scale = max(bounds.width / bufferSize.width, bounds.height / bufferSize.height)
        let displayW = bufferSize.width * scale
        let displayH = bufferSize.height * scale
        let originX = (bounds.width - displayW) / 2
        let originY = (bounds.height - displayH) / 2

        let points = quad.map {
            CGPoint(x: originX + $0.x * displayW, y: originY + $0.y * displayH)
        }
        let path = UIBezierPath()
        path.move(to: points[0])
        for p in points.dropFirst() { path.addLine(to: p) }
        path.close()

        // Don't animate the path implicitly — we already smooth the data.
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        overlayLayer.path = path.cgPath
        CATransaction.commit()
    }

    private func quadArea(_ q: [CGPoint]) -> CGFloat {
        var sum: CGFloat = 0
        for i in 0..<4 {
            let a = q[i], b = q[(i + 1) % 4]
            sum += a.x * b.y - b.x * a.y
        }
        return abs(sum) / 2
    }

    private func isStable(_ a: [CGPoint], _ b: [CGPoint]) -> Bool {
        for i in 0..<4 {
            if hypot(a[i].x - b[i].x, a[i].y - b[i].y) > stabilityTolerance { return false }
        }
        return true
    }
}

// MARK: - Photo capture

extension ScanCameraViewController: AVCapturePhotoCaptureDelegate {
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto,
                     error: Error?) {
        guard error == nil,
              let data = photo.fileDataRepresentation(),
              let image = UIImage(data: data) else { return }

        let source = image.normalizedUp()
        // Prefer the live-detected quad; fall back to a fresh still detection,
        // then to default corners so the page is always editable later.
        let corners = pendingQuad
            ?? DocumentDetector.detectQuad(source)
            ?? DocumentDetector.defaultCorners

        DispatchQueue.main.async {
            self.pendingQuad = nil
            self.flashScreen()
            // Single shot: hand the page straight to the editor.
            self.onComplete?([CropResult(source: source, corners: corners)])
        }
    }
}
