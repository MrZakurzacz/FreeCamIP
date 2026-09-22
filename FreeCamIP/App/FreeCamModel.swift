import CoreMedia
import Foundation
import UIKit

final class FreeCamModel: ObservableObject {
    let camera = CameraCaptureService()
    let transport = TransportService()

    @Published var pcAddress = ""
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

        encoder.onAccessUnit = { [weak self] data, isKeyFrame, timestamp in
            guard let self else { return }

            self.transport.sendAccessUnit(
                data,
                isKeyFrame: isKeyFrame,
                presentationTimeStamp: timestamp
            )

            DispatchQueue.main.async {
                self.encodedFrames += 1
                self.lastAccessUnitBytes = data.count
                self.lastFrameWasKeyFrame = isKeyFrame
            }
        }
    }

    func connect() {
        transport.connect(
            host: pcAddress,
            deviceName: UIDevice.current.name
        )
    }

    func disconnect() {
        transport.disconnect()
    }

    func start() {
        camera.start()
    }

    func stop() {
        camera.stop()
    }
}
