#if os(macOS)
import AVFoundation
import CoreGraphics
import IOSurface
import CoreImage
import ScreenCaptureKit
import Combine
import VideoToolbox

class CaptureSession: NSObject, ObservableObject, SCStreamOutput, SCStreamDelegate {
    private var stream: SCStream? {
        didSet {
            oldValue?.stopCapture()
        }
    }
    let sampleBufferDisplayLayer: AVSampleBufferDisplayLayer = .init()
    var latency: Double = 2 // AirPlay delays 2.0 seconds
    private var audioObjects = AudioObject.collect()
    private var airplayAudioObject: AudioObject? { audioObjects.first {$0.name == "AirPlay"} } // AudioObject.collect cannot get AirPlay when the AirPlay device is not selected as System Output
    private let sampleHandlerQueue = DispatchQueue(label: "sampleHandlerQueue", qos: .userInteractive)
    private var cancellables: Set<AnyCancellable> = []
    @Published private(set) var latestImageBufferData: Data?

    override init() {
        super.init()
        NSLog("%@", "CGRequestScreenCaptureAccess() = \(CGRequestScreenCaptureAccess())")
    }

    func startRunning(window: SCWindow) {
        let c = SCStreamConfiguration()
        c.minimumFrameInterval = .init(seconds: 1 / 60, preferredTimescale: 10000) // low fps such as 1 / 30 drops frames
        c.queueDepth = 480 // low value or high value cause frame drops
//        c.width = Int(window.frame.width)
//        c.height = Int(window.frame.height)
//        c.pixelFormat = "420f".utf16.reduce(0) {$0 << 8 + FourCharCode($1)}
        c.colorSpaceName = CGColorSpace.displayP3 // default value converts to less colors...

        c.scalesToFit = true
        if #available(macOS 13.0, *) {
            c.capturesAudio = false
        }
        stream = SCStream(filter: SCContentFilter(desktopIndependentWindow: window), configuration: c, delegate: self)
        _ = try? stream?.addStreamOutput(self, type: .screen, sampleHandlerQueue: sampleHandlerQueue)

        audioObjects = AudioObject.collect()
        NSLog("%@", "airplayAudioObject = \(airplayAudioObject), totalLatency = \(airplayAudioObject?.totalLatency)")
        latency = airplayAudioObject?.totalLatency ?? 2

        stream?.startCapture()
    }

    func stopRunning() {
        stream = nil
        compressionSession = nil
    }

    private var fpsTimer: Date = .init()
    private var frames: Int = 0

    private var firstFrameTimestamp: Double = 0
    private var compressionSession: VTCompressionSession?

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, sampleBuffer.dataReadiness == .ready else { return }

//        frames += 1
//        if Date().timeIntervalSince(fpsTimer) > 10 {
//            NSLog("%@", "fps = \(frames / 10)")
//            frames = 0
//            fpsTimer = Date()
//        }

        /*
         ▿ Optional<CMFormatDescriptionRef>
           - some : <CMVideoFormatDescription 0x6000025a2dc0 [0x1e033b9a0]> {
             mediaType:'vide'
             mediaSubType:'420v'
             mediaSpecific: {
                 codecType: '420v'        dimensions: 1920 x 1080
             }
             extensions: {{
             CVBytesPerRow = 1920;
             CVImageBufferChromaLocationTopField = Left;
             CVImageBufferColorPrimaries = "ITU_R_709_2";
             CVImageBufferTransferFunction = "ITU_R_709_2";
             CVImageBufferYCbCrMatrix = "ITU_R_709_2";
             Version = 2;
         */

        guard let compressionSession else {
            // https://developer.apple.com/documentation/videotoolbox/encoding_video_for_low-latency_conferencing
            var compressionSession: VTCompressionSession?
            let error = VTCompressionSessionCreate(
                allocator: nil,
                width: 1920,
                height: 1080,
                codecType: kCMVideoCodecType_HEVC,
                encoderSpecification: [kVTVideoEncoderSpecification_EnableLowLatencyRateControl: true as CFBoolean] as CFDictionary,
                imageBufferAttributes: [kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange] as CFDictionary,
                compressedDataAllocator: nil,
                outputCallback: nil,
                refcon: nil,
                compressionSessionOut: &compressionSession)
            if error == noErr, let compressionSession {
                self.compressionSession = compressionSession

                func setProperty(key: CFString, value: CFTypeRef?) {
                    let error = VTSessionSetProperty(compressionSession, key: key, value: value)
                    NSLog("%@", "settings \(key) = \(value): error = \(error)")
                }

                setProperty(key: kVTCompressionPropertyKey_ProfileLevel, value: kVTProfileLevel_HEVC_Main_AutoLevel)
                setProperty(key: kVTCompressionPropertyKey_RealTime, value: kCFBooleanTrue)
                setProperty(key: kVTCompressionPropertyKey_MaxKeyFrameIntervalDuration, value: 1 as CFNumber)
            }
            return
        }

        guard let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        VTCompressionSessionEncodeFrame(compressionSession, imageBuffer: imageBuffer, presentationTimeStamp: sampleBuffer.presentationTimeStamp, duration: sampleBuffer.duration, frameProperties: nil, infoFlagsOut: nil) { error, info, sampleBuffer in
            guard error == noErr, let sampleBuffer else { return }

            guard let formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer) else { return }
            func parameterSet(at index: Int) -> Data? {
                var parameterSetPointer: UnsafePointer<UInt8>?
                var parameterSetSize: Int = 0
                var parameterSetCount: Int = 0
                var nalUnitHeaderLength: Int32 = 0
                CMVideoFormatDescriptionGetHEVCParameterSetAtIndex(formatDescription, parameterSetIndex: index, parameterSetPointerOut: &parameterSetPointer, parameterSetSizeOut: &parameterSetSize, parameterSetCountOut: &parameterSetCount, nalUnitHeaderLengthOut: &nalUnitHeaderLength)
                return Data(buffer: UnsafeBufferPointer(start: parameterSetPointer, count: parameterSetSize))
           }
            guard let videoParameterSet = parameterSet(at: 0) else { return }
            guard let sequenceParameterSet = parameterSet(at: 1) else { return }
            guard let pictureParameterSet = parameterSet(at: 2) else { return }
            guard let data = try? sampleBuffer.dataBuffer?.dataBytes() else { return }

//            let attachmentsArray = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as Array?
//            let dependsOnOthers = attachmentsArray?.compactMap {$0 as? [String: Any]}.map {$0?["DependsOnOthers"] as? Bool}
//            NSLog("%@", "DependsOnOthers = \(dependsOnOthers)")
//            NSLog("%@", "sampleBuffer.numSamples = \(sampleBuffer.numSamples)")
            let hevc = HEVC(videoParameterSetSize: UInt32(videoParameterSet.count), videoParameterSet: videoParameterSet, sequenceParameterSetSize: UInt32(sequenceParameterSet.count), sequenceParameterSet: sequenceParameterSet, pictureParameterSetSize: UInt32(pictureParameterSet.count), pictureParameterSet: pictureParameterSet, data: data)
            Task.detached { @MainActor in
                self.latestImageBufferData = Data(hevc: hevc)

                if self.firstFrameTimestamp == 0 {
                    self.firstFrameTimestamp = Date().timeIntervalSince1970
                }
                self.sampleBufferDisplayLayer.enqueue(CMSampleBuffer.decode(hevc: hevc, firstFrameTimestamp: self.firstFrameTimestamp)!)
            }
        }
        return

//        if let imageBuffer = .some(CMSampleBufferGetImageBuffer(sampleBuffer)),
//           CVPixelBufferLockBaseAddress(imageBuffer, .readOnly) == kCVReturnSuccess,
//           let base = CVPixelBufferGetBaseAddress(imageBuffer) {
//            let size = CVPixelBufferGetDataSize(imageBuffer)
//            let buffer = UnsafeBufferPointer(start: base.assumingMemoryBound(to: UInt8.self), count: size)
//            let data = Data(buffer: buffer)
//            CVPixelBufferUnlockBaseAddress(imageBuffer, .readOnly)
//            Task.detached { @MainActor in
//                self.latestImageBufferData = data
//
//
//                let now = Date().timeIntervalSince1970
//                if self.firstFrameTimestamp == 0 {
//                    self.firstFrameTimestamp = now
//                }
//
//                var imageBuffer2: CVImageBuffer?
//                var planeBaseAddresses: [UnsafeMutableRawPointer?] = [base, UnsafeMutableRawPointer(mutating: base.assumingMemoryBound(to: UInt8.self).advanced(by: 1920 * 1080 + 7168))]
//                var planeWidths = [1920, 960]
//                var planeHeights = [1080, 540]
//                var planeBytesPerRow = [1920, 1920]
//
//                CVPixelBufferCreateWithPlanarBytes(kCFAllocatorDefault, 1920, 1080, kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange, base, size, 2, &planeBaseAddresses, &planeWidths, &planeHeights, &planeBytesPerRow, nil, nil, nil, &imageBuffer2)
//                //(kCFAllocatorDefault, 1920, 1080, kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange, base, 1920, nil, nil, nil, &imageBuffer2)
//
//                let timing = CMSampleTimingInfo(duration: .init(seconds: 1, preferredTimescale: 600), presentationTimeStamp: .init(seconds: now - self.firstFrameTimestamp, preferredTimescale: 600), decodeTimeStamp: .invalid)
//                if let imageBuffer2 {
//                    let sampleBuffer = try? CMSampleBuffer(imageBuffer: imageBuffer2, formatDescription: try! CMFormatDescription(imageBuffer: imageBuffer2), sampleTiming: timing)
//                    if let sampleBuffer {
//                        self.sampleBufferDisplayLayer.enqueue(sampleBuffer)
//                    }
//                }
            }
//        }
//
//        sampleHandlerQueue.asyncAfter(deadline: .now() + latency) { [weak self] in
//            guard let self else { return }
//            self.sampleBufferDisplayLayer.enqueue(sampleBuffer)
//        }
//    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        NSLog("%@", "\(#function), didStopWithError = \(error)")
    }
}
#endif
