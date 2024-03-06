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

        // enablePresenterOverlay()
    }
    private var avCaptureSession: AVCaptureSession?

    func stopRunning() {
        stream = nil
        compressionSession = nil
        avCaptureSession = nil
    }

    private func enablePresenterOverlay() {
        if #available(macOS 13, *),
           let camera = AVCaptureDevice.default(for: .video),
           let cameraInput = try? AVCaptureDeviceInput(device: camera) {
            let session = AVCaptureSession()
            session.addInput(cameraInput)
            let output = AVCaptureVideoDataOutput()
            session.addOutput(output)
            session.startRunning()
            self.avCaptureSession = session
        } else {
            self.avCaptureSession = nil
        }
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
            guard let hevc = HEVC(encodedFrameSampleBuffer: sampleBuffer) else { return }
            Task.detached { @MainActor in
                self.latestImageBufferData = Data(hevc: hevc)

                if self.firstFrameTimestamp == 0 {
                    self.firstFrameTimestamp = Date().timeIntervalSince1970
                }
                self.sampleBufferDisplayLayer.enqueue(CMSampleBuffer.decode(hevc: hevc, firstFrameTimestamp: self.firstFrameTimestamp)!)
            }
        }

//        sampleHandlerQueue.asyncAfter(deadline: .now() + latency) { [weak self] in
//            guard let self else { return }
//            self.sampleBufferDisplayLayer.enqueue(sampleBuffer)
//        }
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        NSLog("%@", "\(#function), didStopWithError = \(error)")
    }
}
#endif
