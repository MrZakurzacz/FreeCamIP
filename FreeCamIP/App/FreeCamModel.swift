import CoreMedia
import Foundation

final class FreeCamModel: ObservableObject {
    let camera = CameraCaptureService()

    @Published private(set) var encodedFrames: Int = 0
    @Published private(set) var lastAccessUnitBytes: Int = 0
    @Published private(set) var lastFrameWasKeyFrame: Bool = false

    private let encoder = H264Encoder(
        width: 1280,
        height: 720,
        framesPerSecond: 30,
        averageBitRate: 4_000_000
    )

    init() {
        camera.onFrame = { [weak self] pixelBuffer, presentationTimeStamp in
            self?.encoder.encode(
                pixelBuffer: pixelBuffer,
                presentationTimeStamp: presentationTimeStamp
            )
        }

        encoder.onAccessUnit = { [weak self] data, isKeyFrame, _ in
            DispatchQueue.main.async {
                self?.encodedFrames += 1
                self?.lastAccessUnitBytes = data.count
                self?.lastFrameWasKeyFrame = isKeyFrame
            }
        }
    }

    func start() {
        camera.start()
    }

    func stop() {
        camera.stop()
    }
}
