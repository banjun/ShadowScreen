import AVFoundation
import CoreGraphics
import IOSurface
import CoreImage
import ScreenCaptureKit
import Combine

class CaptureSession: NSObject, ObservableObject, SCStreamOutput {
    private var stream: SCStream? {
        didSet {
            oldValue?.stopCapture()
        }
    }
    let sampleBufferDisplayLayer: AVSampleBufferDisplayLayer = .init()
    var latency: Double = 2 // AirPlay delays 2.0 seconds
    private let sampleHandlerQueue = DispatchQueue(label: "sampleHandlerQueue", qos: .userInteractive)
    private var cancellables: Set<AnyCancellable> = []

    override init() {
        super.init()
        NSLog("%@", "CGRequestScreenCaptureAccess() = \(CGRequestScreenCaptureAccess())")
    }

    func startRunning(window: SCWindow) {
        let c = SCStreamConfiguration()
        c.minimumFrameInterval = .init(value: 1001, timescale: 30000)
        c.queueDepth = 60 // low value or high value cause frame drops
        c.width = Int(window.frame.width)
        c.height = Int(window.frame.height)
        c.scalesToFit = true
        if #available(macOS 13.0, *) {
            c.capturesAudio = false
        }
        stream = SCStream(filter: SCContentFilter(desktopIndependentWindow: window), configuration: c, delegate: nil)
        _ = try? stream?.addStreamOutput(self, type: .screen, sampleHandlerQueue: sampleHandlerQueue)
        stream?.startCapture()
    }

    func stopRunning() {
        stream = nil
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, sampleBuffer.dataReadiness == .ready else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + latency) { [weak self] in
            guard let self else { return }
            self.sampleBufferDisplayLayer.enqueue(sampleBuffer)
        }
    }
}
