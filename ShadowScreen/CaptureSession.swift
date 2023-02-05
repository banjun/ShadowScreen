import AVFoundation
import CoreGraphics
import IOSurface
import CoreImage
import ScreenCaptureKit
import Combine

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
    }

    private var fpsTimer: Date = .init()
    private var frames: Int = 0

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, sampleBuffer.dataReadiness == .ready else { return }

//        frames += 1
//        if Date().timeIntervalSince(fpsTimer) > 10 {
//            NSLog("%@", "fps = \(frames / 10)")
//            frames = 0
//            fpsTimer = Date()
//        }

        sampleHandlerQueue.asyncAfter(deadline: .now() + latency) { [weak self] in
            guard let self else { return }
            self.sampleBufferDisplayLayer.enqueue(sampleBuffer)
        }
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        NSLog("%@", "\(#function), didStopWithError = \(error)")
    }
}
