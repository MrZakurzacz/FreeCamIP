import SwiftUI

struct ContentView: View {
    @ObservedObject var model: FreeCamModel

    var body: some View {
        VStack(spacing: 16) {
            CameraPreview(session: model.camera.session)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .aspectRatio(16.0 / 9.0, contentMode: .fit)

            VStack(spacing: 6) {
                Text(model.camera.statusText)
                    .font(.headline)

                Text("Encoded frames: \(model.encodedFrames)")
                    .font(.caption.monospacedDigit())

                Text(
                    "Last access unit: \(model.lastAccessUnitBytes) bytes" +
                    (model.lastFrameWasKeyFrame ? " • keyframe" : "")
                )
                .font(.caption.monospacedDigit())
            }

            HStack {
                Button("Start") {
                    model.start()
                }
                .buttonStyle(.borderedProminent)

                Button("Stop") {
                    model.stop()
                }
                .buttonStyle(.bordered)
            }
        }
        .padding()
    }
}
