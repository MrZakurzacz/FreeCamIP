import SwiftUI

struct ContentView: View {
    @ObservedObject var model: FreeCamModel
    @ObservedObject private var transport: TransportService

    init(model: FreeCamModel) {
        self.model = model
        self._transport = ObservedObject(wrappedValue: model.transport)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                CameraPreview(session: model.camera.session)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .aspectRatio(16.0 / 9.0, contentMode: .fit)

                VStack(alignment: .leading, spacing: 8) {
                    TextField("PC IPv4 address", text: $model.pcAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.numbersAndPunctuation)
                        .textFieldStyle(.roundedBorder)

                    HStack {
                        Button("Connect") {
                            model.connect()
                        }
                        .buttonStyle(.borderedProminent)

                        Button("Disconnect") {
                            model.disconnect()
                        }
                        .buttonStyle(.bordered)
                    }

                    Text(transport.statusText)
                        .font(.caption)
                }

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

                    Text(
                        "Sent: \(transport.sentFrames) frames • " +
                        "\(transport.sentDatagrams) datagrams • " +
                        "\(transport.sendErrors) send errors"
                    )
                    .font(.caption.monospacedDigit())
                }

                HStack {
                    Button("Start Camera") {
                        model.start()
                    }
                    .buttonStyle(.borderedProminent)

                    Button("Stop Camera") {
                        model.stop()
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding()
        }
    }
}
