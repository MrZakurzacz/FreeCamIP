import AVFoundation
import CoreMedia
import CoreVideo
import Foundation

final class CameraCaptureService: NSObject, ObservableObject {
    let session = AVCaptureSession()

    @Published private(set) var isRunning = false
    @Published private(set) var statusText = "Idle"

    var onFrame: ((CVPixelBuffer, CMTime) -> Void)?

    private let sessionQueue = DispatchQueue(
        label: "io.github.MrZakurzacz.FreeCamIP.camera.session"
    )

    private let videoQueue = DispatchQueue(
        label: "io.github.MrZakurzacz.FreeCamIP.camera.video"
    )

    private var isConfigured = false

    func start() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            startAuthorized()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                guard let self else { return }

                if granted {
                    self.startAuthorized()
                } else {
                    self.updateStatus("Camera permission denied", running: false)
                }
            }
        default:
            updateStatus("Camera permission denied", running: false)
        }
    }

    func stop() {
        sessionQueue.async { [weak self] in
            guard let self else { return }

            if self.session.isRunning {
                self.session.stopRunning()
            }

            self.updateStatus("Stopped", running: false)
        }
    }

    private func startAuthorized() {
        sessionQueue.async { [weak self] in
            guard let self else { return }

            do {
                if !self.isConfigured {
                    try self.configureSession()
                    self.isConfigured = true
                }

                if !self.session.isRunning {
                    self.session.startRunning()
                }

                self.updateStatus("Capturing 720p30", running: true)
            } catch {
                self.updateStatus(
                    "Camera setup failed: \(error.localizedDescription)",
                    running: false
                )
            }
        }
    }

    private func configureSession() throws {
        session.beginConfiguration()
        defer { session.commitConfiguration() }

        session.sessionPreset = .hd1280x720

        guard let camera = AVCaptureDevice.default(
            .builtInWideAngleCamera,
            for: .video,
            position: .back
        ) else {
            throw CameraError.noCamera
        }

        let input = try AVCaptureDeviceInput(device: camera)

        guard session.canAddInput(input) else {
            throw CameraError.cannotAddInput
        }

        session.addInput(input)

        let output = AVCaptureVideoDataOutput()
        output.alwaysDiscardsLateVideoFrames = true
        output.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String:
                kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
        ]
        output.setSampleBufferDelegate(self, queue: videoQueue)

        guard session.canAddOutput(output) else {
            throw CameraError.cannotAddOutput
        }

        session.addOutput(output)

        if let connection = output.connection(with: .video),
           connection.isVideoOrientationSupported {
            connection.videoOrientation = .landscapeRight
        }
    }

    private func updateStatus(_ text: String, running: Bool) {
        DispatchQueue.main.async { [weak self] in
            self?.statusText = text
            self?.isRunning = running
        }
    }
}

extension CameraCaptureService: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return
        }

        let presentationTimeStamp =
            CMSampleBufferGetPresentationTimeStamp(sampleBuffer)

        onFrame?(pixelBuffer, presentationTimeStamp)
    }
}

private enum CameraError: LocalizedError {
    case noCamera
    case cannotAddInput
    case cannotAddOutput

    var errorDescription: String? {
        switch self {
        case .noCamera:
            return "No usable camera was found."
        case .cannotAddInput:
            return "The camera input could not be added."
        case .cannotAddOutput:
            return "The video output could not be added."
        }
    }
}
