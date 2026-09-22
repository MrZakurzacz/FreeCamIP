import CoreMedia
import Foundation
import Network

final class TransportService: ObservableObject {
    @Published private(set) var isConnected = false
    @Published private(set) var statusText = "Disconnected"
    @Published private(set) var sentFrames: UInt64 = 0
    @Published private(set) var sentDatagrams: UInt64 = 0
    @Published private(set) var sendErrors: UInt64 = 0

    private let queue = DispatchQueue(
        label: "io.github.MrZakurzacz.FreeCamIP.transport"
    )

    private var controlConnection: NWConnection?
    private var videoConnection: NWConnection?
    private var controlBuffer = ""
    private var sequence: UInt32 = 0
    private var frameID: UInt32 = 0

    private let controlPort: UInt16 = 47820
    private let videoPort: UInt16 = 47821
    private let maxDatagramBytes = 1200
    private let headerBytes = 26

    func connect(host: String, deviceName: String) {
        let trimmedHost = host.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedHost.isEmpty else {
            setStatus("Enter the PC IP address", connected: false)
            return
        }

        disconnect()

        guard
            let controlNWPort = NWEndpoint.Port(rawValue: controlPort),
            let videoNWPort = NWEndpoint.Port(rawValue: videoPort)
        else {
            setStatus("Invalid network port", connected: false)
            return
        }

        let endpointHost = NWEndpoint.Host(trimmedHost)

        let udp = NWConnection(
            host: endpointHost,
            port: videoNWPort,
            using: .udp
        )

        let tcp = NWConnection(
            host: endpointHost,
            port: controlNWPort,
            using: .tcp
        )

        videoConnection = udp
        controlConnection = tcp
        controlBuffer = ""

        udp.stateUpdateHandler = { [weak self] state in
            guard let self else { return }

            if case .failed(let error) = state {
                self.setStatus(
                    "Video connection failed: \(error.localizedDescription)",
                    connected: false
                )
            }
        }

        tcp.stateUpdateHandler = { [weak self] state in
            guard let self else { return }

            switch state {
            case .ready:
                self.sendHello(deviceName: deviceName)
                self.receiveControl()
            case .failed(let error):
                self.setStatus(
                    "Connection failed: \(error.localizedDescription)",
                    connected: false
                )
            case .cancelled:
                self.setStatus("Disconnected", connected: false)
            default:
                break
            }
        }

        setStatus("Connecting to \(trimmedHost)…", connected: false)
        udp.start(queue: queue)
        tcp.start(queue: queue)
    }

    func disconnect() {
        controlConnection?.stateUpdateHandler = nil
        videoConnection?.stateUpdateHandler = nil
        controlConnection?.cancel()
        videoConnection?.cancel()

        controlConnection = nil
        videoConnection = nil
        controlBuffer = ""

        setStatus("Disconnected", connected: false)
    }

    func sendAccessUnit(
        _ data: Data,
        isKeyFrame: Bool,
        presentationTimeStamp: CMTime
    ) {
        guard !data.isEmpty else { return }

        queue.async { [weak self] in
            guard let self,
                  self.isConnected,
                  let videoConnection = self.videoConnection else {
                return
            }

            let maxPayloadBytes = self.maxDatagramBytes - self.headerBytes
            let fragmentCount =
                (data.count + maxPayloadBytes - 1) / maxPayloadBytes

            guard fragmentCount > 0,
                  fragmentCount <= Int(UInt16.max) else {
                self.incrementSendErrors()
                return
            }

            let currentFrameID = self.frameID
            self.frameID &+= 1

            let seconds = CMTimeGetSeconds(presentationTimeStamp)
            let timestampMicros: UInt64

            if seconds.isFinite, seconds > 0 {
                timestampMicros = UInt64(seconds * 1_000_000)
            } else {
                timestampMicros = 0
            }

            for fragmentIndex in 0..<fragmentCount {
                let start = fragmentIndex * maxPayloadBytes
                let end = min(start + maxPayloadBytes, data.count)
                let payload = data.subdata(in: start..<end)

                var packet = Data(capacity: self.headerBytes + payload.count)
                packet.append(contentsOf: [0x46, 0x43, 0x41, 0x4D])
                packet.append(0)
                packet.append(isKeyFrame ? 1 : 0)
                packet.appendBigEndian(self.sequence)
                packet.appendBigEndian(currentFrameID)
                packet.appendBigEndian(UInt16(fragmentIndex))
                packet.appendBigEndian(UInt16(fragmentCount))
                packet.appendBigEndian(timestampMicros)
                packet.append(payload)

                self.sequence &+= 1

                videoConnection.send(
                    content: packet,
                    completion: .contentProcessed { [weak self] error in
                        if error != nil {
                            self?.incrementSendErrors()
                        }
                    }
                )

                self.incrementSentDatagrams()
            }

            self.incrementSentFrames()
        }
    }

    private func sendHello(deviceName: String) {
        guard let controlConnection else { return }

        let safeDeviceName = deviceName
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: """, with: "\\"")

        let line =
            "{\"type\":\"hello\",\"protocol\":0,\"deviceName\":\"" +
            safeDeviceName +
            "\"}\n"

        controlConnection.send(
            content: Data(line.utf8),
            completion: .contentProcessed { [weak self] error in
                if let error {
                    self?.setStatus(
                        "Handshake send failed: \(error.localizedDescription)",
                        connected: false
                    )
                } else {
                    self?.setStatus(
                        "Waiting for PC handshake…",
                        connected: false
                    )
                }
            }
        )
    }

    private func receiveControl() {
        guard let controlConnection else { return }

        controlConnection.receive(
            minimumIncompleteLength: 1,
            maximumLength: 4096
        ) { [weak self] data, _, isComplete, error in
            guard let self else { return }

            if let data,
               !data.isEmpty,
               let chunk = String(data: data, encoding: .utf8) {
                self.controlBuffer.append(chunk)
                self.processControlBuffer()
            }

            if let error {
                self.setStatus(
                    "Control connection lost: \(error.localizedDescription)",
                    connected: false
                )
                return
            }

            if isComplete {
                self.setStatus("PC disconnected", connected: false)
                return
            }

            self.receiveControl()
        }
    }

    private func processControlBuffer() {
        while let newline = controlBuffer.firstIndex(of: "\n") {
            var line = String(controlBuffer[..<newline])
            controlBuffer.removeSubrange(...newline)

            if line.last == "\r" {
                line.removeLast()
            }

            if line.contains("\"type\":\"hello_ack\""),
               line.contains("\"protocol\":0") {
                setStatus("Connected", connected: true)
            }
        }
    }

    private func setStatus(_ text: String, connected: Bool) {
        DispatchQueue.main.async { [weak self] in
            self?.statusText = text
            self?.isConnected = connected
        }
    }

    private func incrementSentFrames() {
        DispatchQueue.main.async { [weak self] in
            self?.sentFrames &+= 1
        }
    }

    private func incrementSentDatagrams() {
        DispatchQueue.main.async { [weak self] in
            self?.sentDatagrams &+= 1
        }
    }

    private func incrementSendErrors() {
        DispatchQueue.main.async { [weak self] in
            self?.sendErrors &+= 1
        }
    }
}

private extension Data {
    mutating func appendBigEndian<T: FixedWidthInteger>(_ value: T) {
        var bigEndianValue = value.bigEndian

        Swift.withUnsafeBytes(of: &bigEndianValue) { bytes in
            append(contentsOf: bytes)
        }
    }
}
