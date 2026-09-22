import CoreMedia
import CoreVideo
import Foundation
import VideoToolbox

final class H264Encoder {
    typealias AccessUnitHandler = (
        _ data: Data,
        _ isKeyFrame: Bool,
        _ presentationTimeStamp: CMTime
    ) -> Void

    var onAccessUnit: AccessUnitHandler?

    private var compressionSession: VTCompressionSession?
    private let framesPerSecond: Int32

    init(
        width: Int32,
        height: Int32,
        framesPerSecond: Int32,
        averageBitRate: Int32
    ) {
        self.framesPerSecond = framesPerSecond

        var session: VTCompressionSession?

        let status = VTCompressionSessionCreate(
            allocator: kCFAllocatorDefault,
            width: width,
            height: height,
            codecType: kCMVideoCodecType_H264,
            encoderSpecification: nil,
            imageBufferAttributes: nil,
            compressedDataAllocator: nil,
            outputCallback: h264CompressionOutputCallback,
            refcon: Unmanaged.passUnretained(self).toOpaque(),
            compressionSessionOut: &session
        )

        guard status == noErr, let session else {
            return
        }

        compressionSession = session

        VTSessionSetProperty(
            session,
            key: kVTCompressionPropertyKey_RealTime,
            value: kCFBooleanTrue
        )

        VTSessionSetProperty(
            session,
            key: kVTCompressionPropertyKey_ProfileLevel,
            value: kVTProfileLevel_H264_Baseline_AutoLevel
        )

        var fps = framesPerSecond
        let fpsNumber = CFNumberCreate(
            kCFAllocatorDefault,
            .sInt32Type,
            &fps
        )

        VTSessionSetProperty(
            session,
            key: kVTCompressionPropertyKey_ExpectedFrameRate,
            value: fpsNumber
        )

        var bitRate = averageBitRate
        let bitRateNumber = CFNumberCreate(
            kCFAllocatorDefault,
            .sInt32Type,
            &bitRate
        )

        VTSessionSetProperty(
            session,
            key: kVTCompressionPropertyKey_AverageBitRate,
            value: bitRateNumber
        )

        var keyFrameInterval = framesPerSecond * 2
        let keyFrameIntervalNumber = CFNumberCreate(
            kCFAllocatorDefault,
            .sInt32Type,
            &keyFrameInterval
        )

        VTSessionSetProperty(
            session,
            key: kVTCompressionPropertyKey_MaxKeyFrameInterval,
            value: keyFrameIntervalNumber
        )

        VTCompressionSessionPrepareToEncodeFrames(session)
    }

    deinit {
        if let compressionSession {
            VTCompressionSessionCompleteFrames(
                compressionSession,
                untilPresentationTimeStamp: .invalid
            )
            VTCompressionSessionInvalidate(compressionSession)
        }
    }

    func encode(
        pixelBuffer: CVPixelBuffer,
        presentationTimeStamp: CMTime
    ) {
        guard let compressionSession else { return }

        let duration = CMTime(
            value: 1,
            timescale: framesPerSecond
        )

        VTCompressionSessionEncodeFrame(
            compressionSession,
            imageBuffer: pixelBuffer,
            presentationTimeStamp: presentationTimeStamp,
            duration: duration,
            frameProperties: nil,
            sourceFrameRefcon: nil,
            infoFlagsOut: nil
        )
    }

    fileprivate func handleEncodedSampleBuffer(
        _ sampleBuffer: CMSampleBuffer
    ) {
        guard CMSampleBufferDataIsReady(sampleBuffer) else {
            return
        }

        let isKeyFrame = Self.isKeyFrame(sampleBuffer)

        guard let annexBData = Self.makeAnnexBAccessUnit(
            from: sampleBuffer,
            includeParameterSets: isKeyFrame
        ) else {
            return
        }

        onAccessUnit?(
            annexBData,
            isKeyFrame,
            CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        )
    }

    private static func isKeyFrame(
        _ sampleBuffer: CMSampleBuffer
    ) -> Bool {
        guard
            let attachments =
                CMSampleBufferGetSampleAttachmentsArray(
                    sampleBuffer,
                    createIfNecessary: false
                ) as? [[CFString: Any]],
            let first = attachments.first
        else {
            return true
        }

        let notSync =
            (first[kCMSampleAttachmentKey_NotSync] as? Bool) ?? false

        return !notSync
    }

    private static func makeAnnexBAccessUnit(
        from sampleBuffer: CMSampleBuffer,
        includeParameterSets: Bool
    ) -> Data? {
        var output = Data()

        if includeParameterSets,
           let formatDescription =
                CMSampleBufferGetFormatDescription(sampleBuffer) {
            appendParameterSet(
                index: 0,
                formatDescription: formatDescription,
                to: &output
            )
            appendParameterSet(
                index: 1,
                formatDescription: formatDescription,
                to: &output
            )
        }

        guard let blockBuffer =
                CMSampleBufferGetDataBuffer(sampleBuffer) else {
            return nil
        }

        var totalLength = 0
        var dataPointer: UnsafeMutablePointer<Int8>?

        let status = CMBlockBufferGetDataPointer(
            blockBuffer,
            atOffset: 0,
            lengthAtOffsetOut: nil,
            totalLengthOut: &totalLength,
            dataPointerOut: &dataPointer
        )

        guard status == kCMBlockBufferNoErr,
              let dataPointer else {
            return nil
        }

        let bytes = UnsafeRawPointer(dataPointer)
            .assumingMemoryBound(to: UInt8.self)

        var offset = 0
        let nalLengthFieldSize = 4

        while offset + nalLengthFieldSize <= totalLength {
            let nalLength =
                (Int(bytes[offset]) << 24) |
                (Int(bytes[offset + 1]) << 16) |
                (Int(bytes[offset + 2]) << 8) |
                Int(bytes[offset + 3])

            offset += nalLengthFieldSize

            guard nalLength > 0,
                  offset + nalLength <= totalLength else {
                return nil
            }

            output.append(contentsOf: [0, 0, 0, 1])
            output.append(bytes + offset, count: nalLength)
            offset += nalLength
        }

        return output
    }

    private static func appendParameterSet(
        index: Int,
        formatDescription: CMFormatDescription,
        to output: inout Data
    ) {
        var pointer: UnsafePointer<UInt8>?
        var size = 0
        var count = 0
        var nalHeaderLength: Int32 = 0

        let status =
            CMVideoFormatDescriptionGetH264ParameterSetAtIndex(
                formatDescription,
                parameterSetIndex: index,
                parameterSetPointerOut: &pointer,
                parameterSetSizeOut: &size,
                parameterSetCountOut: &count,
                nalUnitHeaderLengthOut: &nalHeaderLength
            )

        guard status == noErr,
              let pointer,
              size > 0 else {
            return
        }

        output.append(contentsOf: [0, 0, 0, 1])
        output.append(pointer, count: size)
    }
}

private let h264CompressionOutputCallback:
    VTCompressionOutputCallback = {
        outputCallbackRefCon,
        _,
        status,
        _,
        sampleBuffer
    in
        guard status == noErr,
              let outputCallbackRefCon,
              let sampleBuffer else {
            return
        }

        let encoder =
            Unmanaged<H264Encoder>
                .fromOpaque(outputCallbackRefCon)
                .takeUnretainedValue()

        encoder.handleEncodedSampleBuffer(sampleBuffer)
    }
